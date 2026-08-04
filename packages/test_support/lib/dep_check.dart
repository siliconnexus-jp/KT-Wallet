/// Dependency-firewall checks for the cold_signer app.
///
/// Pure functions so they can be unit-tested against fixtures; the repo-level
/// entrypoint is `tool/check_deps.dart`.
library;

import 'dart:convert';

final _cjkText = RegExp(r'[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]');
final _asciiPunctuationBesideCjk = RegExp(
  r'[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af][,:;]|'
  r'[,:;](?:[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]|\{)',
);

/// Verifies an intentionally narrow set of Gradle dependency pins.
///
/// Each artifact must appear exactly once with the reviewed SHA-256 and
/// [origin]. The origin marker must not appear on any additional artifact, so
/// copying it onto an unreviewed dependency cannot silently broaden trust.
List<String> findReviewedArtifactPinIssues(
  String verificationMetadata,
  Map<String, String> reviewedArtifacts, {
  required String origin,
}) {
  final issues = <String>[];
  for (final artifact in reviewedArtifacts.entries) {
    final artifactTag = RegExp(
      '<artifact name="${RegExp.escape(artifact.key)}">',
    );
    final exactBlock = RegExp(
      '<artifact name="${RegExp.escape(artifact.key)}">\\s*'
      '<sha256 value="${artifact.value}" origin="${RegExp.escape(origin)}"/>\\s*'
      '</artifact>',
    );
    if (artifactTag.allMatches(verificationMetadata).length != 1 ||
        exactBlock.allMatches(verificationMetadata).length != 1) {
      issues.add('${artifact.key}: missing, duplicated, or hash mismatch');
    }
  }
  if (RegExp(
        'origin="${RegExp.escape(origin)}"',
      ).allMatches(verificationMetadata).length !=
      reviewedArtifacts.length) {
    issues.add('reviewed trust set was broadened or truncated');
  }
  return issues;
}

Set<String> _icuPlaceholders(String value) => RegExp(
  r'\{([A-Za-z_][A-Za-z0-9_]*)\s*(?:,|\})',
).allMatches(value).map((match) => match.group(1)!).toSet();

/// Rejects retired or locale-inappropriate brand terms in user-visible ARB
/// messages. Terms are matched literally and reported with locale + key so a
/// release review can distinguish production copy from source comments and
/// historical documentation.
List<String> findForbiddenLocalizationTermIssues(
  Map<String, String> catalogs,
  Map<String, Set<String>> forbiddenTermsByLocale,
) {
  final issues = <String>[];
  for (final policy in forbiddenTermsByLocale.entries) {
    final source = catalogs[policy.key];
    if (source == null) {
      issues.add('${policy.key}: missing catalog for forbidden-term policy');
      continue;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      issues.add('${policy.key}: invalid JSON for forbidden-term policy');
      continue;
    }
    if (decoded is! Map<String, dynamic>) {
      issues.add('${policy.key}: ARB root must be an object');
      continue;
    }
    for (final term in policy.value) {
      if (term.isEmpty) {
        issues.add('${policy.key}: forbidden term must not be empty');
        continue;
      }
      for (final message in decoded.entries) {
        if (message.key.startsWith('@') || message.value is! String) continue;
        if ((message.value as String).contains(term)) {
          issues.add(
            '${policy.key}:${message.key}: contains forbidden term "$term"',
          );
        }
      }
    }
  }
  return issues;
}

/// Validates that localized Flutter ARB catalogs expose the exact same
/// user-visible keys and ICU placeholders as the English source catalog.
///
/// Metadata entries (`@key`) are intentionally ignored: Flutter permits
/// translator catalogs to omit source-only descriptions, while the runtime
/// contract is the user-visible key and placeholder set. English is also
/// checked for accidental CJK fallback text because it is the platform and
/// unsupported-locale fallback.
List<String> findArbCatalogIssues(
  Map<String, String> catalogs, {
  String defaultLocale = 'en',
  Map<String, Set<String>> sameAsDefaultAllowedKeys = const {},
  Map<String, Set<String>> cjkAsciiPunctuationAllowedKeys = const {},
}) {
  final issues = <String>[];
  final parsed = <String, Map<String, String>>{};

  for (final entry in catalogs.entries) {
    Object? decoded;
    try {
      decoded = jsonDecode(entry.value);
    } on FormatException {
      issues.add('${entry.key}: invalid JSON');
      continue;
    }
    if (decoded is! Map<String, dynamic>) {
      issues.add('${entry.key}: ARB root must be an object');
      continue;
    }
    if (decoded['@@locale'] != entry.key) {
      issues.add(
        '${entry.key}: @@locale must equal ${entry.key}, got ${decoded['@@locale']}',
      );
    }
    final messages = <String, String>{};
    for (final message in decoded.entries) {
      if (message.key.startsWith('@')) continue;
      if (message.value is! String) {
        issues.add('${entry.key}:${message.key}: value must be a string');
        continue;
      }
      if ((message.value as String).trim().isEmpty) {
        issues.add('${entry.key}:${message.key}: value is empty');
      }
      messages[message.key] = message.value as String;
    }
    parsed[entry.key] = messages;
  }

  final source = parsed[defaultLocale];
  if (source == null) {
    issues.add('missing default ARB catalog: $defaultLocale');
    return issues;
  }

  for (final allowance in sameAsDefaultAllowedKeys.entries) {
    if (allowance.key == defaultLocale || !parsed.containsKey(allowance.key)) {
      issues.add(
        '${allowance.key}: identical-value allowlist locale is invalid',
      );
      continue;
    }
    final unknown = allowance.value.difference(source.keys.toSet());
    if (unknown.isNotEmpty) {
      issues.add(
        '${allowance.key}: identical-value allowlist has unknown keys '
        '${unknown.toList()..sort()}',
      );
    }
  }
  for (final allowance in cjkAsciiPunctuationAllowedKeys.entries) {
    if (allowance.key == defaultLocale || !parsed.containsKey(allowance.key)) {
      issues.add(
        '${allowance.key}: CJK punctuation allowlist locale is invalid',
      );
      continue;
    }
    final unknown = allowance.value.difference(source.keys.toSet());
    if (unknown.isNotEmpty) {
      issues.add(
        '${allowance.key}: CJK punctuation allowlist has unknown keys '
        '${unknown.toList()..sort()}',
      );
    }
  }

  for (final entry in parsed.entries) {
    final missing = source.keys.toSet().difference(entry.value.keys.toSet());
    final extra = entry.value.keys.toSet().difference(source.keys.toSet());
    if (missing.isNotEmpty) {
      issues.add('${entry.key}: missing keys ${missing.toList()..sort()}');
    }
    if (extra.isNotEmpty) {
      issues.add('${entry.key}: extra keys ${extra.toList()..sort()}');
    }
    for (final key in source.keys.toSet().intersection(
      entry.value.keys.toSet(),
    )) {
      final expected = _icuPlaceholders(source[key]!);
      final actual = _icuPlaceholders(entry.value[key]!);
      if (expected.length != actual.length || !expected.containsAll(actual)) {
        issues.add(
          '${entry.key}:$key: placeholders ${actual.toList()..sort()} '
          'do not match ${expected.toList()..sort()}',
        );
      }
      if (entry.key != defaultLocale &&
          entry.value[key] == source[key] &&
          !(sameAsDefaultAllowedKeys[entry.key]?.contains(key) ?? false)) {
        issues.add('${entry.key}:$key: value is identical to $defaultLocale');
      }
      if (entry.key != defaultLocale &&
          _asciiPunctuationBesideCjk.hasMatch(entry.value[key]!) &&
          !(cjkAsciiPunctuationAllowedKeys[entry.key]?.contains(key) ??
              false)) {
        issues.add('${entry.key}:$key: ASCII punctuation beside CJK');
      }
    }
  }

  for (final entry in source.entries) {
    if (_cjkText.hasMatch(entry.value)) {
      issues.add('$defaultLocale:${entry.key}: English fallback contains CJK');
    }
  }
  return issues;
}

/// Rejects ordinary English interface prose accidentally left inside Chinese
/// or Japanese ARB messages. Protocol identifiers and reviewed product terms
/// are intentionally not part of [forbiddenTerms]; this gate targets words a
/// translator should localize (for example `From`, `Retry`, or `Password`).
List<String> findUntranslatedCjkProseIssues(
  Map<String, String> catalogs, {
  Set<String> forbiddenTerms = const {
    'Account',
    'Address',
    'Amount',
    'Back',
    'Balance',
    'Cancel',
    'Confirm',
    'Continue',
    'Error',
    'Failed',
    'Failure',
    'Fee',
    'From',
    'Invalid',
    'Network',
    'Next',
    'Password',
    'Receive',
    'Recipient',
    'Required',
    'Retry',
    'Seed',
    'Send',
    'Settings',
    'Symbol',
    'To',
    'Unable',
    'Unavailable',
    'Unknown',
    'Warning',
  },
  Map<String, Set<String>> allowedKeys = const {},
}) {
  final issues = <String>[];
  final forbiddenLowercase = {
    for (final term in forbiddenTerms) term.toLowerCase(),
  };
  final remainingAllowedKeys = {
    for (final entry in allowedKeys.entries) entry.key: {...entry.value},
  };
  for (final locale in remainingAllowedKeys.keys.where(
    (locale) => locale != 'zh' && locale != 'ja',
  )) {
    issues.add('$locale: unsupported untranslated-prose allowlist locale');
  }
  for (final locale in const ['zh', 'ja']) {
    final contents = catalogs[locale];
    if (contents == null) continue;
    Object? decoded;
    try {
      decoded = jsonDecode(contents);
    } on FormatException {
      continue;
    }
    if (decoded is! Map<String, dynamic>) continue;
    for (final entry in decoded.entries) {
      if (entry.key.startsWith('@') || entry.value is! String) continue;
      if (allowedKeys[locale]?.contains(entry.key) ?? false) {
        remainingAllowedKeys[locale]?.remove(entry.key);
        continue;
      }
      final withoutPlaceholders = (entry.value as String).replaceAll(
        RegExp(r'\{[^{}]*\}'),
        '',
      );
      final words = RegExp(
        r'[A-Za-z]+',
      ).allMatches(withoutPlaceholders).map((match) => match.group(0)!);
      final found =
          words
              .where((word) => forbiddenLowercase.contains(word.toLowerCase()))
              .toSet()
              .toList()
            ..sort();
      if (found.isNotEmpty) {
        issues.add('$locale:${entry.key}: untranslated UI prose $found');
      }
    }
  }
  for (final locale in const ['zh', 'ja']) {
    for (final key in remainingAllowedKeys[locale] ?? const <String>{}) {
      issues.add('$locale:$key: stale untranslated-prose allowlist');
    }
  }
  return issues;
}

/// Keeps official network names, protocol identifiers, and asset symbols
/// byte-for-byte stable across locales. The rule applies only when the English
/// source message contains a protected term; surrounding prose remains fully
/// translatable.
List<String> findProtectedArbTermIssues(
  Map<String, String> catalogs, {
  String defaultLocale = 'en',
  Set<String> protectedTerms = const {
    'Ethereum',
    'Polygon',
    'Base',
    'Arbitrum',
    'Avalanche',
    'BNB Smart Chain',
    'TRON',
    'Solana',
    'ETH',
    'POL',
    'AVAX',
    'BNB',
    'TRX',
    'SOL',
    'USDT',
    'USDC',
    'BUSD',
    'PYUSD',
    'DAI',
    'WETH',
    'WBTC',
    'LINK',
    'UNI',
    'SHIB',
    'PEPE',
    'JUP',
    'BONK',
    'Tether USD',
    'USD Coin',
    'Dai Stablecoin',
    'Wrapped Ether',
    'Wrapped Bitcoin',
    'Chainlink',
    'Uniswap',
    'Shiba Inu',
    'Pepe',
    'Binance USD',
    'PayPal USD',
    'Jupiter',
    'Bonk',
    'ERC-20',
    'TRC-20',
    'SPL',
  },
}) {
  final parsed = <String, Map<String, String>>{};
  for (final catalog in catalogs.entries) {
    Object? decoded;
    try {
      decoded = jsonDecode(catalog.value);
    } on FormatException {
      continue;
    }
    if (decoded is! Map<String, dynamic>) continue;
    parsed[catalog.key] = {
      for (final message in decoded.entries)
        if (!message.key.startsWith('@') && message.value is String)
          message.key: message.value as String,
    };
  }
  final source = parsed[defaultLocale];
  if (source == null) return const [];

  final issues = <String>[];
  for (final message in source.entries) {
    final required = protectedTerms
        .where((term) => _containsBoundedAsciiTerm(message.value, term))
        .toList();
    if (required.isEmpty) continue;
    for (final locale in parsed.entries) {
      if (locale.key == defaultLocale) continue;
      final localized = locale.value[message.key];
      if (localized == null) continue;
      for (final term in required) {
        if (!_containsBoundedAsciiTerm(localized, term)) {
          issues.add(
            '${locale.key}:${message.key}: missing protected term "$term"',
          );
        }
      }
    }
  }
  return issues;
}

bool _containsBoundedAsciiTerm(String value, String term) {
  var start = 0;
  while (true) {
    final index = value.indexOf(term, start);
    if (index < 0) return false;
    final end = index + term.length;
    final leftIsWord = index > 0 && _asciiWord.hasMatch(value[index - 1]);
    final rightIsWord = end < value.length && _asciiWord.hasMatch(value[end]);
    if (!leftIsWord && !rightIsWord) return true;
    start = index + 1;
  }
}

final _asciiWord = RegExp(r'[A-Za-z0-9]');

Map<String, String> _parseAndroidStrings(String xml) {
  final values = <String, String>{};
  final pattern = RegExp(
    r'''<string\b[^>]*\bname\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)</string>''',
  );
  for (final match in pattern.allMatches(xml)) {
    values[match.group(1)!] = match.group(2)!.trim();
  }
  return values;
}

/// Validates Android's default/Chinese/Japanese string resources. The default
/// file is the fallback for every unsupported locale and therefore must stay
/// English-only.
List<String> findAndroidStringResourceIssues(
  Map<String, String> resources, {
  String defaultQualifier = 'values',
}) {
  final issues = <String>[];
  final parsed = {
    for (final entry in resources.entries)
      entry.key: _parseAndroidStrings(entry.value),
  };
  final source = parsed[defaultQualifier];
  if (source == null) return ['missing Android fallback: $defaultQualifier'];

  for (final entry in parsed.entries) {
    final missing = source.keys.toSet().difference(entry.value.keys.toSet());
    final extra = entry.value.keys.toSet().difference(source.keys.toSet());
    if (missing.isNotEmpty) {
      issues.add('${entry.key}: missing strings ${missing.toList()..sort()}');
    }
    if (extra.isNotEmpty) {
      issues.add('${entry.key}: extra strings ${extra.toList()..sort()}');
    }
    for (final value in entry.value.entries) {
      if (value.value.isEmpty) {
        issues.add('${entry.key}:${value.key}: value is empty');
      }
    }
  }
  for (final entry in source.entries) {
    if (_cjkText.hasMatch(entry.value)) {
      issues.add('$defaultQualifier:${entry.key}: fallback contains CJK');
    }
  }
  return issues;
}

Map<String, String> _parseInfoPlistStrings(String contents) {
  final values = <String, String>{};
  final pattern = RegExp(r'''"([^"]+)"\s*=\s*"((?:\\.|[^"])*)"\s*;''');
  for (final match in pattern.allMatches(contents)) {
    values[match.group(1)!] = match.group(2)!;
  }
  return values;
}

/// Validates the localized iOS display names and permission explanations.
/// All locales must expose exactly [requiredKeys], so a new permission cannot
/// silently fall back to English on a Chinese or Japanese device.
List<String> findInfoPlistStringsIssues(
  Map<String, String> localizations, {
  required Set<String> requiredKeys,
  String defaultLocale = 'en',
}) {
  final issues = <String>[];
  final parsed = {
    for (final entry in localizations.entries)
      entry.key: _parseInfoPlistStrings(entry.value),
  };
  if (!parsed.containsKey(defaultLocale)) {
    issues.add('missing iOS fallback: $defaultLocale');
  }
  for (final entry in parsed.entries) {
    final keys = entry.value.keys.toSet();
    final missing = requiredKeys.difference(keys);
    final extra = keys.difference(requiredKeys);
    if (missing.isNotEmpty) {
      issues.add(
        '${entry.key}: missing InfoPlist keys ${missing.toList()..sort()}',
      );
    }
    if (extra.isNotEmpty) {
      issues.add(
        '${entry.key}: unexpected InfoPlist keys ${extra.toList()..sort()}',
      );
    }
    for (final value in entry.value.entries) {
      if (value.value.trim().isEmpty) {
        issues.add('${entry.key}:${value.key}: value is empty');
      }
    }
  }
  final fallback = parsed[defaultLocale];
  if (fallback != null) {
    for (final entry in fallback.entries) {
      if (_cjkText.hasMatch(entry.value)) {
        issues.add('$defaultLocale:${entry.key}: fallback contains CJK');
      }
    }
  }
  return issues;
}

/// Direct dependencies cold_signer is allowed to declare.
///
/// The rule this encodes: **nothing here may be able to open a socket.** Every
/// entry is an offline capability (UI, storage, crypto, camera, i18n). Adding
/// a dependency to this set is a security decision, not a build fix — if it
/// can reach the network, the air-gap claim in README/SECURITY_AND_RISK is no
/// longer true for the standalone signer.
///
/// Kept in sync with the real pubspec by `whitelistCoversDeclaredDeps` (see
/// the test in packages/test_support) so it cannot silently drift again.
const coldSignerDependencyWhitelist = {
  // Framework + first-party offline packages.
  'flutter',
  'flutter_localizations',
  'intl',
  'core_crypto',
  'airgap_protocol',
  'chains', // rpc.dart / src/rpc are banned imports below.
  'ui_kit',
  'go_router',
  'cupertino_icons',
  // Local persistence (no network transport).
  'shared_preferences',
  'flutter_secure_storage',
  'drift',
  'path',
  'path_provider',
  // Offline crypto + device capabilities.
  'crypto',
  'local_auth',
  'mobile_scanner', // camera only; scanning is the air-gap's optical channel.
};

/// Import prefixes that must never appear in cold_signer sources.
const coldSignerBannedImports = [
  'package:http/',
  'package:dio/',
  'package:chains/rpc.dart',
  'package:chains/src/rpc/',
];

/// Returns dependency names declared in the `dependencies:` block of a
/// pubspec.yaml (direct dependencies only, ignores dev_dependencies).
List<String> parseDirectDependencies(String pubspecYaml) {
  final deps = <String>[];
  var inDeps = false;
  for (final rawLine in pubspecYaml.split('\n')) {
    final line = rawLine.replaceAll('\r', '');
    if (line.startsWith('dependencies:')) {
      inDeps = true;
      continue;
    }
    // A new top-level key ends the dependencies block.
    if (inDeps &&
        line.isNotEmpty &&
        !line.startsWith(' ') &&
        !line.startsWith('#')) {
      inDeps = false;
    }
    if (!inDeps) continue;
    final match = RegExp(r'^  (\w[\w-]*):').firstMatch(line);
    if (match != null) {
      deps.add(match.group(1)!);
    }
  }
  return deps;
}

/// Dependencies present in [pubspecYaml] but not in [whitelist].
List<String> findWhitelistViolations(
  String pubspecYaml, {
  Set<String> whitelist = coldSignerDependencyWhitelist,
}) {
  return parseDirectDependencies(
    pubspecYaml,
  ).where((d) => !whitelist.contains(d)).toList();
}

/// Banned import statements found in a Dart source file.
List<String> findBannedImports(
  String dartSource, {
  List<String> banned = coldSignerBannedImports,
}) {
  final violations = <String>[];
  final importRe = RegExp('''import\\s+['"]([^'"]+)['"]''');
  for (final match in importRe.allMatches(dartSource)) {
    final uri = match.group(1)!;
    for (final prefix in banned) {
      if (uri.startsWith(prefix)) {
        violations.add(uri);
      }
    }
  }
  return violations;
}

/// True when the manifest requests the INTERNET permission.
///
/// A high-priority app manifest can use `tools:node="remove"` to delete a
/// permission contributed by a transitive Android library. That marker is a
/// security control, not an active request, so it must not trip the source
/// firewall.
bool manifestDeclaresInternet(String manifestXml) {
  final permissionTags = RegExp(
    r'<uses-permission\b[^>]*>',
    caseSensitive: false,
    multiLine: true,
  );
  for (final match in permissionTags.allMatches(manifestXml)) {
    final tag = match.group(0)!;
    if (!tag.contains('android.permission.INTERNET')) continue;
    final removesPermission = RegExp(
      r'''tools:node\s*=\s*["']remove["']''',
      caseSensitive: false,
    ).hasMatch(tag);
    if (!removesPermission) return true;
  }
  return false;
}

/// Whether the application explicitly disables backup and supplies rules for
/// both the pre-Android-12 and Android-12+ extraction systems.
bool manifestHasFailClosedBackup(String manifestXml) {
  return RegExp(
        r'''android:allowBackup\s*=\s*["']false["']''',
      ).hasMatch(manifestXml) &&
      manifestXml.contains('android:fullBackupContent=') &&
      manifestXml.contains('android:dataExtractionRules=');
}

/// True when an Apple privacy manifest declares app-scoped UserDefaults under
/// the CA92.1 required-reason code and explicitly disables tracking.
bool privacyManifestDeclaresAppScopedUserDefaults(String plistXml) {
  return plistXml.contains('NSPrivacyAccessedAPICategoryUserDefaults') &&
      plistXml.contains('<string>CA92.1</string>') &&
      RegExp(
        r'<key>NSPrivacyTracking</key>\s*<false\s*/>',
        multiLine: true,
      ).hasMatch(plistXml);
}

/// Both supported Apple package managers must embed the SDK manifest, while
/// CocoaPods must not also compile `.xcprivacy` as a source file.
bool applePackageMetadataEmbedsPrivacyManifest({
  required String podspec,
  required String packageSwift,
}) {
  final podEmbeds =
      podspec.contains('s.resource_bundles') &&
      podspec.contains("'core_crypto_privacy'") &&
      podspec.contains('PrivacyInfo.xcprivacy');
  final podSourcesAreNarrow = podspec.contains(
    "s.source_files = 'core_crypto/Sources/core_crypto/**/*.swift'",
  );
  final swiftPackageEmbeds = packageSwift.contains(
    '.process("PrivacyInfo.xcprivacy")',
  );
  return podEmbeds && podSourcesAreNarrow && swiftPackageEmbeds;
}

/// Ensures a Flutter iOS Podfile declares the same minimum supported version
/// as the Runner and raises older transitive Pod targets during generation.
bool podfileEnforcesIos13Floor(String podfile) {
  return RegExp(r'''platform\s+:ios\s*,\s*['"]13\.0['"]''').hasMatch(podfile) &&
      podfile.contains("config.build_settings['IPHONEOS_DEPLOYMENT_TARGET']") &&
      podfile.contains("Gem::Version.new('13.0')");
}

/// Network-capable `dart:io` symbols. The signer legitimately imports
/// `dart:io` for `Platform` and file paths, so the import itself cannot be
/// banned — but these types open sockets, and on iOS there is no permission
/// layer to catch them. Checking symbols keeps the firewall honest without
/// forcing an awkward abstraction over the filesystem.
const coldSignerBannedSymbols = [
  'HttpClient',
  'HttpServer',
  'Socket(',
  'SecureSocket',
  'ServerSocket',
  'RawSocket',
  'RawDatagramSocket',
  'WebSocket',
  'InternetAddress',
];

/// Occurrences of [banned] network symbols in a Dart source file. Matches on
/// word boundaries so identifiers that merely contain the name (e.g. a
/// `WebSocketNotUsedHere` comment) are reported too — a false positive here
/// is far cheaper than a missed socket.
List<String> findBannedSymbols(
  String dartSource, {
  List<String> banned = coldSignerBannedSymbols,
}) {
  final violations = <String>[];
  // Strip line comments so prose about the ban does not trip it.
  final code = dartSource
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');
  for (final symbol in banned) {
    if (code.contains(symbol)) violations.add(symbol);
  }
  return violations;
}

/// Whitelist entries that the pubspec no longer declares. A stale whitelist is
/// how this firewall rotted the first time: it listed packages the app never
/// used, so nobody noticed when the real dependency set outgrew it.
List<String> findStaleWhitelistEntries(
  String pubspecYaml, {
  Set<String> whitelist = coldSignerDependencyWhitelist,
}) {
  final declared = parseDirectDependencies(pubspecYaml).toSet();
  return whitelist.where((w) => !declared.contains(w)).toList()..sort();
}

/// Stock package-template text that must not survive in a repository claiming
/// public-test readiness. Besides looking unfinished, these placeholders hide
/// the API and security boundaries reviewers need in order to use the code
/// safely.
const documentationPlaceholderMarkers = [
  'TODO: Put a short description',
  'TODO: List what your package can do',
  'TODO: List prerequisites',
  'TODO: Include short and useful examples',
  'TODO: Tell users more about the package',
  'TODO: Describe initial release',
  'A new Flutter plugin project',
  'A new Flutter package project',
  'This project is a starting point',
  'github.com/my_org/my_repo',
];

/// Returns every known stock template marker still present in [contents].
List<String> findDocumentationPlaceholders(String contents) => [
  for (final marker in documentationPlaceholderMarkers)
    if (contents.contains(marker)) marker,
];

/// Keeps the Gateway source version and the separately deployed production
/// version synchronized across their respective public evidence surfaces.
///
/// A source candidate can legitimately be ahead of production before a
/// reviewed rollout. Conflating those values forces documentation to claim an
/// undeployed build is live, so both are checked independently. Historical
/// notes may still mention older versions.
List<String> findGatewayReleaseVersionIssues({
  required String gatewaySource,
  required String backendReadme,
  required String rootReadme,
  required String readinessPlan,
  required String htmlReport,
}) {
  final matches = RegExp(
    r'^\s*Version:\s*"([0-9]+\.[0-9]+\.[0-9]+)",\s*$',
    multiLine: true,
  ).allMatches(gatewaySource).toList(growable: false);
  if (matches.length != 1) {
    return ['Gateway source must declare exactly one release version'];
  }
  final sourceVersion = matches.single.group(1)!;
  final deployedMatches = RegExp(
    r'^\| KT Gateway \| `([0-9]+\.[0-9]+\.[0-9]+)` \| Production service ',
    multiLine: true,
  ).allMatches(rootReadme).toList(growable: false);
  if (deployedMatches.length != 1) {
    return ['root README must declare exactly one production Gateway version'];
  }
  final deployedVersion = deployedMatches.single.group(1)!;
  final issues = <String>[];
  final requiredMarkers = <(String, String, String)>[
    (
      backendReadme,
      '"version":"$sourceVersion"',
      'backend README health example is not source $sourceVersion',
    ),
    (
      rootReadme,
      'Gateway source version: `$sourceVersion`',
      'root README source marker is not $sourceVersion',
    ),
    (
      rootReadme,
      'Gateway `$deployedVersion` currently exposes',
      'root README reliability section is not production $deployedVersion',
    ),
    (
      readinessPlan,
      '当前 Gateway 源码版本 $sourceVersion',
      'P0/P1 readiness plan source marker is not $sourceVersion',
    ),
    (
      readinessPlan,
      '当前生产 Gateway $deployedVersion',
      'P0/P1 readiness plan production marker is not $deployedVersion',
    ),
    (
      htmlReport,
      'Gateway 源码版本 · $sourceVersion',
      'HTML report source marker is not $sourceVersion',
    ),
    (
      htmlReport,
      'Gateway 发布状态 · $deployedVersion 已上线',
      'HTML report deployed section is not $deployedVersion',
    ),
  ];
  for (final (contents, marker, issue) in requiredMarkers) {
    if (!contents.contains(marker)) issues.add(issue);
  }
  return issues;
}

/// Every real-chain integration entrypoint that reads the funded mnemonic must
/// validate the versioned batch metadata before registering or running tests.
bool realE2eEntrypointHasCredentialGuard(String contents) {
  const readsMnemonic = "String.fromEnvironment('SEPOLIA_E2E_MNEMONIC')";
  const guard = 'requireFreshE2eCredentialBatchIfConfigured();';
  return !contents.contains(readsMnemonic) || contents.contains(guard);
}

/// Prevents direct Flutter-test invocation from bypassing the all-chain
/// funding gate in entrypoints that can broadcast more than one transaction.
///
/// The guard call must appear before the first broadcast expression in source
/// order. This is intentionally a narrow, explicit list: single-chain tests
/// retain their own dynamic balance checks, while every batch below must fail
/// before signing anything when any later chain is unavailable or unfunded.
bool multiBroadcastE2eHasFundingPreflight(String path, String contents) {
  final basename = path.replaceAll('\\', '/').split('/').last;
  const selectedGuardEntrypoints = {
    'evm_airgap_full_loop_matrix_e2e_test.dart',
    'non_evm_airgap_full_loop_e2e_test.dart',
    'evm_expansion_transfer_e2e_test.dart',
    'evm_replacement_matrix_e2e_test.dart',
  };
  const bridgeEntrypoint = 'l2_bridge_funding_e2e_test.dart';
  if (!selectedGuardEntrypoints.contains(basename) &&
      basename != bridgeEntrypoint) {
    return true;
  }
  final guard = basename == bridgeEntrypoint
      ? 'await _requireBridgeFundingBeforeAnyBroadcast('
      : 'await _requireSelectedFundingBeforeAnyBroadcast(';
  final guardIndex = contents.indexOf(guard);
  final signatureIndex = contents.indexOf('.signTransaction(');
  final broadcastIndex = contents.indexOf('.broadcast(');
  return guardIndex >= 0 &&
      signatureIndex >= 0 &&
      broadcastIndex >= 0 &&
      guardIndex < signatureIndex &&
      guardIndex < broadcastIndex;
}

/// Keeps the post-broadcast result screen usable where public chain RPCs are
/// blocked or slow but the configured KT Gateway remains reachable.
///
/// Finality must be resolved through the Gateway-first status service before
/// any direct-RPC confirmation-depth enrichment. Depth is display-only and
/// therefore must be launched without awaiting it; otherwise a confirmed
/// transaction can remain visibly pending for the whole direct timeout.
List<String> findGatewayFirstFinalityIssues(String contents) {
  const statusMarker = 'final chainStatus = await _statusService?.check(tx);';
  const nonBlockingDepthMarker = 'unawaited(_readConfirmationDepth());';
  final statusIndex = contents.indexOf(statusMarker);
  final depthIndex = contents.indexOf(nonBlockingDepthMarker);
  final issues = <String>[];

  if (statusIndex < 0) {
    issues.add('missing Gateway-first transaction status lookup');
  }
  if (depthIndex < 0) {
    issues.add('confirmation depth is not a non-blocking enrichment');
  } else if (statusIndex >= 0 && depthIndex < statusIndex) {
    issues.add('confirmation depth starts before Gateway-first finality');
  }
  if (contents.contains('= await _readConfirmationDepth()')) {
    issues.add('direct confirmation depth blocks finality persistence');
  }
  return issues;
}

/// Keeps the funding preflight runnable by the standalone Dart VM.
///
/// This tool is deliberately outside the App runtime: it accepts public
/// addresses, performs one bounded HTTPS request and writes optional public
/// readiness evidence. An App/Flutter import can pass model tests while making
/// `dart run` fail at startup because `dart:ui` is unavailable, so the import
/// surface and environment/process boundaries are closed here.
List<String> findHostFundingCliBoundaryIssues(String contents) {
  const allowedImports = {
    'dart:convert',
    'dart:io',
    'package:http/http.dart',
    'e2e_funding_preflight_model.dart',
  };
  final imports = RegExp(
    r'''^import\s+['"]([^'"]+)['"]\s*(?:as\s+\w+\s*)?;''',
    multiLine: true,
  ).allMatches(contents).map((match) => match.group(1)!).toList();
  final issues = <String>[];
  final missing = allowedImports.difference(imports.toSet());
  final unexpected = imports.toSet().difference(allowedImports);
  if (missing.isNotEmpty) {
    issues.add('missing standalone imports: ${missing.toList()..sort()}');
  }
  if (unexpected.isNotEmpty) {
    issues.add('unexpected host CLI imports: ${unexpected.toList()..sort()}');
  }
  for (final boundary in const {
    'Platform.environment': 'environment credentials/configuration',
    'String.fromEnvironment': 'dart-define credentials/configuration',
    'Process.run': 'child process execution',
    'Process.start': 'child process execution',
  }.entries) {
    if (contents.contains(boundary.key)) {
      issues.add('host funding CLI reads ${boundary.value}');
    }
  }
  if (!contents.contains('Future<void> main(List<String> arguments) async')) {
    issues.add('host funding CLI entrypoint is missing');
  }
  if (!contents.contains('decodeGatewayFundingJson(')) {
    issues.add('remote Gateway body is not decoded with duplicate-key checks');
  }
  if (RegExp(r'\bjsonDecode\(').hasMatch(contents)) {
    issues.add('remote Gateway body uses the duplicate-unsafe JSON decoder');
  }
  return issues;
}

/// Keeps imported encrypted-backup JSON single-interpretable.
///
/// Both the restore parser and its display-only timestamp helper receive an
/// attacker-controlled file. Dart's ordinary decoder silently keeps the last
/// duplicate member, so a backup can otherwise carry conflicting format, KDF,
/// timestamp, or payload identities even though the post-decode schema is
/// closed.
List<String> findExternalBackupJsonBoundaryIssues(String contents) {
  final issues = <String>[];
  final safeDecodeCount = RegExp(
    r'decodeJsonWithoutDuplicateKeys\(\s*utf8\.decode\(bytes\)\s*\)',
  ).allMatches(contents).length;
  if (safeDecodeCount != 2) {
    issues.add(
      'restore and timestamp paths must both reject duplicate JSON members',
    );
  }
  if (RegExp(r'jsonDecode\(\s*utf8\.decode\(bytes\)\s*\)').hasMatch(contents)) {
    issues.add('external backup uses the duplicate-unsafe JSON decoder');
  }
  return issues;
}

/// Keeps TRON's signed transaction JSON single-interpretable and bounded at
/// both the cryptographic verification and submission boundaries.
List<String> findTronSignedJsonBoundaryIssues(
  String verifierContents,
  String broadcasterContents,
) {
  final issues = <String>[];
  const verifierRequired = {
    'const tronSignedTransactionJsonMaxBytes = 1024 * 1024':
        'TRON signed JSON byte size is not bounded',
    'signed.length > tronSignedTransactionJsonMaxBytes':
        'TRON verifier does not enforce the signed JSON byte bound',
    'decodeJsonWithUniqueObjectMembers(':
        'TRON verifier does not reject duplicate JSON members',
    'maxChars: tronSignedTransactionJsonMaxBytes':
        'TRON verifier does not enforce the decoder size bound',
    'map.keys.any((key) => key != \'transaction\' && key != \'txID\')':
        'TRON signed JSON schema is not closed',
  };
  for (final entry in verifierRequired.entries) {
    if (!verifierContents.contains(entry.key)) issues.add(entry.value);
  }
  const broadcasterRequired = {
    'signedTx.length > tronSignedTransactionJsonMaxBytes':
        'TRON broadcaster does not enforce the signed JSON byte bound',
    'decodeJsonWithUniqueObjectMembers(':
        'TRON broadcaster does not reject duplicate JSON members',
  };
  for (final entry in broadcasterRequired.entries) {
    if (!broadcasterContents.contains(entry.key)) issues.add(entry.value);
  }
  if (RegExp(
        r'_decodeTronSignedJson\(signedTx\)',
      ).allMatches(broadcasterContents).length <
      2) {
    issues.add(
      'TRON direct and Gateway submission do not share the strict decoder',
    );
  }
  if (RegExp(
    r'jsonDecode\(\s*utf8\.decode\(signed\)\s*\)',
  ).hasMatch(verifierContents)) {
    issues.add('TRON verifier uses the duplicate-unsafe JSON decoder');
  }
  if (RegExp(
    r'json\.decode\(\s*(?:utf8\.decode\(signedTx\)|text)\s*\)',
  ).hasMatch(broadcasterContents)) {
    issues.add('TRON broadcaster uses the duplicate-unsafe JSON decoder');
  }
  return issues;
}

/// Keeps wallet balance and transaction-history display caches bounded,
/// single-interpretable and closed-schema.
///
/// These records do not authorize transfers, but malformed cached data can
/// still falsely label an asset/transaction as verified or block startup with
/// excessive local work. Both loaders must fail the whole snapshot closed and
/// let their live refresh paths replace it.
List<String> findWalletDisplaySnapshotBoundaryIssues(
  String marketContents,
  String historyContents,
) {
  final issues = <String>[];
  const marketRequired = {
    'static const maxSnapshotChars = 262144':
        'market snapshot JSON size is not bounded before parsing',
    'static const _maxTokens = 512':
        'market snapshot token maps are not bounded',
    'decodeJsonWithoutDuplicateKeys(':
        'market snapshot does not reject duplicate JSON members',
    'maxChars: maxSnapshotChars':
        'market snapshot decoder does not enforce its size bound',
    'members: rawVersion == 1 ? _topV1 : _topV2':
        'market snapshot top-level schema is not version-closed',
    'members: _amountMembers': 'market snapshot amount schema is not closed',
    'positiveFiniteMarketNumber(entry.value)':
        'market snapshot prices are not positive finite values',
  };
  for (final entry in marketRequired.entries) {
    if (!marketContents.contains(entry.key)) issues.add(entry.value);
  }
  const historyRequired = {
    'static const maxSnapshotChars = 1048576':
        'history snapshot JSON size is not bounded before parsing',
    'static const _maxRecordsPerCoin = 100':
        'history snapshot rows are not bounded per chain',
    'decodeJsonWithoutDuplicateKeys(':
        'history snapshot does not reject duplicate JSON members',
    'maxChars: maxSnapshotChars':
        'history snapshot decoder does not enforce its size bound',
    'requireExactSnapshotObject(decoded, members: _topMembers)':
        'history snapshot top-level schema is not closed',
    'members: switch (version)': 'history record schema is not version-closed',
    "final verified = record['verified'];":
        'history verification state is not explicitly decoded',
    'outgoing is! bool || verified is! bool':
        'history verification state is not required to be boolean',
    'assetVerified: verified':
        'history record does not preserve the required verification value',
  };
  for (final entry in historyRequired.entries) {
    if (!historyContents.contains(entry.key)) issues.add(entry.value);
  }
  if (RegExp(r'jsonDecode\(\s*encoded\s*\)').hasMatch(marketContents)) {
    issues.add('market snapshot uses the duplicate-unsafe JSON decoder');
  }
  if (RegExp(r'jsonDecode\(\s*encoded\s*\)').hasMatch(historyContents)) {
    issues.add('history snapshot uses the duplicate-unsafe JSON decoder');
  }
  if (RegExp(
    r"assetVerified:\s*[^,]+\?[^:]+:\s*true",
  ).hasMatch(historyContents)) {
    issues.add('history snapshot defaults malformed verification to trusted');
  }
  return issues;
}

/// Keeps persisted custom networks from becoming an ambiguous or unbounded
/// source of RPC routing and EVM signing-domain authority.
List<String> findNetworkSnapshotBoundaryIssues(
  String networkContents,
  String endpointPolicyContents,
  String settingsContents,
) {
  final issues = <String>[];
  const networkRequired = {
    'static const maxSnapshotChars = 262144':
        'network snapshot JSON size is not bounded before parsing',
    'static const maxCustomNetworks = 64':
        'custom network count is not bounded',
    'decodeJsonWithoutDuplicateKeys(':
        'network snapshot does not reject duplicate JSON members',
    'maxChars: maxSnapshotChars':
        'network snapshot decoder does not enforce its size bound',
    'value.keys.toSet().difference(_networkSnapshotMembers)':
        'network snapshot top-level schema is not closed',
    'required: _networkRequiredMembers':
        'custom network required fields are not closed',
    'allowed: _networkAllowedMembers':
        'custom network allowed fields are not closed',
    "m['isTestnet'] is! bool":
        'custom network testnet classification is not strict',
    'static const maxEvmChainId = 2147483647':
        'custom EVM signing-domain id is not bounded',
    r"networkIdentity != '$evmChainId'":
        'persisted EVM probe identity is not bound to the chain id',
    'if (hasSnapshot && snapshot == null) return':
        'corrupt versioned snapshot can fall back to legacy routing state',
  };
  for (final entry in networkRequired.entries) {
    if (!networkContents.contains(entry.key)) issues.add(entry.value);
  }
  if (RegExp(r'json\.decode\(\s*source\s*\)').hasMatch(networkContents)) {
    issues.add('network snapshot uses the duplicate-unsafe JSON decoder');
  }
  if (networkContents.contains("m['isTestnet'] == true")) {
    issues.add('malformed testnet classification silently becomes mainnet');
  }
  if (!endpointPolicyContents.contains('static const maxUrlChars = 2048') ||
      !endpointPolicyContents.contains('normalized.length > maxUrlChars')) {
    issues.add('user-configurable endpoint length is not bounded');
  }
  const allEvmFamilies =
      'final isEvm = chain != Chain.tron && chain != Chain.solana;';
  if (!settingsContents.contains(allEvmFamilies)) {
    issues.add('custom-network UI does not require Chain ID for every EVM');
  }
  if (!settingsContents.contains('typedChainId <= Network.maxEvmChainId')) {
    issues.add('custom-network UI does not enforce the Chain ID upper bound');
  }
  return issues;
}

/// Keeps the app-lock PIN record bounded and single-interpretable.
///
/// Secure storage availability does not make its bytes infallible: migration,
/// corruption, or a compromised device can still supply an open/ambiguous
/// record. Authentication must reject that state before PBKDF2 work, and an
/// attacker-controlled failure count must never create an unbounded shift or
/// duration.
List<String> findWalletPinStateBoundaryIssues(String contents) {
  final issues = <String>[];
  const required = {
    'decodeJsonWithoutDuplicateKeys(raw)':
        'PIN state does not reject duplicate JSON members',
    "allowed: const {'algo', 'salt', 'hash', 'iterations'}":
        'PIN record schema is not closed',
    "allowed: const {'fails', 'lockedUntil'}":
        'PIN lockout schema is not closed',
    'static const maxStoredIterations = 1000000':
        'stored PBKDF2 work is not bounded',
    'static const maxStoredRecordChars = 4096':
        'persisted PIN JSON size is not bounded before parsing',
    'static const maxTrackedFailures = 64':
        'persisted failure count is not bounded',
    'static const maxLockout = Duration(hours: 24)':
        'computed lockout duration is not bounded',
    "_decodeCanonicalBase64(record['salt'], saltLength)":
        'PIN salt length/canonical encoding is not bound',
    "_decodeCanonicalBase64(record['hash'], hashLength)":
        'PIN hash length/canonical encoding is not bound',
    'until = now.add(_lockoutDuration(newFails))':
        'lockout growth bypasses the bounded duration helper',
  };
  for (final entry in required.entries) {
    if (!contents.contains(entry.key)) issues.add(entry.value);
  }
  if (RegExp(r'jsonDecode\(\s*raw\s*\)').hasMatch(contents)) {
    issues.add('PIN state uses the duplicate-unsafe JSON decoder');
  }
  if (RegExp(r'1\s*<<\s*\(newFails').hasMatch(contents)) {
    issues.add('PIN lockout uses an attacker-sized bit shift');
  }
  if (RegExp(
    r'Future<bool> isSet\(\)[\s\S]{0,250}read\(pinKey\)\s*!=\s*null',
  ).hasMatch(contents)) {
    issues.add('PIN enrollment check trusts record presence without parsing');
  }
  return issues;
}

/// Keeps KT Cold Signer's local PIN and lockout records bounded and
/// single-interpretable before they can authorize an offline signature.
List<String> findSignerPinStateBoundaryIssues(String contents) {
  final issues = <String>[];
  const required = {
    'decodeStrictLocalJson(':
        'signer PIN state does not reject duplicate JSON members',
    'maxChars: maxStoredRecordChars':
        'signer PIN strict decoder is not bound to the record size limit',
    "allowed: const {'algo', 'salt', 'hash', 'iterations'}":
        'signer PIN record schema is not closed',
    "allowed: const {'fails', 'lockedUntil'}":
        'signer PIN lockout schema is not closed',
    'static const maxStoredIterations = 1000000':
        'signer stored PBKDF2 work is not bounded',
    'static const maxStoredRecordChars = 4096':
        'signer persisted PIN JSON size is not bounded before parsing',
    'static const maxTrackedFailures = 64':
        'signer persisted failure count is not bounded',
    'static const maxLockout = Duration(hours: 24)':
        'signer computed lockout duration is not bounded',
    "_decodeCanonicalBase64(record['salt'], saltLength)":
        'signer PIN salt length/canonical encoding is not bound',
    "_decodeCanonicalBase64(record['hash'], hashLength)":
        'signer PIN hash length/canonical encoding is not bound',
    'until = now.add(_lockoutDuration(newFails))':
        'signer lockout growth bypasses the bounded duration helper',
  };
  for (final entry in required.entries) {
    if (!contents.contains(entry.key)) issues.add(entry.value);
  }
  if (RegExp(r'jsonDecode\(\s*raw\s*\)').hasMatch(contents)) {
    issues.add('signer PIN state uses the duplicate-unsafe JSON decoder');
  }
  if (RegExp(r'1\s*<<\s*\(newFails').hasMatch(contents)) {
    issues.add('signer PIN lockout uses an attacker-sized bit shift');
  }
  if (RegExp(
    r'Future<bool> isSet\(\)[\s\S]{0,250}read\([^)]*pinKey\)\s*!=\s*null',
  ).hasMatch(contents)) {
    issues.add(
      'signer PIN enrollment check trusts record presence without parsing',
    );
  }
  return issues;
}

/// Keeps Cold Signer's public wallet descriptor and crash-recovery tombstone
/// closed, bounded, and bound to the same native wallet identity.
List<String> findSignerVaultStateBoundaryIssues(
  String vaultContents,
  String controllerContents,
) {
  final issues = <String>[];
  const vaultRequired = {
    'static const maxMetadataChars = 16384':
        'signer metadata JSON size is not bounded before parsing',
    'decodeStrictLocalJson(raw, maxChars: maxMetadataChars)':
        'signer metadata does not reject duplicate JSON members',
    "const allowed = {": 'signer metadata schema is not closed',
    "'walletId',": 'signer metadata schema omits wallet identity',
    "'biometricEnabled',":
        'signer metadata schema omits its authentication setting',
    'Future<bool> hasWallet() async => await readMetadata() != null':
        'signer wallet presence trusts an unparsed metadata record',
    'CoreCryptoValidation.checkWalletId(walletId)':
        'signer deletion marker wallet identity is not validated',
  };
  for (final entry in vaultRequired.entries) {
    if (!vaultContents.contains(entry.key)) issues.add(entry.value);
  }
  const controllerRequired = {
    'metadata.walletId != pendingDeletion':
        'signer deletion recovery does not bind tombstone to metadata',
    'deleteNative: metadata != null':
        'signer deletion recovery may delete an unbound native wallet',
    'if (deleteNative)':
        'signer deletion recovery ignores the native-delete safety decision',
  };
  for (final entry in controllerRequired.entries) {
    if (!controllerContents.contains(entry.key)) issues.add(entry.value);
  }
  if (RegExp(r'jsonDecode\(\s*raw\s*\)').hasMatch(vaultContents)) {
    issues.add('signer metadata uses the duplicate-unsafe JSON decoder');
  }
  if (RegExp(
    r'Future<bool> hasWallet\(\)[\s\S]{0,120}read\(metadataKey\)\s*!=\s*null',
  ).hasMatch(vaultContents)) {
    issues.add('signer wallet presence trusts metadata key presence');
  }
  return issues;
}

/// Keeps AIRGAP wallet identities and user-visible fields single-interpretable
/// across direct construction, QR decoding, and online request creation.
///
/// A walletId binds an online watch wallet to one offline signing authority.
/// Silently truncating or normalizing it can therefore authorize a different
/// identity. Invisible controls and bidi overrides are rejected from all
/// display-bearing protocol fields so a QR cannot render one value while the
/// signer processes another.
List<String> findAirgapIdentityTextBoundaryIssues(
  String payloadContents,
  String codecContents,
) {
  final issues = <String>[];
  const required = {
    r"RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$')":
        'walletId is not restricted to canonical ASCII identity syntax',
    'value.trim().isEmpty':
        'AIRGAP text fields do not reject empty or whitespace-only values',
    'value.runes.any(_isUnsafeProtocolTextRune)':
        'AIRGAP text fields do not reject unsafe invisible runes',
    'rune >= 0x202a && rune <= 0x202e':
        'AIRGAP text fields do not reject bidi override controls',
    '_validateProtocolText(v, name, maxLen)':
        'decoded AIRGAP text bypasses the shared text validator',
    '_validateWalletId(v)':
        'decoded walletId bypasses the canonical identity validator',
    'List<AccountRecord>.unmodifiable(accounts)':
        'account export does not snapshot its bounded account list',
    "_validateProtocolText(address, 'address', AirgapLimits.maxAddress)":
        'account address bypasses construction-time validation',
    "_validateProtocolText(path, 'path', AirgapLimits.maxPath)":
        'account derivation path bypasses construction-time validation',
    "_validateProtocolText(walletName, 'walletName', AirgapLimits.maxWalletName)":
        'wallet name bypasses construction-time validation',
    "_validateProtocolText(signer, 'signer', AirgapLimits.maxAddress)":
        'signer address bypasses construction-time validation',
    "_validateProtocolText(txHash, 'txHash', AirgapLimits.maxAddress)":
        'transaction hash bypasses construction-time validation',
  };
  for (final entry in required.entries) {
    if (!payloadContents.contains(entry.key)) issues.add(entry.value);
  }
  if (RegExp(
        r'_validateWalletId\(walletId\)',
      ).allMatches(payloadContents).length <
      3) {
    issues.add('walletId is not validated by every AIRGAP payload constructor');
  }
  if (RegExp(
        r'walletId:\s*_walletIdText\(',
      ).allMatches(payloadContents).length <
      3) {
    issues.add('walletId decode paths do not all use the canonical validator');
  }
  if (!codecContents.contains('walletId: walletId')) {
    issues.add('online sign request does not preserve the exact walletId');
  }
  if (codecContents.contains('substring(0, AirgapLimits.maxWalletId)')) {
    issues.add('online sign request silently truncates wallet identity');
  }
  return issues;
}
