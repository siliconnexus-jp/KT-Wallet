import 'dart:convert';
import 'dart:typed_data';

/// Minimal CBOR (RFC 8949) codec covering exactly the subset the AIRGAP-V1
/// payloads use: unsigned ints, byte strings, text strings, arrays and maps,
/// all definite-length. Kept self-contained so the offline signer's dependency
/// tree stays minimal and auditable (tech-plan.md §4).
///
/// Decoding is strict and total: any malformed or unsupported input throws
/// [CborError] rather than partially decoding (fuzz-safety, DD §8.6).
class CborError implements Exception {
  CborError(this.message);
  final String message;
  @override
  String toString() => 'CborError: $message';
}

// Major types (high 3 bits).
const int _mtUint = 0;
const int _mtBytes = 2;
const int _mtText = 3;
const int _mtArray = 4;
const int _mtMap = 5;

/// Encodes a Dart value tree to CBOR bytes.
///
/// Supported: `int` (>= 0), `Uint8List`/`List<int>` (byte string), `String`,
/// `List` (array), `Map` (map, keys sorted by encoded bytes for determinism).
Uint8List cborEncode(Object? value) {
  final out = BytesBuilder();
  _encode(value, out);
  return out.toBytes();
}

void _encodeHead(int major, int arg, BytesBuilder out) {
  final mt = major << 5;
  if (arg < 24) {
    out.addByte(mt | arg);
  } else if (arg < 0x100) {
    out.addByte(mt | 24);
    out.addByte(arg);
  } else if (arg < 0x10000) {
    out.addByte(mt | 25);
    out.addByte((arg >> 8) & 0xFF);
    out.addByte(arg & 0xFF);
  } else if (arg < 0x100000000) {
    out.addByte(mt | 26);
    for (var s = 24; s >= 0; s -= 8) {
      out.addByte((arg >> s) & 0xFF);
    }
  } else {
    out.addByte(mt | 27);
    for (var s = 56; s >= 0; s -= 8) {
      out.addByte((arg >> s) & 0xFF);
    }
  }
}

void _encode(Object? value, BytesBuilder out) {
  switch (value) {
    case final int v:
      if (v < 0) throw CborError('negative ints unsupported');
      _encodeHead(_mtUint, v, out);
    case final String v:
      final bytes = utf8.encode(v);
      _encodeHead(_mtText, bytes.length, out);
      out.add(bytes);
    case final Uint8List v:
      _encodeHead(_mtBytes, v.length, out);
      out.add(v);
    case final List<Object?> v:
      _encodeHead(_mtArray, v.length, out);
      for (final e in v) {
        _encode(e, out);
      }
    case final Map<Object?, Object?> v:
      final entries = v.entries.map((e) {
        final kb = cborEncode(e.key);
        return (kb, e.value);
      }).toList()
        ..sort((a, b) => _compareBytes(a.$1, b.$1));
      _encodeHead(_mtMap, entries.length, out);
      for (final e in entries) {
        out.add(e.$1);
        _encode(e.$2, out);
      }
    default:
      throw CborError('unsupported type: ${value.runtimeType}');
  }
}

int _compareBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return a.length - b.length;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return 0;
}

/// Decodes CBOR bytes. Throws [CborError] on any malformed/trailing input.
Object? cborDecode(Uint8List bytes) {
  final dec = _Decoder(bytes);
  final value = dec.readValue();
  if (dec.offset != bytes.length) {
    throw CborError('trailing bytes after top-level value');
  }
  return value;
}

class _Decoder {
  _Decoder(this.bytes);
  final Uint8List bytes;
  int offset = 0;

  // Bounds on collection sizes to keep a malicious header from allocating huge
  // structures before the (short) buffer is exhausted.
  static const int _maxItems = 4096;

  // Max nesting depth. A hostile payload of nested-array bytes (0x81 0x81 …)
  // would otherwise recurse once per byte and overflow the stack (INV-6). Our
  // payloads nest at most ~3 levels; 16 is generous headroom.
  static const int _maxDepth = 16;
  int _depth = 0;

  int _byte() {
    if (offset >= bytes.length) throw CborError('unexpected end of input');
    return bytes[offset++];
  }

  int _readArg(int info) {
    if (info < 24) return info;
    switch (info) {
      case 24:
        return _byte();
      case 25:
        return (_byte() << 8) | _byte();
      case 26:
        var v = 0;
        for (var i = 0; i < 4; i++) {
          v = (v << 8) | _byte();
        }
        return v;
      case 27:
        var v = 0;
        for (var i = 0; i < 8; i++) {
          v = (v << 8) | _byte();
        }
        if (v < 0) throw CborError('length exceeds platform int');
        return v;
      default:
        throw CborError('unsupported additional info $info');
    }
  }

  Object? readValue() {
    final initial = _byte();
    final major = initial >> 5;
    final info = initial & 0x1F;
    switch (major) {
      case _mtUint:
        return _readArg(info);
      case _mtBytes:
        final len = _readArg(info);
        return _readBytes(len);
      case _mtText:
        final len = _readArg(info);
        return utf8.decode(_readBytes(len), allowMalformed: false);
      case _mtArray:
        final len = _readArg(info);
        if (len > _maxItems) throw CborError('array too large');
        return _nested(() => [for (var i = 0; i < len; i++) readValue()]);
      case _mtMap:
        final len = _readArg(info);
        if (len > _maxItems) throw CborError('map too large');
        return _nested(() {
          final map = <Object?, Object?>{};
          for (var i = 0; i < len; i++) {
            final key = readValue();
            if (map.containsKey(key)) throw CborError('duplicate map key');
            map[key] = readValue();
          }
          return map;
        });
      default:
        throw CborError('unsupported major type $major');
    }
  }

  T _nested<T>(T Function() body) {
    if (++_depth > _maxDepth) throw CborError('nesting too deep');
    try {
      return body();
    } finally {
      _depth--;
    }
  }

  Uint8List _readBytes(int len) {
    // `len` may be a huge positive from an 8-byte header; compare against the
    // remaining bytes (never `offset + len`, which can overflow to negative and
    // slip past the check → untyped RangeError). INV-6.
    if (len < 0 || len > bytes.length - offset) {
      throw CborError('byte string length out of range');
    }
    final slice = Uint8List.sublistView(bytes, offset, offset + len);
    offset += len;
    return Uint8List.fromList(slice);
  }
}
