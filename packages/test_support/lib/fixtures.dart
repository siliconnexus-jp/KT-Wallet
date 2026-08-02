/// Fixture loading helpers for this package's `test/fixtures` directory.
///
/// The path is resolved through the Dart package configuration instead of the
/// process working directory, so the same test behaves identically when run
/// from this package or from the monorepo root.
library;

import 'dart:convert';
import 'dart:io';

Directory _testSupportRoot() {
  for (final relative in const ['.', 'packages/test_support']) {
    final candidate = Directory(relative).absolute;
    if (Directory.fromUri(
      candidate.uri.resolve('test/fixtures/'),
    ).existsSync()) {
      return candidate;
    }
  }
  throw StateError(
    'Unable to resolve test_support from ${Directory.current.path}',
  );
}

/// Reads a fixture file relative to the current package's `test/fixtures/`.
String readFixture(String relativePath) {
  final file = File.fromUri(
    _testSupportRoot().uri.resolve('test/fixtures/$relativePath'),
  );
  if (!file.existsSync()) {
    throw ArgumentError('Fixture not found: ${file.path}');
  }
  return file.readAsStringSync();
}

/// Reads and decodes a JSON fixture.
dynamic readJsonFixture(String relativePath) =>
    jsonDecode(readFixture(relativePath));

/// Reads a fixture containing hex bytes (whitespace tolerated).
List<int> readHexFixture(String relativePath) {
  final hex = readFixture(relativePath).replaceAll(RegExp(r'\s|0x'), '');
  if (hex.length.isOdd) {
    throw FormatException('Odd-length hex in $relativePath');
  }
  return [
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
}
