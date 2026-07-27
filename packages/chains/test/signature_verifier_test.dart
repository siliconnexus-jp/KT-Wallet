import 'dart:convert';
import 'dart:typed_data';

import 'package:chains/chains.dart';
import 'package:cryptography/cryptography.dart';
import 'package:pointycastle/export.dart';
import 'package:test/test.dart';

void main() {
  group('EVM signed transaction verification', () {
    test('recovers signer and rejects any changed unsigned field', () async {
      final tx = Eip1559Tx(
        chainId: BigInt.from(11155111),
        nonce: BigInt.from(7),
        maxPriorityFeePerGas: BigInt.from(1500000000),
        maxFeePerGas: BigInt.from(3000000000),
        gasLimit: BigInt.from(21000),
        to: Eip1559Tx.addressBytes(
          '0x000000000000000000000000000000000000dEaD',
        ),
        value: BigInt.from(12345),
        data: Uint8List(0),
      );
      final unsigned = tx.encodeUnsigned();
      final signature = _signSecp256k1(keccak256(unsigned));
      const expectedSigner = '0x7e5f4552091a69125d5dfcb7b8c2659029395bdf';
      final signed = await _evmSignedWithRecovery(
        tx,
        signature,
        expectedSigner,
      );

      final verified = await verifySignedTransaction(
        chain: Chain.ethereum,
        unsignedTx: unsigned,
        signedTx: signed,
        claimedSigner: expectedSigner,
      );
      expect(verified.signer, expectedSigner);
      expect(verified.txHash, startsWith('0x'));

      final changed = Uint8List.fromList(unsigned)..last ^= 1;
      expect(
        () => verifySignedTransaction(
          chain: Chain.ethereum,
          unsignedTx: changed,
          signedTx: signed,
          claimedSigner: expectedSigner,
        ),
        throwsA(isA<SignatureVerificationError>()),
      );
    });
  });

  group('TRON signed transaction verification', () {
    test('recovers Base58Check signer and binds raw_data + txID', () async {
      final unsigned = Uint8List.fromList(
        List<int>.generate(96, (index) => (index * 17) & 0xff),
      );
      final digest = sha256(unsigned);
      final signature = _signSecp256k1(digest);
      final expectedSigner = _privateKeyOneTronAddress();
      final signed = await _tronSignedWithRecovery(
        unsigned,
        digest,
        signature,
        expectedSigner,
      );

      final verified = await verifySignedTransaction(
        chain: Chain.tron,
        unsignedTx: unsigned,
        signedTx: signed,
        claimedSigner: expectedSigner,
      );
      expect(verified.signer, expectedSigner);
      expect(verified.txHash, _hex(digest));

      final decoded = jsonDecode(utf8.decode(signed)) as Map<String, dynamic>;
      decoded['txID'] = List<String>.filled(32, '00').join();
      expect(
        () => verifySignedTransaction(
          chain: Chain.tron,
          unsignedTx: unsigned,
          signedTx: Uint8List.fromList(utf8.encode(jsonEncode(decoded))),
          claimedSigner: expectedSigner,
        ),
        throwsA(isA<SignatureVerificationError>()),
      );
    });

    // The signers emit the broadcasthex shape; verification must accept it,
    // since that is the only payload the online side ever gets to check.
    test('accepts the {transaction} protobuf shape the signers emit', () async {
      final unsigned = Uint8List.fromList(
        List<int>.generate(200, (index) => (index * 13) & 0xff),
      );
      final digest = sha256(unsigned);
      final signature = _signSecp256k1(digest);
      final expectedSigner = _privateKeyOneTronAddress();
      final legacy = await _tronSignedWithRecovery(
        unsigned,
        digest,
        signature,
        expectedSigner,
      );
      final wireSignature = _hexDecode(
        ((jsonDecode(utf8.decode(legacy)) as Map)['signature'] as List).first
            as String,
      );

      // raw_data is 200 bytes here on purpose: its length needs a two-byte
      // varint, which a naive single-byte length would corrupt.
      final protobuf = Uint8List.fromList([
        0x0a, 0xc8, 0x01, ...unsigned, //
        0x12, 0x41, ...wireSignature,
      ]);
      final signed = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'transaction': _hex(protobuf),
            'txID': _hex(digest),
          }),
        ),
      );

      final verified = await verifySignedTransaction(
        chain: Chain.tron,
        unsignedTx: unsigned,
        signedTx: signed,
        claimedSigner: expectedSigner,
      );
      expect(verified.signer, expectedSigner);
      expect(verified.txHash, _hex(digest));
    });

    test('rejects a {transaction} whose raw_data was swapped', () async {
      final unsigned = Uint8List.fromList(
        List<int>.generate(96, (index) => (index * 17) & 0xff),
      );
      final digest = sha256(unsigned);
      final signature = _signSecp256k1(digest);
      final expectedSigner = _privateKeyOneTronAddress();
      final legacy = await _tronSignedWithRecovery(
        unsigned,
        digest,
        signature,
        expectedSigner,
      );
      final wireSignature = _hexDecode(
        ((jsonDecode(utf8.decode(legacy)) as Map)['signature'] as List).first
            as String,
      );

      final tampered = Uint8List.fromList(unsigned)..[0] ^= 0xff;
      final protobuf = Uint8List.fromList([
        0x0a, 96, ...tampered, //
        0x12, 0x41, ...wireSignature,
      ]);
      expect(
        () => verifySignedTransaction(
          chain: Chain.tron,
          unsignedTx: unsigned,
          signedTx: Uint8List.fromList(
            utf8.encode(jsonEncode({'transaction': _hex(protobuf)})),
          ),
          claimedSigner: expectedSigner,
        ),
        throwsA(isA<SignatureVerificationError>()),
      );
    });

    test('rejects a {transaction} with trailing bytes', () async {
      final unsigned = Uint8List.fromList(
        List<int>.generate(96, (index) => (index * 17) & 0xff),
      );
      final digest = sha256(unsigned);
      final signature = _signSecp256k1(digest);
      final expectedSigner = _privateKeyOneTronAddress();
      final legacy = await _tronSignedWithRecovery(
        unsigned,
        digest,
        signature,
        expectedSigner,
      );
      final wireSignature = _hexDecode(
        ((jsonDecode(utf8.decode(legacy)) as Map)['signature'] as List).first
            as String,
      );

      final protobuf = Uint8List.fromList([
        0x0a, 96, ...unsigned, //
        0x12, 0x41, ...wireSignature,
        0x1a, 0x01, 0x00, // an extra field we never wrote
      ]);
      expect(
        () => verifySignedTransaction(
          chain: Chain.tron,
          unsignedTx: unsigned,
          signedTx: Uint8List.fromList(
            utf8.encode(jsonEncode({'transaction': _hex(protobuf)})),
          ),
          claimedSigner: expectedSigner,
        ),
        throwsA(isA<SignatureVerificationError>()),
      );
    });
  });

  group('Solana signed transaction verification', () {
    test('accepts the exact message signed by its fee payer', () async {
      final algorithm = Ed25519();
      final keyPair = await algorithm.newKeyPairFromSeed(
        List<int>.generate(32, (index) => index + 1),
      );
      final publicKey = await keyPair.extractPublicKey();
      final signer = base58Encode(Uint8List.fromList(publicKey.bytes));
      final message = SolanaMessage.systemTransfer(
        from: signer,
        to: '11111111111111111111111111111111',
        lamports: BigInt.one,
        recentBlockhash: '11111111111111111111111111111111',
      ).serialize();
      final signature = await algorithm.sign(message, keyPair: keyPair);
      final wire = Uint8List.fromList([1, ...signature.bytes, ...message]);

      final verified = await verifySignedTransaction(
        chain: Chain.solana,
        unsignedTx: message,
        signedTx: wire,
        claimedSigner: signer,
      );

      expect(verified.signer, signer);
      expect(
        verified.txHash,
        base58Encode(Uint8List.fromList(signature.bytes)),
      );
    });

    test('rejects a transaction whose message changed after signing', () async {
      final algorithm = Ed25519();
      final keyPair = await algorithm.newKeyPairFromSeed(
        List<int>.filled(32, 7),
      );
      final publicKey = await keyPair.extractPublicKey();
      final signer = base58Encode(Uint8List.fromList(publicKey.bytes));
      final message = SolanaMessage.systemTransfer(
        from: signer,
        to: '11111111111111111111111111111111',
        lamports: BigInt.one,
        recentBlockhash: '11111111111111111111111111111111',
      ).serialize();
      final signature = await algorithm.sign(message, keyPair: keyPair);
      final modified = Uint8List.fromList(message)..last ^= 1;
      final wire = Uint8List.fromList([1, ...signature.bytes, ...modified]);

      expect(
        () => verifySignedTransaction(
          chain: Chain.solana,
          unsignedTx: message,
          signedTx: wire,
          claimedSigner: signer,
        ),
        throwsA(isA<SignatureVerificationError>()),
      );
    });

    test('rejects a forged claimed signer', () async {
      final algorithm = Ed25519();
      final keyPair = await algorithm.newKeyPairFromSeed(
        List<int>.filled(32, 9),
      );
      final publicKey = await keyPair.extractPublicKey();
      final signer = base58Encode(Uint8List.fromList(publicKey.bytes));
      final message = SolanaMessage.systemTransfer(
        from: signer,
        to: '11111111111111111111111111111111',
        lamports: BigInt.one,
        recentBlockhash: '11111111111111111111111111111111',
      ).serialize();
      final signature = await algorithm.sign(message, keyPair: keyPair);
      final wire = Uint8List.fromList([1, ...signature.bytes, ...message]);

      expect(
        () => verifySignedTransaction(
          chain: Chain.solana,
          unsignedTx: message,
          signedTx: wire,
          claimedSigner: '11111111111111111111111111111111',
        ),
        throwsA(isA<SignatureVerificationError>()),
      );
    });
  });
}

ECSignature _signSecp256k1(Uint8List digest) {
  final params = ECCurve_secp256k1();
  final signer = ECDSASigner(null, HMac(SHA256Digest(), 64))
    ..init(
      true,
      PrivateKeyParameter<ECPrivateKey>(ECPrivateKey(BigInt.one, params)),
    );
  return signer.generateSignature(digest) as ECSignature;
}

Future<Uint8List> _evmSignedWithRecovery(
  Eip1559Tx tx,
  ECSignature signature,
  String expectedSigner,
) async {
  for (var parity = 0; parity < 2; parity++) {
    final signed = Uint8List.fromList([
      Eip1559Tx.txType,
      ...Rlp.encodeList([
        Rlp.encodeBigInt(tx.chainId),
        Rlp.encodeBigInt(tx.nonce),
        Rlp.encodeBigInt(tx.maxPriorityFeePerGas),
        Rlp.encodeBigInt(tx.maxFeePerGas),
        Rlp.encodeBigInt(tx.gasLimit),
        Rlp.encodeBytes(tx.to ?? Uint8List(0)),
        Rlp.encodeBigInt(tx.value),
        Rlp.encodeBytes(tx.data),
        Rlp.encodeList(const []),
        Rlp.encodeBigInt(BigInt.from(parity)),
        Rlp.encodeBigInt(signature.r),
        Rlp.encodeBigInt(signature.s),
      ]),
    ]);
    try {
      await verifySignedTransaction(
        chain: Chain.ethereum,
        unsignedTx: tx.encodeUnsigned(),
        signedTx: signed,
        claimedSigner: expectedSigner,
      );
      return signed;
    } on SignatureVerificationError {
      // Try the other recovery parity.
    }
  }
  throw StateError('no EVM recovery parity matched');
}

Future<Uint8List> _tronSignedWithRecovery(
  Uint8List unsigned,
  Uint8List digest,
  ECSignature signature,
  String expectedSigner,
) async {
  for (var recovery = 0; recovery < 4; recovery++) {
    final wireSignature = Uint8List.fromList([
      ..._leftPad32(signature.r),
      ..._leftPad32(signature.s),
      recovery,
    ]);
    final signed = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'raw_data_hex': _hex(unsigned),
          'signature': [_hex(wireSignature)],
          'txID': _hex(digest),
        }),
      ),
    );
    try {
      await verifySignedTransaction(
        chain: Chain.tron,
        unsignedTx: unsigned,
        signedTx: signed,
        claimedSigner: expectedSigner,
      );
      return signed;
    } on SignatureVerificationError {
      // Try the next SEC1 recovery id.
    }
  }
  throw StateError('no TRON recovery id matched');
}

String _privateKeyOneTronAddress() {
  final publicKey = ECCurve_secp256k1().G.getEncoded(false);
  final body = keccak256(Uint8List.sublistView(publicKey, 1)).sublist(12);
  final payload = Uint8List.fromList([0x41, ...body]);
  final checksum = sha256(sha256(payload)).sublist(0, 4);
  return base58Encode(Uint8List.fromList([...payload, ...checksum]));
}

Uint8List _leftPad32(BigInt value) {
  final raw = Rlp.bigIntBytes(value);
  return Uint8List.fromList([...List<int>.filled(32 - raw.length, 0), ...raw]);
}

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

Uint8List _hexDecode(String hex) => Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
