import 'package:cold_signer/src/security/secure_vault.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('flutter test keeps its explicit process-local storage seam', () async {
    final storage = SecureVaultStorage.withTestEnvironment(
      isTestEnvironment: true,
    );
    const key = 'secure-vault-test-only';

    await storage.write(key, 'value');
    expect(await storage.read(key), 'value');
    await storage.delete(key);
    expect(await storage.read(key), isNull);
  });

  test('a missing device secure-storage plugin fails closed', () async {
    final storage = SecureVaultStorage.withTestEnvironment(
      isTestEnvironment: false,
    );
    const key = 'secure-vault-missing-plugin';

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

    final testFallback = SecureVaultStorage.withTestEnvironment(
      isTestEnvironment: true,
    );
    expect(await testFallback.read(key), isNull);
  });
}
