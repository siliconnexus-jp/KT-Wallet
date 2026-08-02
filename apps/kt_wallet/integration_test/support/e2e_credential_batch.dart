import 'package:test_support/e2e_credentials.dart';

const _mnemonic = String.fromEnvironment(e2eMnemonicKey);
const _schema = String.fromEnvironment('KT_E2E_SCHEMA_VERSION');
const _batchId = String.fromEnvironment(e2eBatchIdKey);
const _createdAt = String.fromEnvironment(e2eCreatedAtKey);
const _expiresAt = String.fromEnvironment(e2eExpiresAtKey);

/// Makes direct `flutter test integration_test/...` runs fail closed when a
/// real mnemonic is supplied without a fresh, versioned credential batch.
///
/// Tests without any real credential keep their existing skip behavior.
void requireFreshE2eCredentialBatchIfConfigured() {
  if (_mnemonic.trim().isEmpty) return;
  final failures = validateE2eCredentialDocument({
    'KT_E2E_SCHEMA_VERSION': _schema,
    e2eBatchIdKey: _batchId,
    e2eCreatedAtKey: _createdAt,
    e2eExpiresAtKey: _expiresAt,
    e2eMnemonicKey: _mnemonic,
  }, nowUtc: DateTime.now().toUtc());
  if (failures.isNotEmpty) {
    throw StateError(
      'Real-chain E2E credential batch rejected: ${failures.join('; ')}. '
      'Run tool/e2e_credential_guard.dart validate before the device test.',
    );
  }
}
