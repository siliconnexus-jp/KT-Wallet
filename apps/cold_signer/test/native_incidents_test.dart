import 'dart:convert';

import 'package:cold_signer/src/observability/native_incidents.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('kt/native-observability.signer-test');

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('persists only aggregate counters before acknowledging', () async {
    MethodCall? acknowledgement;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'ackIncidents') {
            acknowledgement = call;
            return null;
          }
          return {
            'schemaVersion': 1,
            'events': [
              {'id': 1, 'kind': 'fatal'},
              {'id': 2, 'kind': 'anr'},
            ],
          };
        });

    await ColdSignerNativeIncidents(channel: channel).ingest();
    final prefs = await SharedPreferences.getInstance();
    final stored =
        jsonDecode(prefs.getString('observability.nativeIncidents.v1')!)
            as Map<String, dynamic>;
    expect(stored, {
      'schemaVersion': 1,
      'highWatermark': 2,
      'fatalCount': 1,
      'anrCount': 1,
    });
    expect(acknowledgement?.arguments, {'throughId': 2});
  });

  test('replayed native events do not increment counters twice', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => call.method == 'pendingIncidents'
              ? {
                  'schemaVersion': 1,
                  'events': [
                    {'id': 4, 'kind': 'fatal'},
                  ],
                }
              : null,
        );
    final incidents = ColdSignerNativeIncidents(channel: channel);
    await incidents.ingest();
    await incidents.ingest();

    final prefs = await SharedPreferences.getInstance();
    final stored =
        jsonDecode(prefs.getString('observability.nativeIncidents.v1')!)
            as Map<String, dynamic>;
    expect(stored['fatalCount'], 1);
  });

  test('payloads containing diagnostic details are rejected whole', () async {
    var acknowledged = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'ackIncidents') acknowledged = true;
          return {
            'schemaVersion': 1,
            'events': [
              {'id': 1, 'kind': 'fatal', 'stack': 'private'},
            ],
          };
        });

    await ColdSignerNativeIncidents(channel: channel).ingest();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('observability.nativeIncidents.v1'), isNull);
    expect(acknowledged, isFalse);
  });
}
