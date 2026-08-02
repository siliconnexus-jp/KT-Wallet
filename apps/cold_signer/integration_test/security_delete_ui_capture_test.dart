import 'dart:math';

import 'package:cold_signer/l10n/app_localizations.dart';
import 'package:cold_signer/src/screens/signer_settings_screens.dart';
import 'package:cold_signer/src/screens/signer_signing_screens.dart';
import 'package:cold_signer/src/security/biometric_auth.dart';
import 'package:cold_signer/src/security/secure_vault.dart';
import 'package:cold_signer/src/security/security_check.dart';
import 'package:cold_signer/src/signing/demo_airgap.dart';
import 'package:cold_signer/src/signing/sign_record_store.dart';
import 'package:cold_signer/src/state/signer_wallet_controller.dart';
import 'package:core_crypto/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ui_kit/ui_kit.dart';

const _offline = DeviceState(
  networkReachable: false,
  airplaneMode: true,
  bluetoothOn: false,
  devicePasscodeSet: true,
  biometricEnrolled: true,
  screenCaptured: false,
  rootedOrJailbroken: false,
);

Widget _app(Widget home, Locale locale) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData(
    fontFamily: 'Inter',
    brightness: Brightness.dark,
    scaffoldBackgroundColor: SignerColors.bg,
  ),
  home: home,
);

Future<void> _evidencePause(WidgetTester tester, String marker) async {
  // ignore: avoid_print
  print('COLD_SECURITY_CAPTURE READY=$marker');
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(seconds: 20)),
  );
}

Future<SignerWalletController> _wallet() async {
  final storage = InMemoryVaultStorage();
  final crypto = MockCoreCrypto();
  await crypto.storeWallet(
    walletId: demoWalletId,
    mnemonic:
        'abandon ability able about above absent absorb abstract absurd abuse access accident',
    requireAuth: false,
  );
  await SecureVault(storage).storeMetadata(
    const WalletMetadata(
      walletId: demoWalletId,
      name: 'KT Wallet',
      createdAt: 1786000000,
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'localized security status and destructive deletion authentication gate',
    (tester) async {
      await tester.pumpWidget(
        _app(
          SignerSecurityCheckScreen(probe: () async => _offline),
          const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No network connection detected'), findsOneWidget);
      expect(find.text('未检测到网络连接'), findsNothing);
      await _evidencePause(tester, 'security-localized-en');

      final wallet = await _wallet();
      await tester.pumpWidget(
        _app(
          SignerWalletScope(
            controller: wallet,
            child: const SignerDeleteScreen(
              auth: FakeBiometricAuth(BiometricOutcome.success),
            ),
          ),
          const Locale('zh'),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.widgetWithText(FilledButton, '永久删除钱包');
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await _evidencePause(tester, 'delete-phrase-gate');

      await tester.enterText(
        find.byKey(const ValueKey('delete-confirmation-input')),
        '删除钱包',
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('输入 App 密码以继续删除'), findsOneWidget);
      expect(wallet.hasWallet, isTrue);
      await _evidencePause(tester, 'delete-pin-required');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
