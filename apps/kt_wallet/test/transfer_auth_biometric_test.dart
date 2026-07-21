import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/main.dart';
import 'package:kt_wallet/src/security/biometric_auth.dart';

/// W30 transfer auth sheet against a fake [BiometricAuth]: success proceeds
/// to the broadcast result, failure stays on the sheet with a snackbar, and
/// an unavailable platform keeps the historical demo shortcut (proceed).
void main() {
  final original = BiometricAuth.instance;
  tearDown(() => BiometricAuth.instance = original);

  Future<void> pumpAuthSheet(WidgetTester tester) async {
    tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(KtWalletApp(initialLocation: '/transfer-auth'));
    await tester.pumpAndSettle();
    expect(find.text('验证以确认转账'), findsOneWidget);
  }

  testWidgets('biometric success proceeds to the broadcast result', (tester) async {
    BiometricAuth.instance = const FakeBiometricAuth(BiometricOutcome.success);
    await pumpAuthSheet(tester);

    await tester.tap(find.text('使用 Face ID 验证'));
    await tester.pumpAndSettle();
    expect(find.text('交易已提交'), findsOneWidget);
  });

  testWidgets('biometric failure stays on the sheet with a snackbar', (tester) async {
    BiometricAuth.instance = const FakeBiometricAuth(BiometricOutcome.failure);
    await pumpAuthSheet(tester);

    await tester.tap(find.text('使用 Face ID 验证'));
    await tester.pumpAndSettle();
    expect(find.text('验证失败，请重试'), findsOneWidget);
    expect(find.text('验证以确认转账'), findsOneWidget); // still on the sheet
    expect(find.text('交易已提交'), findsNothing);
  });

  testWidgets('unavailable biometrics keep the demo shortcut (proceed)', (tester) async {
    BiometricAuth.instance = const FakeBiometricAuth(BiometricOutcome.unavailable);
    await pumpAuthSheet(tester);

    await tester.tap(find.text('使用 Face ID 验证'));
    await tester.pumpAndSettle();
    expect(find.text('交易已提交'), findsOneWidget);
  });
}
