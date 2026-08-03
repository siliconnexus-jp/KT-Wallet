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
      expect(parseDirectDependencies(_cleanPubspec), [
        'flutter',
        'core_crypto',
        'airgap_protocol',
        'cupertino_icons',
      ]);
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
      expect(findWhitelistViolations(_dirtyPubspec), [
        'http',
        'firebase_analytics',
      ]);
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

    test('does not treat a manifest-merger removal marker as a request', () {
      const manifest = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">
  <uses-permission android:name="android.permission.INTERNET"
      tools:node="remove" />
</manifest>
''';
      expect(manifestDeclaresInternet(manifest), isFalse);
    });
  });

  group('manifestHasFailClosedBackup', () {
    test('requires opt-out and both generations of extraction rules', () {
      const secure = '''
<application android:allowBackup="false"
    android:fullBackupContent="@xml/backup_rules"
    android:dataExtractionRules="@xml/data_extraction_rules" />
''';
      expect(manifestHasFailClosedBackup(secure), isTrue);
      expect(
        manifestHasFailClosedBackup(
          '<application android:allowBackup="false" />',
        ),
        isFalse,
      );
    });
  });

  group('Apple privacy manifest packaging', () {
    test('requires CA92.1, no tracking and both package-manager resources', () {
      const manifest = '''
<key>NSPrivacyTracking</key><false/>
<string>NSPrivacyAccessedAPICategoryUserDefaults</string>
<string>CA92.1</string>
''';
      expect(privacyManifestDeclaresAppScopedUserDefaults(manifest), isTrue);
      expect(
        privacyManifestDeclaresAppScopedUserDefaults(
          manifest.replaceFirst('CA92.1', 'UNKNOWN'),
        ),
        isFalse,
      );

      const podspec = '''
s.source_files = 'core_crypto/Sources/core_crypto/**/*.swift'
s.resource_bundles = {
  'core_crypto_privacy' => ['core_crypto/Sources/core_crypto/PrivacyInfo.xcprivacy']
}
''';
      const packageSwift = '.process("PrivacyInfo.xcprivacy"),';
      expect(
        applePackageMetadataEmbedsPrivacyManifest(
          podspec: podspec,
          packageSwift: packageSwift,
        ),
        isTrue,
      );
      expect(
        applePackageMetadataEmbedsPrivacyManifest(
          podspec: podspec.replaceFirst('**/*.swift', '**/*'),
          packageSwift: packageSwift,
        ),
        isFalse,
      );
    });

    test('Podfile must declare and propagate the iOS 13 floor', () {
      const podfile = '''
platform :ios, '13.0'
deployment_target = config.build_settings['IPHONEOS_DEPLOYMENT_TARGET']
if deployment_target && Gem::Version.new(deployment_target) < Gem::Version.new('13.0')
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
end
''';
      expect(podfileEnforcesIos13Floor(podfile), isTrue);
      expect(
        podfileEnforcesIos13Floor(
          podfile.replaceFirst("platform :ios, '13.0'", ''),
        ),
        isFalse,
      );
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
      expect(
        findWhitelistViolations(yaml),
        isEmpty,
        reason: 'a new dependency must be reviewed for network capability',
      );
      expect(
        findStaleWhitelistEntries(yaml),
        isEmpty,
        reason: 'stale entries are how this firewall rotted before',
      );
    });
  });

  group('documentation hygiene', () {
    test('flags stock package templates', () {
      expect(
        findDocumentationPlaceholders('TODO: Put a short description here'),
        ['TODO: Put a short description'],
      );
      expect(
        findDocumentationPlaceholders(
          'description: A new Flutter plugin project',
        ),
        ['A new Flutter plugin project'],
      );
    });

    test('accepts an explicit API and security description', () {
      expect(
        findDocumentationPlaceholders(
          '# Package\n\nAPI contract.\n\n## Security boundary\nFail closed.',
        ),
        isEmpty,
      );
    });
  });

  group('Gateway public release version', () {
    const source = '''
GatewayConfig{
  Version: "1.2.3",
}
''';
    const backendReadme = '{"result":{"version":"1.2.3"}}';
    const rootReadme = '''
| KT Gateway | `1.2.3` | Production service |
Gateway `1.2.3` currently exposes 16 mainnet/testnet network profiles.
''';
    const readinessPlan = '生产 1.2.3 的公开 Ethereum 历史只读 smoke 返回 5 条且 5/5 ok。';
    const report = '''
<span>Gateway 1.2.3 生产发布</span>
<strong>Gateway 发布状态 · 1.2.3 已上线</strong>
''';

    test('accepts one source version and exact current public markers', () {
      expect(
        findGatewayReleaseVersionIssues(
          gatewaySource: source,
          backendReadme: backendReadme,
          rootReadme: rootReadme,
          readinessPlan: readinessPlan,
          htmlReport: report,
        ),
        isEmpty,
      );
    });

    test('rejects stale current markers even if history mentions the version', () {
      final issues = findGatewayReleaseVersionIssues(
        gatewaySource: source,
        backendReadme:
            '${backendReadme.replaceAll('1.2.3', '1.2.2')}\nHistorical 1.2.3 notes.',
        rootReadme:
            '${rootReadme.replaceAll('1.2.3', '1.2.2')}\nHistorical 1.2.3 notes.',
        readinessPlan:
            '${readinessPlan.replaceAll('1.2.3', '1.2.2')}\nHistorical 1.2.3 notes.',
        htmlReport:
            '${report.replaceAll('1.2.3', '1.2.2')}\nHistorical Gateway 1.2.3.',
      );

      expect(issues, contains('backend README health example is not 1.2.3'));
      expect(issues, contains('root README status table is not 1.2.3'));
      expect(issues, contains('root README reliability section is not 1.2.3'));
      expect(
        issues,
        contains('P0/P1 readiness plan production evidence is not 1.2.3'),
      );
      expect(issues, contains('HTML report release badge is not 1.2.3'));
      expect(issues, contains('HTML report deployed section is not 1.2.3'));
      expect(issues, hasLength(6));
    });

    test('rejects missing or ambiguous source versions', () {
      expect(
        findGatewayReleaseVersionIssues(
          gatewaySource: 'GatewayConfig{}',
          backendReadme: backendReadme,
          rootReadme: rootReadme,
          readinessPlan: readinessPlan,
          htmlReport: report,
        ),
        ['Gateway source must declare exactly one release version'],
      );
      expect(
        findGatewayReleaseVersionIssues(
          gatewaySource: '$source\n$source',
          backendReadme: backendReadme,
          rootReadme: rootReadme,
          readinessPlan: readinessPlan,
          htmlReport: report,
        ),
        ['Gateway source must declare exactly one release version'],
      );
    });
  });

  group('reviewed Gradle artifact pins', () {
    const origin = 'Official SHA-256 verified';
    const reviewed = {
      'alpha.module':
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'beta.jar':
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    };

    test('accepts the exact reviewed set', () {
      const metadata =
          '''
<artifact name="alpha.module">
  <sha256 value="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" origin="$origin"/>
</artifact>
<artifact name="beta.jar">
  <sha256 value="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" origin="$origin"/>
</artifact>
''';
      expect(
        findReviewedArtifactPinIssues(metadata, reviewed, origin: origin),
        isEmpty,
      );
    });

    test(
      'rejects hash drift, duplicate pins, missing pins and trust expansion',
      () {
        const badMetadata =
            '''
<artifact name="alpha.module">
  <sha256 value="cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc" origin="$origin"/>
</artifact>
<artifact name="alpha.module">
  <sha256 value="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" origin="$origin"/>
</artifact>
<artifact name="unreviewed.jar">
  <sha256 value="dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd" origin="$origin"/>
</artifact>
''';
        final issues = findReviewedArtifactPinIssues(
          badMetadata,
          reviewed,
          origin: origin,
        );
        expect(issues, contains(contains('alpha.module')));
        expect(issues, contains(contains('beta.jar')));
        expect(issues, contains(contains('broadened or truncated')));
      },
    );
  });

  group('real E2E credential guard', () {
    test('rejects a mnemonic-backed entrypoint without batch validation', () {
      const source = '''
const mnemonic = String.fromEnvironment('SEPOLIA_E2E_MNEMONIC');
void main() { runRealTransfer(mnemonic); }
''';
      expect(realE2eEntrypointHasCredentialGuard(source), isFalse);
    });

    test('accepts guarded or credential-free entrypoints', () {
      const guarded = '''
const mnemonic = String.fromEnvironment('SEPOLIA_E2E_MNEMONIC');
void main() {
  requireFreshE2eCredentialBatchIfConfigured();
  runRealTransfer(mnemonic);
}
''';
      expect(realE2eEntrypointHasCredentialGuard(guarded), isTrue);
      expect(realE2eEntrypointHasCredentialGuard('void main() {}'), isTrue);
    });
  });

  group('Flutter ARB localization gate', () {
    test('rejects retired and locale-inappropriate brand terms', () {
      final issues = findForbiddenLocalizationTermIssues(
        {
          'en': '{"@@locale":"en","pair":"Pair KT Wallet Cold Signer"}',
          'zh': '{"@@locale":"zh","pair":"连接 KT Cold Signer"}',
          'ja': '{"@@locale":"ja","pair":"KT Cold Signerと接続"}',
        },
        {
          'en': {'KT Wallet Cold Signer'},
          'zh': {'KT Wallet Cold Signer', 'KT Cold Signer'},
        },
      );

      expect(
        issues,
        contains('en:pair: contains forbidden term "KT Wallet Cold Signer"'),
      );
      expect(
        issues,
        contains('zh:pair: contains forbidden term "KT Cold Signer"'),
      );
      expect(issues.where((issue) => issue.startsWith('ja:')), isEmpty);
    });

    test('accepts exact keys, locales and ICU placeholders', () {
      final issues = findArbCatalogIssues({
        'en': '''{
          "@@locale":"en",
          "title":"Wallet",
          "count":"{count} assets",
          "@count":{"placeholders":{"count":{"type":"int"}}}
        }''',
        'zh': '''{
          "@@locale":"zh",
          "title":"钱包",
          "count":"{count} 项资产"
        }''',
        'ja': '''{
          "@@locale":"ja",
          "title":"ウォレット",
          "count":"資産 {count} 件"
        }''',
      });
      expect(issues, isEmpty);
    });

    test('rejects locale, key, placeholder and fallback-language drift', () {
      final issues = findArbCatalogIssues({
        'en': '{"@@locale":"en","title":"钱包","count":"{count} items"}',
        'zh': '{"@@locale":"ja","title":"钱包","extra":"额外"}',
      });
      expect(issues, contains(contains('@@locale')));
      expect(issues, contains(contains('missing keys')));
      expect(issues, contains(contains('extra keys')));
      expect(issues, contains(contains('English fallback contains CJK')));
    });

    test(
      'rejects untranslated fallback copy unless the locale key is reviewed',
      () {
        final issues = findArbCatalogIssues(
          {
            'en': '{"@@locale":"en","title":"Wallet","chain":"Chain ID"}',
            'zh': '{"@@locale":"zh","title":"Wallet","chain":"Chain ID"}',
            'ja': '{"@@locale":"ja","title":"ウォレット","chain":"Chain ID"}',
          },
          sameAsDefaultAllowedKeys: {
            'zh': {'chain'},
            'ja': {'chain'},
          },
        );

        expect(issues, contains('zh:title: value is identical to en'));
        expect(issues, isNot(contains(contains('zh:chain'))));
        expect(issues, isNot(contains(contains('ja:chain'))));
      },
    );

    test('rejects ASCII prose punctuation beside CJK unless reviewed', () {
      final issues = findArbCatalogIssues(
        {
          'en': '{"@@locale":"en","error":"Failed: retry","call":"Approve"}',
          'zh': '{"@@locale":"zh","error":"失败,请重试","call":"调用 approve(合约, 0)"}',
          'ja':
              '{"@@locale":"ja","error":"失敗:再試行","call":"approve(spender, 0) を呼び出す"}',
        },
        cjkAsciiPunctuationAllowedKeys: {
          'zh': {'call'},
        },
      );

      expect(issues, contains('zh:error: ASCII punctuation beside CJK'));
      expect(issues, contains('ja:error: ASCII punctuation beside CJK'));
      expect(issues, isNot(contains(contains('zh:call'))));
    });
  });

  group('Android native localization gate', () {
    test('accepts matching fallback, Chinese and Japanese resources', () {
      final issues = findAndroidStringResourceIssues({
        'values': '<resources><string name="app">Wallet</string></resources>',
        'values-zh-rCN':
            '<resources><string name="app">钱包</string></resources>',
        'values-ja': '<resources><string name="app">ウォレット</string></resources>',
      });
      expect(issues, isEmpty);
    });

    test('rejects missing keys and CJK fallback text', () {
      final issues = findAndroidStringResourceIssues({
        'values': '''<resources>
          <string name="app">钱包</string>
          <string name="privacy">Hidden</string>
        </resources>''',
        'values-ja': '<resources><string name="app">ウォレット</string></resources>',
      });
      expect(issues, contains(contains('missing strings')));
      expect(issues, contains(contains('fallback contains CJK')));
    });
  });

  group('iOS native localization gate', () {
    const required = {
      'CFBundleDisplayName',
      'CFBundleName',
      'NSCameraUsageDescription',
    };

    test('accepts complete localized InfoPlist.strings files', () {
      final issues = findInfoPlistStringsIssues({
        'en': '''
          "CFBundleDisplayName" = "Wallet";
          "CFBundleName" = "Wallet";
          "NSCameraUsageDescription" = "Scan QR codes.";
        ''',
        'zh-Hans': '''
          "CFBundleDisplayName" = "钱包";
          "CFBundleName" = "钱包";
          "NSCameraUsageDescription" = "用于扫描二维码。";
        ''',
        'ja': '''
          "CFBundleDisplayName" = "Wallet";
          "CFBundleName" = "Wallet";
          "NSCameraUsageDescription" = "QRコードをスキャンします。";
        ''',
      }, requiredKeys: required);
      expect(issues, isEmpty);
    });

    test('rejects missing permissions and unexpected native keys', () {
      final issues = findInfoPlistStringsIssues({
        'en': '''
          "CFBundleDisplayName" = "Wallet";
          "CFBundleName" = "Wallet";
          "NSCameraUsageDescription" = "Scan QR codes.";
        ''',
        'zh-Hans': '''
          "CFBundleDisplayName" = "钱包";
          "CFBundleName" = "钱包";
          "Unexpected" = "值";
        ''',
      }, requiredKeys: required);
      expect(issues, contains(contains('missing InfoPlist keys')));
      expect(issues, contains(contains('unexpected InfoPlist keys')));
    });
  });
}
