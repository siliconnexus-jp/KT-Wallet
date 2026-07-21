import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/main.dart';
import 'package:kt_wallet/src/security/biometric_auth.dart';
import 'package:kt_wallet/src/security/wallet_pin.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Security-settings app-lock switch: turning it ON with no PIN enrolled
/// walks through the set-PIN sheet (twice-entry, mismatch resets); turning it
/// OFF demands the current PIN (or a biometric success).
void main() {
  late WalletPin realPin;
  late BiometricAuth realAuth;
  late InMemoryPinStorage storage;

  setUp(() {
    realPin = WalletPin.instance;
    realAuth = BiometricAuth.instance;
    storage = InMemoryPinStorage();
    // Low iteration count keeps PBKDF2 fast; the record stores its own count.
    WalletPin.instance = WalletPin(storage, iterations: 1000);
    BiometricAuth.instance =
        const FakeBiometricAuth(BiometricOutcome.unavailable, available: false);
  });

  tearDown(() {
    WalletPin.instance = realPin;
    BiometricAuth.instance = realAuth;
  });

  Future<void> openSecurity(WidgetTester tester, {required bool appLock}) async {
    SharedPreferences.setMockInitialValues({'prefs.appLock': appLock});
    tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(KtWalletApp(initialLocation: '/security'));
    await tester.pumpAndSettle();
  }

  /// The app-lock switch is the first toggle on the screen (privacy mode is
  /// the second).
  Future<void> tapAppLockSwitch(WidgetTester tester) async {
    await tester.tap(find.byType(AnimatedAlign).first);
    await tester.pumpAndSettle();
  }

  Future<void> tapPin(WidgetTester tester, String digits) async {
    for (final d in digits.split('')) {
      await tester.tap(find.text(d));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<bool?> persistedAppLock() async =>
      (await SharedPreferences.getInstance()).getBool('prefs.appLock');

  testWidgets('switching ON with no PIN opens enrollment; twice-entry enrolls',
      (tester) async {
    await openSecurity(tester, appLock: false);

    await tapAppLockSwitch(tester);
    expect(find.text('设置 6 位密码'), findsOneWidget);

    await tapPin(tester, '135790');
    expect(find.text('再次输入以确认'), findsOneWidget);

    await tapPin(tester, '135790');
    expect(find.text('设置 6 位密码'), findsNothing); // sheet closed
    expect(await WalletPin.instance.isSet(), isTrue);
    expect((await WalletPin.instance.verify('135790')).isOk, isTrue);
    expect(await persistedAppLock(), isTrue);
  });

  testWidgets('mismatched confirmation resets enrollment; lock stays off',
      (tester) async {
    await openSecurity(tester, appLock: false);

    await tapAppLockSwitch(tester);
    await tapPin(tester, '135790');
    await tapPin(tester, '000000');

    // Back to phase one with the mismatch message; nothing enrolled yet.
    expect(find.text('两次输入不一致，请重新设置'), findsOneWidget);
    expect(find.text('设置 6 位密码'), findsOneWidget);
    expect(await WalletPin.instance.isSet(), isFalse);

    // Dismissing the sheet leaves the lock off.
    await tester.tapAt(const Offset(200, 40));
    await tester.pumpAndSettle();
    expect(await persistedAppLock(), isNot(isTrue));
  });

  testWidgets('switching ON with a PIN already enrolled skips the sheet',
      (tester) async {
    await WalletPin.instance.setPin('135790');
    await openSecurity(tester, appLock: false);

    await tapAppLockSwitch(tester);
    expect(find.text('设置 6 位密码'), findsNothing);
    expect(await persistedAppLock(), isTrue);
  });

  testWidgets('switching OFF requires the current PIN when biometrics cannot',
      (tester) async {
    await WalletPin.instance.setPin('135790');
    await openSecurity(tester, appLock: true);

    await tapAppLockSwitch(tester);
    expect(find.text('输入密码以关闭 App 锁'), findsOneWidget);

    // Wrong PIN: sheet stays with the error, the lock stays on.
    await tapPin(tester, '000000');
    expect(find.text('密码错误，请重试'), findsOneWidget);
    expect(await persistedAppLock(), isTrue);

    // Correct PIN: verified, lock off.
    await tapPin(tester, '135790');
    expect(find.text('输入密码以关闭 App 锁'), findsNothing);
    expect(await persistedAppLock(), isFalse);
  });

  testWidgets('a biometric success also authorizes switching OFF',
      (tester) async {
    BiometricAuth.instance = const FakeBiometricAuth(BiometricOutcome.success);
    await WalletPin.instance.setPin('135790');
    await openSecurity(tester, appLock: true);

    await tapAppLockSwitch(tester);
    expect(find.text('输入密码以关闭 App 锁'), findsNothing); // no sheet needed
    expect(await persistedAppLock(), isFalse);
  });

  testWidgets('dismissing the verify sheet keeps the lock on', (tester) async {
    await WalletPin.instance.setPin('135790');
    await openSecurity(tester, appLock: true);

    await tapAppLockSwitch(tester);
    expect(find.text('输入密码以关闭 App 锁'), findsOneWidget);
    await tester.tapAt(const Offset(200, 40));
    await tester.pumpAndSettle();
    expect(await persistedAppLock(), isTrue);
  });
}
