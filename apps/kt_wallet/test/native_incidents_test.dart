import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/observability/native_incidents.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('kt/native_observability.test');
  const bridge = MethodChannelNativeIncidentBridge(channel: channel);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('accepts only the bounded privacy-minimal native schema', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'pendingIncidents');
          return {
            'schemaVersion': 1,
            'events': [
              {'id': 4, 'kind': 'fatal'},
              {'id': 7, 'kind': 'anr'},
            ],
          };
        });

    final incidents = await bridge.pending();
    expect(incidents.map((event) => event.id), [4, 7]);
    expect(incidents.map((event) => event.kind), [
      NativeIncidentKind.fatal,
      NativeIncidentKind.anr,
    ]);
  });

  test('rejects diagnostic content and non-monotonic identifiers', () async {
    for (final payload in <Object?>[
      {
        'schemaVersion': 1,
        'events': [
          {'id': 1, 'kind': 'fatal', 'stack': 'must-not-cross-bridge'},
        ],
      },
      {
        'schemaVersion': 1,
        'events': [
          {'id': 2, 'kind': 'fatal'},
          {'id': 2, 'kind': 'anr'},
        ],
      },
      {
        'schemaVersion': 1,
        'events': [
          {'id': 1, 'kind': 'exception-message'},
        ],
      },
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => payload);
      await expectLater(
        bridge.pending(),
        throwsA(isA<NativeIncidentPayloadException>()),
      );
    }
  });

  test('acknowledgement contains only the positive high watermark', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'ackIncidents');
          expect(call.arguments, {'throughId': 9});
          return null;
        });

    await bridge.acknowledge(9);
    await expectLater(bridge.acknowledge(0), throwsArgumentError);
  });
}
