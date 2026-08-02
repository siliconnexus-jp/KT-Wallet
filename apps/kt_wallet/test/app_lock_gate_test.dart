import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/security/app_lock_gate.dart';
import 'package:kt_wallet/src/security/biometric_auth.dart';
import 'package:kt_wallet/src/security/wallet_pin.dart';
import 'package:kt_wallet/src/state/app_prefs.dart';
import 'package:kt_wallet/src/state/locale_controller.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _UnavailablePinStorage implements PinStorage {
  const _UnavailablePinStorage();

  @override
  Future<void> delete(String key) =>
      Future<void>.error(StateError('secure storage unavailable'));

  @override
  Future<String?> read(String key) =>
      Future<String?>.error(StateError('secure storage unavailable'));

  @override
  Future<void> write(String key, String value) =>
      Future<void>.error(StateError('secure storage unavailable'));
}

class _WriteUnavailablePinStorage implements PinStorage {
  const _WriteUnavailablePinStorage();

  @override
  Future<void> delete(String key) =>
      Future<void>.error(StateError('secure storage unavailable'));

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) =>
      Future<void>.error(StateError('secure storage unavailable'));
}

/// Wallet-mode app lock: with the preference on the gate blocks until the
/// (fake) biometric prompt passes — or, when biometrics are unavailable or
/// fail, until the enrolled app PIN is entered on the numpad. There is no
/// pass-through: with neither a usable prompt nor a PIN the gate stops on the
/// PIN-enrollment screen.
void main() {
  const child = MaterialApp(home: Scaffold(body: Text('WALLET-HOME')));

  // Low iteration count keeps PBKDF2 fast in tests; the record stores its own
  // count, so this mirrors production behavior exactly.
  WalletPin newPin([InMemoryPinStorage? storage]) =>
      WalletPin(storage ?? InMemoryPinStorage(), iterations: 1000);

  Future<void> pumpGate(
    WidgetTester tester, {
    required AppPrefsController prefs,
    required BiometricAuth auth,
    WalletPin? pin,
  }) async {
    tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      AppLockGate(
        localeController: LocaleController(),
        prefs: prefs,
        auth: auth,
        pin: pin ?? newPin(),
        child: child,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapPin(WidgetTester tester, String digits) async {
    for (final d in digits.split('')) {
      await tester.tap(find.text(d));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('app lock on: gate blocks, then a successful prompt unlocks', (
    tester,
  ) async {
    // Default preference is appLock=true (persistence is dead in tests).
    await pumpGate(
      tester,
      prefs: AppPrefsController(),
      auth: const FakeBiometricAuth(BiometricOutcome.success),
    );

    // Locked: the wallet is hidden behind the lock screen.
    expect(find.text('WALLET-HOME'), findsNothing);
    expect(find.text('App 锁'), findsOneWidget);

    await tester.tap(find.text('使用生物识别验证'));
    await tester.pumpAndSettle();
    expect(find.text('WALLET-HOME'), findsOneWidget);
  });

  testWidgets('a failed prompt with no PIN enrolled keeps the gate locked', (
    tester,
  ) async {
    await pumpGate(
      tester,
      prefs: AppPrefsController(),
      auth: const FakeBiometricAuth(BiometricOutcome.failure),
    );

    await tester.tap(find.text('使用生物识别验证'));
    await tester.pumpAndSettle();
    expect(find.text('WALLET-HOME'), findsNothing);
    expect(find.text('App 锁'), findsOneWidget);
  });

  testWidgets(
    'cancelling the platform prompt does NOT unlock (no PIN enrolled)',
    (tester) async {
      // local_auth 3.x reports a cancel by THROWING. The old catch-all mapped
      // that to "unavailable", which the gate then treated as the legacy
      // pass-through: tapping Cancel opened the wallet. It must stay locked.
      await pumpGate(
        tester,
        prefs: AppPrefsController(),
        auth: const FakeBiometricAuth.throwing(
          LocalAuthException(code: LocalAuthExceptionCode.userCanceled),
        ),
      );

      expect(find.text('App 锁'), findsOneWidget);
      await tester.tap(find.text('使用生物识别验证'));
      await tester.pumpAndSettle();

      expect(find.text('WALLET-HOME'), findsNothing);
      expect(find.text('App 锁'), findsOneWidget); // still the bio lock screen
    },
  );

  testWidgets('a cancelled prompt falls back to the PIN numpad when enrolled', (
    tester,
  ) async {
    final pin = newPin();
    await pin.setPin('135790');
    await pumpGate(
      tester,
      prefs: AppPrefsController(),
      auth: const FakeBiometricAuth.throwing(
        LocalAuthException(code: LocalAuthExceptionCode.userCanceled),
      ),
      pin: pin,
    );

    await tester.tap(find.text('使用生物识别验证'));
    await tester.pumpAndSettle();
    expect(find.text('WALLET-HOME'), findsNothing);
    expect(find.text('输入密码解锁'), findsOneWidget);
  });

  testWidgets('a biometric lockout does NOT unlock either', (tester) async {
    await pumpGate(
      tester,
      prefs: AppPrefsController(),
      auth: const FakeBiometricAuth.throwing(
        LocalAuthException(code: LocalAuthExceptionCode.biometricLockout),
      ),
    );

    await tester.tap(find.text('使用生物识别验证'));
    await tester.pumpAndSettle();
    expect(find.text('WALLET-HOME'), findsNothing);
  });

  testWidgets('secure storage startup failure keeps the wallet hard locked', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpGate(
      tester,
      prefs: AppPrefsController(),
      auth: const FakeBiometricAuth(BiometricOutcome.success),
      pin: WalletPin(const _UnavailablePinStorage(), iterations: 1000),
    );

    expect(find.text('WALLET-HOME'), findsNothing);
    expect(find.text('安全存储不可用'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    await expectLater(
      find.byType(AppLockGate),
      matchesGoldenFile('goldens/screens/secure-storage-unavailable.png'),
    );

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('WALLET-HOME'), findsNothing);
    expect(find.text('安全存储不可用'), findsOneWidget);
  });

  testWidgets('PIN enrollment write failure never unlocks the wallet', (
    tester,
  ) async {
    await pumpGate(
      tester,
      prefs: AppPrefsController(),
      auth: const FakeBiometricAuth(BiometricOutcome.failure, available: false),
      pin: WalletPin(const _WriteUnavailablePinStorage(), iterations: 1000),
    );

    await tapPin(tester, '135790135790');
    expect(find.text('WALLET-HOME'), findsNothing);
    expect(find.text('安全存储不可用'), findsOneWidget);
  });

  testWidgets(
    'no usable biometrics AND no PIN: enrollment screen, not pass-through',
    (tester) async {
      await pumpGate(
        tester,
        prefs: AppPrefsController(),
        auth: const FakeBiometricAuth(
          BiometricOutcome.success,
          available: false,
        ),
      );

      // The wallet stays hidden; the gate asks for a PIN to be established.
      expect(find.text('WALLET-HOME'), findsNothing);
      expect(find.text('设置解锁密码'), findsOneWidget);
      expect(find.text('设置 6 位密码'), findsOneWidget);
    },
  );

  testWidgets('enrolling a PIN from the gate opens the wallet and persists', (
    tester,
  ) async {
    final storage = InMemoryPinStorage();
    await pumpGate(
      tester,
      prefs: AppPrefsController(),
      auth: const FakeBiometricAuth(BiometricOutcome.success, available: false),
      pin: newPin(storage),
    );

    expect(find.text('设置解锁密码'), findsOneWidget);

    // Mismatched confirmation restarts the enrollment; the wallet stays shut.
    await tapPin(tester, '135790');
    expect(find.text('再次输入以确认'), findsOneWidget);
    await tapPin(tester, '246800');
    expect(find.text('两次输入不一致，请重新设置'), findsOneWidget);
    expect(find.text('WALLET-HOME'), findsNothing);

    // A matching confirmation enrolls the PIN and lets this launch through.
    await tapPin(tester, '135790');
    await tapPin(tester, '135790');
    expect(find.text('WALLET-HOME'), findsOneWidget);

    // The PIN really landed in storage, so the next launch takes the numpad.
    expect(await newPin(storage).isSet(), isTrue);
    expect((await newPin(storage).verify('135790')).isOk, isTrue);
  });

  testWidgets('app lock off: straight through', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = AppPrefsController();
    await prefs.setAppLock(false);
    await pumpGate(
      tester,
      prefs: prefs,
      auth: const FakeBiometricAuth(BiometricOutcome.failure),
    );

    expect(find.text('WALLET-HOME'), findsOneWidget);
  });

  testWidgets(
    'bio unavailable + PIN enrolled: numpad appears, correct PIN unlocks',
    (tester) async {
      final pin = newPin();
      await pin.setPin('135790');
      await pumpGate(
        tester,
        prefs: AppPrefsController(),
        auth: const FakeBiometricAuth(
          BiometricOutcome.success,
          available: false,
        ),
        pin: pin,
      );

      // No pass-through: the PIN numpad is the lock screen.
      expect(find.text('WALLET-HOME'), findsNothing);
      expect(find.text('输入密码解锁'), findsOneWidget);

      await tapPin(tester, '135790');
      expect(find.text('WALLET-HOME'), findsOneWidget);
    },
  );

  testWidgets('wrong PIN stays locked with the error message; retry unlocks', (
    tester,
  ) async {
    final pin = newPin();
    await pin.setPin('135790');
    await pumpGate(
      tester,
      prefs: AppPrefsController(),
      auth: const FakeBiometricAuth(BiometricOutcome.success, available: false),
      pin: pin,
    );

    await tapPin(tester, '000000');
    expect(find.text('WALLET-HOME'), findsNothing);
    expect(find.text('密码错误，请重试'), findsOneWidget);

    await tapPin(tester, '135790');
    expect(find.text('WALLET-HOME'), findsOneWidget);
  });

  testWidgets(
    '5 wrong PINs engage the lockout message and refuse the right PIN',
    (tester) async {
      final pin = newPin();
      await pin.setPin('135790');
      await pumpGate(
        tester,
        prefs: AppPrefsController(),
        auth: const FakeBiometricAuth(
          BiometricOutcome.success,
          available: false,
        ),
        pin: pin,
      );

      for (var i = 0; i < 5; i++) {
        await tapPin(tester, '000000');
      }
      // 5th failure engaged the 30s lock: 尝试次数过多，请 N 秒后重试.
      expect(find.textContaining('尝试次数过多'), findsOneWidget);

      // Even the correct PIN is refused while locked out.
      await tapPin(tester, '135790');
      expect(find.text('WALLET-HOME'), findsNothing);
      expect(find.textContaining('尝试次数过多'), findsOneWidget);
    },
  );

  testWidgets('persisted lockout shows its message before any key is pressed', (
    tester,
  ) async {
    final storage = InMemoryPinStorage();
    final enrolled = newPin(storage);
    await enrolled.setPin('135790');
    for (var i = 0; i < 5; i++) {
      await enrolled.verify('000000');
    }
    // "Restart": a fresh WalletPin over the same storage still knows the lock.
    await pumpGate(
      tester,
      prefs: AppPrefsController(),
      auth: const FakeBiometricAuth(BiometricOutcome.success, available: false),
      pin: newPin(storage),
    );

    expect(find.textContaining('尝试次数过多'), findsOneWidget);
  });

  testWidgets('bio failure with a PIN enrolled falls back to the numpad', (
    tester,
  ) async {
    final pin = newPin();
    await pin.setPin('135790');
    await pumpGate(
      tester,
      prefs: AppPrefsController(),
      auth: const FakeBiometricAuth(BiometricOutcome.failure),
      pin: pin,
    );

    await tester.tap(find.text('使用生物识别验证'));
    await tester.pumpAndSettle();
    expect(find.text('输入密码解锁'), findsOneWidget);

    await tapPin(tester, '135790');
    expect(find.text('WALLET-HOME'), findsOneWidget);
  });

  testWidgets(
    'the biometric lock screen offers a direct PIN path when enrolled',
    (tester) async {
      final pin = newPin();
      await pin.setPin('135790');
      await pumpGate(
        tester,
        prefs: AppPrefsController(),
        auth: const FakeBiometricAuth(BiometricOutcome.success),
        pin: pin,
      );

      await tester.tap(find.text('使用密码解锁'));
      await tester.pumpAndSettle();
      expect(find.text('输入密码解锁'), findsOneWidget);

      await tapPin(tester, '135790');
      expect(find.text('WALLET-HOME'), findsOneWidget);
    },
  );
}
