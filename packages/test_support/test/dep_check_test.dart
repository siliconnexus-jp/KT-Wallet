import 'dart:io';

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

  group('socket-symbol firewall', () {
    test('flags dart:io network types even when the import is legitimate', () {
      const source = """
import 'dart:io';
Future<void> leak() async => HttpClient().getUrl(Uri.parse('https://x'));
""";
      expect(findBannedSymbols(source), contains('HttpClient'));
    });

    test('ignores prose in comments about the ban', () {
      const source = """
// Never use HttpClient or WebSocket here — this app is air-gapped.
import 'dart:io' show Platform;
bool get isIos => Platform.isIOS;
""";
      expect(findBannedSymbols(source), isEmpty);
    });
  });

  group('whitelist drift', () {
    test('reports entries the pubspec no longer declares', () {
      const pubspec = """
dependencies:
  flutter:
    sdk: flutter
  chains:
    path: ../../packages/chains
""";
      final stale = findStaleWhitelistEntries(
        pubspec,
        whitelist: {'flutter', 'chains', 'ghost_package'},
      );
      expect(stale, ['ghost_package']);
    });

    test('the real cold_signer whitelist is neither stale nor short', () {
      final pubspec = File('../../apps/cold_signer/pubspec.yaml');
      if (!pubspec.existsSync()) return; // path differs under some runners
      final yaml = pubspec.readAsStringSync();
      expect(findWhitelistViolations(yaml), isEmpty,
          reason: 'a new dependency must be reviewed for network capability');
      expect(findStaleWhitelistEntries(yaml), isEmpty,
          reason: 'stale entries are how this firewall rotted before');
    });
  });
}
