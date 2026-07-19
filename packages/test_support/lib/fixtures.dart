/// Fixture loading helpers. Tests run with cwd == package root, so fixtures
/// live at `<package>/test/fixtures/...` (detailed-design.md §9).
library;

import 'dart:convert';
import 'dart:io';

/// Reads a fixture file relative to the current package's `test/fixtures/`.
String readFixture(String relativePath) {
  final file = File('test/fixtures/$relativePath');
  if (!file.existsSync()) {
    throw ArgumentError(
      'Fixture not found: ${file.path} (cwd=${Directory.current.path}). '
      'Run tests from the package root.',
    );
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
