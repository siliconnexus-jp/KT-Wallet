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
| KT Gateway | `1.2.2` | Production service at `https://gateway.example` |
Gateway source version: `1.2.3`
Gateway `1.2.2` currently exposes 16 mainnet/testnet network profiles.
''';
    const readinessPlan = '当前 Gateway 源码版本 1.2.3；当前生产 Gateway 1.2.2。';
    const report = '''
<span>Gateway 源码版本 · 1.2.3</span>
<strong>Gateway 发布状态 · 1.2.2 已上线</strong>
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

    test(
      'rejects stale current markers even if history mentions the version',
      () {
        final issues = findGatewayReleaseVersionIssues(
          gatewaySource: source,
          backendReadme:
              '${backendReadme.replaceAll('1.2.3', '1.2.2')}\nHistorical 1.2.3 notes.',
          rootReadme: rootReadme
              .replaceFirst(
                'Gateway source version: `1.2.3`',
                'Gateway source version: `1.2.1`',
              )
              .replaceFirst(
                'Gateway `1.2.2` currently exposes',
                'Gateway `1.2.1` currently exposes',
              ),
          readinessPlan: readinessPlan
              .replaceFirst('源码版本 1.2.3', '源码版本 1.2.1')
              .replaceFirst('生产 Gateway 1.2.2', '生产 Gateway 1.2.1'),
          htmlReport: report
              .replaceFirst('源码版本 · 1.2.3', '源码版本 · 1.2.1')
              .replaceFirst('发布状态 · 1.2.2', '发布状态 · 1.2.1'),
        );

        expect(
          issues,
          contains('backend README health example is not source 1.2.3'),
        );
        expect(issues, contains('root README source marker is not 1.2.3'));
        expect(
          issues,
          contains('root README reliability section is not production 1.2.2'),
        );
        expect(
          issues,
          contains('P0/P1 readiness plan source marker is not 1.2.3'),
        );
        expect(
          issues,
          contains('P0/P1 readiness plan production marker is not 1.2.2'),
        );
        expect(issues, contains('HTML report source marker is not 1.2.3'));
        expect(issues, contains('HTML report deployed section is not 1.2.2'));
        expect(issues, hasLength(7));
      },
    );

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

  group('multi-broadcast E2E funding guard', () {
    test('requires the selected-chain preflight before any broadcast', () {
      const path = 'integration_test/evm_expansion_transfer_e2e_test.dart';
      const safe = '''
await _requireSelectedFundingBeforeAnyBroadcast(
  selected: selected,
  addresses: addresses,
  transport: transport,
);
await crypto.signTransaction(walletId: walletId, signingInput: input);
await broadcaster.broadcast(chain, signedTx);
''';
      const missing = '''
await crypto.signTransaction(walletId: walletId, signingInput: input);
await broadcaster.broadcast(chain, signedTx);
''';
      const late = '''
await crypto.signTransaction(walletId: walletId, signingInput: input);
await broadcaster.broadcast(chain, signedTx);
await _requireSelectedFundingBeforeAnyBroadcast();
''';
      expect(multiBroadcastE2eHasFundingPreflight(path, safe), isTrue);
      expect(multiBroadcastE2eHasFundingPreflight(path, missing), isFalse);
      expect(multiBroadcastE2eHasFundingPreflight(path, late), isFalse);
    });

    test(
      'requires the bridge-specific preflight and ignores single-chain tests',
      () {
        const bridge = 'integration_test/l2_bridge_funding_e2e_test.dart';
        const safe = '''
await _requireBridgeFundingBeforeAnyBroadcast();
await crypto.signTransaction(walletId: walletId, signingInput: input);
await broadcaster.broadcast(chain, signedTx);
''';
        expect(multiBroadcastE2eHasFundingPreflight(bridge, safe), isTrue);
        expect(
          multiBroadcastE2eHasFundingPreflight(
            bridge,
            safe.replaceFirst('_requireBridge', '_requireSelected'),
          ),
          isFalse,
        );
        expect(
          multiBroadcastE2eHasFundingPreflight(
            'integration_test/sepolia_transfer_e2e_test.dart',
            'await broadcaster.broadcast(chain, signedTx);',
          ),
          isTrue,
        );
      },
    );
  });

  group('Gateway-first transaction finality', () {
    test(
      'accepts status-first finality with non-blocking depth enrichment',
      () {
        const source = '''
final chainStatus = await _statusService?.check(tx);
await persist(chainStatus);
unawaited(_readConfirmationDepth());
''';
        expect(findGatewayFirstFinalityIssues(source), isEmpty);
      },
    );

    test('rejects the old direct-RPC-first blocking order', () {
      const source = '''
final directStatus = await _readConfirmationDepth();
final chainStatus = await _statusService?.check(tx);
''';
      expect(
        findGatewayFirstFinalityIssues(source),
        containsAll(<String>[
          'confirmation depth is not a non-blocking enrichment',
          'direct confirmation depth blocks finality persistence',
        ]),
      );
    });

    test('rejects non-blocking depth when it starts before status', () {
      const source = '''
unawaited(_readConfirmationDepth());
final chainStatus = await _statusService?.check(tx);
''';
      expect(
        findGatewayFirstFinalityIssues(source),
        contains('confirmation depth starts before Gateway-first finality'),
      );
    });
  });

  group('host funding CLI boundary', () {
    const standalone = '''
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart';
import 'e2e_funding_preflight_model.dart';
Future<void> main(List<String> arguments) async {}
Object? decode(String source) => decodeGatewayFundingJson(source);
''';

    test('accepts the exact standalone Dart import surface', () {
      expect(findHostFundingCliBoundaryIssues(standalone), isEmpty);
    });

    test('rejects Flutter/App imports and implicit configuration channels', () {
      final issues = findHostFundingCliBoundaryIssues('''
$standalone
import 'package:flutter/material.dart';
import 'package:kt_wallet/src/market/gateway_client.dart';
void leak() {
  Platform.environment['TOKEN'];
  const value = String.fromEnvironment('SECRET');
  Process.run('helper', const []);
}
''');
      expect(issues, contains(contains('package:flutter/material.dart')));
      expect(issues, contains(contains('package:kt_wallet')));
      expect(issues, contains(contains('environment credentials')));
      expect(issues, contains(contains('dart-define credentials')));
      expect(issues, contains(contains('child process execution')));
    });

    test('rejects duplicate-unsafe remote JSON decoding', () {
      final issues = findHostFundingCliBoundaryIssues('''
$standalone
Object? unsafe(String source) => jsonDecode(source);
''');
      expect(issues, contains(contains('duplicate-unsafe JSON decoder')));
    });
  });

  group('external backup JSON boundary', () {
    const safe = '''
final restored = decodeJsonWithoutDuplicateKeys(utf8.decode(bytes));
final timestamp = decodeJsonWithoutDuplicateKeys(utf8.decode(bytes));
''';

    test('requires duplicate-safe decoding on both file paths', () {
      expect(findExternalBackupJsonBoundaryIssues(safe), isEmpty);
      expect(
        findExternalBackupJsonBoundaryIssues(
          'final value = decodeJsonWithoutDuplicateKeys(utf8.decode(bytes));',
        ),
        contains(contains('both reject duplicate JSON members')),
      );
    });

    test('rejects the ordinary decoder even beside safe calls', () {
      expect(
        findExternalBackupJsonBoundaryIssues('''
$safe
final unsafe = jsonDecode(utf8.decode(bytes));
'''),
        contains(contains('duplicate-unsafe JSON decoder')),
      );
    });
  });

  group('TRON signed JSON boundary', () {
    const verifier = '''
const tronSignedTransactionJsonMaxBytes = 1024 * 1024;
if (signed.length > tronSignedTransactionJsonMaxBytes) throw FormatException();
final decoded = decodeJsonWithUniqueObjectMembers(
  utf8.decode(signed),
  maxChars: tronSignedTransactionJsonMaxBytes,
);
if (map.keys.any((key) => key != 'transaction' && key != 'txID')) throw FormatException();
''';
    const broadcaster = '''
final decoded = _decodeTronSignedJson(signedTx);
final checked = _decodeTronSignedJson(signedTx);
if (signedTx.length > tronSignedTransactionJsonMaxBytes) throw FormatException();
return decodeJsonWithUniqueObjectMembers(source);
''';

    test(
      'accepts a bounded unique decoder at verify and submit boundaries',
      () {
        expect(
          findTronSignedJsonBoundaryIssues(verifier, broadcaster),
          isEmpty,
        );
      },
    );

    test('rejects unsafe decoding or a missing submission bound', () {
      final issues = findTronSignedJsonBoundaryIssues(
        verifier.replaceFirst(
          'decodeJsonWithUniqueObjectMembers(',
          'jsonDecode(utf8.decode(signed)); unused(',
        ),
        broadcaster
            .replaceFirst(
              'decodeJsonWithUniqueObjectMembers(source)',
              'json.decode(text)',
            )
            .replaceFirst(
              'signedTx.length > tronSignedTransactionJsonMaxBytes',
              'false',
            ),
      );
      expect(issues, contains(contains('verifier does not reject duplicate')));
      expect(issues, contains(contains('verifier uses the duplicate-unsafe')));
      expect(
        issues,
        contains(contains('broadcaster does not reject duplicate')),
      );
      expect(issues, contains(contains('broadcaster does not enforce')));
      expect(
        issues,
        contains(contains('broadcaster uses the duplicate-unsafe')),
      );
    });
  });

  group('wallet display snapshot boundary', () {
    const market = '''
static const maxSnapshotChars = 262144;
static const _maxTokens = 512;
final decoded = decodeJsonWithoutDuplicateKeys(
  encoded,
  maxChars: maxSnapshotChars,
);
final body = requireExactSnapshotObject(
  decoded,
  members: rawVersion == 1 ? _topV1 : _topV2,
);
final amount = requireExactSnapshotObject(value, members: _amountMembers);
final number = positiveFiniteMarketNumber(entry.value);
''';
    const history = '''
static const maxSnapshotChars = 1048576;
static const _maxRecordsPerCoin = 100;
final decoded = decodeJsonWithoutDuplicateKeys(
  encoded,
  maxChars: maxSnapshotChars,
);
final body = requireExactSnapshotObject(decoded, members: _topMembers);
final record = requireExactSnapshotObject(
  value,
  members: switch (version) { 1 => _recordV1, _ => _recordV3 },
);
final verified = record['verified'];
if (outgoing is! bool || verified is! bool) throw FormatException();
return ChainTxRecord(assetVerified: verified);
''';

    test('accepts bounded duplicate-safe closed cache schemas', () {
      expect(findWalletDisplaySnapshotBoundaryIssues(market, history), isEmpty);
    });

    test('rejects unsafe decoding and trusted verification fallback', () {
      final issues = findWalletDisplaySnapshotBoundaryIssues(
        market.replaceFirst(
          'decodeJsonWithoutDuplicateKeys(',
          'jsonDecode(encoded); unused(',
        ),
        history
            .replaceFirst('maxSnapshotChars = 1048576', 'gone')
            .replaceFirst(
              'assetVerified: verified',
              "assetVerified: value['verified'] is bool ? true : true",
            ),
      );
      expect(issues, contains(contains('market snapshot does not reject')));
      expect(issues, contains(contains('duplicate-unsafe JSON decoder')));
      expect(issues, contains(contains('history snapshot JSON size')));
      expect(issues, contains(contains('defaults malformed verification')));
    });
  });

  group('network snapshot boundary', () {
    const network = '''
static const maxSnapshotChars = 262144;
static const maxCustomNetworks = 64;
static const maxEvmChainId = 2147483647;
final decoded = decodeJsonWithoutDuplicateKeys(
  source,
  maxChars: maxSnapshotChars,
);
if (value.keys.toSet().difference(_networkSnapshotMembers).isNotEmpty) {}
final valid = _hasExactStringMembers(
  record,
  required: _networkRequiredMembers,
  allowed: _networkAllowedMembers,
);
if (m['isTestnet'] is! bool) return null;
if (networkIdentity != '\$evmChainId') return null;
if (hasSnapshot && snapshot == null) return;
''';
    const endpoint = '''
static const maxUrlChars = 2048;
if (normalized.length > maxUrlChars) throw FormatException();
''';
    const settings = '''
final isEvm = chain != Chain.tron && chain != Chain.solana;
final valid = typedChainId <= Network.maxEvmChainId;
''';

    test('accepts closed bounded routing and signing-domain state', () {
      expect(
        findNetworkSnapshotBoundaryIssues(network, endpoint, settings),
        isEmpty,
      );
    });

    test('rejects unsafe JSON, mainnet coercion and incomplete EVM UI', () {
      final issues = findNetworkSnapshotBoundaryIssues(
        '''
${network.replaceFirst('decodeJsonWithoutDuplicateKeys(', 'json.decode(source); unused(')}
final testnet = m['isTestnet'] == true;
''',
        endpoint.replaceFirst('normalized.length > maxUrlChars', 'gone'),
        settings.replaceFirst(
          'chain != Chain.tron && chain != Chain.solana',
          'chain == Chain.ethereum || chain == Chain.polygon',
        ),
      );
      expect(issues, contains(contains('does not reject duplicate')));
      expect(issues, contains(contains('duplicate-unsafe JSON decoder')));
      expect(issues, contains(contains('silently becomes mainnet')));
      expect(issues, contains(contains('endpoint length')));
      expect(issues, contains(contains('every EVM')));
    });
  });

  group('wallet PIN state boundary', () {
    const safe = '''
static const maxStoredIterations = 1000000;
static const maxStoredRecordChars = 4096;
static const maxTrackedFailures = 64;
static const maxLockout = Duration(hours: 24);
final decoded = decodeJsonWithoutDuplicateKeys(raw);
final pin = _decode(allowed: const {'algo', 'salt', 'hash', 'iterations'});
final lock = _decode(allowed: const {'fails', 'lockedUntil'});
final salt = _decodeCanonicalBase64(record['salt'], saltLength);
final hash = _decodeCanonicalBase64(record['hash'], hashLength);
until = now.add(_lockoutDuration(newFails));
''';

    test('accepts closed bounded PIN and lockout records', () {
      expect(findWalletPinStateBoundaryIssues(safe), isEmpty);
    });

    test(
      'rejects unsafe JSON, presence-only enrollment, and unbounded shift',
      () {
        final issues = findWalletPinStateBoundaryIssues('''
$safe
final record = jsonDecode(raw);
Future<bool> isSet() async => await storage.read(pinKey) != null;
final factor = 1 << (newFails - threshold);
''');
        expect(issues, contains(contains('duplicate-unsafe JSON decoder')));
        expect(issues, contains(contains('presence without parsing')));
        expect(issues, contains(contains('attacker-sized bit shift')));
      },
    );

    test('rejects removal of every resource and schema bound', () {
      for (final marker in [
        'maxStoredIterations = 1000000',
        'maxStoredRecordChars = 4096',
        'maxTrackedFailures = 64',
        'maxLockout = Duration(hours: 24)',
        "allowed: const {'algo', 'salt', 'hash', 'iterations'}",
        "allowed: const {'fails', 'lockedUntil'}",
      ]) {
        expect(
          findWalletPinStateBoundaryIssues(safe.replaceFirst(marker, 'gone')),
          isNotEmpty,
        );
      }
    });
  });

  group('cold signer PIN state boundary', () {
    const safe = '''
static const maxStoredIterations = 1000000;
static const maxStoredRecordChars = 4096;
static const maxTrackedFailures = 64;
static const maxLockout = Duration(hours: 24);
final decoded = decodeStrictLocalJson(raw, maxChars: maxStoredRecordChars);
final pin = _decode(allowed: const {'algo', 'salt', 'hash', 'iterations'});
final lock = _decode(allowed: const {'fails', 'lockedUntil'});
final salt = _decodeCanonicalBase64(record['salt'], saltLength);
final hash = _decodeCanonicalBase64(record['hash'], hashLength);
until = now.add(_lockoutDuration(newFails));
''';

    test('accepts the closed bounded signer PIN format', () {
      expect(findSignerPinStateBoundaryIssues(safe), isEmpty);
    });

    test('rejects unsafe decoding and unbounded lockout growth', () {
      final issues = findSignerPinStateBoundaryIssues('''
$safe
final record = jsonDecode(raw);
Future<bool> isSet() async => await storage.read(pinKey) != null;
final factor = 1 << (newFails - threshold);
''');
      expect(issues, contains(contains('duplicate-unsafe JSON decoder')));
      expect(issues, contains(contains('presence without parsing')));
      expect(issues, contains(contains('attacker-sized bit shift')));
    });
  });

  group('cold signer vault state boundary', () {
    const safeVault = '''
static const maxMetadataChars = 16384;
final decoded = decodeStrictLocalJson(raw, maxChars: maxMetadataChars);
const allowed = {'walletId', 'name', 'createdAt', 'version', 'addresses',
  'publicKeys', 'biometricEnabled',};
Future<bool> hasWallet() async => await readMetadata() != null;
CoreCryptoValidation.checkWalletId(walletId);
''';
    const safeController = '''
if (metadata.walletId != pendingDeletion) throw StateError('mismatch');
await finish(pendingDeletion, deleteNative: metadata != null);
if (deleteNative) await crypto.deleteWallet(walletId);
''';

    test('accepts closed metadata and identity-bound deletion recovery', () {
      expect(
        findSignerVaultStateBoundaryIssues(safeVault, safeController),
        isEmpty,
      );
    });

    test('rejects presence-only metadata and unbound deletion recovery', () {
      final issues = findSignerVaultStateBoundaryIssues('''
$safeVault
final metadata = jsonDecode(raw);
Future<bool> hasWallet() async => await storage.read(metadataKey) != null;
''', 'await crypto.deleteWallet(pendingDeletion);');
      expect(issues, contains(contains('duplicate-unsafe JSON decoder')));
      expect(issues, contains(contains('presence')));
      expect(issues, contains(contains('bind tombstone')));
      expect(issues, contains(contains('unbound native wallet')));
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

    test('rejects ordinary English UI prose left inside CJK messages', () {
      final issues = findUntranslatedCjkProseIssues({
        'en': '{"@@locale":"en","from":"From account","retry":"Retry"}',
        'zh': '''{
          "@@locale":"zh",
          "from":"转出账户（From）",
          "retry":"重试",
          "password":"输入 password"
        }''',
        'ja': '{"@@locale":"ja","from":"送金元","retry":"Retry"}',
      });

      expect(issues, contains('zh:from: untranslated UI prose [From]'));
      expect(issues, contains('zh:password: untranslated UI prose [password]'));
      expect(issues, contains('ja:retry: untranslated UI prose [Retry]'));

      final allowlistIssues = findUntranslatedCjkProseIssues(
        {
          'zh': '{"@@locale":"zh","from":"转出账户（From）"}',
          'ja': '{"@@locale":"ja","retry":"再試行"}',
        },
        allowedKeys: const {
          'zh': {'from', 'missing'},
          'fr': {'from'},
        },
      );
      expect(
        allowlistIssues,
        contains('zh:missing: stale untranslated-prose allowlist'),
      );
      expect(
        allowlistIssues,
        contains('fr: unsupported untranslated-prose allowlist locale'),
      );
      expect(allowlistIssues, isNot(contains(contains('zh:from'))));
    });

    test('preserves official chain names and token symbols across locales', () {
      final issues = findProtectedArbTermIssues({
        'en': '''{
          "@@locale":"en",
          "send":"Send USDT on Ethereum",
          "approval":"ERC-20 approval",
          "pyusd":"PayPal USD (PYUSD)"
        }''',
        'zh': '''{
          "@@locale":"zh",
          "send":"在以太坊发送泰达币",
          "approval":"ERC-20 授权",
          "pyusd":"贝宝美元（PYUSD）"
        }''',
        'ja': '''{
          "@@locale":"ja",
          "send":"Ethereum で USDT を送信",
          "approval":"ERC-20 承認",
          "pyusd":"PayPal USD（PYUSD）"
        }''',
      });

      expect(issues, contains('zh:send: missing protected term "Ethereum"'));
      expect(issues, contains('zh:send: missing protected term "USDT"'));
      expect(issues, contains('zh:pyusd: missing protected term "PayPal USD"'));
      expect(issues.where((issue) => issue.startsWith('ja:')), isEmpty);
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
