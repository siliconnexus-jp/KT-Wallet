import 'dart:convert';

import 'package:chains/rpc.dart';
import 'package:http/http.dart' as http;

/// HTTP-backed JSON-RPC transport (the online app's concrete implementation of
/// the injectable transport in `chains/rpc`). Lives in kt_wallet — never in the
/// offline signer, which has no network capability.
class HttpJsonRpcTransport implements JsonRpcTransport {
  HttpJsonRpcTransport({http.Client? client, this.timeout = const Duration(seconds: 10)})
      : _client = client ?? http.Client();
  final http.Client _client;
  final Duration timeout;

  @override
  Future<Object?> post(String url, Object body) async {
    final resp = await _client
        .post(
          Uri.parse(url),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(timeout);
    if (resp.statusCode != 200) {
      throw RpcException('HTTP ${resp.statusCode}', code: resp.statusCode);
    }
    return jsonDecode(resp.body);
  }

  void close() => _client.close();
}

/// HTTP-backed REST transport (TronGrid).
class HttpRestTransport implements RestTransport {
  HttpRestTransport({http.Client? client, this.timeout = const Duration(seconds: 10)})
      : _client = client ?? http.Client();
  final http.Client _client;
  final Duration timeout;

  @override
  Future<Object?> getJson(String url) async {
    final resp = await _client.get(Uri.parse(url)).timeout(timeout);
    if (resp.statusCode != 200) {
      throw RpcException('HTTP ${resp.statusCode}', code: resp.statusCode);
    }
    return jsonDecode(resp.body);
  }

  @override
  Future<Object?> postJson(String url, Object body) async {
    final resp = await _client
        .post(
          Uri.parse(url),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(timeout);
    if (resp.statusCode != 200) {
      throw RpcException('HTTP ${resp.statusCode}', code: resp.statusCode);
    }
    return jsonDecode(resp.body);
  }

  void close() => _client.close();
}
