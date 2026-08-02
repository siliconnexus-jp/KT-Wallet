import 'dart:math';

import 'package:cold_signer/main.dart';
import 'package:cold_signer/src/security/biometric_auth.dart';
import 'package:cold_signer/src/security/secure_vault.dart';
import 'package:cold_signer/src/signing/sign_record_store.dart';
import 'package:cold_signer/src/state/signer_wallet_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core_crypto/testing.dart';
import 'package:local_auth/local_auth.dart';

/// C8 against the injectable [BiometricAuth]: a (fake) biometric success
/// authorizes the signature exactly like a verified PIN, a failure stays on
/// the screen, and — the signer's key property — an unavailable platform
/// falls back to the REAL PIN numpad sheet when a wallet is enrolled.
void main() {
  final original = BiometricAuth.instance;
  tearDown(() => BiometricAuth.instance = original);

  Future<void> openC8(
    WidgetTester tester, {
    SignerWalletController? wallet,
  }) async {
    tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      wallet == null
          ? ColdSignerApp()
          : ColdSignerApp(walletController: wallet),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('C8 身份验证'), 200);
    await tester.tap(find.text('C8 身份验证'));
    await tester.pumpAndSettle();
    expect(find.text('验证以完成签名'), findsOneWidget);
  }

  testWidgets(
    'biometric success authorizes the signature (same as PIN success)',
    (tester) async {
      BiometricAuth.instance = const FakeBiometricAuth(
        BiometricOutcome.success,
      );
      await openC8(tester);

      await tester.tap(find.text('使用 Face ID 验证'));
      // C9's result QR cycles frames on a periodic timer; pump discrete frames
      // instead of settling.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('签名完成'), findsOneWidget); // C9 result QR
    },
  );

  testWidgets('biometric failure stays on C8 with a snackbar', (tester) async {
    BiometricAuth.instance = const FakeBiometricAuth(BiometricOutcome.failure);
    await openC8(tester);

    await tester.tap(find.text('使用 Face ID 验证'));
    await tester.pumpAndSettle();
    expect(find.text('验证失败，请重试'), findsOneWidget);
    expect(find.text('验证以完成签名'), findsOneWidget); // still on C8
    expect(find.text('签名完成'), findsNothing);
  });

  testWidgets('system-sheet cancellation does not silently switch to PIN', (
    tester,
  ) async {
    BiometricAuth.instance = const FakeBiometricAuth.throwing(
      LocalAuthException(code: LocalAuthExceptionCode.userCanceled),
    );
    await openC8(tester);

    await tester.tap(find.text('使用 Face ID 验证'));
    await tester.pumpAndSettle();

    expect(find.text('验证失败，请重试'), findsOneWidget);
    expect(find.text('验证以完成签名'), findsOneWidget);
    expect(find.text('输入 App 密码以完成签名'), findsNothing);
    expect(find.text('签名完成'), findsNothing);
  });

  testWidgets(
    'biometrics unavailable + enrolled wallet: falls back to the real PIN sheet',
    (tester) async {
      // Enroll a wallet + PIN directly (the UI flow is covered by live_loop).
      final wallet = SignerWalletController(
        storage: InMemoryVaultStorage(),
        records: InMemorySignRecordPersistence(),
        crypto: MockCoreCrypto(),
        random: Random(42),
        pinIterations: 500,
      );
      final words = await wallet.beginCreate();
      wallet.markMnemonicVerified(words);
      await wallet.setPin('135790');
      await wallet.completeOnboarding();
      expect(wallet.hasWallet, isTrue);

      // Default BiometricAuth.instance: under `flutter test` the plugin is
      // dead, so the real implementation reports "unavailable" — exactly the
      // no-biometrics device case.
      await openC8(tester, wallet: wallet);
      await tester.tap(find.text('使用 Face ID 验证'));
      await tester.pumpAndSettle();

      // The REAL PIN numpad sheet appears, and the enrolled PIN completes the
      // signature like any PIN success.
      expect(find.text('输入 App 密码以完成签名'), findsOneWidget);
      for (final d in '135790'.split('')) {
        await tester.tap(find.text(d).last);
        await tester.pump();
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('签名完成'), findsOneWidget);
    },
  );
}
