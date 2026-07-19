import 'dart:typed_data';

/// Self-contained Keccak-256 (the pre-NIST padding used by Ethereum), needed
/// for EIP-55 address checksums and ERC-20 calldata. Kept dependency-free.
///
/// Operates on 64-bit lanes via a (hi, lo) 32-bit split so it works correctly
/// on the web (JS) target too, where ints are 53-bit.
Uint8List keccak256(List<int> input) {
  final k = _Keccak();
  k.absorb(Uint8List.fromList(input));
  return k.squeeze();
}

class _Keccak {
  // 25 lanes × (hi, lo) 32-bit halves.
  final _hi = Int32List(25);
  final _lo = Int32List(25);
  static const int _rate = 136; // 1088 bits for keccak-256

  void absorb(Uint8List data) {
    var offset = 0;
    // Full blocks.
    while (data.length - offset >= _rate) {
      _xorBlock(data, offset, _rate);
      _permute();
      offset += _rate;
    }
    // Final block with Keccak padding 0x01 … 0x80.
    final block = Uint8List(_rate);
    final remaining = data.length - offset;
    block.setRange(0, remaining, data, offset);
    block[remaining] = 0x01;
    block[_rate - 1] |= 0x80;
    _xorBlock(block, 0, _rate);
    _permute();
  }

  Uint8List squeeze() {
    final out = Uint8List(32);
    for (var i = 0; i < 4; i++) {
      final lo = _lo[i];
      final hi = _hi[i];
      out[i * 8 + 0] = lo & 0xFF;
      out[i * 8 + 1] = (lo >> 8) & 0xFF;
      out[i * 8 + 2] = (lo >> 16) & 0xFF;
      out[i * 8 + 3] = (lo >> 24) & 0xFF;
      out[i * 8 + 4] = hi & 0xFF;
      out[i * 8 + 5] = (hi >> 8) & 0xFF;
      out[i * 8 + 6] = (hi >> 16) & 0xFF;
      out[i * 8 + 7] = (hi >> 24) & 0xFF;
    }
    return out;
  }

  void _xorBlock(Uint8List data, int offset, int len) {
    for (var i = 0; i < len ~/ 8; i++) {
      final b = offset + i * 8;
      _lo[i] ^= data[b] |
          (data[b + 1] << 8) |
          (data[b + 2] << 16) |
          (data[b + 3] << 24);
      _hi[i] ^= data[b + 4] |
          (data[b + 5] << 8) |
          (data[b + 6] << 16) |
          (data[b + 7] << 24);
    }
  }

  static const _rc = [
    [0x00000000, 0x00000001], [0x00000000, 0x00008082],
    [0x80000000, 0x0000808a], [0x80000000, 0x80008000],
    [0x00000000, 0x0000808b], [0x00000000, 0x80000001],
    [0x80000000, 0x80008081], [0x80000000, 0x00008009],
    [0x00000000, 0x0000008a], [0x00000000, 0x00000088],
    [0x00000000, 0x80008009], [0x00000000, 0x8000000a],
    [0x00000000, 0x8000808b], [0x80000000, 0x0000008b],
    [0x80000000, 0x00008089], [0x80000000, 0x00008003],
    [0x80000000, 0x00008002], [0x80000000, 0x00000080],
    [0x00000000, 0x0000800a], [0x80000000, 0x8000000a],
    [0x80000000, 0x80008081], [0x80000000, 0x00008080],
    [0x00000000, 0x80000001], [0x80000000, 0x80008008],
  ];

  static const _rot = [
    0, 1, 62, 28, 27, 36, 44, 6, 55, 20, 3, 10, 43, //
    25, 39, 41, 45, 15, 21, 8, 18, 2, 61, 56, 14
  ];

  void _permute() {
    for (var round = 0; round < 24; round++) {
      // Theta.
      final cHi = Int32List(5), cLo = Int32List(5);
      for (var x = 0; x < 5; x++) {
        cHi[x] = _hi[x] ^ _hi[x + 5] ^ _hi[x + 10] ^ _hi[x + 15] ^ _hi[x + 20];
        cLo[x] = _lo[x] ^ _lo[x + 5] ^ _lo[x + 10] ^ _lo[x + 15] ^ _lo[x + 20];
      }
      for (var x = 0; x < 5; x++) {
        final dHi = cHi[(x + 4) % 5] ^ _rotl32Hi(cHi[(x + 1) % 5], cLo[(x + 1) % 5], 1);
        final dLo = cLo[(x + 4) % 5] ^ _rotl32Lo(cHi[(x + 1) % 5], cLo[(x + 1) % 5], 1);
        for (var y = 0; y < 25; y += 5) {
          _hi[x + y] ^= dHi;
          _lo[x + y] ^= dLo;
        }
      }
      // Rho + Pi.
      final bHi = Int32List(25), bLo = Int32List(25);
      for (var i = 0; i < 25; i++) {
        final x = i % 5, y = i ~/ 5;
        final ni = y + ((2 * x + 3 * y) % 5) * 5;
        bHi[ni] = _rotl32Hi(_hi[i], _lo[i], _rot[i]);
        bLo[ni] = _rotl32Lo(_hi[i], _lo[i], _rot[i]);
      }
      // Chi.
      for (var y = 0; y < 25; y += 5) {
        for (var x = 0; x < 5; x++) {
          _hi[x + y] = bHi[x + y] ^ (~bHi[(x + 1) % 5 + y] & bHi[(x + 2) % 5 + y]);
          _lo[x + y] = bLo[x + y] ^ (~bLo[(x + 1) % 5 + y] & bLo[(x + 2) % 5 + y]);
        }
      }
      // Iota.
      _hi[0] ^= _rc[round][0];
      _lo[0] ^= _rc[round][1];
    }
  }

  // 64-bit rotate-left on the (hi, lo) split.
  static int _rotl32Hi(int hi, int lo, int n) {
    n %= 64;
    if (n == 0) return hi;
    if (n < 32) {
      return ((hi << n) | (_ushr(lo, 32 - n))).toSigned(32);
    }
    if (n == 32) return lo;
    return ((lo << (n - 32)) | (_ushr(hi, 64 - n))).toSigned(32);
  }

  static int _rotl32Lo(int hi, int lo, int n) {
    n %= 64;
    if (n == 0) return lo;
    if (n < 32) {
      return ((lo << n) | (_ushr(hi, 32 - n))).toSigned(32);
    }
    if (n == 32) return hi;
    return ((hi << (n - 32)) | (_ushr(lo, 64 - n))).toSigned(32);
  }

  static int _ushr(int v, int n) => (v & 0xFFFFFFFF) >>> n;
}
