import 'dart:math';
import 'dart:typed_data';
import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:chains/chains.dart';
import 'package:cold_signer/l10n/app_localizations.dart';
import 'package:cold_signer/src/screens/signer_signing_screens.dart';
import 'package:cold_signer/src/security/secure_vault.dart';
import 'package:cold_signer/src/security/security_check.dart';
import 'package:cold_signer/src/signing/sign_record_store.dart';
import 'package:cold_signer/src/state/signer_wallet_controller.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:core_crypto/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class ProbeCrypto extends MockCoreCrypto {
  int calls = 0;
  Coin? receivedCoin;
  @override
  Future<SignedTransaction> signTransaction({
    required String walletId,
    required Coin coin,
    required Uint8List signingInput,
  }) {
    calls++;
    receivedCoin = coin;
    return super.signTransaction(
      walletId: walletId,
      coin: coin,
      signingInput: signingInput,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Ethereum as BNB is rejected before display and native signing', (
    tester,
  ) async {
    final crypto = ProbeCrypto();
    final wallet = SignerWalletController(
      storage: InMemoryVaultStorage(),
      records: InMemorySignRecordPersistence(),
      crypto: crypto,
      random: Random(42),
      pinIterations: 500,
      clock: () => DateTime.fromMillisecondsSinceEpoch(1000000),
      deviceProbe: () async => const DeviceState(
        networkReachable: false,
        airplaneMode: true,
        bluetoothOn: false,
        devicePasscodeSet: true,
        biometricEnrolled: true,
        screenCaptured: false,
        rootedOrJailbroken: false,
      ),
    );
    final words = await wallet.beginCreate();
    wallet.markMnemonicVerified(words);
    await wallet.setPin('135790');
    await wallet.completeOnboarding();
    final raw = Eip1559Tx(
      chainId: BigInt.one,
      nonce: BigInt.zero,
      maxPriorityFeePerGas: BigInt.one,
      maxFeePerGas: BigInt.two,
      gasLimit: BigInt.from(21000),
      to: Eip1559Tx.addressBytes('0x0000000000000000000000000000000000000001'),
      value: BigInt.parse('1000000000000000000'),
      data: Uint8List(0),
    ).encodeUnsigned();
    final req = SignRequest(
      reqId: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
      walletId: wallet.localWalletId!,
      coin: 714,
      chainId: 1,
      rawTx: raw,
      createdAt: 1000,
      expiresAt: 1600,
    );
    expect(() => parseUnsignedTransfer(Chain.bnb, raw), throwsFormatException);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SignerAuthScreen(request: req),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 BNB'), findsNothing);
    await expectLater(wallet.signRequest(req), throwsA(isA<StateError>()));
    expect(crypto.calls, 0);
    expect(crypto.receivedCoin, isNull);
    for (final claimedId in <int?>[null, 56]) {
      final invalid = SignRequest(
        reqId: Uint8List.fromList([8, 7, 6, 5, 4, 3, 2, 1]),
        walletId: wallet.localWalletId!,
        coin: 60,
        chainId: claimedId,
        rawTx: raw,
        createdAt: 1000,
        expiresAt: 1600,
      );
      await expectLater(
        wallet.signRequest(invalid),
        throwsA(isA<StateError>()),
      );
    }
    expect(crypto.calls, 0);
    wallet.dispose();
  });
}
