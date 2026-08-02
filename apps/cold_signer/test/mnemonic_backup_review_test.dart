import 'dart:math';

import 'package:cold_signer/main.dart';
import 'package:cold_signer/src/security/secure_vault.dart';
import 'package:cold_signer/src/security/security_check.dart';
import 'package:cold_signer/src/signing/sign_record_store.dart';
import 'package:cold_signer/src/state/signer_wallet_controller.dart';
import 'package:core_crypto/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SignerWalletController _controller(
  InMemoryVaultStorage storage,
  MockCoreCrypto crypto,
) => SignerWalletController(
  storage: storage,
  records: InMemorySignRecordPersistence(),
  crypto: crypto,
  deviceProbe: () async => const DeviceState(
    networkReachable: false,
    airplaneMode: true,
    bluetoothOn: false,
    devicePasscodeSet: true,
    biometricEnrolled: true,
    screenCaptured: false,
    rootedOrJailbroken: false,
  ),
  random: Random(91),
  pinIterations: 50,
);

Future<List<String>> _createWallet(SignerWalletController wallet) async {
  final words = List<String>.of(await wallet.beginCreate());
  wallet.markMnemonicVerified(words);
  await wallet.setPin('135790');
  await wallet.completeOnboarding(walletName: 'Real offline wallet');
  return words;
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  test(
    'native backup export is exact, validated, and not controller state',
    () async {
      final storage = InMemoryVaultStorage();
      final crypto = MockCoreCrypto();
      final wallet = _controller(storage, crypto);
      final words = await _createWallet(wallet);

      final review = await wallet.exportMnemonicForReview();

      expect(review.words, words);
      expect(wallet.pendingMnemonic, isNull);
      expect(storage.values.containsKey(SecureVault.mnemonicKey), isFalse);
      expect(() => review.words.add('secret'), throwsUnsupportedError);
    },
  );

  testWidgets(
    'existing wallet backup authenticates, shows exact phrase, and returns to wallet',
    (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('en')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final storage = InMemoryVaultStorage();
      final crypto = MockCoreCrypto();
      final wallet = _controller(storage, crypto);
      final words = await _createWallet(wallet);

      await tester.pumpWidget(
        ColdSignerApp(walletController: wallet, initialLocation: '/wallet'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Real offline wallet'), findsOneWidget);
      expect(find.textContaining('WLT-3E8A91'), findsNothing);
      await tester.tap(find.text('Verify phrase backup'));
      await tester.pumpAndSettle();

      final shown = [
        for (var i = 0; i < words.length; i++)
          tester.widget<Text>(find.byKey(Key('mnemonic-word-$i'))).data!,
      ];
      expect(shown, words);

      await tester.tap(find.text('I\'ve written it down — verify'));
      await tester.pumpAndSettle();
      final question = tester
          .widget<Text>(find.textContaining('What is word'))
          .data!;
      final position = int.parse(
        RegExp(r'word (\d+)').firstMatch(question)!.group(1)!,
      );
      await tester.tap(find.text(words[position - 1]).last);
      await tester.pump();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(find.text('Wallet management'), findsOneWidget);
      expect(find.text('Set a 6-digit PIN'), findsNothing);
      expect(wallet.pendingMnemonic, isNull);
    },
  );

  testWidgets('authentication failure never opens or reveals a phrase', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final storage = InMemoryVaultStorage();
    final crypto = MockCoreCrypto(authenticator: () async => false);
    final wallet = _controller(storage, crypto);
    await _createWallet(wallet);

    await tester.pumpWidget(
      ColdSignerApp(walletController: wallet, initialLocation: '/wallet'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verify phrase backup'));
    await tester.pumpAndSettle();

    expect(find.text('Backup recovery phrase'), findsNothing);
    expect(find.byKey(const Key('mnemonic-word-0')), findsNothing);
    expect(
      find.text(
        'Authentication or phrase validation failed. No recovery phrase was shown.',
      ),
      findsOneWidget,
    );
  });
}
