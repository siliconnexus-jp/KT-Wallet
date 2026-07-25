import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/main.dart';
import 'package:kt_wallet/src/security/biometric_auth.dart';
import 'package:kt_wallet/src/security/wallet_pin.dart';

/// W30 transfer auth sheet against a fake [BiometricAuth]: success proceeds
/// to the broadcast result, failure stays on the sheet with a snackbar, and
/// an unavailable platform fails closed.
void main() {
  final original = BiometricAuth.instance;
  final originalPin = WalletPin.instance;
  tearDown(() {
    BiometricAuth.instance = original;
    WalletPin.instance = originalPin;
  });

  Future<void> pumpAuthSheet(WidgetTester tester) async {
    tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(KtWalletApp(initialLocation: '/transfer-auth'));
    await tester.pumpAndSettle();
    expect(find.text('验证以确认转账'), findsOneWidget);
  }

  testWidgets('biometric success proceeds to the broadcast result', (
    tester,
  ) async {
    BiometricAuth.instance = const FakeBiometricAuth(BiometricOutcome.success);
    await pumpAuthSheet(tester);

    await tester.tap(find.text('使用生物识别验证'));
    await tester.pumpAndSettle();
    expect(find.text('交易已提交'), findsOneWidget);
  });

  testWidgets('biometric failure stays on the sheet with a snackbar', (
    tester,
  ) async {
    BiometricAuth.instance = const FakeBiometricAuth(BiometricOutcome.failure);
    await pumpAuthSheet(tester);

    await tester.tap(find.text('使用生物识别验证'));
    await tester.pumpAndSettle();
    expect(find.text('验证失败，请重试'), findsOneWidget);
    expect(find.text('验证以确认转账'), findsOneWidget); // still on the sheet
    expect(find.text('交易已提交'), findsNothing);
  });

  testWidgets('unavailable biometrics fail closed', (tester) async {
    BiometricAuth.instance = const FakeBiometricAuth(
      BiometricOutcome.unavailable,
    );
    await pumpAuthSheet(tester);

    await tester.tap(find.text('使用生物识别验证'));
    await tester.pumpAndSettle();
    expect(find.text('生物识别不可用，请使用钱包 PIN'), findsOneWidget);
    expect(find.text('交易已提交'), findsNothing);
  });

  testWidgets('wallet PIN must verify before proceeding', (tester) async {
    BiometricAuth.instance = const FakeBiometricAuth(
      BiometricOutcome.unavailable,
    );
    final pin = WalletPin(InMemoryPinStorage(), iterations: 10);
    await pin.setPin('123456');
    WalletPin.instance = pin;
    await pumpAuthSheet(tester);

    await tester.tap(find.text('改用密码'));
    await tester.pumpAndSettle();
    for (final digit in '123456'.split('')) {
      await tester.tap(find.text(digit).last);
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.text('交易已提交'), findsOneWidget);
  });

  testWidgets(
    'tapping the dimmed scrim dismisses the auth sheet back to confirm',
    (tester) async {
      BiometricAuth.instance = const FakeBiometricAuth(
        BiometricOutcome.success,
      );
      tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(KtWalletApp(initialLocation: '/confirm-hot'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('确认转账'));
      await tester.pumpAndSettle();
      expect(find.text('验证以确认转账'), findsOneWidget);

      // Tap the dimmed area above the sheet card.
      await tester.tapAt(const Offset(200, 80));
      await tester.pumpAndSettle();

      expect(
        find.text('验证以确认转账'),
        findsNothing,
        reason: 'scrim tap must dismiss',
      );
      expect(find.text('确认转账'), findsOneWidget); // back on W29 confirm
    },
  );
}
