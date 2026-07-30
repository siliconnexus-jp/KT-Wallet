import 'dart:collection';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

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

class ExperienceMetrics {
  ExperienceMetrics._();

  static final ExperienceMetrics instance = ExperienceMetrics._();
  static const _capacity = 100;
  final ListQueue<ExperienceMetric> _recent = ListQueue(_capacity);

  List<ExperienceMetric> get recent => List.unmodifiable(_recent);

  void record(String name, Duration duration, {required bool success}) {
    if (_recent.length == _capacity) _recent.removeFirst();
    _recent.add(
      ExperienceMetric(
        name: name,
        duration: duration,
        success: success,
        recordedAt: DateTime.now(),
      ),
    );
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

  void clear() => _recent.clear();
}
