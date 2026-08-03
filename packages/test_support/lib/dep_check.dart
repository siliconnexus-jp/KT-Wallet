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

/// Keeps the production Gateway version in code and current public release
/// surfaces synchronized.
///
/// Historical notes may legitimately mention older versions, so this checks
/// exact status-table, reliability, release-badge and deployment headings
/// instead of merely looking for the current number somewhere in each file.
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
  final version = matches.single.group(1)!;
  final issues = <String>[];
  final requiredMarkers = <(String, String, String)>[
    (
      backendReadme,
      '"version":"$version"',
      'backend README health example is not $version',
    ),
    (
      rootReadme,
      '| KT Gateway | `$version` |',
      'root README status table is not $version',
    ),
    (
      rootReadme,
      'Gateway `$version` currently exposes',
      'root README reliability section is not $version',
    ),
    (
      readinessPlan,
      '生产 $version 的公开 Ethereum 历史只读 smoke',
      'P0/P1 readiness plan production evidence is not $version',
    ),
    (
      htmlReport,
      'Gateway $version 生产发布',
      'HTML report release badge is not $version',
    ),
    (
      htmlReport,
      'Gateway 发布状态 · $version 已上线',
      'HTML report deployed section is not $version',
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
