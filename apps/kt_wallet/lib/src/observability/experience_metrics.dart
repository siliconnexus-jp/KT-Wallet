import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'native_incidents.dart';

abstract final class ExperienceMetricNames {
  static const appStartup = 'app.startup';
  static const appFlutterError = 'app.flutterError';
  static const appPlatformError = 'app.platformError';
  static const appNativeFatal = 'app.nativeFatal';
  static const appNativeAnr = 'app.nativeAnr';
  static const marketRefresh = 'market.refresh';
  static const historyRefresh = 'history.refresh';
  static const historyLoadMore = 'history.loadMore';
  static const transactionPrepare = 'transaction.prepare';
  static const transactionSign = 'transaction.sign';
  static const transactionBroadcast = 'transaction.broadcast';
  static const transactionFinality = 'transaction.finality';

  static const all = <String>{
    appStartup,
    appFlutterError,
    appPlatformError,
    appNativeFatal,
    appNativeAnr,
    marketRefresh,
    historyRefresh,
    historyLoadMore,
    transactionPrepare,
    transactionSign,
    transactionBroadcast,
    transactionFinality,
  };
}

/// Privacy-preserving, in-process performance samples for critical UX paths.
///
/// No wallet address, balance or transaction data is recorded. DevTools sees
/// the timeline event and integration tests/report tooling can inspect the
/// bounded recent list without adding a third-party analytics SDK.
class ExperienceMetric {
  const ExperienceMetric({
    required this.name,
    required this.duration,
    required this.success,
    required this.recordedAt,
  });

  final String name;
  final Duration duration;
  final bool success;
  final DateTime recordedAt;
}

/// Anonymous finality sample restored from the wallet database.
///
/// The database row intentionally has no transaction identity or timestamp;
/// this DTO keeps that boundary explicit when the in-memory diagnostic ring
/// is refreshed.
class DurableTransactionFinalityMetric {
  const DurableTransactionFinalityMetric({
    required this.duration,
    required this.success,
  });

  final Duration duration;
  final bool success;
}

class ExperienceMetrics {
  ExperienceMetrics._();

  @visibleForTesting
  ExperienceMetrics.forTesting(ExperienceMetricsPersistence persistence)
    : _persistence = persistence;

  static final ExperienceMetrics instance = ExperienceMetrics._();
  static const _capacity = 100;
  static const _persistenceSchemaVersion = 3;
  static const maxDurationMs = 6 * 60 * 60 * 1000;
  final ListQueue<ExperienceMetric> _recent = ListQueue(_capacity);
  final ListQueue<ExperienceMetric> _durableFinality = ListQueue(_capacity);
  bool _errorObserversInstalled = false;
  ExperienceMetricsPersistence? _persistence;
  Future<void>? _initializeFuture;
  Future<void> _writeChain = Future.value();
  bool _persistenceReady = false;
  int _nativeIncidentHighWatermark = 0;

  /// Returns both independently bounded pools. Durable finality must not evict
  /// startup, refresh, signing or broadcast evidence merely because a wallet
  /// has accumulated 100 completed transactions.
  List<ExperienceMetric> get recent =>
      List.unmodifiable([..._recent, ..._durableFinality]);

  /// Restores the privacy-minimal bounded sample list from the device.
  ///
  /// Persistence deliberately stores only allowlisted metric names, bounded
  /// durations and booleans. Error objects, messages, stack traces, wallet
  /// identifiers, transaction data and endpoint details never enter the
  /// payload. A corrupt or future-version payload is ignored fail-safe and
  /// must never prevent the wallet from starting.
  Future<void> initializePersistence({
    ExperienceMetricsPersistence? persistence,
  }) {
    return _initializeFuture ??= _initializePersistence(
      persistence ?? _persistence ?? const SharedPrefsExperienceMetricsStore(),
    );
  }

  Future<void> _initializePersistence(
    ExperienceMetricsPersistence persistence,
  ) async {
    _persistence = persistence;
    try {
      final encoded = await persistence.read();
      if (encoded != null && encoded.isNotEmpty) {
        final restored = _decode(encoded);
        if (restored != null) {
          // Error observers may already have produced a current-session
          // sample while SharedPreferences was opening. Preserve those newest
          // samples after the restored list instead of overwriting them.
          final currentSession = _recent.toList(growable: false);
          _recent.clear();
          for (final metric in [...restored.samples, ...currentSession]) {
            _append(metric);
          }
          if (restored.nativeIncidentHighWatermark >
              _nativeIncidentHighWatermark) {
            _nativeIncidentHighWatermark = restored.nativeIncidentHighWatermark;
          }
        }
      }
    } on Object {
      // Observability is never allowed to make wallet startup fail.
    } finally {
      // Do not write while the initial read is in flight: an early Flutter
      // error could otherwise replace last session's samples before they have
      // been merged. Persist the final merged snapshot once initialization is
      // complete.
      _persistenceReady = true;
      _schedulePersist();
    }
  }

  void record(String name, Duration duration, {required bool success}) {
    // Observability must never break a wallet operation. Unknown names are
    // silently discarded (and not printed) so a typo cannot fail a transfer,
    // while user-derived strings can never become metric identifiers.
    if (!ExperienceMetricNames.all.contains(name) ||
        name == ExperienceMetricNames.transactionFinality) {
      return;
    }
    _append(
      ExperienceMetric(
        name: name,
        duration: duration,
        success: success,
        recordedAt: DateTime.now(),
      ),
    );
    _schedulePersist();
    developer.Timeline.instantSync(
      'ktwallet.$name',
      arguments: {
        'durationMs': duration.inMicroseconds / 1000,
        'success': success,
      },
    );
    if (kDebugMode) {
      debugPrint(
        '[KT metrics] $name ${duration.inMilliseconds}ms '
        '${success ? 'ok' : 'failed'}',
      );
    }
  }

  void _append(ExperienceMetric metric) {
    if (_recent.length == _capacity) _recent.removeFirst();
    _recent.add(metric);
  }

  _DecodedExperienceMetrics? _decode(String encoded) {
    final Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic> ||
        !const {
          1,
          2,
          _persistenceSchemaVersion,
        }.contains(decoded['schemaVersion']) ||
        decoded['samples'] is! List<Object?>) {
      return null;
    }
    final schemaVersion = decoded['schemaVersion']! as int;
    final nativeWatermark = schemaVersion == 1
        ? 0
        : decoded['nativeIncidentHighWatermark'];
    if (nativeWatermark is! int || nativeWatermark < 0) return null;

    final samples = <ExperienceMetric>[];
    for (final raw in decoded['samples']! as List<Object?>) {
      if (raw is! List<Object?> || raw.length != 3) return null;
      final name = raw[0];
      final durationMs = raw[1];
      final success = raw[2];
      if (name is! String ||
          !ExperienceMetricNames.all.contains(name) ||
          durationMs is! int ||
          durationMs < 0 ||
          durationMs > maxDurationMs ||
          success is! bool) {
        return null;
      }
      // Schema 3 moved finality to the Drift transaction that owns the status
      // transition. Seeing it here means the payload does not obey the new
      // single-source contract, so reject the unit rather than dual-count it.
      if (schemaVersion == _persistenceSchemaVersion &&
          name == ExperienceMetricNames.transactionFinality) {
        return null;
      }
      samples.add(
        ExperienceMetric(
          name: name,
          duration: Duration(milliseconds: durationMs),
          success: success,
          // Exact event time is intentionally not persisted. Diagnostics only
          // aggregate counts and percentiles, which reduces identifying data.
          recordedAt: DateTime.now(),
        ),
      );
    }
    final bounded = samples.length <= _capacity
        ? samples
        : samples.sublist(samples.length - _capacity);
    return _DecodedExperienceMetrics(
      samples: bounded,
      nativeIncidentHighWatermark: nativeWatermark,
    );
  }

  String _encode() => jsonEncode({
    'schemaVersion': _persistenceSchemaVersion,
    'nativeIncidentHighWatermark': _nativeIncidentHighWatermark,
    'samples': [
      for (final metric in _recent)
        if (metric.name != ExperienceMetricNames.transactionFinality)
          [
            metric.name,
            metric.duration.inMilliseconds.clamp(0, maxDurationMs),
            metric.success,
          ],
    ],
  });

  /// Replaces every in-memory finality sample with the crash-safe SQLite ring.
  ///
  /// These samples remain visible to local diagnostics and the explicitly
  /// consented aggregate report, but [_encode] deliberately excludes them:
  /// persisting the same event in SharedPreferences would reintroduce a
  /// cross-store crash/duplication window.
  void replaceDurableTransactionFinality(
    Iterable<DurableTransactionFinalityMetric> samples,
  ) {
    // Schema 1/2 may have restored finality into the legacy generic ring.
    // Remove those copies exactly once before installing SQLite's authority.
    final retained = _recent
        .where(
          (metric) => metric.name != ExperienceMetricNames.transactionFinality,
        )
        .toList(growable: false);
    _recent
      ..clear()
      ..addAll(retained);
    _durableFinality.clear();
    for (final sample in samples) {
      if (sample.duration.isNegative) continue;
      if (_durableFinality.length == _capacity) {
        _durableFinality.removeFirst();
      }
      _durableFinality.add(
        ExperienceMetric(
          name: ExperienceMetricNames.transactionFinality,
          duration: sample.duration,
          success: sample.success,
          recordedAt: DateTime.now(),
        ),
      );
    }
    _schedulePersist();
  }

  void _schedulePersist() {
    unawaited(_persistWithResult());
  }

  Future<bool> _persistWithResult() {
    final persistence = _persistence;
    if (persistence == null || !_persistenceReady) {
      return Future<bool>.value(false);
    }
    final encoded = _encode();
    final result = Completer<bool>();
    _writeChain = _writeChain.then((_) async {
      try {
        await persistence.write(encoded);
        result.complete(true);
      } on Object {
        // A full or unavailable preferences store must not affect the App.
        result.complete(false);
      }
    });
    return result.future;
  }

  /// Imports incidents from the previous native process without collecting
  /// diagnostic payload content.
  ///
  /// Samples and the native high-watermark are persisted together before the
  /// platform queue is acknowledged. If persistence fails, acknowledgement is
  /// withheld. If the process dies after persistence but before ack, the
  /// watermark deduplicates the replay on the next launch.
  Future<void> ingestNativeIncidents({NativeIncidentBridge? bridge}) async {
    await initializePersistence();
    final source = bridge ?? const MethodChannelNativeIncidentBridge();
    final List<NativeIncident> incidents;
    try {
      incidents = await source.pending();
    } on Object {
      return;
    }
    if (incidents.isEmpty) return;

    var newestId = _nativeIncidentHighWatermark;
    for (final incident in incidents) {
      if (incident.id <= _nativeIncidentHighWatermark) continue;
      _append(
        ExperienceMetric(
          name: switch (incident.kind) {
            NativeIncidentKind.fatal => ExperienceMetricNames.appNativeFatal,
            NativeIncidentKind.anr => ExperienceMetricNames.appNativeAnr,
          },
          duration: Duration.zero,
          success: false,
          recordedAt: DateTime.now(),
        ),
      );
      if (incident.id > newestId) newestId = incident.id;
    }
    _nativeIncidentHighWatermark = newestId;
    final persisted = await _persistWithResult();
    if (!persisted) return;
    try {
      await source.acknowledge(incidents.last.id);
    } on Object {
      // Persisted watermark makes a repeated native delivery harmless.
    }
  }

  /// Waits until all already-scheduled persistence writes have completed.
  /// Production does not need to call this; it exists for deterministic tests
  /// and orderly lifecycle handoff.
  Future<void> flush() => _writeChain;

  /// Measures an asynchronous operation without observing its arguments,
  /// result, exception text or stack trace.
  Future<T> measure<T>(
    String name,
    Future<T> Function() operation, {
    bool Function(T value)? isSuccess,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final value = await operation();
      record(name, stopwatch.elapsed, success: isSuccess?.call(value) ?? true);
      return value;
    } on Object {
      record(name, stopwatch.elapsed, success: false);
      rethrow;
    }
  }

  /// Counts framework and uncaught asynchronous error signals without
  /// retaining the error, message or stack. Existing handlers still receive
  /// the original details so installing observability never changes crash
  /// semantics.
  void installErrorObservers() {
    if (_errorObserversInstalled) return;
    _errorObserversInstalled = true;

    final previousFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      record(
        ExperienceMetricNames.appFlutterError,
        Duration.zero,
        success: false,
      );
      if (previousFlutterError != null) {
        previousFlutterError(details);
      } else {
        FlutterError.presentError(details);
      }
    };

    final previousPlatformError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      record(
        ExperienceMetricNames.appPlatformError,
        Duration.zero,
        success: false,
      );
      return previousPlatformError?.call(error, stack) ?? false;
    };
  }

  void clear() {
    _recent.clear();
    _durableFinality.clear();
    _nativeIncidentHighWatermark = 0;
    _schedulePersist();
  }
}

class _DecodedExperienceMetrics {
  const _DecodedExperienceMetrics({
    required this.samples,
    required this.nativeIncidentHighWatermark,
  });

  final List<ExperienceMetric> samples;
  final int nativeIncidentHighWatermark;
}

/// Narrow persistence contract so privacy and restart behavior can be tested
/// without exposing SharedPreferences throughout the observability layer.
abstract interface class ExperienceMetricsPersistence {
  Future<String?> read();
  Future<void> write(String encoded);
}

class SharedPrefsExperienceMetricsStore
    implements ExperienceMetricsPersistence {
  const SharedPrefsExperienceMetricsStore();

  static const _key = 'observability.experienceMetrics.v1';

  @override
  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  @override
  Future<void> write(String encoded) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, encoded);
  }
}
