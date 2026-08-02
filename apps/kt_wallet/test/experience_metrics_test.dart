import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/observability/experience_metrics.dart';
import 'package:kt_wallet/src/observability/native_incidents.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryMetricsStore implements ExperienceMetricsPersistence {
  String? encoded;

  @override
  Future<String?> read() async => encoded;

  @override
  Future<void> write(String encoded) async {
    this.encoded = encoded;
  }
}

void main() {
  setUp(() {
    ExperienceMetrics.instance.clear();
    SharedPreferences.setMockInitialValues({});
  });

  test('unknown metric names are discarded without breaking the caller', () {
    ExperienceMetrics.instance.record(
      'transaction.0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
      const Duration(milliseconds: 1),
      success: false,
    );
    expect(ExperienceMetrics.instance.recent, isEmpty);
  });

  test('measure records duration and outcome without error details', () async {
    final value = await ExperienceMetrics.instance.measure(
      ExperienceMetricNames.transactionPrepare,
      () async => 42,
    );
    expect(value, 42);

    await expectLater(
      ExperienceMetrics.instance.measure<void>(
        ExperienceMetricNames.transactionSign,
        () async => throw StateError('private provider detail'),
      ),
      throwsStateError,
    );

    final metrics = ExperienceMetrics.instance.recent;
    expect(metrics, hasLength(2));
    expect(metrics.first.name, ExperienceMetricNames.transactionPrepare);
    expect(metrics.first.success, isTrue);
    expect(metrics.last.name, ExperienceMetricNames.transactionSign);
    expect(metrics.last.success, isFalse);
    expect(
      metrics.map((metric) => metric.name).join(' '),
      isNot(contains('private provider detail')),
    );
  });

  test('the in-memory metric buffer stays bounded', () {
    for (var index = 0; index < 120; index++) {
      ExperienceMetrics.instance.record(
        ExperienceMetricNames.marketRefresh,
        Duration(milliseconds: index),
        success: true,
      );
    }

    final metrics = ExperienceMetrics.instance.recent;
    expect(metrics, hasLength(100));
    expect(metrics.first.duration, const Duration(milliseconds: 20));
    expect(metrics.last.duration, const Duration(milliseconds: 119));
  });

  test('privacy-minimal samples survive an app restart', () async {
    final store = _MemoryMetricsStore();
    final firstRun = ExperienceMetrics.forTesting(store);
    await firstRun.initializePersistence();
    firstRun.record(
      ExperienceMetricNames.appFlutterError,
      Duration.zero,
      success: false,
    );
    firstRun.record(
      ExperienceMetricNames.transactionBroadcast,
      const Duration(milliseconds: 81),
      success: true,
    );
    await firstRun.flush();

    expect(store.encoded, isNotNull);
    expect(store.encoded, isNot(contains('stack')));
    expect(store.encoded, isNot(contains('errorMessage')));

    final secondRun = ExperienceMetrics.forTesting(store);
    await secondRun.initializePersistence();
    expect(secondRun.recent.map((sample) => sample.name), [
      ExperienceMetricNames.appFlutterError,
      ExperienceMetricNames.transactionBroadcast,
    ]);
    expect(secondRun.recent.first.success, isFalse);
    expect(secondRun.recent.last.duration, const Duration(milliseconds: 81));
  });

  test(
    'unknown or malformed persisted fields are rejected as a unit',
    () async {
      final store = _MemoryMetricsStore()
        ..encoded = jsonEncode({
          'schemaVersion': 1,
          'samples': [
            [ExperienceMetricNames.marketRefresh, 12, true],
            ['wallet.0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed', 1, false],
          ],
        });
      final metrics = ExperienceMetrics.forTesting(store);
      await metrics.initializePersistence();

      expect(metrics.recent, isEmpty);
    },
  );

  test('persistence failures never break metric recording', () async {
    final metrics = ExperienceMetrics.forTesting(_ThrowingMetricsStore());
    await metrics.initializePersistence();
    metrics.record(
      ExperienceMetricNames.appPlatformError,
      Duration.zero,
      success: false,
    );
    await metrics.flush();

    expect(metrics.recent, hasLength(1));
  });

  test(
    'the production SharedPreferences store round-trips its payload',
    () async {
      const store = SharedPrefsExperienceMetricsStore();
      await store.write('{"schemaVersion":1,"samples":[]}');

      expect(await store.read(), '{"schemaVersion":1,"samples":[]}');
    },
  );

  test(
    'an error during restore is merged without losing either session',
    () async {
      final store = _DelayedReadMetricsStore(
        jsonEncode({
          'schemaVersion': 1,
          'samples': [
            [ExperienceMetricNames.marketRefresh, 12, true],
          ],
        }),
      );
      final metrics = ExperienceMetrics.forTesting(store);
      final initializing = metrics.initializePersistence();

      metrics.record(
        ExperienceMetricNames.appFlutterError,
        Duration.zero,
        success: false,
      );
      store.completeRead();
      await initializing;
      await metrics.flush();

      final restored = ExperienceMetrics.forTesting(store);
      await restored.initializePersistence();
      expect(restored.recent.map((sample) => sample.name), [
        ExperienceMetricNames.marketRefresh,
        ExperienceMetricNames.appFlutterError,
      ]);
    },
  );

  test('schema one is migrated to the privacy-minimal schema two', () async {
    final store = _MemoryMetricsStore()
      ..encoded = jsonEncode({
        'schemaVersion': 1,
        'samples': [
          [ExperienceMetricNames.marketRefresh, 12, true],
        ],
      });
    final metrics = ExperienceMetrics.forTesting(store);
    await metrics.initializePersistence();
    await metrics.flush();

    final migrated = jsonDecode(store.encoded!) as Map<String, dynamic>;
    expect(migrated['schemaVersion'], 2);
    expect(migrated['nativeIncidentHighWatermark'], 0);
  });

  test(
    'native incidents are persisted before the queue is acknowledged',
    () async {
      final store = _MemoryMetricsStore();
      final bridge = _FakeNativeIncidentBridge([
        const NativeIncident(id: 1, kind: NativeIncidentKind.fatal),
        const NativeIncident(id: 2, kind: NativeIncidentKind.anr),
      ]);
      final metrics = ExperienceMetrics.forTesting(store);
      await metrics.initializePersistence();
      await metrics.ingestNativeIncidents(bridge: bridge);

      expect(metrics.recent.map((sample) => sample.name), [
        ExperienceMetricNames.appNativeFatal,
        ExperienceMetricNames.appNativeAnr,
      ]);
      expect(bridge.acknowledgedThrough, 2);
      expect(store.encoded, isNot(contains('stack')));
      expect(store.encoded, isNot(contains('message')));

      // Simulates death after local persistence but before the native queue was
      // durably removed. The high watermark prevents double counting.
      final replayBridge = _FakeNativeIncidentBridge(bridge.events);
      final replay = ExperienceMetrics.forTesting(store);
      await replay.initializePersistence();
      await replay.ingestNativeIncidents(bridge: replayBridge);
      expect(replay.recent, hasLength(2));
      expect(replayBridge.acknowledgedThrough, 2);
    },
  );

  test('native queue is not acknowledged when persistence fails', () async {
    final bridge = _FakeNativeIncidentBridge([
      const NativeIncident(id: 1, kind: NativeIncidentKind.fatal),
    ]);
    final metrics = ExperienceMetrics.forTesting(_ThrowingMetricsStore());
    await metrics.initializePersistence();
    await metrics.ingestNativeIncidents(bridge: bridge);

    expect(metrics.recent.single.name, ExperienceMetricNames.appNativeFatal);
    expect(bridge.acknowledgedThrough, isNull);
  });
}

class _FakeNativeIncidentBridge implements NativeIncidentBridge {
  _FakeNativeIncidentBridge(this.events);

  final List<NativeIncident> events;
  int? acknowledgedThrough;

  @override
  Future<void> acknowledge(int throughId) async {
    acknowledgedThrough = throughId;
  }

  @override
  Future<List<NativeIncident>> pending() async => events;
}

class _ThrowingMetricsStore implements ExperienceMetricsPersistence {
  @override
  Future<String?> read() async => throw StateError('storage unavailable');

  @override
  Future<void> write(String encoded) async =>
      throw StateError('storage unavailable');
}

class _DelayedReadMetricsStore implements ExperienceMetricsPersistence {
  _DelayedReadMetricsStore(this.encoded);

  String? encoded;
  final Completer<String?> _read = Completer<String?>();

  void completeRead() => _read.complete(encoded);

  @override
  Future<String?> read() =>
      _read.isCompleted ? Future<String?>.value(encoded) : _read.future;

  @override
  Future<void> write(String encoded) async {
    this.encoded = encoded;
  }
}
