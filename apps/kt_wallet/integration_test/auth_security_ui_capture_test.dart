import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/main.dart';
import 'package:kt_wallet/src/security/biometric_auth.dart';
import 'package:kt_wallet/src/security/wallet_pin.dart';
import 'package:kt_wallet/src/state/app_prefs.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _tapPin(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    await tester.tap(find.text(digit).last);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _evidencePause(WidgetTester tester, String marker) async {
  // ignore: avoid_print
  print('AUTH_SECURITY_CAPTURE READY=$marker');
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(seconds: 15)),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final originalAuth = BiometricAuth.instance;
  final originalPin = WalletPin.instance;

  tearDownAll(() {
    BiometricAuth.instance = originalAuth;
    WalletPin.instance = originalPin;
  });

  testWidgets(
    'transfer authentication evidence keeps the previous page under the scrim',
    (tester) async {
      await (await SharedPreferences.getInstance()).clear();
      final prefs = AppPrefsController();
      await prefs.setAuthMethod(AuthMethod.password);
      tester.platformDispatcher.localesTestValue = const [Locale('zh')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      await tester.pumpWidget(
        KtWalletApp(
          key: const ValueKey('transfer-auth-evidence'),
          prefs: prefs,
          initialLocation: '/security',
        ),
      );
      await tester.pumpAndSettle();
      unawaited(
        GoRouter.of(tester.element(find.text('安全设置'))).push('/transfer-auth'),
      );
      await tester.pumpAndSettle();

      expect(find.text('安全设置'), findsOneWidget);
      expect(find.text('验证以确认转账'), findsOneWidget);
      expect(find.text('钱包密码'), findsNWidgets(2));
      await _evidencePause(tester, 'password-transfer-auth-layered');
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  testWidgets(
    'authentication settings require current proof and production deep links fail closed',
    (tester) async {
      await (await SharedPreferences.getInstance()).clear();
      BiometricAuth.instance = const FakeBiometricAuth(
        BiometricOutcome.success,
      );
      WalletPin.instance = WalletPin(InMemoryPinStorage(), iterations: 1000);
      final prefs = AppPrefsController();

      tester.platformDispatcher.localesTestValue = const [Locale('zh')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      await tester.pumpWidget(
        KtWalletApp(
          key: const ValueKey('security-settings'),
          prefs: prefs,
          initialLocation: '/security',
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('人脸 / 生物识别'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('钱包密码'));
      await tester.pumpAndSettle();
      expect(find.text('设置 6 位密码'), findsOneWidget);
      await _tapPin(tester, '135790');
      await _tapPin(tester, '135790');
      expect(find.text('钱包密码'), findsOneWidget);
      expect(find.text('修改钱包密码'), findsOneWidget);
      expect(find.textContaining('iCloud'), findsNothing);
      expect(find.text('通过系统文件选择器保存加密副本'), findsOneWidget);
      await _evidencePause(tester, 'password-settings');

      await tester.tap(find.text('修改钱包密码'));
      await tester.pumpAndSettle();
      expect(find.text('请输入当前钱包密码'), findsOneWidget);
      await _evidencePause(tester, 'current-pin-required');

      await _tapPin(tester, '135790');
      await _tapPin(tester, '246810');
      await _tapPin(tester, '246810');
      expect(find.text('钱包密码已修改'), findsOneWidget);
      expect((await WalletPin.instance.verify('246810')).isOk, isTrue);

      await tester.pumpWidget(
        KtWalletApp(
          key: const ValueKey('password-transfer-auth'),
          prefs: prefs,
          initialLocation: '/security',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('安全设置'), findsOneWidget);
      unawaited(
        GoRouter.of(tester.element(find.text('安全设置'))).push('/transfer-auth'),
      );
      await tester.pumpAndSettle();
      // One copy remains visible on the dimmed security page and one is the
      // primary action in the authentication sheet.
      expect(find.text('钱包密码'), findsNWidgets(2));
      expect(find.text('验证以确认转账'), findsOneWidget);
      await _evidencePause(tester, 'password-transfer-auth');

      await tester.pumpWidget(
        KtWalletApp(
          key: const ValueKey('production-route-guard'),
          controller: WalletController(WalletManager()),
          prefs: prefs,
          initialLocation: '/broadcast-result',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('无法验证链上交易参数，签名已禁用。'), findsOneWidget);
      expect(find.text('交易已提交'), findsNothing);
      await _evidencePause(tester, 'production-route-guard');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
