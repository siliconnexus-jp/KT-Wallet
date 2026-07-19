import 'dart:typed_data';

/// CRC-32 (IEEE 802.3, reflected) over a byte buffer. Used to verify a
/// reassembled payload before decoding (detailed-design.md §3.2).
int crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// CRC-32 of [data] as 4 big-endian bytes.
Uint8List crc32Bytes(List<int> data) {
  final v = crc32(data);
  return Uint8List.fromList([
    (v >> 24) & 0xFF,
    (v >> 16) & 0xFF,
    (v >> 8) & 0xFF,
    v & 0xFF,
  ]);
}
