import 'dart:typed_data';

/// Canonical RLP (Recursive Length Prefix) encoding — the serialization used
/// by EVM transactions (Ethereum yellow paper, appendix B). Encoding only:
/// the wallet builds unsigned payloads and the offline signer rebuilds them
/// from the same fields, so no decoder is needed. Kept dependency-free like
/// keccak.
abstract final class Rlp {
  /// Encodes a byte string. A single byte < 0x80 is its own encoding; short
  /// strings (0–55 bytes) get a `0x80 + length` header; longer strings a
  /// `0xb7 + lengthOfLength` header followed by the big-endian length.
  static Uint8List encodeBytes(List<int> bytes) {
    if (bytes.length == 1 && bytes[0] < 0x80) {
      return Uint8List.fromList(bytes);
    }
    final out = BytesBuilder();
    out.add(_header(bytes.length, 0x80));
    out.add(bytes);
    return out.toBytes();
  }

  /// Encodes a list from its already-encoded items; nest by calling again on
  /// the result. Short payloads (0–55 bytes) get a `0xc0 + length` header,
  /// longer ones `0xf7 + lengthOfLength` followed by the big-endian length.
  static Uint8List encodeList(List<Uint8List> encodedItems) {
    final payload = BytesBuilder();
    for (final item in encodedItems) {
      payload.add(item);
    }
    final body = payload.toBytes();
    final out = BytesBuilder();
    out.add(_header(body.length, 0xc0));
    out.add(body);
    return out.toBytes();
  }

  /// Encodes a non-negative integer as its minimal big-endian byte string
  /// (RLP's canonical scalar form: no leading zeros, zero → empty string).
  static Uint8List encodeBigInt(BigInt value) => encodeBytes(bigIntBytes(value));

  /// Minimal big-endian bytes of a non-negative [BigInt]: no leading zeros,
  /// zero → empty. Throws on negative values (RLP has no signed scalars).
  static Uint8List bigIntBytes(BigInt value) {
    if (value < BigInt.zero) {
      throw ArgumentError('RLP scalars are non-negative: $value');
    }
    if (value == BigInt.zero) return Uint8List(0);
    final bytes = <int>[];
    final mask = BigInt.from(0xFF);
    var x = value;
    while (x > BigInt.zero) {
      bytes.add((x & mask).toInt());
      x = x >> 8;
    }
    return Uint8List.fromList(bytes.reversed.toList());
  }

  /// Length header for strings ([shortOffset] 0x80) or lists (0xc0).
  static Uint8List _header(int length, int shortOffset) {
    if (length <= 55) {
      return Uint8List.fromList([shortOffset + length]);
    }
    final lenBytes = bigIntBytes(BigInt.from(length));
    return Uint8List.fromList(
        [shortOffset + 55 + lenBytes.length, ...lenBytes]);
  }
}
