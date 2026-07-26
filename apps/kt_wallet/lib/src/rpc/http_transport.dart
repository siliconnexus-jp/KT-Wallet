import 'dart:convert';

import 'package:chains/rpc.dart';
import 'package:http/http.dart' as http;

const _rpcFallbacks = <String, List<String>>{
  'https://ethereum-rpc.publicnode.com': [
    'https://cloudflare-eth.com',
    'https://eth.llamarpc.com',
  ],
  'https://ethereum-sepolia-rpc.publicnode.com': [
    'https://rpc.sepolia.org',
    'https://1rpc.io/sepolia',
  ],
  'https://polygon-bor-rpc.publicnode.com': [
    'https://polygon-rpc.com',
    'https://polygon.llamarpc.com',
  ],
  'https://polygon-amoy-bor-rpc.publicnode.com': [
    'https://rpc-amoy.polygon.technology',
  ],
  'https://mainnet.base.org': [
    'https://base-rpc.publicnode.com',
    'https://base.llamarpc.com',
  ],
  'https://sepolia.base.org': ['https://base-sepolia-rpc.publicnode.com'],
  'https://arb1.arbitrum.io/rpc': [
    'https://arbitrum-one-rpc.publicnode.com',
    'https://arbitrum.llamarpc.com',
  ],
  'https://sepolia-rollup.arbitrum.io/rpc': [
    'https://arbitrum-sepolia-rpc.publicnode.com',
  ],
  'https://api.avax.network/ext/bc/C/rpc': [
    'https://avalanche-c-chain-rpc.publicnode.com',
  ],
  'https://api.avax-test.network/ext/bc/C/rpc': [
    'https://avalanche-fuji-c-chain-rpc.publicnode.com',
  ],
  'https://api.mainnet-beta.solana.com': ['https://solana-rpc.publicnode.com'],
  'https://api.devnet.solana.com': ['https://solana-devnet-rpc.publicnode.com'],
};

const _restFallbacks = <String, List<String>>{
  'https://api.trongrid.io': ['https://api.tronstack.io'],
  'https://nile.trongrid.io': ['https://nile.tronstack.io'],
};

/// HTTP-backed JSON-RPC transport (the online app's concrete implementation of
/// the injectable transport in `chains/rpc`). Lives in kt_wallet — never in the
/// offline signer, which has no network capability.
class HttpJsonRpcTransport implements JsonRpcTransport {
  HttpJsonRpcTransport({
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();
  final http.Client _client;
  final Duration timeout;

  @override
  Future<Object?> post(String url, Object body) async {
    Object? lastError;
    for (final candidate in [url, ...?_rpcFallbacks[url]]) {
      try {
        final resp = await _client
            .post(
              Uri.parse(candidate),
              headers: const {'content-type': 'application/json'},
              body: jsonEncode(body),
            )
            .timeout(timeout);
        if (resp.statusCode != 200) {
          throw RpcException('HTTP ${resp.statusCode}', code: resp.statusCode);
        }
        final decoded = jsonDecode(resp.body);
        if (_retryableRpcError(decoded) && candidate != _last(url)) {
          continue;
        }
        return decoded;
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError ?? RpcException('all RPC endpoints failed');
  }

  String _last(String primary) =>
      (_rpcFallbacks[primary]?.lastOrNull ?? primary);

  void close() => _client.close();
}

/// HTTP-backed REST transport (TronGrid).
class HttpRestTransport implements RestTransport {
  HttpRestTransport({
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();
  final http.Client _client;
  final Duration timeout;

  @override
  Future<Object?> getJson(String url) async {
    return _restRequest(url, (candidate) => _client.get(Uri.parse(candidate)));
  }

  @override
  Future<Object?> postJson(String url, Object body) async {
    return _restRequest(
      url,
      (candidate) => _client.post(
        Uri.parse(candidate),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode(body),
      ),
    );
  }

  Future<Object?> _restRequest(
    String url,
    Future<http.Response> Function(String candidate) request,
  ) async {
    final candidates = <String>[url];
    for (final entry in _restFallbacks.entries) {
      if (url.startsWith(entry.key)) {
        candidates.addAll([
          for (final fallback in entry.value)
            url.replaceFirst(entry.key, fallback),
        ]);
        break;
      }
    }
    Object? lastError;
    for (final candidate in candidates) {
      try {
        final response = await request(candidate).timeout(timeout);
        if (response.statusCode != 200) {
          throw RpcException(
            'HTTP ${response.statusCode}',
            code: response.statusCode,
          );
        }
        return jsonDecode(response.body);
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError ?? RpcException('all REST endpoints failed');
  }

  void close() => _client.close();
}

bool _retryableRpcError(Object? body) {
  if (body is! Map || body['error'] is! Map) return false;
  final error = body['error'] as Map;
  final code = error['code'];
  final message = '${error['message'] ?? ''}'.toLowerCase();
  return code == 429 ||
      code == -32005 ||
      message.contains('rate limit') ||
      message.contains('too many requests');
}
