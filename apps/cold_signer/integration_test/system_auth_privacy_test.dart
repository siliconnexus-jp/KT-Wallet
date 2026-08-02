import 'package:cold_signer/src/security/biometric_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Android device regression for the privacy-cover/authentication boundary.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'system authentication returns without privacy Activity hijack',
    () async {
      const auth = LocalAuthBiometricAuth();
      expect(await auth.canAuthenticate(), isTrue);
      expect(
        await auth.authenticate(reason: 'Verify KT Cold Signer authentication'),
        BiometricOutcome.success,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
