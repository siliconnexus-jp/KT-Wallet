import 'package:flutter/services.dart' show MissingPluginException;
import 'package:local_auth/local_auth.dart';

import '../state/flutter_test_env.dart';

/// Outcome of a biometric/device-credential prompt.
enum BiometricOutcome {
  /// The user passed the platform prompt.
  success,

  /// The user failed or dismissed the prompt, or the platform refused to
  /// produce a verdict for a reason that is NOT a capability problem
  /// (cancellation, timeout, lockout, device error). Callers must stay locked.
  failure,

  /// No usable authentication on this device (no hardware, nothing enrolled,
  /// plugin missing — e.g. widget tests). Callers decide the fallback.
  unavailable,
}

/// Maps an error thrown out of `LocalAuthentication.authenticate` onto a
/// [BiometricOutcome].
///
/// local_auth 3.x signals every non-success outcome *by throwing*: only a
/// plain "user failed the challenge" comes back as `false`; cancellation,
/// timeouts and lockouts arrive as [LocalAuthException]s
/// (local_auth_android/local_auth_darwin). A catch-all that answered
/// [BiometricOutcome.unavailable] would therefore turn a user tapping
/// "Cancel" into "this device cannot authenticate" and let callers fail open.
///
/// Classification rule: only a *capability* problem — nothing to verify
/// against, no biometric hardware, or no plugin at all — is
/// [BiometricOutcome.unavailable]. Everything else is a
/// [BiometricOutcome.failure], which keeps callers locked and lets them offer
/// a retry or their own PIN fallback.
BiometricOutcome biometricOutcomeForError(Object error) {
  // No plugin registered (widget tests, unsupported host): nothing to prompt.
  if (error is MissingPluginException) return BiometricOutcome.unavailable;
  // Anything that is not the plugin's typed error is unclassifiable — fail
  // closed rather than guessing that the device is incapable.
  if (error is! LocalAuthException) return BiometricOutcome.failure;
  // Exhaustive on purpose (no default): a new plugin code must not silently
  // land in the fail-open bucket — the analyzer will flag it here first.
  return switch (error.code) {
    // Capability problems: the platform has nothing to authenticate against
    // on this device, so no amount of retrying produces a verdict.
    LocalAuthExceptionCode.noCredentialsSet ||
    LocalAuthExceptionCode.noBiometricsEnrolled ||
    LocalAuthExceptionCode.noBiometricHardware => BiometricOutcome.unavailable,

    // Real negative verdicts and transient errors. The user dismissed the
    // prompt, the system took it away, the sensor is busy or locked out, or
    // the platform errored — none of these may unlock anything.
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
      // `false` is the one non-throwing negative: the user failed the
      // challenge with no side effects. Every other outcome throws.
      final ok = await auth.authenticate(localizedReason: reason);
      return ok ? BiometricOutcome.success : BiometricOutcome.failure;
    } catch (error) {
      return biometricOutcomeForError(error);
    }
  }
}

/// Scripted implementation for tests.
class FakeBiometricAuth extends BiometricAuth {
  const FakeBiometricAuth(this.outcome, {this.available = true}) : error = null;

  /// Reproduces the plugin's throw-based contract: [error] (typically a
  /// `LocalAuthException`) is pushed through the production classifier
  /// [biometricOutcomeForError], so a test that scripts a user cancellation
  /// gets exactly the outcome a real device produces.
  const FakeBiometricAuth.throwing(Object this.error, {this.available = true})
    : outcome = BiometricOutcome.failure;

  final BiometricOutcome outcome;
  final bool available;

  /// When set, the prompt "throws" this error and the result is classified.
  final Object? error;

  @override
  Future<bool> canAuthenticate() async => available;

  @override
  Future<BiometricOutcome> authenticate({required String reason}) async {
    if (!available) return BiometricOutcome.unavailable;
    final e = error;
    return e == null ? outcome : biometricOutcomeForError(e);
  }
}
