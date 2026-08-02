import 'package:cold_signer/src/security/biometric_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';

void main() {
  BiometricOutcome outcomeFor(LocalAuthExceptionCode code) =>
      biometricOutcomeForError(LocalAuthException(code: code));

  group('capability problems permit the explicit PIN fallback', () {
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

    test('missing plugin', () {
      expect(
        biometricOutcomeForError(MissingPluginException('local_auth')),
        BiometricOutcome.unavailable,
      );
    });
  });

  group('every other provider outcome fails closed', () {
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

    test('unknown error type', () {
      expect(
        biometricOutcomeForError(StateError('boom')),
        BiometricOutcome.failure,
      );
    });
  });

  test('throwing fake uses the production classifier', () async {
    const cancelled = FakeBiometricAuth.throwing(
      LocalAuthException(code: LocalAuthExceptionCode.userCanceled),
    );
    expect(
      await cancelled.authenticate(reason: 'test'),
      BiometricOutcome.failure,
    );

    const noHardware = FakeBiometricAuth.throwing(
      LocalAuthException(code: LocalAuthExceptionCode.noBiometricHardware),
    );
    expect(
      await noHardware.authenticate(reason: 'test'),
      BiometricOutcome.unavailable,
    );
  });
}
