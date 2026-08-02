import 'dart:async';

import 'package:http/http.dart' as http;

/// Hard ceiling applied to every response the online wallet buffers in memory.
/// The Gateway enforces the same 8 MiB upper boundary; direct RPC/explorer
/// fallbacks must not be allowed to bypass it.
const int walletHttpResponseLimitBytes = 8 * 1024 * 1024;

/// Fixed, privacy-safe failure. It deliberately carries neither endpoint nor
/// response content because both can contain provider credentials or node data.
final class HttpResponseTooLargeException implements Exception {
  const HttpResponseTooLargeException();

  @override
  String toString() => 'HTTP response exceeded the safe size limit';
}

/// Caps both declared and chunked/decompressed response bodies before
/// `package:http` turns them into an in-memory [http.Response].
final class BoundedHttpClient extends http.BaseClient {
  BoundedHttpClient(
    this._inner, {
    this.maxResponseBytes = walletHttpResponseLimitBytes,
  }) {
    if (maxResponseBytes <= 0) {
      throw ArgumentError.value(
        maxResponseBytes,
        'maxResponseBytes',
        'must be positive',
      );
    }
  }

  final http.Client _inner;
  final int maxResponseBytes;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    final declared = response.contentLength;
    if (declared != null && declared > maxResponseBytes) {
      final subscription = response.stream.listen(null);
      await subscription.cancel();
      throw const HttpResponseTooLargeException();
    }

    return http.StreamedResponse(
      _bounded(response.stream),
      response.statusCode,
      contentLength: declared,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  Stream<List<int>> _bounded(Stream<List<int>> source) async* {
    var received = 0;
    await for (final chunk in source) {
      received += chunk.length;
      if (received > maxResponseBytes) {
        throw const HttpResponseTooLargeException();
      }
      yield chunk;
    }
  }

  @override
  void close() => _inner.close();
}
