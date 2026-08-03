import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/security/wallet_pin.dart';
import 'package:kt_wallet/src/state/flutter_test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('non-debug builds never trust the FLUTTER_TEST process marker', () {
    expect(
      resolveFlutterTestFallback(
        isDebugBuild: false,
        isWeb: false,
        markerPresent: true,
      ),
      isFalse,
    );
    expect(
      resolveFlutterTestFallback(
        isDebugBuild: true,
        isWeb: false,
        markerPresent: true,
      ),
      isTrue,
    );
    expect(
      resolveFlutterTestFallback(
        isDebugBuild: true,
        isWeb: true,
        markerPresent: true,
      ),
      isFalse,
    );
  });

  test('flutter test keeps its explicit process-local PIN seam', () async {
    final storage = SecurePinStorage.withTestEnvironment(
      isTestEnvironment: true,
    );
    const key = 'secure-pin-test-only';

    await storage.write(key, 'value');
    expect(await storage.read(key), 'value');
    await storage.delete(key);
    expect(await storage.read(key), isNull);
  });

  test('a missing device secure-storage plugin fails closed', () async {
    final storage = SecurePinStorage.withTestEnvironment(
      isTestEnvironment: false,
    );
    const key = 'secure-pin-missing-plugin';

    await expectLater(
      storage.write(key, 'must-not-become-ephemeral'),
      throwsA(isA<MissingPluginException>()),
    );
    await expectLater(
      storage.read(key),
      throwsA(isA<MissingPluginException>()),
    );
    await expectLater(
      storage.delete(key),
      throwsA(isA<MissingPluginException>()),
    );

    final testFallback = SecurePinStorage.withTestEnvironment(
      isTestEnvironment: true,
    );
    expect(await testFallback.read(key), isNull);
  });
}
