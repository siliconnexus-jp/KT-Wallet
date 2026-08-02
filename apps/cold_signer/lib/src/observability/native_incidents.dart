import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bounded local crash/hang counters for the standalone signer.
///
/// Native payloads are deliberately reduced to an ID and fixed kind before
/// crossing the channel. This layer stores only aggregate counts and a replay
/// watermark; it never receives diagnostics, stacks, timestamps or wallet data.
class ColdSignerNativeIncidents {
  ColdSignerNativeIncidents({
    MethodChannel? channel,
    Future<SharedPreferences> Function()? preferences,
  }) : _channel = channel ?? const MethodChannel('kt/native_observability'),
       _preferences = preferences ?? SharedPreferences.getInstance;

  static final instance = ColdSignerNativeIncidents();
  static const _storageKey = 'observability.nativeIncidents.v1';
  static const _maxEvents = 32;
  final MethodChannel _channel;
  final Future<SharedPreferences> Function() _preferences;

  Future<void> ingest() async {
    try {
      final raw = await _channel.invokeMethod<Object?>('pendingIncidents');
      final events = _parse(raw);
      if (events.isEmpty) return;
      final prefs = await _preferences();
      final state = _decodeState(prefs.getString(_storageKey));
      var highWatermark = state.highWatermark;
      var fatalCount = state.fatalCount;
      var anrCount = state.anrCount;
      for (final event in events) {
        if (event.id <= state.highWatermark) continue;
        highWatermark = event.id;
        if (event.kind == 'fatal') {
          fatalCount++;
        } else {
          anrCount++;
        }
      }
      final persisted = await prefs.setString(
        _storageKey,
        jsonEncode({
          'schemaVersion': 1,
          'highWatermark': highWatermark,
          'fatalCount': fatalCount,
          'anrCount': anrCount,
        }),
      );
      if (!persisted) return;
      await _channel.invokeMethod<void>('ackIncidents', {
        'throughId': events.last.id,
      });
    } on Object {
      // Observability must never prevent an offline signer from starting.
    }
  }

  List<_NativeIncident> _parse(Object? raw) {
    if (raw is! Map<Object?, Object?> ||
        raw.length != 2 ||
        raw['schemaVersion'] != 1 ||
        raw['events'] is! List<Object?>) {
      throw const FormatException('native incident schema');
    }
    final rows = raw['events']! as List<Object?>;
    if (rows.length > _maxEvents) {
      throw const FormatException('native incident capacity');
    }
    final events = <_NativeIncident>[];
    var previousID = 0;
    for (final row in rows) {
      if (row is! Map<Object?, Object?> ||
          row.length != 2 ||
          row['id'] is! int ||
          row['kind'] is! String) {
        throw const FormatException('native incident event');
      }
      final id = row['id']! as int;
      final kind = row['kind']! as String;
      if (id <= previousID || (kind != 'fatal' && kind != 'anr')) {
        throw const FormatException('native incident value');
      }
      events.add(_NativeIncident(id, kind));
      previousID = id;
    }
    return events;
  }

  _IncidentState _decodeState(String? encoded) {
    if (encoded == null) return const _IncidentState();
    try {
      final raw = jsonDecode(encoded);
      if (raw is! Map<String, dynamic> ||
          raw.length != 4 ||
          raw['schemaVersion'] != 1 ||
          raw['highWatermark'] is! int ||
          raw['fatalCount'] is! int ||
          raw['anrCount'] is! int) {
        return const _IncidentState();
      }
      final state = _IncidentState(
        highWatermark: raw['highWatermark']! as int,
        fatalCount: raw['fatalCount']! as int,
        anrCount: raw['anrCount']! as int,
      );
      if (state.highWatermark < 0 ||
          state.fatalCount < 0 ||
          state.anrCount < 0) {
        return const _IncidentState();
      }
      return state;
    } on FormatException {
      return const _IncidentState();
    }
  }
}

class _NativeIncident {
  const _NativeIncident(this.id, this.kind);
  final int id;
  final String kind;
}

class _IncidentState {
  const _IncidentState({
    this.highWatermark = 0,
    this.fatalCount = 0,
    this.anrCount = 0,
  });
  final int highWatermark;
  final int fatalCount;
  final int anrCount;
}
