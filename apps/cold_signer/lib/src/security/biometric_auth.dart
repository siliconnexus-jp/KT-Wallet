import 'package:flutter/services.dart'
    show MethodChannel, MissingPluginException;
import 'package:local_auth/local_auth.dart';

import 'secure_vault.dart' show isFlutterTestEnv;

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

/// Classifies the throw-based `local_auth` contract without turning a real
/// negative verdict into a capability problem.
///
/// Callers may offer the App PIN automatically only for [unavailable]. User
/// cancellation, OS cancellation, timeout, lockout and device errors must
/// remain [failure], otherwise tapping Cancel on the system sheet silently
/// changes the selected authentication method.
BiometricOutcome biometricOutcomeForError(Object error) {
  if (error is MissingPluginException) return BiometricOutcome.unavailable;
  if (error is! LocalAuthException) return BiometricOutcome.failure;
  return switch (error.code) {
    LocalAuthExceptionCode.noCredentialsSet ||
    LocalAuthExceptionCode.noBiometricsEnrolled ||
    LocalAuthExceptionCode.noBiometricHardware => BiometricOutcome.unavailable,
    LocalAuthExceptionCode.userCanceled ||
    LocalAuthExceptionCode.systemCanceled ||
    LocalAuthExceptionCode.timeout ||
    LocalAuthExceptionCode.authInProgress ||
    LocalAuthExceptionCode.userRequestedFallback ||
    LocalAuthExceptionCode.temporaryLockout ||
    LocalAuthExceptionCode.biometricLockout ||
    LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable ||
    LocalAuthExceptionCode.uiUnavailable ||
    LocalAuthExceptionCode.deviceError ||
    LocalAuthExceptionCode.unknownError => BiometricOutcome.failure,
  };
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

  static const _authVisibility = MethodChannel('kt/system_auth_visibility');

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
      await _notifyAuthVisibility('started');
      try {
        final ok = await auth.authenticate(localizedReason: reason);
        return ok ? BiometricOutcome.success : BiometricOutcome.failure;
      } finally {
        await _notifyAuthVisibility('finished');
      }
    } catch (error) {
      return biometricOutcomeForError(error);
    }
  }

  Future<void> _notifyAuthVisibility(String method) async {
    try {
      await _authVisibility.invokeMethod<void>(method);
    } catch (_) {
      // Coordination failure cannot weaken or replace authentication.
    }
  }
}

/// Scripted implementation for tests.
class FakeBiometricAuth extends BiometricAuth {
  const FakeBiometricAuth(this.outcome, {this.available = true}) : error = null;

  const FakeBiometricAuth.throwing(Object this.error, {this.available = true})
    : outcome = BiometricOutcome.failure;

  final BiometricOutcome outcome;
  final bool available;
  final Object? error;

  @override
  Future<bool> canAuthenticate() async => available;

  @override
  Future<BiometricOutcome> authenticate({required String reason}) async {
    if (!available) return BiometricOutcome.unavailable;
    final thrown = error;
    return thrown == null ? outcome : biometricOutcomeForError(thrown);
  }
}
