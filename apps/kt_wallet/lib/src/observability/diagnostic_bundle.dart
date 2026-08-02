import 'dart:convert';
import 'dart:io';

import 'package:chains/chains.dart' show Chain;
import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../app_info.dart';
import '../market/market_controller.dart';
import '../state/app_prefs.dart';
import '../state/networks.dart';
import 'experience_metrics.dart';

/// A support artifact whose schema is deliberately too narrow to carry wallet
/// data.
///
/// This is an allowlist, not a best-effort redactor. Unknown keys, unexpected
/// strings and oversized output are rejected before a file can be written.
class DiagnosticBundle {
  DiagnosticBundle._({required this.json, required this.generatedAtUtc});

  static const schemaVersion = 1;
  static const maxUtf8Bytes = 64 * 1024;

  final String json;
  final DateTime generatedAtUtc;

  factory DiagnosticBundle.checked(Map<String, Object?> body) {
    _DiagnosticSchema.validate(body);
    final encoded = const JsonEncoder.withIndent('  ').convert(body);
    if (utf8.encode(encoded).length > maxUtf8Bytes) {
      throw const DiagnosticBundleValidationException(
        'diagnostic bundle exceeds its size limit',
      );
    }
    final generatedAt = DateTime.parse(body['generatedAtUtc']! as String);
    return DiagnosticBundle._(json: encoded, generatedAtUtc: generatedAt);
  }
}

class DiagnosticBundleValidationException implements Exception {
  const DiagnosticBundleValidationException(this.message);

  final String message;

  @override
  String toString() => 'DiagnosticBundleValidationException: $message';
}

enum DiagnosticBuildMode { debug, profile, release }

/// Builds a privacy-minimal diagnostic snapshot from already-redacted state.
class DiagnosticBundleBuilder {
  const DiagnosticBundleBuilder();

  static const _allowedMetricNames = ExperienceMetricNames.all;

  DiagnosticBundle build({
    DateTime? generatedAt,
    String localeCode = 'en',
    TargetPlatform? platform,
    DiagnosticBuildMode? buildMode,
    NetworkController? networks,
    AppPrefsController? prefs,
    MarketController? market,
    Iterable<ExperienceMetric>? metrics,
  }) {
    final utc = (generatedAt ?? DateTime.now()).toUtc();
    final roundedUtc = DateTime.utc(
      utc.year,
      utc.month,
      utc.day,
      utc.hour,
      utc.minute,
    );
    final effectivePlatform = platform ?? defaultTargetPlatform;
    final effectiveMode = buildMode ?? _currentBuildMode;

    final activeNetworks = <Map<String, Object?>>[];
    if (networks != null) {
      for (final chain in Chain.values) {
        final active = networks.activeFor(chain);
        activeNetworks.add({
          'chain': chain.name,
          'profile': active.builtin ? active.id : 'custom',
          'testnet': active.isTestnet,
          'endpointMode': _endpointMode(chain, active.builtin, prefs),
        });
      }
    }

    final grouped = <String, List<ExperienceMetric>>{};
    for (final metric in metrics ?? ExperienceMetrics.instance.recent) {
      if (!_allowedMetricNames.contains(metric.name)) continue;
      (grouped[metric.name] ??= []).add(metric);
    }
    final performance = <Map<String, Object?>>[];
    for (final name in grouped.keys.toList()..sort()) {
      final samples = grouped[name]!;
      final durations =
          samples
              .map(
                (sample) => sample.duration.inMilliseconds.clamp(
                  0,
                  ExperienceMetrics.maxDurationMs,
                ),
              )
              .toList()
            ..sort();
      final successCount = samples.where((sample) => sample.success).length;
      performance.add({
        'name': name,
        'count': samples.length,
        'successCount': successCount,
        'failureCount': samples.length - successCount,
        'p50Ms': _percentile(durations, 0.50),
        'p95Ms': _percentile(durations, 0.95),
      });
    }

    return DiagnosticBundle.checked({
      'schemaVersion': DiagnosticBundle.schemaVersion,
      'generatedAtUtc': roundedUtc.toIso8601String(),
      'app': {'name': 'KT Wallet', 'version': AppInfo.version},
      'runtime': {
        'platform': effectivePlatform.name,
        'locale': _safeLocale(localeCode),
        'buildMode': effectiveMode.name,
      },
      'networkConfiguration': {
        'environment': networks?.environment.name ?? 'unknown',
        'gatewayMode': _gatewayMode(prefs),
        'active': activeNetworks,
      },
      'serviceState': {
        'market': _marketState(market),
        'lastMarketUpdateAge': _ageBucket(roundedUtc, market?.lastUpdatedAt),
      },
      'performance': performance,
      'redaction': {
        'walletData': 'omitted',
        'financialData': 'omitted',
        'transactionData': 'omitted',
        'cryptographicMaterial': 'omitted',
        'endpointLocations': 'omitted',
      },
    });
  }

  static DiagnosticBuildMode get _currentBuildMode {
    if (kReleaseMode) return DiagnosticBuildMode.release;
    if (kProfileMode) return DiagnosticBuildMode.profile;
    return DiagnosticBuildMode.debug;
  }

  static String _safeLocale(String locale) {
    final language = locale.split(RegExp('[-_]')).first.toLowerCase();
    return RegExp(r'^[a-z]{2,3}$').hasMatch(language) ? language : 'unknown';
  }

  static String _gatewayMode(AppPrefsController? prefs) {
    if (prefs == null) return 'unavailable';
    final configured = prefs.gatewayUrl;
    if (configured == null) return 'direct';
    return configured == AppPrefsController.defaultGatewayUrl
        ? 'default'
        : 'override';
  }

  static String _endpointMode(
    Chain chain,
    bool builtin,
    AppPrefsController? prefs,
  ) {
    if (prefs?.rpcOverride(_coinForChain(chain)) != null) {
      return 'preference-override';
    }
    return builtin ? 'network-profile' : 'custom-network';
  }

  static Coin _coinForChain(Chain chain) => switch (chain) {
    Chain.ethereum => Coin.eth,
    Chain.polygon => Coin.polygon,
    Chain.base => Coin.base,
    Chain.arbitrum => Coin.arbitrum,
    Chain.avalanche => Coin.avalanche,
    Chain.bnb => Coin.bnb,
    Chain.tron => Coin.tron,
    Chain.solana => Coin.solana,
  };

  static String _marketState(MarketController? market) {
    if (market == null) return 'not-mounted';
    if (market.isRefreshing) return 'refreshing';
    if (!market.hasRefreshed) return 'not-refreshed';
    if (market.showingCachedData) return 'cached';
    if (market.isOffline) return 'offline';
    if (market.hasLiveBalances) return 'live';
    return 'unavailable';
  }

  static String _ageBucket(DateTime now, DateTime? value) {
    if (value == null) return 'never';
    final age = now.difference(value.toUtc());
    if (age.isNegative) return 'clock-skew';
    if (age < const Duration(minutes: 1)) return 'under-1m';
    if (age < const Duration(minutes: 5)) return '1m-5m';
    if (age < const Duration(minutes: 30)) return '5m-30m';
    if (age < const Duration(hours: 6)) return '30m-6h';
    return 'over-6h';
  }

  static int _percentile(List<int> sorted, double percentile) {
    if (sorted.isEmpty) return 0;
    final index = ((sorted.length - 1) * percentile).round();
    return sorted[index];
  }
}

/// Stores the bundle in the app's temporary directory. The caller removes it
/// after the system share sheet returns.
abstract class DiagnosticBundleFileStore {
  static DiagnosticBundleFileStore instance =
      const PlatformDiagnosticBundleFileStore();

  Future<String> write(DiagnosticBundle bundle);
  Future<void> remove(String filePath);
}

class PlatformDiagnosticBundleFileStore implements DiagnosticBundleFileStore {
  const PlatformDiagnosticBundleFileStore();

  @override
  Future<String> write(DiagnosticBundle bundle) async {
    final directory = await getTemporaryDirectory();
    final fileName =
        'kt-wallet-diagnostics-${_fileStamp(bundle.generatedAtUtc)}.json';
    final file = File(path.join(directory.path, fileName));
    await file.writeAsString(bundle.json, flush: true);
    return file.path;
  }

  @override
  Future<void> remove(String filePath) async {
    final file = File(filePath);
    if (!path.basename(file.path).startsWith('kt-wallet-diagnostics-')) return;
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Best-effort cleanup: the OS may already have moved the shared file.
    }
  }

  static String _fileStamp(DateTime utc) =>
      '${utc.year.toString().padLeft(4, '0')}'
      '${utc.month.toString().padLeft(2, '0')}'
      '${utc.day.toString().padLeft(2, '0')}-'
      '${utc.hour.toString().padLeft(2, '0')}'
      '${utc.minute.toString().padLeft(2, '0')}';
}

class FakeDiagnosticBundleFileStore implements DiagnosticBundleFileStore {
  String filePath = '/tmp/kt-wallet-diagnostics-test.json';
  String? writtenJson;
  final List<String> removed = [];

  @override
  Future<String> write(DiagnosticBundle bundle) async {
    writtenJson = bundle.json;
    return filePath;
  }

  @override
  Future<void> remove(String filePath) async {
    removed.add(filePath);
  }
}

abstract final class _DiagnosticSchema {
  static const _allowedKeys = <String, Set<String>>{
    '': {
      'schemaVersion',
      'generatedAtUtc',
      'app',
      'runtime',
      'networkConfiguration',
      'serviceState',
      'performance',
      'redaction',
    },
    'app': {'name', 'version'},
    'runtime': {'platform', 'locale', 'buildMode'},
    'networkConfiguration': {'environment', 'gatewayMode', 'active'},
    'networkConfiguration.active[]': {
      'chain',
      'profile',
      'testnet',
      'endpointMode',
    },
    'serviceState': {'market', 'lastMarketUpdateAge'},
    'performance[]': {
      'name',
      'count',
      'successCount',
      'failureCount',
      'p50Ms',
      'p95Ms',
    },
    'redaction': {
      'walletData',
      'financialData',
      'transactionData',
      'cryptographicMaterial',
      'endpointLocations',
    },
  };

  static void validate(Map<String, Object?> body) {
    _validateMap(body, '');
    _expect(
      body['schemaVersion'] == DiagnosticBundle.schemaVersion,
      'schemaVersion',
    );

    final generatedAt = body['generatedAtUtc'];
    _expect(generatedAt is String, 'generatedAtUtc');
    final parsed = DateTime.tryParse(generatedAt! as String);
    _expect(
      parsed != null && parsed.isUtc && parsed.second == 0,
      'generatedAtUtc',
    );

    final app = body['app']! as Map<String, Object?>;
    _expect(app['name'] == 'KT Wallet', 'app.name');
    _expect(
      app['version'] is String &&
          RegExp(r'^\d+\.\d+\.\d+$').hasMatch(app['version']! as String),
      'app.version',
    );

    final runtime = body['runtime']! as Map<String, Object?>;
    _expect(
      TargetPlatform.values
          .map((value) => value.name)
          .contains(runtime['platform']),
      'runtime.platform',
    );
    _expect(
      runtime['locale'] == 'unknown' ||
          runtime['locale'] is String &&
              RegExp(r'^[a-z]{2,3}$').hasMatch(runtime['locale']! as String),
      'runtime.locale',
    );
    _expect(
      DiagnosticBuildMode.values
          .map((value) => value.name)
          .contains(runtime['buildMode']),
      'runtime.buildMode',
    );

    final network = body['networkConfiguration']! as Map<String, Object?>;
    _expect(
      const {'mainnet', 'testnet', 'unknown'}.contains(network['environment']),
      'networkConfiguration.environment',
    );
    _expect(
      const {
        'default',
        'override',
        'direct',
        'unavailable',
      }.contains(network['gatewayMode']),
      'networkConfiguration.gatewayMode',
    );
    final active = network['active']! as List<Object?>;
    _expect(
      active.length <= Chain.values.length,
      'networkConfiguration.active',
    );
    final seenChains = <String>{};
    for (final value in active) {
      final row = value! as Map<String, Object?>;
      final chain = row['chain'];
      _expect(
        chain is String &&
            Chain.values.map((value) => value.name).contains(chain),
        'networkConfiguration.active.chain',
      );
      _expect(
        seenChains.add(chain! as String),
        'networkConfiguration.active.chain',
      );
      final profile = row['profile'];
      _expect(
        profile == 'custom' ||
            profile is String && RegExp(r'^[a-z0-9-]{1,40}$').hasMatch(profile),
        'networkConfiguration.active.profile',
      );
      _expect(row['testnet'] is bool, 'networkConfiguration.active.testnet');
      _expect(
        const {
          'network-profile',
          'custom-network',
          'preference-override',
        }.contains(row['endpointMode']),
        'networkConfiguration.active.endpointMode',
      );
    }

    final service = body['serviceState']! as Map<String, Object?>;
    _expect(
      const {
        'not-mounted',
        'refreshing',
        'not-refreshed',
        'cached',
        'offline',
        'live',
        'unavailable',
      }.contains(service['market']),
      'serviceState.market',
    );
    _expect(
      const {
        'never',
        'clock-skew',
        'under-1m',
        '1m-5m',
        '5m-30m',
        '30m-6h',
        'over-6h',
      }.contains(service['lastMarketUpdateAge']),
      'serviceState.lastMarketUpdateAge',
    );

    final performance = body['performance']! as List<Object?>;
    _expect(
      performance.length <= ExperienceMetricNames.all.length,
      'performance',
    );
    final seenMetrics = <String>{};
    for (final value in performance) {
      final row = value! as Map<String, Object?>;
      final name = row['name'];
      _expect(
        name is String &&
            DiagnosticBundleBuilder._allowedMetricNames.contains(name),
        'performance.name',
      );
      _expect(seenMetrics.add(name! as String), 'performance.name');
      for (final key in const ['count', 'successCount', 'failureCount']) {
        final number = row[key];
        _expect(
          number is int && number >= 0 && number <= 100,
          'performance.$key',
        );
      }
      for (final key in const ['p50Ms', 'p95Ms']) {
        final number = row[key];
        _expect(
          number is int &&
              number >= 0 &&
              number <= ExperienceMetrics.maxDurationMs,
          'performance.$key',
        );
      }
      _expect(
        (row['successCount'] as int) + (row['failureCount'] as int) ==
            row['count'],
        'performance.counts',
      );
    }

    final redaction = body['redaction']! as Map<String, Object?>;
    _expect(redaction.values.every((value) => value == 'omitted'), 'redaction');
  }

  static void _validateMap(Map<String, Object?> map, String path) {
    final allowed = _allowedKeys[path];
    _expect(allowed != null, path.isEmpty ? 'root' : path);
    _expect(map.keys.toSet().containsAll(allowed!), '$path missing keys');
    _expect(allowed.containsAll(map.keys), '$path unknown keys');
    for (final entry in map.entries) {
      final childPath = path.isEmpty ? entry.key : '$path.${entry.key}';
      final value = entry.value;
      if (value is Map) {
        _validateMap(value.cast<String, Object?>(), childPath);
      } else if (value is List) {
        for (final item in value) {
          _expect(item is Map, '$childPath[]');
          _validateMap((item! as Map).cast<String, Object?>(), '$childPath[]');
        }
      }
    }
  }

  static void _expect(bool condition, String field) {
    if (!condition) {
      throw DiagnosticBundleValidationException(
        'invalid or unexpected field: $field',
      );
    }
  }
}
