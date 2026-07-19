// Repo-level dependency firewall for cold_signer (todolist.md P0-2).
//
// Usage: dart run tool/check_deps.dart   (from workspace root)
// Exits non-zero on any violation. Wired into CI.

import 'dart:io';

import 'package:test_support/dep_check.dart';

void main() {
  final failures = <String>[];

  final pubspec = File('apps/cold_signer/pubspec.yaml');
  final violations = findWhitelistViolations(pubspec.readAsStringSync());
  if (violations.isNotEmpty) {
    failures.add('cold_signer pubspec has non-whitelisted deps: $violations');
  }

  final libDir = Directory('apps/cold_signer/lib');
  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final bad = findBannedImports(entity.readAsStringSync());
    if (bad.isNotEmpty) {
      failures.add('${entity.path} imports banned libraries: $bad');
    }
  }

  // Release/profile builds must be provably offline (no INTERNET). The debug
  // manifest is exempt (Flutter hot-reload needs it and never ships).
  for (final variant in ['main', 'profile']) {
    final manifest = File(
        'apps/cold_signer/android/app/src/$variant/AndroidManifest.xml');
    if (manifest.existsSync() &&
        manifestDeclaresInternet(manifest.readAsStringSync())) {
      failures.add('cold_signer $variant AndroidManifest declares INTERNET');
    }
  }

  if (failures.isEmpty) {
    stdout.writeln('check_deps: OK');
    return;
  }
  for (final f in failures) {
    stderr.writeln('check_deps FAIL: $f');
  }
  // main() returning a non-zero int does NOT set the process exit code — must
  // call exit() explicitly or CI would pass despite violations.
  exit(1);
}
