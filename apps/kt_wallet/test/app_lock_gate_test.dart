import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/security/app_lock_gate.dart';
import 'package:kt_wallet/src/security/biometric_auth.dart';
import 'package:kt_wallet/src/state/app_prefs.dart';
import 'package:kt_wallet/src/state/locale_controller.dart';

/// Wallet-mode app lock: with the preference on the gate blocks until the
/// (fake) biometric prompt passes; without usable biometrics — or with the
/// preference off — it lets the wallet through.
void main() {
  const child = MaterialApp(home: Scaffold(body: Text('WALLET-HOME')));

  Future<void> pumpGate(WidgetTester tester,
      {required AppPrefsController prefs, required BiometricAuth auth}) async {
    tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(AppLockGate(
      localeController: LocaleController(),
      prefs: prefs,
      auth: auth,
      child: child,
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('app lock on: gate blocks, then a successful prompt unlocks',
      (tester) async {
    // Default preference is appLock=true (persistence is dead in tests).
    await pumpGate(tester,
        prefs: AppPrefsController(),
        auth: const FakeBiometricAuth(BiometricOutcome.success));

    // Locked: the wallet is hidden behind the lock screen.
    expect(find.text('WALLET-HOME'), findsNothing);
    expect(find.text('App 锁'), findsOneWidget);

    await tester.tap(find.text('使用 Face ID 验证'));
    await tester.pumpAndSettle();
    expect(find.text('WALLET-HOME'), findsOneWidget);
  });

  testWidgets('a failed prompt keeps the gate locked', (tester) async {
    await pumpGate(tester,
        prefs: AppPrefsController(),
        auth: const FakeBiometricAuth(BiometricOutcome.failure));

    await tester.tap(find.text('使用 Face ID 验证'));
    await tester.pumpAndSettle();
    expect(find.text('WALLET-HOME'), findsNothing);
    expect(find.text('App 锁'), findsOneWidget);
  });

  testWidgets('no usable biometrics: let through (no PIN exists to fall back to)',
      (tester) async {
    await pumpGate(tester,
        prefs: AppPrefsController(),
        auth: const FakeBiometricAuth(BiometricOutcome.success, available: false));

    expect(find.text('WALLET-HOME'), findsOneWidget);
  });

  testWidgets('app lock off: straight through', (tester) async {
    final prefs = AppPrefsController();
    prefs.setAppLock(false).ignore(); // persistence is dead in tests
    await pumpGate(tester,
        prefs: prefs, auth: const FakeBiometricAuth(BiometricOutcome.failure));

    expect(find.text('WALLET-HOME'), findsOneWidget);
  });
}
