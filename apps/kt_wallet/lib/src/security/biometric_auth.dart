import 'package:local_auth/local_auth.dart';

import '../state/flutter_test_env.dart';

/// Outcome of a biometric/device-credential prompt.
enum BiometricOutcome {
  /// The user passed the platform prompt.
  success,

  /// The user failed or dismissed the prompt.
  failure,

  /// No usable authentication on this device (no hardware, nothing enrolled,
  /// plugin missing — e.g. widget tests). Callers decide the fallback.
  unavailable,
}

/// Injectable local-authentication gate. The default routes through
/// local_auth; tests swap [instance] (or pass a fake directly) because the
/// plugin's MethodChannels are dead in the widget-test environment.
abstract class BiometricAuth {
  const BiometricAuth();

  /// Process-wide default, swappable in tests.
  static BiometricAuth instance = const LocalAuthBiometricAuth();

  /// Whether the platform can show any authentication prompt at all.
  Future<bool> canAuthenticate();

  /// Shows the platform prompt (biometrics with device-credential fallback).
  Future<BiometricOutcome> authenticate({required String reason});
}

/// Real implementation over the local_auth plugin. `biometricOnly` stays
/// false: the device PIN/pattern is an acceptable fallback for the prompt.
class LocalAuthBiometricAuth extends BiometricAuth {
  const LocalAuthBiometricAuth();

  @override
  Future<bool> canAuthenticate() async {
    // Under `flutter test` the plugin channel is dead — its futures never
    // complete — so the answer must short-circuit, not await.
    if (isFlutterTestEnv) return false;
    try {
      final auth = LocalAuthentication();
      return await auth.isDeviceSupported() || await auth.canCheckBiometrics;
    } catch (_) {
      return false; // Plugin missing or platform error: unavailable.
    }
  }

  @override
  Future<BiometricOutcome> authenticate({required String reason}) async {
    if (isFlutterTestEnv) return BiometricOutcome.unavailable; // see above
    final auth = LocalAuthentication();
    try {
      if (!await auth.isDeviceSupported()) return BiometricOutcome.unavailable;
      final ok = await auth.authenticate(localizedReason: reason);
      return ok ? BiometricOutcome.success : BiometricOutcome.failure;
    } catch (_) {
      // LocalAuthException (not enrolled, locked out, no activity) or a
      // missing plugin — either way there is no biometric verdict.
      return BiometricOutcome.unavailable;
    }
  }
}

/// Scripted implementation for tests.
class FakeBiometricAuth extends BiometricAuth {
  const FakeBiometricAuth(this.outcome, {this.available = true});
  final BiometricOutcome outcome;
  final bool available;

  @override
  Future<bool> canAuthenticate() async => available;

  @override
  Future<BiometricOutcome> authenticate({required String reason}) async =>
      available ? outcome : BiometricOutcome.unavailable;
}
