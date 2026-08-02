import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:chains/chains.dart';
import 'package:cold_signer/src/security/secure_vault.dart';
import 'package:cold_signer/src/security/security_check.dart';
import 'package:cold_signer/src/signing/sign_record_store.dart';
import 'package:cold_signer/src/state/signer_wallet_controller.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:core_crypto/testing.dart';
import 'package:flutter_test/flutter_test.dart';

const _safeDevice = DeviceState(
  networkReachable: false,
  airplaneMode: true,
  bluetoothOn: false,
  devicePasscodeSet: true,
  biometricEnrolled: true,
  screenCaptured: false,
  rootedOrJailbroken: false,
);

class _ControlledCrypto extends MockCoreCrypto {
  _ControlledCrypto({this.failSigning = false, this.blockSigning = false});

  final bool failSigning;
  final bool blockSigning;
  final enteredSigning = Completer<void>();
  final releaseSigning = Completer<void>();
  int signCalls = 0;

  @override
  Future<SignedTransaction> signTransaction({
    required String walletId,
    required Coin coin,
    required Uint8List signingInput,
  }) async {
    signCalls += 1;
    if (!enteredSigning.isCompleted) enteredSigning.complete();
    if (blockSigning) await releaseSigning.future;
    if (failSigning) throw StateError('injected native signing failure');
    return super.signTransaction(
      walletId: walletId,
      coin: coin,
      signingInput: signingInput,
    );
  }
}

class _FailingRecords implements SignRecordPersistence {
  @override
  Future<bool> reserve(SignatureRecord record) =>
      Future<bool>.error(StateError('injected database failure'));

  @override
  Future<bool> finalizeReservation(SignatureRecord record) =>
      Future<bool>.error(StateError('unexpected finalize'));

  @override
  Future<SignatureRecord?> get(String reqIdHex) async => null;

  @override
  Future<List<SignatureRecord>> all() async => const [];

  @override
  Future<void> clear() async {}
}

Future<SignerWalletController> _createWallet({
  required SignRecordPersistence records,
  required _ControlledCrypto crypto,
  required DateTime Function() clock,
  Future<DeviceState> Function()? deviceProbe,
}) async {
  final controller = SignerWalletController(
    storage: InMemoryVaultStorage(),
    records: records,
    crypto: crypto,
    deviceProbe: deviceProbe ?? () async => _safeDevice,
    random: Random(42),
    clock: clock,
    pinIterations: 500,
  );
  final words = await controller.beginCreate();
  controller.markMnemonicVerified(words);
  await controller.setPin('135790');
  await controller.completeOnboarding();
  return controller;
}

SignRequest _request(
  SignerWalletController wallet, {
  required int createdAt,
  required int expiresAt,
}) {
  final from = wallet.metadata!.addresses['eth']!;
  final rawTx = Eip1559Tx.forTransfer(
    TransferIntent(
      chain: Chain.ethereum,
      operation: TxOperation.nativeTransfer,
      from: from,
      to: '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
      amount: Amount(raw: BigInt.one, decimals: 18, symbol: 'ETH'),
    ),
    chainId: BigInt.from(11155111),
    nonce: BigInt.zero,
    maxPriorityFeePerGas: BigInt.from(1000000000),
    maxFeePerGas: BigInt.from(2000000000),
    gasLimit: BigInt.from(21000),
  ).encodeUnsigned();
  return SignRequest(
    reqId: Uint8List.fromList(const [1, 2, 3, 4, 5, 6, 7, 8]),
    walletId: wallet.localWalletId!,
    coin: 60,
    chainId: 11155111,
    rawTx: rawTx,
    createdAt: createdAt,
    expiresAt: expiresAt,
  );
}

void main() {
  test(
    'request that expires during auth is rejected at the key boundary',
    () async {
      var now = DateTime.fromMillisecondsSinceEpoch(1000 * 1000);
      final records = InMemorySignRecordPersistence();
      final crypto = _ControlledCrypto();
      final wallet = await _createWallet(
        records: records,
        crypto: crypto,
        clock: () => now,
      );
      final request = _request(wallet, createdAt: 1000, expiresAt: 1010);

      now = DateTime.fromMillisecondsSinceEpoch(1010 * 1000);
      await expectLater(
        wallet.signRequest(request),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('expired'),
          ),
        ),
      );
      expect(crypto.signCalls, 0);
      expect(await records.all(), isEmpty);
    },
  );

  test(
    'future-dated request beyond clock skew never reaches the key',
    () async {
      final records = InMemorySignRecordPersistence();
      final crypto = _ControlledCrypto();
      final wallet = await _createWallet(
        records: records,
        crypto: crypto,
        clock: () => DateTime.fromMillisecondsSinceEpoch(1000 * 1000),
      );

      await expectLater(
        wallet.signRequest(_request(wallet, createdAt: 1601, expiresAt: 1700)),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('clock skew'),
          ),
        ),
      );
      expect(crypto.signCalls, 0);
      expect(await records.all(), isEmpty);
    },
  );

  test('concurrent callbacks can invoke native signing only once', () async {
    final records = InMemorySignRecordPersistence();
    final crypto = _ControlledCrypto(blockSigning: true);
    final wallet = await _createWallet(
      records: records,
      crypto: crypto,
      clock: () => DateTime.fromMillisecondsSinceEpoch(1000 * 1000),
    );
    final request = _request(wallet, createdAt: 1000, expiresAt: 1100);

    final first = wallet.signRequest(request);
    await crypto.enteredSigning.future;
    await expectLater(
      wallet.signRequest(request),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('already consumed'),
        ),
      ),
    );
    expect(crypto.signCalls, 1);

    crypto.releaseSigning.complete();
    await first;
    expect((await records.get(request.reqIdHex))!.status, RequestStatus.signed);
  });

  test('native signing failure burns the request and blocks retry', () async {
    final records = InMemorySignRecordPersistence();
    final crypto = _ControlledCrypto(failSigning: true);
    final wallet = await _createWallet(
      records: records,
      crypto: crypto,
      clock: () => DateTime.fromMillisecondsSinceEpoch(1000 * 1000),
    );
    final request = _request(wallet, createdAt: 1000, expiresAt: 1100);

    await expectLater(wallet.signRequest(request), throwsStateError);
    expect(
      (await records.get(request.reqIdHex))!.status,
      RequestStatus.scanned,
    );
    await expectLater(
      wallet.signRequest(request),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('already consumed'),
        ),
      ),
    );
    expect(crypto.signCalls, 1);
  });

  test(
    'device becoming unsafe after reservation burns and blocks request',
    () async {
      final records = InMemorySignRecordPersistence();
      final crypto = _ControlledCrypto();
      var probeCalls = 0;
      final wallet = await _createWallet(
        records: records,
        crypto: crypto,
        clock: () => DateTime.fromMillisecondsSinceEpoch(1000 * 1000),
        deviceProbe: () async {
          probeCalls += 1;
          if (probeCalls == 1) return _safeDevice;
          return const DeviceState(
            networkReachable: true,
            airplaneMode: false,
            bluetoothOn: false,
            devicePasscodeSet: true,
            biometricEnrolled: true,
            screenCaptured: false,
            rootedOrJailbroken: false,
          );
        },
      );
      final request = _request(wallet, createdAt: 1000, expiresAt: 1100);

      await expectLater(
        wallet.signRequest(request),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('security changed'),
          ),
        ),
      );
      expect(crypto.signCalls, 0);
      expect(
        (await records.get(request.reqIdHex))!.status,
        RequestStatus.scanned,
      );
    },
  );

  test('record-store failure blocks signing instead of degrading', () async {
    final crypto = _ControlledCrypto();
    final wallet = await _createWallet(
      records: _FailingRecords(),
      crypto: crypto,
      clock: () => DateTime.fromMillisecondsSinceEpoch(1000 * 1000),
    );

    await expectLater(
      wallet.signRequest(_request(wallet, createdAt: 1000, expiresAt: 1100)),
      throwsA(isA<StateError>()),
    );
    expect(crypto.signCalls, 0);
  });
}
