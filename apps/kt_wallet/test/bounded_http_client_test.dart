import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kt_wallet/src/rpc/bounded_http_client.dart';

void main() {
  test('rejects an oversized declared response before buffering it', () async {
    final inner = _StreamClient(
      (_) async => http.StreamedResponse(
        http.ByteStream.fromBytes(List<int>.filled(32, 1)),
        200,
        contentLength: 32,
      ),
    );
    final client = BoundedHttpClient(inner, maxResponseBytes: 16);

    await expectLater(
      client.get(Uri.parse('https://rpc.example/credential-secret')),
      throwsA(
        isA<HttpResponseTooLargeException>().having(
          (error) => error.toString(),
          'sanitized message',
          isNot(contains('credential-secret')),
        ),
      ),
    );
  });

  test(
    'rejects chunked responses as soon as the streamed limit is crossed',
    () async {
      final inner = _StreamClient(
        (_) async => http.StreamedResponse(
          http.ByteStream(
            Stream<List<int>>.fromIterable(const [
              [1, 2, 3],
              [4, 5, 6],
            ]),
          ),
          200,
        ),
      );
      final client = BoundedHttpClient(inner, maxResponseBytes: 5);

      await expectLater(
        client.get(Uri.parse('https://rpc.example')),
        throwsA(isA<HttpResponseTooLargeException>()),
      );
    },
  );

  test(
    'accepts a response exactly at the hard limit and forwards close',
    () async {
      final inner = _StreamClient(
        (_) async => http.StreamedResponse(
          http.ByteStream.fromBytes(const [1, 2, 3, 4]),
          200,
          contentLength: 4,
        ),
      );
      final client = BoundedHttpClient(inner, maxResponseBytes: 4);

      final response = await client.get(Uri.parse('https://rpc.example'));
      expect(response.bodyBytes, const [1, 2, 3, 4]);
      client.close();
      expect(inner.closed, isTrue);
    },
  );

  test(
    'every production-owned HTTP client is created behind the hard limit',
    () {
      final violations = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var index = 0; index < lines.length; index++) {
          final line = lines[index];
          if (!line.contains('http.Client()')) continue;
          if (!line.contains('BoundedHttpClient(')) {
            violations.add('${entity.path}:${index + 1}');
          }
        }
      }
      expect(violations, isEmpty);
    },
  );
}

class _StreamClient extends http.BaseClient {
  _StreamClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  handler;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);

  @override
  void close() {
    closed = true;
  }
}
