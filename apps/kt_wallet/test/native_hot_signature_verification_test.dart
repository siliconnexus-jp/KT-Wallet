import 'dart:typed_data';

import 'package:chains/chains.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:core_crypto/testing.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/transfer/broadcast_service.dart';
import 'package:kt_wallet/src/transfer/local_transfer_service.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';

const _evmAddress = '0x70997970C51812dc3A010C7d01b50e0d17dc79C8';
const _tronAddress = 'TNXoiAJ3dct8Fjg4M9fkLFh9S2v9TXc32G';

HotWallet _wallet({required String solana}) => HotWallet(
  id: 'wallet-1',
  name: 'Test',
  avatarColor: 0,
  addresses: ChainAddresses(
    eth: _evmAddress,
    polygon: _evmAddress,
    tron: _tronAddress,
    solana: solana,
  ),
);

class _FixedSigningCrypto extends MockCoreCrypto {
  _FixedSigningCrypto(this.result);

  final SignedTransaction result;

  @override
  Future<SignedTransaction> signTransaction({
    required String walletId,
    required Coin coin,
    required Uint8List signingInput,
  }) async => result;
}

class _Ed25519SigningCrypto extends MockCoreCrypto {
  _Ed25519SigningCrypto(this.keyPair, {this.returnWrongHash = false});

  final KeyPair keyPair;
  final bool returnWrongHash;

  @override
  Future<SignedTransaction> signTransaction({
    required String walletId,
    required Coin coin,
    required Uint8List signingInput,
  }) async {
    expect(coin, Coin.solana);
    final signature = await Ed25519().sign(signingInput, keyPair: keyPair);
    final signatureBytes = Uint8List.fromList(signature.bytes);
    return SignedTransaction(
      signedTx: Uint8List.fromList([1, ...signatureBytes, ...signingInput]),
      txHash: returnWrongHash
          ? 'forged-native-hash'
          : base58Encode(signatureBytes),
    );
  }
}

class _CountingBroadcaster extends BroadcastService {
  _CountingBroadcaster({this.returnedHash = 'accepted-hash'});

  final String returnedHash;
  int calls = 0;

  @override
  Future<BroadcastOutcome> broadcast(
    Chain chain,
    Uint8List signedTx, {
    required String expectedTxHash,
  }) async {
    calls++;
    return BroadcastOutcome.ok(returnedHash);
  }
}

void main() {
  test('valid native Solana signature is independently verified', () async {
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
    final expectedHash = base58Encode(Uint8List.fromList(signature.bytes));
    final broadcaster = _CountingBroadcaster(returnedHash: expectedHash);
    final service = LocalTransferService(broadcaster: broadcaster);

    final result = await service.signAndBroadcastSolana(
      wallet: _wallet(solana: signer),
      crypto: _Ed25519SigningCrypto(keyPair),
      prepared: PreparedSolanaTransfer(
        from: signer,
        recipient: '11111111111111111111111111111111',
        amountRaw: BigInt.one,
        tokenMint: null,
        tokenProgram: null,
        networkFeeLamports: BigInt.one,
        rentDepositLamports: BigInt.zero,
        lastValidBlockHeight: 1,
        message: message,
      ),
      expectedNetworkIdentity: null,
    );

    expect(result.hash, expectedHash);
    expect(broadcaster.calls, 1);
  });

  test(
    'EVM node hash comparison accepts casing but keeps local form',
    () async {
      const expectedHash = '0xABCDEF';
      final service = LocalTransferService(
        broadcaster: _CountingBroadcaster(returnedHash: '0xabcdef'),
      );

      final result = await service.broadcastSigned(
        Chain.ethereum,
        Uint8List.fromList(const [1, 2, 3]),
        expectedTxHash: expectedHash,
      );

      expect(result, expectedHash);
    },
  );

  test('missing local hash fails before network broadcast', () async {
    final broadcaster = _CountingBroadcaster();
    final service = LocalTransferService(broadcaster: broadcaster);

    await expectLater(
      service.broadcastSigned(
        Chain.tron,
        Uint8List.fromList(const [1, 2, 3]),
        expectedTxHash: '',
      ),
      throwsA(isA<SignatureVerificationError>()),
    );
    expect(broadcaster.calls, 0);
  });

  test('native hash disagreement fails before Solana broadcast', () async {
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPairFromSeed(List<int>.filled(32, 7));
    final publicKey = await keyPair.extractPublicKey();
    final signer = base58Encode(Uint8List.fromList(publicKey.bytes));
    final message = SolanaMessage.systemTransfer(
      from: signer,
      to: '11111111111111111111111111111111',
      lamports: BigInt.one,
      recentBlockhash: '11111111111111111111111111111111',
    ).serialize();
    final broadcaster = _CountingBroadcaster();
    final service = LocalTransferService(broadcaster: broadcaster);

    await expectLater(
      service.signAndBroadcastSolana(
        wallet: _wallet(solana: signer),
        crypto: _Ed25519SigningCrypto(keyPair, returnWrongHash: true),
        prepared: PreparedSolanaTransfer(
          from: signer,
          recipient: '11111111111111111111111111111111',
          amountRaw: BigInt.one,
          tokenMint: null,
          tokenProgram: null,
          networkFeeLamports: BigInt.one,
          rentDepositLamports: BigInt.zero,
          lastValidBlockHeight: 1,
          message: message,
        ),
        expectedNetworkIdentity: null,
      ),
      throwsA(isA<SignatureVerificationError>()),
    );
    expect(broadcaster.calls, 0);
  });

  test(
    'mismatched node hash is uncertain and never replaces local hash',
    () async {
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
      final broadcaster = _CountingBroadcaster(
        returnedHash: 'forged-node-hash',
      );
      final service = LocalTransferService(broadcaster: broadcaster);

      await expectLater(
        service.signAndBroadcastSolana(
          wallet: _wallet(solana: signer),
          crypto: _Ed25519SigningCrypto(keyPair),
          prepared: PreparedSolanaTransfer(
            from: signer,
            recipient: '11111111111111111111111111111111',
            amountRaw: BigInt.one,
            tokenMint: null,
            tokenProgram: null,
            networkFeeLamports: BigInt.one,
            rentDepositLamports: BigInt.zero,
            lastValidBlockHeight: 1,
            message: message,
          ),
          expectedNetworkIdentity: null,
        ),
        throwsA(isA<LocalTransferUncertainException>()),
      );
      expect(broadcaster.calls, 1);
    },
  );

  test('malformed native EVM signature fails before broadcast', () async {
    final broadcaster = _CountingBroadcaster();
    final service = LocalTransferService(broadcaster: broadcaster);
    final tx = Eip1559Tx(
      chainId: BigInt.one,
      nonce: BigInt.zero,
      maxPriorityFeePerGas: BigInt.one,
      maxFeePerGas: BigInt.two,
      gasLimit: BigInt.from(21000),
      to: Eip1559Tx.addressBytes('0x000000000000000000000000000000000000dEaD'),
      value: BigInt.one,
      data: Uint8List(0),
    );

    await expectLater(
      service.signAndBroadcastEvm(
        wallet: _wallet(solana: '11111111111111111111111111111111'),
        crypto: _FixedSigningCrypto(
          SignedTransaction(
            signedTx: Uint8List.fromList(const [0x02]),
            txHash: '0xforged',
          ),
        ),
        prepared: PreparedEvmTransfer(
          chain: Chain.ethereum,
          evmChainId: 1,
          coin: Coin.eth,
          operation: TxOperation.nativeTransfer,
          from: _evmAddress,
          recipient: '0x000000000000000000000000000000000000dEaD',
          amountRaw: BigInt.one,
          tokenContract: null,
          nonce: BigInt.zero,
          maxPriorityFeePerGas: BigInt.one,
          maxFeePerGas: BigInt.two,
          gasLimit: BigInt.from(21000),
          unsignedTx: tx.encodeUnsigned(),
        ),
      ),
      throwsA(isA<SignatureVerificationError>()),
    );
    expect(broadcaster.calls, 0);
  });

  test('malformed native TRON signature fails before broadcast', () async {
    final broadcaster = _CountingBroadcaster();
    final service = LocalTransferService(broadcaster: broadcaster);
    final raw = Uint8List.fromList(List<int>.generate(96, (i) => i));

    await expectLater(
      service.signAndBroadcastTron(
        wallet: _wallet(solana: '11111111111111111111111111111111'),
        crypto: _FixedSigningCrypto(
          SignedTransaction(
            signedTx: Uint8List.fromList(const [1, 2, 3]),
            txHash: 'forged',
          ),
        ),
        prepared: PreparedTronTransfer(
          from: _tronAddress,
          recipient: _tronAddress,
          amountRaw: BigInt.one,
          tokenContract: null,
          maximumFeeSun: BigInt.one,
          referenceBlockHeight: 1,
          expiresAt: 2,
          rawTx: raw,
        ),
        expectedNetworkIdentity: null,
      ),
      throwsA(isA<SignatureVerificationError>()),
    );
    expect(broadcaster.calls, 0);
  });
}
