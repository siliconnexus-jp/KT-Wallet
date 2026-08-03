/// Test-only credential-batch policy for real-chain E2E runs.
///
/// This library never derives addresses and never logs secret values. It only
/// validates the metadata surrounding a locally stored, disposable test
/// mnemonic and detects accidental disclosure in text reports.
library;

const e2eCredentialSchemaVersion = '1';
const e2eMnemonicKey = 'SEPOLIA_E2E_MNEMONIC';
const e2eBatchIdKey = 'KT_E2E_BATCH_ID';
const e2eCreatedAtKey = 'KT_E2E_CREATED_AT_UTC';
const e2eExpiresAtKey = 'KT_E2E_EXPIRES_AT_UTC';

const e2eCredentialRequiredKeys = {
  'KT_E2E_SCHEMA_VERSION',
  e2eBatchIdKey,
  e2eCreatedAtKey,
  e2eExpiresAtKey,
  e2eMnemonicKey,
};

/// Text files that can carry credentials and are safe to decode as UTF-8.
///
/// This intentionally includes test source. Fake provider fixtures must be
/// assembled at runtime so the repository itself never contains a token-shaped
/// value that GitHub Push Protection would reject.
const _e2eSecretScanTextExtensions = {
  '.arb',
  '.astro',
  '.conf',
  '.css',
  '.dart',
  '.entitlements',
  '.env',
  '.go',
  '.gradle',
  '.h',
  '.html',
  '.js',
  '.json',
  '.kt',
  '.kts',
  '.lock',
  '.log',
  '.m',
  '.md',
  '.mm',
  '.pbxproj',
  '.plist',
  '.podspec',
  '.properties',
  '.rs',
  '.scss',
  '.sh',
  '.swift',
  '.toml',
  '.ts',
  '.txt',
  '.xcconfig',
  '.xcprivacy',
  '.xml',
  '.yaml',
  '.yml',
};

const _e2eSecretScanExtensionlessFiles = {
  'Dockerfile',
  'Gemfile',
  'Makefile',
  'Podfile',
  'gradlew',
};

/// Whether [path] is a public text artifact that the repository secret gate
/// must inspect before commit/push.
bool isE2eSecretScanTextPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final basename = normalized.substring(normalized.lastIndexOf('/') + 1);
  if (_e2eSecretScanExtensionlessFiles.contains(basename)) return true;
  final dot = basename.lastIndexOf('.');
  if (dot < 0) return false;
  return _e2eSecretScanTextExtensions.contains(
    basename.substring(dot).toLowerCase(),
  );
}

/// Maximum lifetime of a real-chain test credential batch.
const e2eCredentialMaximumLifetime = Duration(days: 14);

/// Builds the string-only document consumed by Flutter
/// `--dart-define-from-file` after the operator has generated a fresh phrase
/// with a native Wallet Core screen.
Map<String, String> buildE2eCredentialDocument({
  required String batchId,
  required DateTime createdAtUtc,
  required Duration lifetime,
  required String mnemonic,
}) => {
  'KT_E2E_SCHEMA_VERSION': e2eCredentialSchemaVersion,
  e2eBatchIdKey: batchId,
  e2eCreatedAtKey: createdAtUtc.toUtc().toIso8601String(),
  e2eExpiresAtKey: createdAtUtc.toUtc().add(lifetime).toIso8601String(),
  e2eMnemonicKey: mnemonic.trim(),
};

/// Validates a decoded `--dart-define-from-file` credential document.
///
/// All values must be strings because Flutter's define-from-file contract is
/// a string map. The mnemonic is deliberately validated only structurally;
/// BIP-39 checksum validation remains the responsibility of the native Wallet
/// Core path used by the E2E test.
List<String> validateE2eCredentialDocument(
  Map<String, Object?> document, {
  required DateTime nowUtc,
  Duration maximumLifetime = e2eCredentialMaximumLifetime,
}) {
  final failures = <String>[];
  for (final key in e2eCredentialRequiredKeys) {
    final value = document[key];
    if (value is! String || value.trim().isEmpty) {
      failures.add('missing or empty $key');
    }
  }
  if (failures.isNotEmpty) return failures;

  if (document['KT_E2E_SCHEMA_VERSION'] != e2eCredentialSchemaVersion) {
    failures.add('unsupported KT_E2E_SCHEMA_VERSION');
  }

  final batchId = document[e2eBatchIdKey]! as String;
  if (!RegExp(r'^[a-z0-9][a-z0-9_-]{7,63}$').hasMatch(batchId)) {
    failures.add('invalid KT_E2E_BATCH_ID');
  }

  final createdText = document[e2eCreatedAtKey]! as String;
  final expiresText = document[e2eExpiresAtKey]! as String;
  final createdAt = _parseUtc(createdText);
  final expiresAt = _parseUtc(expiresText);
  if (createdAt == null) failures.add('invalid KT_E2E_CREATED_AT_UTC');
  if (expiresAt == null) failures.add('invalid KT_E2E_EXPIRES_AT_UTC');
  if (createdAt != null && expiresAt != null) {
    if (!expiresAt.isAfter(createdAt)) {
      failures.add('credential expiry must be after creation');
    }
    if (expiresAt.difference(createdAt) > maximumLifetime) {
      failures.add(
        'credential lifetime exceeds ${maximumLifetime.inDays} days',
      );
    }
    if (createdAt.isAfter(nowUtc.toUtc().add(const Duration(minutes: 5)))) {
      failures.add('credential creation time is in the future');
    }
    if (!expiresAt.isAfter(nowUtc.toUtc())) {
      failures.add('credential batch has expired');
    }
  }

  final mnemonic = (document[e2eMnemonicKey]! as String).trim();
  final words = mnemonic.split(RegExp(r'\s+'));
  if (!const {12, 18, 24}.contains(words.length)) {
    failures.add('test mnemonic must contain 12, 18, or 24 words');
  }
  if (words.any((word) => !RegExp(r'^[a-z]+$').hasMatch(word))) {
    failures.add('test mnemonic contains invalid word syntax');
  }
  // The most common public BIP-39 vector must never become a funded E2E key.
  if (mnemonic ==
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about') {
    failures.add(
      'public BIP-39 vector cannot be used as a funded test account',
    );
  }
  if (words.toSet().length == 1) {
    failures.add('repeated-word mnemonic cannot be used as a test account');
  }

  return failures;
}

DateTime? _parseUtc(String value) {
  if (!value.endsWith('Z')) return null;
  final parsed = DateTime.tryParse(value);
  return parsed?.isUtc == true ? parsed : null;
}

/// Returns labels for secrets found in report/source text without returning
/// any part of the secret itself.
List<String> findE2eSecretLeakLabels(String contents, {String? mnemonic}) {
  final labels = <String>[];
  final normalizedMnemonic = mnemonic?.trim();
  if (normalizedMnemonic != null &&
      normalizedMnemonic.isNotEmpty &&
      contents.contains(normalizedMnemonic)) {
    labels.add('configured test mnemonic');
  }

  final credentialPatterns = <String, RegExp>{
    'GitHub token': RegExp(
      r'\b(?:github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{20,})\b',
    ),
    'Alchemy token': RegExp(r'\balch_[A-Za-z0-9_-]{12,}\b'),
    'Etherscan API key': RegExp(
      r'''\bETHERSCAN_API_KEY[ \t]*[:=][ \t]*["']?[A-Za-z0-9]{20,}\b''',
      caseSensitive: false,
    ),
    'Helius API key': RegExp(
      r'''\bHELIUS_API_KEY[ \t]*[:=][ \t]*["']?[A-Za-z0-9_-]{20,}\b''',
      caseSensitive: false,
    ),
    'GoPlus access token': RegExp(
      r'''\bGOPLUS_ACCESS_TOKEN[ \t]*[:=][ \t]*["']?[A-Za-z0-9._~-]{20,}\b''',
      caseSensitive: false,
    ),
    'metrics bearer token': RegExp(
      r'''\bMETRICS_BEARER_TOKEN[ \t]*[:=][ \t]*["']?[A-Za-z0-9_+/=-]{32,}\b''',
      caseSensitive: false,
    ),
    'Slack token': RegExp(
      r'\bxox[baprs]-[A-Za-z0-9-]{20,}\b',
      caseSensitive: false,
    ),
    'Stripe secret key': RegExp(
      r'\bsk_(?:live|test)_[A-Za-z0-9]{20,}\b',
      caseSensitive: false,
    ),
    'Google API key': RegExp(r'\bAIza[A-Za-z0-9_-]{20,}\b'),
    'private-key assignment': RegExp(
      r'''(?:private[_ -]?key|secret[_ -]?key)\s*[:=]\s*["']?(?:0x)?[0-9a-f]{64}\b''',
      caseSensitive: false,
    ),
  };
  for (final entry in credentialPatterns.entries) {
    if (entry.value.hasMatch(contents)) labels.add(entry.key);
  }
  return labels;
}

/// True only for POSIX mode `0600`; type bits in [mode] are ignored.
bool hasPrivateCredentialFileMode(int mode) => (mode & 0x1ff) == 0x180;
