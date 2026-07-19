/// Dependency-firewall checks for the cold_signer app.
///
/// Pure functions so they can be unit-tested against fixtures; the repo-level
/// entrypoint is `tool/check_deps.dart`.
library;

/// Direct dependencies cold_signer is allowed to declare (tech-plan.md §4).
const coldSignerDependencyWhitelist = {
  'flutter',
  'core_crypto',
  'airgap_protocol',
  'chains',
  'ui_kit',
  'cupertino_icons',
  'mobile_scanner',
  'qr_flutter',
  'drift',
  'sqflite',
  'local_auth',
  'flutter_riverpod',
  'go_router',
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
