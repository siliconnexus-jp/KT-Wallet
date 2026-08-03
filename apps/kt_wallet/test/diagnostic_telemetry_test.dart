import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kt_wallet/src/observability/diagnostic_bundle.dart';
import 'package:kt_wallet/src/observability/diagnostic_telemetry.dart';
import 'package:kt_wallet/src/observability/experience_metrics.dart';

class _MemoryReceipts implements DiagnosticTelemetryReceiptStore {
  String? digest;

  @override
  Future<String?> readDigest() async => digest;

  @override
  Future<void> writeDigest(String digest) async => this.digest = digest;
}

ExperienceMetric _sample(
  String name,
  int milliseconds, {
  bool success = true,
}) => ExperienceMetric(
  name: name,
  duration: Duration(milliseconds: milliseconds),
  success: success,
  recordedAt: DateTime.utc(2026, 8, 2),
);

DiagnosticTelemetryReport _report() => DiagnosticTelemetryReport.fromMetrics(
  platform: TargetPlatform.iOS,
  buildMode: DiagnosticBuildMode.release,
  localeCode: 'zh-Hans-CN',
  samples: [
    _sample(ExperienceMetricNames.appStartup, 100),
    _sample(ExperienceMetricNames.appStartup, 300),
    _sample(ExperienceMetricNames.transactionBroadcast, 900, success: false),
  ],
);

void main() {
  test('report is a closed aggregate schema with no identifying fields', () {
    final params = _report().toParams();

    expect(params.keys.toSet(), {
      'schemaVersion',
      'consent',
      'appVersion',
      'platform',
      'locale',
      'buildMode',
      'metrics',
    });
    expect(params['platform'], 'ios');
    expect(params['locale'], 'zh');
    expect(params['buildMode'], 'release');
    expect(params['consent'], isTrue);
    final rows = params['metrics']! as List<Object?>;
    expect(rows, hasLength(2));
    expect(rows.first, {
      'name': ExperienceMetricNames.appStartup,
      'count': 2,
      'successCount': 2,
      'failureCount': 0,
      'p50Ms': 300,
      'p95Ms': 300,
    });

    final encoded = jsonEncode(params).toLowerCase();
    for (final forbidden in const [
      'wallet',
      'address',
      'balance',
      'amount',
      'transactionhash',
      'txhash',
      'timestamp',
      'recordedat',
      'deviceid',
      'sessionid',
      'endpoint',
      'error',
      'stack',
      'mnemonic',
      'recoveryphrase',
      'privatekey',
      'signature',
    ]) {
      expect(encoded, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test(
    'unknown metrics are discarded and an empty report is not sent',
    () async {
      var requests = 0;
      final uploader = GatewayDiagnosticTelemetryUploader(
        client: MockClient((_) async {
          requests += 1;
          return http.Response('{}', 200);
        }),
        receipts: _MemoryReceipts(),
      );
      final report = DiagnosticTelemetryReport.fromMetrics(
        platform: TargetPlatform.android,
        samples: [_sample('wallet.0x-private', 1)],
      );

      expect(report.metrics, isEmpty);
      expect(
        await uploader.upload(
          gatewayBaseUrl: 'https://gateway.kt-wallet.com',
          report: report,
        ),
        DiagnosticTelemetryUploadResult.noSamples,
      );
      expect(requests, 0);
    },
  );

  test(
    'one upload uses the exact RPC method and stores only its digest',
    () async {
      final receipts = _MemoryReceipts();
      late Uri requestUrl;
      late Map<String, Object?> requestJson;
      var requests = 0;
      final uploader = GatewayDiagnosticTelemetryUploader(
        client: MockClient((request) async {
          requests += 1;
          requestUrl = request.url;
          requestJson = jsonDecode(request.body) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'result': {'accepted': true, 'rawEventsStored': false},
            }),
            200,
          );
        }),
        receipts: receipts,
      );
      final report = _report();

      expect(
        await uploader.upload(
          gatewayBaseUrl: 'https://gateway.kt-wallet.com/',
          report: report,
        ),
        DiagnosticTelemetryUploadResult.sent,
      );
      expect(requestUrl.toString(), 'https://gateway.kt-wallet.com/rpc');
      expect(requestJson.keys.toSet(), {'jsonrpc', 'id', 'method', 'params'});
      expect(requestJson['method'], 'kt_reportDiagnostics');
      expect(requestJson['params'], report.toParams());
      expect(receipts.digest, report.digest);

      expect(
        await uploader.upload(
          gatewayBaseUrl: 'https://gateway.kt-wallet.com',
          report: report,
        ),
        DiagnosticTelemetryUploadResult.alreadySent,
      );
      expect(
        requests,
        1,
        reason: 'an identical report must not be counted twice',
      );
    },
  );

  test('unsafe or ambiguous gateway URLs fail before network access', () async {
    var requests = 0;
    final uploader = GatewayDiagnosticTelemetryUploader(
      client: MockClient((_) async {
        requests += 1;
        return http.Response('{}', 200);
      }),
      receipts: _MemoryReceipts(),
    );
    for (final url in const [
      'http://gateway.kt-wallet.com',
      'https://user:secret@gateway.kt-wallet.com',
      'https://gateway.kt-wallet.com?wallet=secret',
      'not a URL',
    ]) {
      await expectLater(
        uploader.upload(gatewayBaseUrl: url, report: _report()),
        throwsA(isA<FormatException>()),
        reason: url,
      );
    }
    expect(requests, 0);
  });

  test('malformed acknowledgement fails and is never marked sent', () async {
    final receipts = _MemoryReceipts();
    final uploader = GatewayDiagnosticTelemetryUploader(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'result': {'accepted': true, 'rawEventsStored': true},
          }),
          200,
        ),
      ),
      receipts: receipts,
    );

    await expectLater(
      uploader.upload(
        gatewayBaseUrl: 'https://gateway.kt-wallet.com',
        report: _report(),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(receipts.digest, isNull);
  });

  test('acknowledgement must bind the exact JSON-RPC request', () async {
    final malformed = <Map<String, Object?>>[
      {
        'jsonrpc': '2.0',
        'id': 2,
        'result': {'accepted': true, 'rawEventsStored': false},
      },
      {
        'id': 1,
        'result': {'accepted': true, 'rawEventsStored': false},
      },
      {
        'jsonrpc': '2.0',
        'id': 1.0,
        'result': {'accepted': true, 'rawEventsStored': false},
      },
      {
        'jsonrpc': '2.0',
        'id': 1,
        'result': {'accepted': true, 'rawEventsStored': false},
        'error': null,
      },
    ];

    for (final acknowledgement in malformed) {
      final receipts = _MemoryReceipts();
      final uploader = GatewayDiagnosticTelemetryUploader(
        client: MockClient(
          (_) async => http.Response(jsonEncode(acknowledgement), 200),
        ),
        receipts: receipts,
      );

      await expectLater(
        uploader.upload(
          gatewayBaseUrl: 'https://gateway.kt-wallet.com',
          report: _report(),
        ),
        throwsA(isA<FormatException>()),
        reason: '$acknowledgement must not acknowledge request id 1',
      );
      expect(receipts.digest, isNull);
    }
  });
}
