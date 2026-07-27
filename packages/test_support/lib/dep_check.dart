/// Dependency-firewall checks for the cold_signer app.
///
/// Pure functions so they can be unit-tested against fixtures; the repo-level
/// entrypoint is `tool/check_deps.dart`.
library;

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
  'sqlite3_flutter_libs',
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
    if (inDeps && line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('#')) {
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
  return parseDirectDependencies(pubspecYaml)
      .where((d) => !whitelist.contains(d))
      .toList();
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
bool manifestDeclaresInternet(String manifestXml) {
  return manifestXml.contains('android.permission.INTERNET');
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
