import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../app_info.dart';
import '../rpc/bounded_http_client.dart';
import '../rpc/json_rpc_envelope.dart';
import '../state/endpoint_policy.dart';
import 'diagnostic_bundle.dart';
import 'experience_metrics.dart';

/// Result of a user-initiated aggregate diagnostics upload.
enum DiagnosticTelemetryUploadResult { sent, alreadySent, noSamples }

class DiagnosticTelemetryMetric {
  const DiagnosticTelemetryMetric({
    required this.name,
    required this.count,
    required this.successCount,
    required this.failureCount,
    required this.p50Ms,
    required this.p95Ms,
  });

  final String name;
  final int count;
  final int successCount;
  final int failureCount;
  final int p50Ms;
  final int p95Ms;

  Map<String, Object?> toJson() => {
    'name': name,
    'count': count,
    'successCount': successCount,
    'failureCount': failureCount,
    'p50Ms': p50Ms,
    'p95Ms': p95Ms,
  };
}

/// Closed-schema report sent only after the user confirms the disclosure.
///
/// It intentionally excludes the richer local support bundle's timestamp,
/// network configuration and service state. There is no device/session ID,
/// endpoint, wallet, balance, transaction, exception text or stack trace.
class DiagnosticTelemetryReport {
  DiagnosticTelemetryReport._({
    required this.appVersion,
    required this.platform,
    required this.locale,
    required this.buildMode,
    required this.metrics,
  });

  static const schemaVersion = 1;

  final String appVersion;
  final String platform;
  final String locale;
  final String buildMode;
  final List<DiagnosticTelemetryMetric> metrics;

  factory DiagnosticTelemetryReport.fromMetrics({
    required Iterable<ExperienceMetric> samples,
    String localeCode = 'en',
    TargetPlatform? platform,
    DiagnosticBuildMode? buildMode,
  }) {
    final grouped = <String, List<ExperienceMetric>>{};
    for (final sample in samples) {
      if (!ExperienceMetricNames.all.contains(sample.name)) continue;
      (grouped[sample.name] ??= []).add(sample);
    }

    final metrics = <DiagnosticTelemetryMetric>[];
    for (final name in grouped.keys.toList()..sort()) {
      final rows = grouped[name]!;
      final durations =
          rows
              .map(
                (row) => row.duration.inMilliseconds.clamp(
                  0,
                  ExperienceMetrics.maxDurationMs,
                ),
              )
              .toList()
            ..sort();
      final successes = rows.where((row) => row.success).length;
      metrics.add(
        DiagnosticTelemetryMetric(
          name: name,
          count: rows.length,
          successCount: successes,
          failureCount: rows.length - successes,
          p50Ms: _percentile(durations, 0.50),
          p95Ms: _percentile(durations, 0.95),
        ),
      );
    }

    final effectivePlatform = platform ?? defaultTargetPlatform;
    final platformName = switch (effectivePlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => throw UnsupportedError('mobile diagnostics only'),
    };
    final language = localeCode.split(RegExp('[-_]')).first.toLowerCase();
    final safeLocale = const {'en', 'zh', 'ja'}.contains(language)
        ? language
        : 'other';
    final mode = buildMode ?? _currentBuildMode;

    return DiagnosticTelemetryReport._(
      appVersion: AppInfo.version,
      platform: platformName,
      locale: safeLocale,
      buildMode: mode.name,
      metrics: List.unmodifiable(metrics),
    );
  }

  Map<String, Object?> toParams() => {
    'schemaVersion': schemaVersion,
    'consent': true,
    'appVersion': appVersion,
    'platform': platform,
    'locale': locale,
    'buildMode': buildMode,
    'metrics': [for (final metric in metrics) metric.toJson()],
  };

  String get digest =>
      sha256.convert(utf8.encode(jsonEncode(toParams()))).toString();

  static DiagnosticBuildMode get _currentBuildMode {
    if (kReleaseMode) return DiagnosticBuildMode.release;
    if (kProfileMode) return DiagnosticBuildMode.profile;
    return DiagnosticBuildMode.debug;
  }

  static int _percentile(List<int> sorted, double percentile) {
    if (sorted.isEmpty) return 0;
    return sorted[((sorted.length - 1) * percentile).round()];
  }
}

abstract interface class DiagnosticTelemetryReceiptStore {
  Future<String?> readDigest();
  Future<void> writeDigest(String digest);
}

class SharedPrefsDiagnosticTelemetryReceiptStore
    implements DiagnosticTelemetryReceiptStore {
  const SharedPrefsDiagnosticTelemetryReceiptStore();

  static const _key = 'observability.lastUploadedDiagnostics.v1';

  @override
  Future<String?> readDigest() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  @override
  Future<void> writeDigest(String digest) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, digest);
  }
}

abstract interface class DiagnosticTelemetryUploader {
  Future<DiagnosticTelemetryUploadResult> upload({
    required String gatewayBaseUrl,
    required DiagnosticTelemetryReport report,
  });
}

/// Sends one exact JSON-RPC request without retries. A diagnostics request is
/// not idempotent at the Gateway counter layer, so transport ambiguity must
/// surface honestly instead of silently duplicating samples.
class GatewayDiagnosticTelemetryUploader
    implements DiagnosticTelemetryUploader {
  GatewayDiagnosticTelemetryUploader({
    this.client,
    DiagnosticTelemetryReceiptStore? receipts,
    this.timeout = const Duration(seconds: 10),
  }) : _receipts =
           receipts ?? const SharedPrefsDiagnosticTelemetryReceiptStore();

  final http.Client? client;
  final DiagnosticTelemetryReceiptStore _receipts;
  final Duration timeout;

  @override
  Future<DiagnosticTelemetryUploadResult> upload({
    required String gatewayBaseUrl,
    required DiagnosticTelemetryReport report,
  }) async {
    if (report.metrics.isEmpty) {
      return DiagnosticTelemetryUploadResult.noSamples;
    }
    final safeBase = EndpointPolicy.requireSafeUrl(gatewayBaseUrl);
    if (Uri.parse(safeBase).hasQuery) {
      throw const FormatException('Gateway base URL must not contain a query');
    }
    final normalizedBase = safeBase.replaceFirst(RegExp(r'/+$'), '');
    final digest = report.digest;
    try {
      if (await _receipts.readDigest() == digest) {
        return DiagnosticTelemetryUploadResult.alreadySent;
      }
    } on Object {
      // Receipt persistence is a duplicate-suppression optimization. Failure
      // must not silently claim the report was sent.
    }

    final ownedClient = this.client == null;
    final client = BoundedHttpClient(this.client ?? http.Client());
    final request = <String, Object?>{
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'kt_reportDiagnostics',
      'params': report.toParams(),
    };
    try {
      final response = await client
          .post(
            Uri.parse('$normalizedBase/rpc'),
            headers: const {
              'accept': 'application/json',
              'content-type': 'application/json',
            },
            body: jsonEncode(request),
          )
          .timeout(timeout);
      if (response.statusCode != 200) {
        throw http.ClientException(
          'diagnostics upload failed',
          response.request?.url,
        );
      }
      final body = decodeJsonWithoutDuplicateKeys(response.body);
      final result = body is Map ? body['result'] : null;
      if (!isBoundJsonRpcResponse(request, body) ||
          body is! Map ||
          body.containsKey('error') ||
          result is! Map ||
          result.length != 2 ||
          !result.containsKey('accepted') ||
          !result.containsKey('rawEventsStored') ||
          result['accepted'] != true ||
          result['rawEventsStored'] != false) {
        throw const FormatException('invalid diagnostics acknowledgement');
      }
      try {
        await _receipts.writeDigest(digest);
      } on Object {
        // The server accepted the report. Do not turn that truth into a UI
        // failure solely because local duplicate suppression could not save.
      }
      return DiagnosticTelemetryUploadResult.sent;
    } finally {
      if (ownedClient) client.close();
    }
  }
}
