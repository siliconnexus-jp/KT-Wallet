import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/security/biometric_auth.dart';
import 'package:local_auth/local_auth.dart';

/// local_auth 3.x signals every non-success outcome by THROWING, so the whole
/// safety of the app lock rests on how those throws are classified. A
/// catch-all that answered [BiometricOutcome.unavailable] turned "the user
/// tapped Cancel" into "this device cannot authenticate", which callers are
/// entitled to treat as a capability problem and fail open on.
///
/// Rule under test: only a capability problem is `unavailable`; every
/// cancellation, timeout, lockout or device error is `failure`.
void main() {
  BiometricOutcome outcomeFor(LocalAuthExceptionCode code) =>
      biometricOutcomeForError(LocalAuthException(code: code));

  group('capability problems are unavailable', () {
    const unavailable = {
      LocalAuthExceptionCode.noCredentialsSet,
      LocalAuthExceptionCode.noBiometricsEnrolled,
      LocalAuthExceptionCode.noBiometricHardware,
    };

    for (final code in unavailable) {
      test(code.name, () {
        expect(outcomeFor(code), BiometricOutcome.unavailable);
      });
    }

    test('a missing plugin (widget tests, unsupported host)', () {
      expect(
        biometricOutcomeForError(MissingPluginException('local_auth')),
        BiometricOutcome.unavailable,
      );
    });
  });

  group('every other outcome is a failure (fail closed)', () {
    // Enumerated from the enum itself minus the capability codes, so a new
    // plugin code cannot quietly skip this test.
    final failures = LocalAuthExceptionCode.values.toSet()
      ..removeAll({
        LocalAuthExceptionCode.noCredentialsSet,
        LocalAuthExceptionCode.noBiometricsEnrolled,
        LocalAuthExceptionCode.noBiometricHardware,
      });

    for (final code in failures) {
      test(code.name, () {
        expect(outcomeFor(code), BiometricOutcome.failure);
      });
    }

    test('user cancellation specifically', () {
      // The release-blocking case: this must never be `unavailable`.
      expect(
        outcomeFor(LocalAuthExceptionCode.userCanceled),
        BiometricOutcome.failure,
      );
    });

    test('an unrecognised error type', () {
      expect(
        biometricOutcomeForError(StateError('boom')),
        BiometricOutcome.failure,
      );
    });
  });

  test('FakeBiometricAuth.throwing routes through the real classifier', () async {
    const cancelled = FakeBiometricAuth.throwing(
      LocalAuthException(code: LocalAuthExceptionCode.userCanceled),
    );
    expect(
      await cancelled.authenticate(reason: 'x'),
      BiometricOutcome.failure,
    );

    const noHardware = FakeBiometricAuth.throwing(
      LocalAuthException(code: LocalAuthExceptionCode.noBiometricHardware),
    );
    expect(
      await noHardware.authenticate(reason: 'x'),
      BiometricOutcome.unavailable,
    );
  });
}
