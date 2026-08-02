import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/src/security/biometric_auth.dart';

/// Android device regression for the privacy-cover/authentication boundary.
///
/// The system prompt must return to the same FragmentActivity. If the native
/// privacy Activity steals the task, this future never completes and the test
/// times out. Run on an emulator or device with biometrics enrolled.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'system authentication returns without privacy Activity hijack',
    () async {
      const auth = LocalAuthBiometricAuth();
      expect(await auth.canAuthenticate(), isTrue);
      expect(
        await auth.authenticate(reason: 'Verify KT Wallet authentication'),
        BiometricOutcome.success,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
