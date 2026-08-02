import 'dart:convert';

import 'package:chains/chains.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/observability/diagnostic_bundle.dart';
import 'package:kt_wallet/src/observability/experience_metrics.dart';
import 'package:kt_wallet/src/state/app_prefs.dart';
import 'package:kt_wallet/src/state/networks.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('bundle uses an allowlist and omits wallet and provider data', () async {
    const sensitiveAddress = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';
    const sensitiveRpc =
        'https://example.invalid/alch_private?key=secret-provider-token';
    const sensitiveGateway = 'https://gateway.invalid/J8B93RI5-secret';

    final prefs = AppPrefsController();
    await prefs.setRpcOverride(Coin.eth, sensitiveRpc);
    await prefs.setGatewayUrl(sensitiveGateway);
    final networks = NetworkController();
    final custom = await networks.addCustom(
      chain: Chain.ethereum,
      name: sensitiveAddress,
      rpcUrl: sensitiveRpc,
      symbol: 'ETH',
      evmChainId: 31337,
      explorerUrl: '$sensitiveRpc/explorer',
    );
    await networks.setOverride(Chain.ethereum, custom.id);

    final now = DateTime.utc(2026, 8, 1, 2, 3, 47);
    final bundle = const DiagnosticBundleBuilder().build(
      generatedAt: now,
      localeCode: 'ja-JP',
      platform: TargetPlatform.iOS,
      buildMode: DiagnosticBuildMode.release,
      networks: networks,
      prefs: prefs,
      metrics: [
        ExperienceMetric(
          name: 'market.refresh',
          duration: const Duration(milliseconds: 10),
          success: true,
          recordedAt: now,
        ),
        ExperienceMetric(
          name: 'market.refresh',
          duration: const Duration(milliseconds: 90),
          success: false,
          recordedAt: now,
        ),
        ExperienceMetric(
          name: ExperienceMetricNames.transactionBroadcast,
          duration: const Duration(hours: 8),
          success: true,
          recordedAt: now,
        ),
        ExperienceMetric(
          name: ExperienceMetricNames.appNativeFatal,
          duration: Duration.zero,
          success: false,
          recordedAt: now,
        ),
        ExperienceMetric(
          name: 'wallet.$sensitiveAddress',
          duration: const Duration(milliseconds: 1),
          success: true,
          recordedAt: now,
        ),
      ],
    );

    expect(bundle.json, isNot(contains(sensitiveAddress)));
    expect(bundle.json, isNot(contains(sensitiveRpc)));
    expect(bundle.json, isNot(contains(sensitiveGateway)));
    expect(bundle.json, isNot(contains('alch_private')));
    expect(bundle.generatedAtUtc, DateTime.utc(2026, 8, 1, 2, 3));

    final body = jsonDecode(bundle.json) as Map<String, dynamic>;
    expect(body['generatedAtUtc'], '2026-08-01T02:03:00.000Z');
    expect(body['runtime'], {
      'platform': 'iOS',
      'locale': 'ja',
      'buildMode': 'release',
    });
    final networkConfiguration = (body['networkConfiguration']! as Map)
        .cast<String, Object?>();
    expect(networkConfiguration['gatewayMode'], 'override');
    final ethereum = (networkConfiguration['active']! as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((row) => row['chain'] == 'ethereum');
    expect(ethereum['profile'], 'custom');
    expect(ethereum['endpointMode'], 'preference-override');
    expect(body['performance'], [
      {
        'name': 'app.nativeFatal',
        'count': 1,
        'successCount': 0,
        'failureCount': 1,
        'p50Ms': 0,
        'p95Ms': 0,
      },
      {
        'name': 'market.refresh',
        'count': 2,
        'successCount': 1,
        'failureCount': 1,
        'p50Ms': 90,
        'p95Ms': 90,
      },
      {
        'name': 'transaction.broadcast',
        'count': 1,
        'successCount': 1,
        'failureCount': 0,
        'p50Ms': ExperienceMetrics.maxDurationMs,
        'p95Ms': ExperienceMetrics.maxDurationMs,
      },
    ]);
    expect(
      (body['redaction'] as Map<String, dynamic>).values,
      everyElement('omitted'),
    );
  });

  test('unknown fields are rejected before serialization', () {
    final original = const DiagnosticBundleBuilder().build(
      generatedAt: DateTime.utc(2026, 8, 1),
      platform: TargetPlatform.android,
    );
    final body = (jsonDecode(original.json) as Map).cast<String, Object?>();
    body['walletAddress'] = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';

    expect(
      () => DiagnosticBundle.checked(body),
      throwsA(isA<DiagnosticBundleValidationException>()),
    );
  });

  test('known fields cannot carry arbitrary URLs or identifiers', () {
    final original = const DiagnosticBundleBuilder().build(
      generatedAt: DateTime.utc(2026, 8, 1),
      platform: TargetPlatform.android,
    );
    final body = (jsonDecode(original.json) as Map).cast<String, Object?>();
    final runtime = (body['runtime']! as Map).cast<String, Object?>();
    runtime['platform'] = 'https://rpc.example.invalid/private';

    expect(
      () => DiagnosticBundle.checked(body),
      throwsA(isA<DiagnosticBundleValidationException>()),
    );
  });
}
