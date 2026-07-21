import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/security/app_lock_gate.dart';
import 'package:kt_wallet/src/security/biometric_auth.dart';
import 'package:kt_wallet/src/security/wallet_pin.dart';
import 'package:kt_wallet/src/state/app_prefs.dart';
import 'package:kt_wallet/src/state/locale_controller.dart';

/// Wallet-mode app lock: with the preference on the gate blocks until the
/// (fake) biometric prompt passes — or, when biometrics are unavailable or
/// fail, until the enrolled app PIN is entered on the numpad. The legacy
/// pass-through only survives with no PIN enrolled AND no usable biometrics.
void main() {
  const child = MaterialApp(home: Scaffold(body: Text('WALLET-HOME')));

  // Low iteration count keeps PBKDF2 fast in tests; the record stores its own
  // count, so this mirrors production behavior exactly.
  WalletPin newPin([InMemoryPinStorage? storage]) =>
      WalletPin(storage ?? InMemoryPinStorage(), iterations: 1000);

  Future<void> pumpGate(WidgetTester tester,
      {required AppPrefsController prefs,
      required BiometricAuth auth,
      WalletPin? pin}) async {
    tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(AppLockGate(
      localeController: LocaleController(),
      prefs: prefs,
      auth: auth,
      pin: pin ?? newPin(),
      child: child,
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tapPin(WidgetTester tester, String digits) async {
    for (final d in digits.split('')) {
      await tester.tap(find.text(d));
      await tester.pump();
    }
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

  testWidgets('a failed prompt with no PIN enrolled keeps the gate locked',
      (tester) async {
    await pumpGate(tester,
        prefs: AppPrefsController(),
        auth: const FakeBiometricAuth(BiometricOutcome.failure));

    await tester.tap(find.text('使用 Face ID 验证'));
    await tester.pumpAndSettle();
    expect(find.text('WALLET-HOME'), findsNothing);
    expect(find.text('App 锁'), findsOneWidget);
  });

  testWidgets(
      'legacy pass-through: no usable biometrics AND no PIN enrolled lets through',
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

  testWidgets('bio unavailable + PIN enrolled: numpad appears, correct PIN unlocks',
      (tester) async {
    final pin = newPin();
    await pin.setPin('135790');
    await pumpGate(tester,
        prefs: AppPrefsController(),
        auth: const FakeBiometricAuth(BiometricOutcome.success, available: false),
        pin: pin);

    // No pass-through: the PIN numpad is the lock screen.
    expect(find.text('WALLET-HOME'), findsNothing);
    expect(find.text('输入密码解锁'), findsOneWidget);

    await tapPin(tester, '135790');
    expect(find.text('WALLET-HOME'), findsOneWidget);
  });

  testWidgets('wrong PIN stays locked with the error message; retry unlocks',
      (tester) async {
    final pin = newPin();
    await pin.setPin('135790');
    await pumpGate(tester,
        prefs: AppPrefsController(),
        auth: const FakeBiometricAuth(BiometricOutcome.success, available: false),
        pin: pin);

    await tapPin(tester, '000000');
    expect(find.text('WALLET-HOME'), findsNothing);
    expect(find.text('密码错误，请重试'), findsOneWidget);

    await tapPin(tester, '135790');
    expect(find.text('WALLET-HOME'), findsOneWidget);
  });

  testWidgets('5 wrong PINs engage the lockout message and refuse the right PIN',
      (tester) async {
    final pin = newPin();
    await pin.setPin('135790');
    await pumpGate(tester,
        prefs: AppPrefsController(),
        auth: const FakeBiometricAuth(BiometricOutcome.success, available: false),
        pin: pin);

    for (var i = 0; i < 5; i++) {
      await tapPin(tester, '000000');
    }
    // 5th failure engaged the 30s lock: 尝试次数过多，请 N 秒后重试.
    expect(find.textContaining('尝试次数过多'), findsOneWidget);

    // Even the correct PIN is refused while locked out.
    await tapPin(tester, '135790');
    expect(find.text('WALLET-HOME'), findsNothing);
    expect(find.textContaining('尝试次数过多'), findsOneWidget);
  });

  testWidgets('persisted lockout shows its message before any key is pressed',
      (tester) async {
    final storage = InMemoryPinStorage();
    final enrolled = newPin(storage);
    await enrolled.setPin('135790');
    for (var i = 0; i < 5; i++) {
      await enrolled.verify('000000');
    }
    // "Restart": a fresh WalletPin over the same storage still knows the lock.
    await pumpGate(tester,
        prefs: AppPrefsController(),
        auth: const FakeBiometricAuth(BiometricOutcome.success, available: false),
        pin: newPin(storage));

    expect(find.textContaining('尝试次数过多'), findsOneWidget);
  });

  testWidgets('bio failure with a PIN enrolled falls back to the numpad',
      (tester) async {
    final pin = newPin();
    await pin.setPin('135790');
    await pumpGate(tester,
        prefs: AppPrefsController(),
        auth: const FakeBiometricAuth(BiometricOutcome.failure),
        pin: pin);

    await tester.tap(find.text('使用 Face ID 验证'));
    await tester.pumpAndSettle();
    expect(find.text('输入密码解锁'), findsOneWidget);

    await tapPin(tester, '135790');
    expect(find.text('WALLET-HOME'), findsOneWidget);
  });

  testWidgets('the biometric lock screen offers a direct PIN path when enrolled',
      (tester) async {
    final pin = newPin();
    await pin.setPin('135790');
    await pumpGate(tester,
        prefs: AppPrefsController(),
        auth: const FakeBiometricAuth(BiometricOutcome.success),
        pin: pin);

    await tester.tap(find.text('使用密码解锁'));
    await tester.pumpAndSettle();
    expect(find.text('输入密码解锁'), findsOneWidget);

    await tapPin(tester, '135790');
    expect(find.text('WALLET-HOME'), findsOneWidget);
  });
}
