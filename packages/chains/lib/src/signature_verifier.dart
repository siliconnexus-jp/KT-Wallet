import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256k1.dart';

import 'base58.dart';
import 'address.dart';
import 'keccak.dart';
import 'rlp.dart';
import 'sha256.dart';
import 'transaction_parser.dart';

class SignatureVerificationError implements Exception {
  const SignatureVerificationError(this.message);
  final String message;

  @override
  String toString() => 'SignatureVerificationError: $message';
}

/// Validates an uncompressed SEC1 public key on secp256k1.
///
/// Length/prefix checks alone are insufficient: arbitrary x/y bytes can be
/// hashed into an apparently matching address even when they are not a point
/// on the curve. Pairing code uses this before accepting exported public keys.
bool isValidSecp256k1PublicKey(List<int> encoded) {
  if (encoded.length != 65 || encoded.first != 0x04) return false;
  try {
    final params = ECCurve_secp256k1();
    final point = params.curve.decodePoint(encoded);
    if (point == null ||
        point.isInfinity ||
        point.x == null ||
        point.y == null) {
      return false;
    }
    final x = point.x!;
    final y = point.y!;
    final curve = params.curve;
    final left = y.square();
    final right = (x.square() * x) + (curve.a! * x) + curve.b!;
    if (left != right) return false;
    return (point * params.n)?.isInfinity ?? false;
  } on Object {
    return false;
  }
}

class VerifiedTransaction {
  const VerifiedTransaction({required this.signer, required this.txHash});

  final String signer;
  final String txHash;
}

/// Verifies that [signedTx] signs exactly [unsignedTx], recovers/derives the
/// signer from the signature itself, and compares it with [claimedSigner].
///
/// This function deliberately has no RPC dependency and is safe for the
/// online QR-ingestion path before any transaction is broadcast.
Future<VerifiedTransaction> verifySignedTransaction({
  required Chain chain,
  required Uint8List unsignedTx,
  required Uint8List signedTx,
  required String claimedSigner,
}) => switch (chain) {
  Chain.ethereum ||
  Chain.polygon ||
  Chain.base ||
  Chain.arbitrum ||
  Chain.avalanche ||
  Chain.bnb => Future.value(
    _verifyEvm(chain, unsignedTx, signedTx, claimedSigner),
  ),
  Chain.tron => Future.value(_verifyTron(unsignedTx, signedTx, claimedSigner)),
  Chain.solana => _verifySolana(unsignedTx, signedTx, claimedSigner),
};

VerifiedTransaction _verifyEvm(
  Chain chain,
  Uint8List unsigned,
  Uint8List signed,
  String claimed,
) {
  if (unsigned.isEmpty ||
      unsigned.first != 0x02 ||
      signed.isEmpty ||
      signed.first != 0x02) {
    throw const SignatureVerificationError('expected EIP-1559 transaction');
  }
  try {
    parseUnsignedTransfer(chain, unsigned);
  } on Object {
    throw const SignatureVerificationError(
      'unsupported or non-canonical EIP-1559 transaction',
    );
  }
  final unsignedList = _decodeRlpList(unsigned, 1);
  final signedList = _decodeRlpList(signed, 1);
  if (unsignedList.length != 9 || signedList.length != 12) {
    throw const SignatureVerificationError('invalid EIP-1559 field count');
  }
  for (var i = 0; i < 9; i++) {
    if (!_bytesEqual(unsignedList[i].encoded, signedList[i].encoded)) {
      throw SignatureVerificationError('signed field $i was modified');
    }
  }
  final parity = _scalar(signedList[9].payload).toInt();
  final r = _scalar(signedList[10].payload);
  final s = _scalar(signedList[11].payload);
  if (signedList[9].isList || signedList[10].isList || signedList[11].isList) {
    throw const SignatureVerificationError('signature scalar cannot be a list');
  }
  if (parity < 0 || parity > 1) {
    throw const SignatureVerificationError('invalid recovery parity');
  }
  final params = ECCurve_secp256k1();
  if (s > (params.n >> 1)) {
    throw const SignatureVerificationError('non-canonical high-s signature');
  }
  final canonicalSigned = Uint8List.fromList([
    0x02,
    ...Rlp.encodeList([
      for (var i = 0; i < 9; i++) signedList[i].encoded,
      Rlp.encodeBigInt(BigInt.from(parity)),
      Rlp.encodeBigInt(r),
      Rlp.encodeBigInt(s),
    ]),
  ]);
  if (!_bytesEqual(canonicalSigned, signed)) {
    throw const SignatureVerificationError(
      'non-canonical EIP-1559 signed transaction',
    );
  }
  final publicKey = _recoverSecp256k1(keccak256(unsigned), r, s, parity);
  final encoded = publicKey.getEncoded(false);
  final addressBytes = keccak256(Uint8List.sublistView(encoded, 1)).sublist(12);
  final signer = '0x${_hex(addressBytes)}';
  if (signer.toLowerCase() != claimed.toLowerCase()) {
    throw const SignatureVerificationError('EVM signer mismatch');
  }
  return VerifiedTransaction(
    signer: signer,
    txHash: '0x${_hex(keccak256(signed))}',
  );
}

/// Pulls `(raw_data, signature)` out of the canonical TRON AIRGAP-V1 result.
///
/// The signers emit `{"transaction": "<full signed Transaction protobuf>"}`
/// (what `/wallet/broadcasthex` takes). An old `raw_data_hex + signature`
/// fragment is deliberately rejected: it is not a complete object accepted
/// by the direct broadcast endpoint and must not pass verification only to
/// fail later or acquire extra broadcast-time fields.
(Uint8List, Uint8List) _tronRawAndSignature(Map<String, Object?> map) {
  if (map.keys.any((key) => key != 'transaction' && key != 'txID')) {
    throw const SignatureVerificationError('unknown TRON signed field');
  }
  final transaction = map['transaction'];
  if (transaction is String) {
    final (raw, signature) = _decodeTronTransaction(_hexDecode(transaction));
    return (raw, signature);
  }
  throw const SignatureVerificationError(
    'expected full signed TRON transaction',
  );
}

/// Reads `Transaction { raw_data = 1; repeated signature = 2; }` — exactly the
/// two length-delimited fields the signers write, in that order, nothing else.
/// V1 accepts a single signature, matching the single-signer policy enforced
/// on every other chain.
(Uint8List, Uint8List) _decodeTronTransaction(Uint8List bytes) {
  var offset = 0;

  (int, int) readVarint(int at) {
    var result = 0;
    var shift = 0;
    var cursor = at;
    while (true) {
      if (cursor >= bytes.length || shift > 28) {
        throw const SignatureVerificationError('invalid TRON transaction');
      }
      final group = bytes[cursor++];
      result |= (group & 0x7f) << shift;
      if (group & 0x80 == 0) {
        if (cursor - at > 1 && group == 0) {
          throw const SignatureVerificationError(
            'non-canonical TRON transaction',
          );
        }
        return (result, cursor);
      }
      shift += 7;
    }
  }

  Uint8List readField(int tag) {
    if (offset >= bytes.length || bytes[offset] != tag) {
      throw const SignatureVerificationError('invalid TRON transaction');
    }
    final (length, after) = readVarint(offset + 1);
    if (length < 0 || after + length > bytes.length) {
      throw const SignatureVerificationError('invalid TRON transaction');
    }
    offset = after + length;
    return Uint8List.sublistView(bytes, after, offset);
  }

  final raw = readField(0x0a);
  final signature = readField(0x12);
  if (offset != bytes.length) {
    // Trailing bytes would mean extra signatures or unknown fields; either way
    // this is not the payload we signed.
    throw const SignatureVerificationError('invalid TRON transaction');
  }
  return (raw, signature);
}

VerifiedTransaction _verifyTron(
  Uint8List unsigned,
  Uint8List signed,
  String claimed,
) {
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(signed));
  } catch (_) {
    throw const SignatureVerificationError('invalid TRON signed JSON');
  }
  if (decoded is! Map) {
    throw const SignatureVerificationError('invalid TRON signed payload');
  }
  final map = decoded.cast<String, Object?>();
  final (raw, signature) = _tronRawAndSignature(map);
  if (!_bytesEqual(raw, unsigned)) {
    throw const SignatureVerificationError('TRON raw_data was modified');
  }
  if (signature.length != 65) {
    throw const SignatureVerificationError('invalid TRON signature length');
  }
  final txIdBytes = sha256(unsigned);
  final r = _scalar(Uint8List.sublistView(signature, 0, 32));
  final s = _scalar(Uint8List.sublistView(signature, 32, 64));
  final recovery = signature[64];
  if (recovery > 3) {
    throw const SignatureVerificationError('invalid TRON recovery id');
  }
  if (s > (ECCurve_secp256k1().n >> 1)) {
    throw const SignatureVerificationError('non-canonical high-s signature');
  }
  final publicKey = _recoverSecp256k1(txIdBytes, r, s, recovery);
  final encoded = publicKey.getEncoded(false);
  final body = keccak256(Uint8List.sublistView(encoded, 1)).sublist(12);
  final payload = Uint8List.fromList([0x41, ...body]);
  final checksum = sha256(sha256(payload)).sublist(0, 4);
  final signer = base58Encode(Uint8List.fromList([...payload, ...checksum]));
  if (signer != claimed) {
    throw const SignatureVerificationError('TRON signer mismatch');
  }
  final txId = _hex(txIdBytes);
  if (map['txID'] != null && map['txID'] != txId) {
    throw const SignatureVerificationError('TRON txID mismatch');
  }
  return VerifiedTransaction(signer: signer, txHash: txId);
}

Future<VerifiedTransaction> _verifySolana(
  Uint8List unsigned,
  Uint8List signed,
  String claimed,
) async {
  if (signed.length != unsigned.length + 65 || signed.first != 1) {
    throw const SignatureVerificationError('invalid Solana transaction');
  }
  final signature = Uint8List.sublistView(signed, 1, 65);
  final message = Uint8List.sublistView(signed, 65);
  if (!_bytesEqual(message, unsigned) || message.length < 36) {
    throw const SignatureVerificationError('Solana message was modified');
  }
  // Legacy message: 3-byte header, compact-u16 key count, then key[0] is the
  // writable fee payer and sole signer accepted by V1.
  if (message[0] != 1) {
    throw const SignatureVerificationError('unsupported Solana signer count');
  }
  final count = _shortVec(message, 3);
  if (count.value < 1 || count.next + 32 > message.length) {
    throw const SignatureVerificationError('invalid Solana account keys');
  }
  final publicKey = Uint8List.sublistView(message, count.next, count.next + 32);
  final signer = base58Encode(publicKey);
  if (signer != claimed) {
    throw const SignatureVerificationError('Solana fee payer mismatch');
  }
  final ok = await Ed25519().verify(
    message,
    signature: Signature(
      signature,
      publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
    ),
  );
  if (!ok) {
    throw const SignatureVerificationError('invalid Solana signature');
  }
  return VerifiedTransaction(signer: signer, txHash: base58Encode(signature));
}

ECPoint _recoverSecp256k1(
  Uint8List digest,
  BigInt r,
  BigInt s,
  int recoveryId,
) {
  try {
    final params = ECCurve_secp256k1();
    final n = params.n;
    if (r <= BigInt.zero || r >= n || s <= BigInt.zero || s >= n) {
      throw const SignatureVerificationError('invalid secp256k1 scalar');
    }
    final x = r + BigInt.from(recoveryId ~/ 2) * n;
    final point = params.curve.decompressPoint(recoveryId & 1, x);
    if (!(point * n)!.isInfinity) {
      throw const SignatureVerificationError('invalid recovery point');
    }
    final e = _scalar(digest);
    final rInv = r.modInverse(n);
    final q = ((point * (s * rInv % n))! - (params.G * (e * rInv % n))!)!;
    if (q.isInfinity) {
      throw const SignatureVerificationError('recovered infinity signer');
    }
    return q;
  } on SignatureVerificationError {
    rethrow;
  } on Object {
    throw const SignatureVerificationError('invalid recovery point');
  }
}

class _RlpItem {
  const _RlpItem({
    required this.payload,
    required this.encoded,
    required this.isList,
    required this.next,
  });
  final Uint8List payload;
  final Uint8List encoded;
  final bool isList;
  final int next;
}

List<_RlpItem> _decodeRlpList(Uint8List bytes, int offset) {
  final outer = _readRlp(bytes, offset);
  if (!outer.isList || outer.next != bytes.length) {
    throw const SignatureVerificationError('invalid RLP list');
  }
  final fields = <_RlpItem>[];
  var cursor = 0;
  while (cursor < outer.payload.length) {
    final item = _readRlp(outer.payload, cursor);
    fields.add(item);
    cursor = item.next;
  }
  return fields;
}

_RlpItem _readRlp(Uint8List source, int offset) {
  if (offset < 0 || offset >= source.length) {
    throw const SignatureVerificationError('RLP out of bounds');
  }
  final prefix = source[offset];
  if (prefix <= 0x7f) {
    return _RlpItem(
      payload: Uint8List.fromList([prefix]),
      encoded: Uint8List.fromList([prefix]),
      isList: false,
      next: offset + 1,
    );
  }
  final isList = prefix >= 0xc0;
  final shortBase = isList ? 0xc0 : 0x80;
  final longBase = isList ? 0xf7 : 0xb7;
  int header;
  int length;
  if (prefix <= longBase) {
    header = 1;
    length = prefix - shortBase;
  } else {
    final lengthBytes = prefix - longBase;
    if (lengthBytes < 1 ||
        lengthBytes > 4 ||
        offset + 1 + lengthBytes > source.length) {
      throw const SignatureVerificationError('invalid RLP length');
    }
    header = 1 + lengthBytes;
    length = 0;
    for (var i = 0; i < lengthBytes; i++) {
      length = (length << 8) | source[offset + 1 + i];
    }
  }
  final start = offset + header;
  final end = start + length;
  if (end > source.length) {
    throw const SignatureVerificationError('invalid RLP bounds');
  }
  return _RlpItem(
    payload: Uint8List.sublistView(source, start, end),
    encoded: Uint8List.sublistView(source, offset, end),
    isList: isList,
    next: end,
  );
}

({int value, int next}) _shortVec(Uint8List bytes, int offset) {
  var value = 0;
  var shift = 0;
  var cursor = offset;
  while (cursor < bytes.length && shift <= 14) {
    final byte = bytes[cursor++];
    value |= (byte & 0x7f) << shift;
    if (byte & 0x80 == 0) {
      final count = cursor - offset;
      if ((count > 1 && byte == 0) || (count == 3 && byte > 3)) {
        throw const SignatureVerificationError('non-canonical shortvec');
      }
      return (value: value, next: cursor);
    }
    shift += 7;
  }
  throw const SignatureVerificationError('invalid shortvec');
}

BigInt _scalar(List<int> bytes) {
  var value = BigInt.zero;
  for (final byte in bytes) {
    value = (value << 8) | BigInt.from(byte);
  }
  return value;
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _hexDecode(String value) {
  if (value.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(value)) {
    throw const SignatureVerificationError('invalid hex');
  }
  return Uint8List.fromList([
    for (var i = 0; i < value.length; i += 2)
      int.parse(value.substring(i, i + 2), radix: 16),
  ]);
}
