import 'dart:typed_data';

/// Bitcoin/Base58 alphabet, used by TRON and Solana addresses.
const _alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
final Map<String, int> _index = {
  for (var i = 0; i < _alphabet.length; i++) _alphabet[i]: i,
};

class Base58Error implements Exception {
  Base58Error(this.message);
  final String message;
  @override
  String toString() => 'Base58Error: $message';
}

/// Decodes a Base58 string to bytes. Throws [Base58Error] on any invalid
/// character (total: never crashes on hostile input).
Uint8List base58Decode(String input) {
  if (input.isEmpty) throw Base58Error('empty');
  var intVal = BigInt.zero;
  final radix = BigInt.from(58);
  for (final ch in input.split('')) {
    final digit = _index[ch];
    if (digit == null) throw Base58Error('invalid character "$ch"');
    intVal = intVal * radix + BigInt.from(digit);
  }
  // Convert big integer to bytes (big-endian).
  final bytes = <int>[];
  var v = intVal;
  final b256 = BigInt.from(256);
  while (v > BigInt.zero) {
    bytes.insert(0, (v % b256).toInt());
    v = v ~/ b256;
  }
  // Restore leading zero bytes (encoded as '1').
  for (final ch in input.split('')) {
    if (ch == '1') {
      bytes.insert(0, 0);
    } else {
      break;
    }
  }
  return Uint8List.fromList(bytes);
}

/// Encodes bytes to a Base58 string.
String base58Encode(Uint8List bytes) {
  var intVal = BigInt.zero;
  for (final b in bytes) {
    intVal = intVal * BigInt.from(256) + BigInt.from(b);
  }
  final out = StringBuffer();
  final radix = BigInt.from(58);
  while (intVal > BigInt.zero) {
    final rem = (intVal % radix).toInt();
    out.write(_alphabet[rem]);
    intVal = intVal ~/ radix;
  }
  for (final b in bytes) {
    if (b == 0) {
      out.write('1');
    } else {
      break;
    }
  }
  return out.toString().split('').reversed.join();
}
