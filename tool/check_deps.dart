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
    final source = entity.readAsStringSync();
    final bad = findBannedImports(source);
    if (bad.isNotEmpty) {
      failures.add('${entity.path} imports banned libraries: $bad');
    }
    // `dart:io` is allowed (Platform, paths) but its socket types are not.
    final sockets = findBannedSymbols(source);
    if (sockets.isNotEmpty) {
      failures.add('${entity.path} uses network symbols: $sockets');
    }
  }

  // A whitelist listing packages the app no longer uses is how this firewall
  // silently stopped protecting anything before; fail on drift in both
  // directions.
  final stale = findStaleWhitelistEntries(pubspec.readAsStringSync());
  if (stale.isNotEmpty) {
    failures.add('whitelist lists deps cold_signer no longer declares: $stale');
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

  // The online wallet is the mirror image: it MUST declare INTERNET in the
  // shipping manifest. It shipped without it once, and because debug/profile
  // manifests carry the permission the gap only surfaced in release builds.
  final walletManifest =
      File('apps/kt_wallet/android/app/src/main/AndroidManifest.xml');
  if (walletManifest.existsSync() &&
      !manifestDeclaresInternet(walletManifest.readAsStringSync())) {
    failures.add('kt_wallet main AndroidManifest is missing INTERNET');
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
