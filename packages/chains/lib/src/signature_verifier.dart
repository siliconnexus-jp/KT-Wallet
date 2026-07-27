import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256k1.dart';

import 'base58.dart';
import 'address.dart';
import 'keccak.dart';
import 'sha256.dart';

class SignatureVerificationError implements Exception {
  const SignatureVerificationError(this.message);
  final String message;

  @override
  String toString() => 'SignatureVerificationError: $message';
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
  Chain.avalanche => Future.value(
    _verifyEvm(unsignedTx, signedTx, claimedSigner),
  ),
  Chain.tron => Future.value(_verifyTron(unsignedTx, signedTx, claimedSigner)),
  Chain.solana => _verifySolana(unsignedTx, signedTx, claimedSigner),
};

VerifiedTransaction _verifyEvm(
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
  if (parity < 0 || parity > 1) {
    throw const SignatureVerificationError('invalid recovery parity');
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

/// Pulls `(raw_data, signature)` out of either TRON signed-payload shape.
///
/// The signers emit `{"transaction": "<full signed Transaction protobuf>"}`
/// (what `/wallet/broadcasthex` takes). The older
/// `{"raw_data_hex", "signature": [...]}` shape is still accepted here: a
/// signature is authentic or not regardless of how it was framed, and an
/// offline signer running an older build must still be verifiable.
(Uint8List, Uint8List) _tronRawAndSignature(Map<String, Object?> map) {
  final transaction = map['transaction'];
  if (transaction is String) {
    final (raw, signature) = _decodeTronTransaction(_hexDecode(transaction));
    return (raw, signature);
  }
  final rawHex = map['raw_data_hex'];
  final signatures = map['signature'];
  if (rawHex is! String ||
      signatures is! List ||
      signatures.length != 1 ||
      signatures.first is! String) {
    throw const SignatureVerificationError('incomplete TRON signature');
  }
  return (_hexDecode(rawHex), _hexDecode(signatures.first as String));
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
      if (group & 0x80 == 0) return (result, cursor);
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
    if (byte & 0x80 == 0) return (value: value, next: cursor);
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
