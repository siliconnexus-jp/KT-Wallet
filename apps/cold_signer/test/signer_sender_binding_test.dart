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

const _walletTron = 'TNXoiAJ3dct8Fjg4M9fkLFh9S2v9TXc32G';
const _foreignTron = 'TBSd3Ju3T5URPH3q5C2HqhPG5qewNDuCtR';
const _walletSolana = '4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T';
const _foreignSolana = '2KW2XRd9kwqet15Aha2oK3tYvd3nWbTFH1MBiRAv1BE1';
const _blockhash = 'DzfXchZJoLMG3cNftcf2sw7qatkkuwQf4xH15N5wkKAb';

class _ValidAddressCrypto extends MockCoreCrypto {
  int signCalls = 0;

  @override
  Future<ChainAddresses> deriveAddresses(String walletId) async =>
      const ChainAddresses(
        eth: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
        polygon: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
        base: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
        arbitrum: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
        avalanche: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
        bnb: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
        tron: _walletTron,
        solana: _walletSolana,
      );

  @override
  Future<ChainPublicKeys> derivePublicKeys(String walletId) async {
    final evm = Uint8List.fromList([4, ...List<int>.filled(64, 1)]);
    return ChainPublicKeys(
      eth: evm,
      polygon: evm,
      base: evm,
      arbitrum: evm,
      avalanche: evm,
      bnb: evm,
      tron: Uint8List.fromList([4, ...List<int>.filled(64, 2)]),
      solana: Uint8List.fromList(List<int>.filled(32, 3)),
    );
  }

  @override
  Future<SignedTransaction> signTransaction({
    required String walletId,
    required Coin coin,
    required Uint8List signingInput,
  }) {
    signCalls += 1;
    return super.signTransaction(
      walletId: walletId,
      coin: coin,
      signingInput: signingInput,
    );
  }
}

const _safeDevice = DeviceState(
  networkReachable: false,
  airplaneMode: true,
  bluetoothOn: false,
  devicePasscodeSet: true,
  biometricEnrolled: true,
  screenCaptured: false,
  rootedOrJailbroken: false,
);

Future<SignerWalletController> _wallet(_ValidAddressCrypto crypto) async {
  final controller = SignerWalletController(
    storage: InMemoryVaultStorage(),
    records: InMemorySignRecordPersistence(),
    crypto: crypto,
    deviceProbe: () async => _safeDevice,
    random: Random(42),
    pinIterations: 500,
  );
  final words = await controller.beginCreate();
  controller.markMnemonicVerified(words);
  await controller.setPin('135790');
  await controller.completeOnboarding();
  return controller;
}

SignRequest _request({
  required SignerWalletController wallet,
  required int coin,
  required Uint8List rawTx,
}) => SignRequest(
  reqId: Uint8List.fromList(const [1, 2, 3, 4, 5, 6, 7, 8]),
  walletId: wallet.localWalletId!,
  coin: coin,
  rawTx: rawTx,
  createdAt: 1900000000,
  expiresAt: 1900000600,
);

void main() {
  test(
    'account export advertises the exact native Wallet Core paths',
    () async {
      final wallet = await _wallet(_ValidAddressCrypto());
      final export = wallet.buildAccountExport();

      expect(export.accounts, hasLength(accountExportDerivationPaths.length));
      expect({
        for (final account in export.accounts) account.coin: account.path,
      }, accountExportDerivationPaths);
    },
  );

  test('TRON owner_address must be this Cold Signer account', () async {
    final crypto = _ValidAddressCrypto();
    final wallet = await _wallet(crypto);
    final raw = TronRawTx.forTransfer(
      TransferIntent(
        chain: Chain.tron,
        operation: TxOperation.nativeTransfer,
        from: _foreignTron,
        to: _walletTron,
        amount: Amount.parse('0.000001', 6, symbol: 'TRX'),
      ),
      refBlockBytes: Uint8List.fromList(const [0x12, 0x34]),
      refBlockHash: Uint8List.fromList(const [1, 2, 3, 4, 5, 6, 7, 8]),
      expiration: 1900000060000,
      timestamp: 1900000000000,
    ).encodeRawData();

    await expectLater(
      wallet.signRequest(_request(wallet: wallet, coin: 195, rawTx: raw)),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('sender does not belong'),
        ),
      ),
    );
    expect(crypto.signCalls, 0, reason: 'foreign sender must never reach key');
  });

  test('Solana fee payer must be this Cold Signer account', () async {
    final crypto = _ValidAddressCrypto();
    final wallet = await _wallet(crypto);
    final raw = SolanaMessage.systemTransfer(
      from: _foreignSolana,
      to: _walletSolana,
      lamports: BigInt.one,
      recentBlockhash: _blockhash,
    ).serialize();

    await expectLater(
      wallet.signRequest(_request(wallet: wallet, coin: 501, rawTx: raw)),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('sender does not belong'),
        ),
      ),
    );
    expect(crypto.signCalls, 0, reason: 'foreign fee payer must not be signed');
  });
}
