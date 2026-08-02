import 'dart:math';

import 'package:cold_signer/l10n/app_localizations.dart';
import 'package:cold_signer/src/screens/signer_settings_screens.dart';
import 'package:cold_signer/src/security/biometric_auth.dart';
import 'package:cold_signer/src/security/secure_vault.dart';
import 'package:cold_signer/src/signing/demo_airgap.dart';
import 'package:cold_signer/src/signing/sign_record_store.dart';
import 'package:cold_signer/src/state/signer_wallet_controller.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:core_crypto/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

class _DeleteFailingCrypto extends MockCoreCrypto {
  @override
  Future<void> deleteWallet(String walletId) =>
      Future<void>.error(const AuthFailedException());
}

Future<SignerWalletController> _wallet({
  required bool biometric,
  MockCoreCrypto? crypto,
}) async {
  final storage = InMemoryVaultStorage();
  crypto ??= MockCoreCrypto();
  await crypto.storeWallet(
    walletId: demoWalletId,
    mnemonic:
        'abandon ability able about above absent absorb abstract absurd abuse access accident',
    requireAuth: false,
  );
  await SecureVault(storage).storeMetadata(
    WalletMetadata(
      walletId: demoWalletId,
      name: 'KT Wallet',
      createdAt: 1786000000,
      biometricEnabled: biometric,
    ),
  );
  final controller = SignerWalletController(
    storage: storage,
    records: InMemorySignRecordPersistence(),
    crypto: crypto,
    random: Random(42),
    pinIterations: 500,
  );
  await controller.pinLock.setPin('135790');
  await controller.load();
  return controller;
}

Widget _app(SignerWalletController controller, {required BiometricAuth auth}) =>
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: SignerColors.bg,
      ),
      home: SignerWalletScope(
        controller: controller,
        child: SignerDeleteScreen(auth: auth),
      ),
    );

Future<void> _enterPin(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.byKey(ValueKey('pin-key-$digit')));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('delete stays disabled until the exact localized phrase', (
    tester,
  ) async {
    final wallet = await _wallet(biometric: false);
    await tester.pumpWidget(
      _app(wallet, auth: const FakeBiometricAuth(BiometricOutcome.success)),
    );
    await tester.pumpAndSettle();

    final button = find.widgetWithText(
      FilledButton,
      'Permanently delete wallet',
    );
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('delete-confirmation-input')),
      'delete wallet',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(wallet.hasWallet, isTrue);
  });

  testWidgets('wrong PIN cannot reach destructive confirmation', (
    tester,
  ) async {
    final wallet = await _wallet(biometric: false);
    await tester.pumpWidget(
      _app(wallet, auth: const FakeBiometricAuth(BiometricOutcome.success)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('delete-confirmation-input')),
      'Delete wallet',
    );
    await tester.pump();
    await tester.tap(find.text('Permanently delete wallet'));
    await tester.pumpAndSettle();
    await _enterPin(tester, '000000');

    expect(find.text('Incorrect PIN, try again'), findsOneWidget);
    expect(find.text('This action is irreversible'), findsOneWidget);
    expect(wallet.hasWallet, isTrue);
  });

  testWidgets('enabled system authentication must pass after the app PIN', (
    tester,
  ) async {
    final wallet = await _wallet(biometric: true);
    expect(wallet.biometricEnabled, isTrue);
    await tester.pumpWidget(
      _app(wallet, auth: const FakeBiometricAuth(BiometricOutcome.failure)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('delete-confirmation-input')),
      'Delete wallet',
    );
    await tester.pump();
    await tester.tap(find.text('Permanently delete wallet'));
    await tester.pumpAndSettle();
    await _enterPin(tester, '135790');

    expect(
      find.text('Authentication failed. The wallet was not deleted.'),
      findsOneWidget,
    );
    expect(find.text('This action is irreversible'), findsOneWidget);
    expect(wallet.hasWallet, isTrue);
  });

  testWidgets('successful PIN and system authentication reach final warning', (
    tester,
  ) async {
    final wallet = await _wallet(biometric: true);
    await tester.pumpWidget(
      _app(wallet, auth: const FakeBiometricAuth(BiometricOutcome.success)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('delete-confirmation-input')),
      'Delete wallet',
    );
    await tester.pump();
    await tester.tap(find.text('Permanently delete wallet'));
    await tester.pumpAndSettle();
    await _enterPin(tester, '135790');

    expect(find.text('Incorrect PIN, try again'), findsNothing);
    expect(
      find.text('Authentication failed. The wallet was not deleted.'),
      findsNothing,
    );
    expect(find.text('Enter app PIN to complete signing'), findsNothing);
    expect(find.byKey(const ValueKey('pin-key-1')), findsNothing);
    expect(find.text('This action is irreversible'), findsNWidgets(2));
    expect(find.text('Permanently delete wallet'), findsNWidgets(2));
    expect(wallet.hasWallet, isTrue, reason: 'the final warning is still open');
  });

  testWidgets('native deletion failure stays on screen with a retry message', (
    tester,
  ) async {
    final wallet = await _wallet(
      biometric: false,
      crypto: _DeleteFailingCrypto(),
    );
    await tester.pumpWidget(
      _app(wallet, auth: const FakeBiometricAuth(BiometricOutcome.success)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('delete-confirmation-input')),
      'Delete wallet',
    );
    await tester.pump();
    await tester.tap(find.text('Permanently delete wallet'));
    await tester.pumpAndSettle();
    await _enterPin(tester, '135790');
    await tester.tap(find.byKey(const ValueKey('kt-dialog-confirm')));
    await tester.pumpAndSettle();

    expect(wallet.hasWallet, isTrue);
    expect(
      find.text(
        'The wallet could not be deleted safely. Nothing was removed; try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('This action is irreversible'), findsOneWidget);
  });
}
