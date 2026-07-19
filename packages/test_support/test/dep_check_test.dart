import 'package:test/test.dart';
import 'package:test_support/dep_check.dart';

const _cleanPubspec = '''
name: cold_signer
environment:
  sdk: ^3.9.0

dependencies:
  flutter:
    sdk: flutter
  core_crypto:
    path: ../../packages/core_crypto
  airgap_protocol:
    path: ../../packages/airgap_protocol
  cupertino_icons: ^1.0.8

dev_dependencies:
  flutter_test:
    sdk: flutter
  http: ^1.0.0
''';

const _dirtyPubspec = '''
name: cold_signer

dependencies:
  flutter:
    sdk: flutter
  http: ^1.2.0
  firebase_analytics: ^11.0.0
  core_crypto:
    path: ../../packages/core_crypto

dev_dependencies:
  flutter_test:
    sdk: flutter
''';

void main() {
  group('parseDirectDependencies', () {
    test('extracts direct dependencies only', () {
      expect(
        parseDirectDependencies(_cleanPubspec),
        ['flutter', 'core_crypto', 'airgap_protocol', 'cupertino_icons'],
      );
    });

    test('ignores dev_dependencies even when banned names appear there', () {
      expect(parseDirectDependencies(_cleanPubspec), isNot(contains('http')));
    });
  });

  group('findWhitelistViolations', () {
    test('clean pubspec passes', () {
      expect(findWhitelistViolations(_cleanPubspec), isEmpty);
    });

    test('http and analytics SDKs are flagged', () {
      expect(
        findWhitelistViolations(_dirtyPubspec),
        ['http', 'firebase_analytics'],
      );
    });
  });

  group('findBannedImports', () {
    test('flags http, dio and chains rpc imports', () {
      const src = '''
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:chains/rpc.dart';
import 'package:chains/chains.dart';
''';
      expect(findBannedImports(src), [
        'package:http/http.dart',
        'package:dio/dio.dart',
        'package:chains/rpc.dart',
      ]);
    });

    test('allows chains core import and flutter imports', () {
      const src = '''
import 'package:chains/chains.dart';
import 'package:flutter/material.dart';
''';
      expect(findBannedImports(src), isEmpty);
    });

    test('handles double-quoted imports', () {
      const src = 'import "package:http/http.dart";';
      expect(findBannedImports(src), ['package:http/http.dart']);
    });
  });

  group('manifestDeclaresInternet', () {
    test('detects INTERNET permission', () {
      const manifest = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <uses-permission android:name="android.permission.INTERNET"/>
</manifest>
''';
      expect(manifestDeclaresInternet(manifest), isTrue);
    });

    test('passes a clean manifest', () {
      const manifest = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <uses-permission android:name="android.permission.CAMERA"/>
</manifest>
''';
      expect(manifestDeclaresInternet(manifest), isFalse);
    });
  });
}
