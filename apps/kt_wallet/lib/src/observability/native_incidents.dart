import 'package:flutter/services.dart';

enum NativeIncidentKind { fatal, anr }

class NativeIncident {
  const NativeIncident({required this.id, required this.kind});

  final int id;
  final NativeIncidentKind kind;
}

class NativeIncidentPayloadException implements Exception {
  const NativeIncidentPayloadException();

  @override
  String toString() => 'NativeIncidentPayloadException';
}

abstract interface class NativeIncidentBridge {
  Future<List<NativeIncident>> pending();
  Future<void> acknowledge(int throughId);
}

/// Reads a bounded, privacy-minimal native incident queue.
///
/// The platform payload contains only a monotonic integer and one of two fixed
/// kind strings. Stack traces, exception names/messages, timestamps, thread
/// names and wallet state are rejected by the exact schema parser.
class MethodChannelNativeIncidentBridge implements NativeIncidentBridge {
  const MethodChannelNativeIncidentBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('kt/native_observability');

  static const schemaVersion = 1;
  static const maxPendingIncidents = 32;

  final MethodChannel _channel;

  @override
  Future<List<NativeIncident>> pending() async {
    final raw = await _channel.invokeMethod<Object?>('pendingIncidents');
    if (raw is! Map<Object?, Object?> ||
        raw.length != 2 ||
        raw['schemaVersion'] != schemaVersion ||
        raw['events'] is! List<Object?>) {
      throw const NativeIncidentPayloadException();
    }
    final events = raw['events']! as List<Object?>;
    if (events.length > maxPendingIncidents) {
      throw const NativeIncidentPayloadException();
    }

    final parsed = <NativeIncident>[];
    var previousId = 0;
    for (final rawEvent in events) {
      if (rawEvent is! Map<Object?, Object?> ||
          rawEvent.length != 2 ||
          rawEvent['id'] is! int ||
          rawEvent['kind'] is! String) {
        throw const NativeIncidentPayloadException();
      }
      final id = rawEvent['id']! as int;
      final kind = switch (rawEvent['kind']! as String) {
        'fatal' => NativeIncidentKind.fatal,
        'anr' => NativeIncidentKind.anr,
        _ => throw const NativeIncidentPayloadException(),
      };
      if (id <= previousId) throw const NativeIncidentPayloadException();
      parsed.add(NativeIncident(id: id, kind: kind));
      previousId = id;
    }
    return parsed;
  }

  @override
  Future<void> acknowledge(int throughId) async {
    if (throughId <= 0) throw ArgumentError.value(throughId, 'throughId');
    await _channel.invokeMethod<void>('ackIncidents', {'throughId': throughId});
  }
}
