import 'dart:typed_data';

import 'crc32.dart';

/// Splits a payload into animated-QR frames and parses frames back
/// (detailed-design.md §3.2). Frame byte layout:
///
///   magic  2B  'K','T'
///   ver    1B  0x01
///   reqId  8B  request id (walletId-hash for account-export)
///   seq    2B  big-endian, from 0
///   total  2B  big-endian, 1..256
///   crc32  4B  CRC of the whole reassembled payload
///   chunk  <=chunkSize
class FragmentError implements Exception {
  FragmentError(this.message);
  final String message;
  @override
  String toString() => 'FragmentError: $message';
}

class AirgapFrame {
  AirgapFrame({
    required this.reqId,
    required this.seq,
    required this.total,
    required this.crc,
    required this.chunk,
  });

  final Uint8List reqId; // 8 bytes
  final int seq;
  final int total;
  final int crc;
  final Uint8List chunk;

  static const magic0 = 0x4B; // 'K'
  static const magic1 = 0x54; // 'T'
  static const version = 0x01;
  static const headerLength = 2 + 1 + 8 + 2 + 2 + 4;
  static const maxTotal = 256;

  Uint8List encode() {
    final out = BytesBuilder();
    out.addByte(magic0);
    out.addByte(magic1);
    out.addByte(version);
    out.add(reqId);
    out.addByte((seq >> 8) & 0xFF);
    out.addByte(seq & 0xFF);
    out.addByte((total >> 8) & 0xFF);
    out.addByte(total & 0xFF);
    out.addByte((crc >> 24) & 0xFF);
    out.addByte((crc >> 16) & 0xFF);
    out.addByte((crc >> 8) & 0xFF);
    out.addByte(crc & 0xFF);
    out.add(chunk);
    return out.toBytes();
  }

  /// Parses one frame. Throws [FragmentError] on any structural problem so a
  /// hostile/garbage QR can never crash the scanner (DD §8.6).
  static AirgapFrame decode(Uint8List bytes) {
    if (bytes.length < headerLength) {
      throw FragmentError('frame shorter than header');
    }
    if (bytes[0] != magic0 || bytes[1] != magic1) {
      throw FragmentError('bad magic');
    }
    if (bytes[2] != version) {
      throw FragmentError('unsupported frame version ${bytes[2]}');
    }
    final reqId = Uint8List.fromList(bytes.sublist(3, 11));
    final seq = (bytes[11] << 8) | bytes[12];
    final total = (bytes[13] << 8) | bytes[14];
    final crc =
        (bytes[15] << 24) | (bytes[16] << 16) | (bytes[17] << 8) | bytes[18];
    if (total < 1 || total > maxTotal) {
      throw FragmentError('total out of range: $total');
    }
    if (seq >= total) {
      throw FragmentError('seq $seq >= total $total');
    }
    final chunk = Uint8List.fromList(bytes.sublist(headerLength));
    return AirgapFrame(
      reqId: reqId, seq: seq, total: total, crc: crc & 0xFFFFFFFF, chunk: chunk);
  }
}

class Fragmenter {
  Fragmenter({this.chunkSize = 400})
      : assert(chunkSize > 0, 'chunkSize must be positive');

  /// Chunk payload byte budget per frame. Default calibrated for mid-range
  /// phone scan reliability (DD §3.2); overridable after P7 field tuning.
  final int chunkSize;

  static const maxPayload = 64 * 1024;

  /// Produces the ordered frame set for [payload]. The animated QR loops over
  /// this list; the same [reqId] is stamped on every frame.
  List<AirgapFrame> fragment(Uint8List payload, {required Uint8List reqId}) {
    if (reqId.length != 8) throw FragmentError('reqId must be 8 bytes');
    if (payload.length > maxPayload) {
      throw FragmentError('payload exceeds 64KB');
    }
    final crc = crc32(payload);
    final total = payload.isEmpty
        ? 1
        : (payload.length + chunkSize - 1) ~/ chunkSize;
    if (total > AirgapFrame.maxTotal) {
      throw FragmentError('payload needs $total frames (>256)');
    }
    return [
      for (var seq = 0; seq < total; seq++)
        AirgapFrame(
          reqId: reqId,
          seq: seq,
          total: total,
          crc: crc,
          chunk: Uint8List.fromList(
            payload.sublist(
              seq * chunkSize,
              ((seq + 1) * chunkSize).clamp(0, payload.length),
            ),
          ),
        ),
    ];
  }
}
