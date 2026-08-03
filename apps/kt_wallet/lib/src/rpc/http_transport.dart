import 'dart:convert';
import 'dart:async';

import 'package:chains/rpc.dart';
import 'package:http/http.dart' as http;

import 'bounded_http_client.dart';

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
    'https://polygon-amoy.drpc.org',
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
  'https://bsc-dataseed.bnbchain.org': ['https://bsc-rpc.publicnode.com'],
  'https://bsc-testnet-dataseed.bnbchain.org': [
    'https://bsc-testnet.drpc.org',
    'https://data-seed-prebsc-1-s1.bnbchain.org:8545',
  ],
  'https://api.mainnet-beta.solana.com': ['https://solana-rpc.publicnode.com'],
};

const _evmNetworkIdentities = <String, int>{
  'https://ethereum-rpc.publicnode.com': 1,
  'https://ethereum-sepolia-rpc.publicnode.com': 11155111,
  'https://polygon-bor-rpc.publicnode.com': 137,
  'https://polygon-amoy-bor-rpc.publicnode.com': 80002,
  'https://mainnet.base.org': 8453,
  'https://sepolia.base.org': 84532,
  'https://arb1.arbitrum.io/rpc': 42161,
  'https://sepolia-rollup.arbitrum.io/rpc': 421614,
  'https://api.avax.network/ext/bc/C/rpc': 43114,
  'https://api.avax-test.network/ext/bc/C/rpc': 43113,
  'https://bsc-dataseed.bnbchain.org': 56,
  'https://bsc-testnet-dataseed.bnbchain.org': 97,
};

const _solanaNetworkIdentities = <String, String>{
  'https://api.mainnet-beta.solana.com':
      '5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d',
  'https://api.devnet.solana.com':
      'EtWTRABZaYq6iMfeYKouRu166VU2xqa1wcaWoxPkrZBG',
};

const _restFallbacks = <String, List<String>>{
  'https://api.trongrid.io': ['https://api.tronstack.io'],
  'https://nile.trongrid.io': ['https://nile.tronstack.io'],
};

const _tronNetworkIdentities = <String, String>{
  'https://api.trongrid.io':
      '00000000000000001ebf88508a03865c71d452e25f4d51194196a1d22b6653dc',
  'https://nile.trongrid.io':
      '0000000000000000d698d4192c56cb6be724a558448e2684802de4d6cd8690dc',
};

/// HTTP-backed JSON-RPC transport (the online app's concrete implementation of
/// the injectable transport in `chains/rpc`). Lives in kt_wallet — never in the
/// offline signer, which has no network capability.
class HttpJsonRpcTransport implements JsonRpcTransport {
  HttpJsonRpcTransport({
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = BoundedHttpClient(client ?? http.Client());
  final http.Client _client;
  final Duration timeout;
  final Map<String, Future<Object?>> _inFlightReads = {};

  @override
  Future<Object?> post(String url, Object body) async {
    final method = body is Map ? body['method'] : null;
    // Only an explicit observation/simulation allowlist may fail over. An
    // unknown future method might be a write; a timeout would not prove that
    // the first node rejected it, so default to one endpoint and one attempt.
    if (method is! String || !_deduplicatedReadMethods.contains(method)) {
      return _postOnce(url, body);
    }
    final key = '$url\n${jsonEncode(body)}';
    final existing = _inFlightReads[key];
    if (existing != null) return existing;
    final future = _postWithFailover(url, body);
    _inFlightReads[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlightReads[key], future)) {
        // The removed value is an already-running Future. Explicitly discard
        // it so the analyzer does not mistake cleanup for an un-awaited RPC.
        unawaited(_inFlightReads.remove(key));
      }
    }
  }

  Future<Object?> _postOnce(String url, Object body) async {
    try {
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
      return _validatedJsonRpcResponse(body, jsonDecode(resp.body));
    } on RpcException {
      rethrow;
    } on Object {
      // http.ClientException.toString() includes its URI. Custom RPC URLs
      // commonly carry provider keys in the path/query, so never propagate a
      // transport/parser exception across the service/UI boundary.
      throw RpcException('RPC transport unavailable');
    }
  }

  Future<Object?> _postWithFailover(String url, Object body) async {
    RpcException? lastError;
    for (final candidate in [url, ...?_rpcFallbacks[url]]) {
      try {
        // A fallback is a separate trust boundary. Verify its chain identity
        // before sending a wallet address, transaction simulation or other
        // request metadata to it. A wrong/misrouted endpoint is skipped and
        // never allowed to populate a balance/history snapshot.
        if (candidate != url &&
            !await _jsonRpcFallbackMatchesNetwork(url, candidate)) {
          lastError = RpcException('RPC network identity mismatch');
          continue;
        }
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
        final decoded = _validatedJsonRpcResponse(body, jsonDecode(resp.body));
        if (_retryableRpcError(decoded) && candidate != _last(url)) {
          continue;
        }
        return decoded;
      } on RpcException catch (error) {
        lastError = error;
      } on Object {
        lastError = RpcException('RPC transport unavailable');
      }
    }
    throw lastError ?? RpcException('all RPC endpoints failed');
  }

  Future<bool> _jsonRpcFallbackMatchesNetwork(
    String primary,
    String candidate,
  ) async {
    final evmChainId = _evmNetworkIdentities[primary];
    final solanaGenesis = _solanaNetworkIdentities[primary];
    if (evmChainId == null && solanaGenesis == null) return false;
    final method = evmChainId != null ? 'eth_chainId' : 'getGenesisHash';
    try {
      final body = <String, Object?>{
        'jsonrpc': '2.0',
        'id': 0,
        'method': method,
        'params': const <Object?>[],
      };
      final response = await _client
          .post(
            Uri.parse(candidate),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout);
      if (response.statusCode != 200) return false;
      final decoded = _validatedJsonRpcResponse(
        body,
        jsonDecode(response.body),
      );
      if (decoded is! Map || decoded.containsKey('error')) return false;
      final result = decoded['result'];
      if (evmChainId != null) {
        if (result is! String || !result.startsWith('0x')) return false;
        return int.tryParse(result.substring(2), radix: 16) == evmChainId;
      }
      return result == solanaGenesis;
    } on Object {
      return false;
    }
  }

  String _last(String primary) =>
      (_rpcFallbacks[primary]?.lastOrNull ?? primary);

  void close() => _client.close();
}

/// Safe to coalesce because these methods are observations/simulations. Send
/// methods are intentionally absent: one user action must always map to one
/// explicit broadcast attempt.
const _deduplicatedReadMethods = {
  'eth_chainId',
  'eth_getBalance',
  'eth_call',
  'eth_getTransactionCount',
  'eth_feeHistory',
  'eth_estimateGas',
  'eth_getTransactionReceipt',
  'eth_getTransactionByHash',
  'getBalance',
  'getTokenAccountsByOwner',
  'getLatestBlockhash',
  'getFeeForMessage',
  'simulateTransaction',
  'getSignatureStatuses',
  'getSignaturesForAddress',
  'getTransaction',
  'getBlockHeight',
  'getGenesisHash',
};

const _restReadPostPaths = {
  '/wallet/getblockbynum',
  '/wallet/gettransactioninfobyid',
  '/wallet/getnowblock',
  '/wallet/triggerconstantcontract',
  '/wallet/getaccountresource',
  '/wallet/getchainparameters',
};

/// HTTP-backed REST transport (TronGrid).
class HttpRestTransport implements RestTransport {
  HttpRestTransport({
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = BoundedHttpClient(client ?? http.Client());
  final http.Client _client;
  final Duration timeout;

  @override
  Future<Object?> getJson(String url) async {
    return _restRequest(
      url,
      (candidate) => _client.get(Uri.parse(candidate)),
      allowFailover: true,
    );
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
      // TronGrid reads happen to use POST. Fail over only the audited read
      // paths; broadcasts and unknown future endpoints are single-attempt.
      allowFailover: _restReadPostPaths.any(url.endsWith),
    );
  }

  Future<Object?> _restRequest(
    String url,
    Future<http.Response> Function(String candidate) request, {
    required bool allowFailover,
  }) async {
    final candidates = <String>[url];
    if (allowFailover) {
      for (final entry in _restFallbacks.entries) {
        if (url.startsWith(entry.key)) {
          candidates.addAll([
            for (final fallback in entry.value)
              url.replaceFirst(entry.key, fallback),
          ]);
          break;
        }
      }
    }
    RpcException? lastError;
    for (final candidate in candidates) {
      try {
        if (candidate != url &&
            !await _restFallbackMatchesNetwork(url, candidate)) {
          lastError = RpcException('REST network identity mismatch');
          continue;
        }
        final response = await request(candidate).timeout(timeout);
        if (response.statusCode != 200) {
          throw RpcException(
            'HTTP ${response.statusCode}',
            code: response.statusCode,
          );
        }
        return jsonDecode(response.body);
      } on RpcException catch (error) {
        lastError = error;
      } on Object {
        lastError = RpcException('REST transport unavailable');
      }
    }
    throw lastError ?? RpcException('all REST endpoints failed');
  }

  Future<bool> _restFallbackMatchesNetwork(
    String originalUrl,
    String candidateUrl,
  ) async {
    String? primary;
    for (final value in _restFallbacks.keys) {
      if (originalUrl.startsWith(value)) {
        primary = value;
        break;
      }
    }
    if (primary == null) return false;
    final expected = _tronNetworkIdentities[primary];
    if (expected == null) return false;
    String? fallbackBase;
    for (final value in _restFallbacks[primary]!) {
      if (candidateUrl.startsWith(value)) {
        fallbackBase = value;
        break;
      }
    }
    if (fallbackBase == null) return false;
    try {
      final response = await _client
          .post(
            Uri.parse('$fallbackBase/wallet/getblockbynum'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode(const {'num': 0}),
          )
          .timeout(timeout);
      if (response.statusCode != 200) return false;
      final decoded = jsonDecode(response.body);
      return decoded is Map && decoded['blockID'] == expected;
    } on Object {
      return false;
    }
  }

  void close() => _client.close();
}

/// Validates the correlation boundary required by JSON-RPC 2.0.
///
/// HTTP connection ordering is not transaction identity: a proxy, cache or
/// provider can return a stale envelope. Every response therefore has to echo
/// the request's exact scalar id and carry exactly one result/error member
/// before any balance, fee, status or broadcast result is trusted.
Object _validatedJsonRpcResponse(Object request, Object? response) {
  if (request is! Map ||
      request['jsonrpc'] != '2.0' ||
      !request.containsKey('id')) {
    throw RpcException('invalid JSON-RPC request');
  }
  final requestId = request['id'];
  if (requestId is! int && requestId is! String) {
    throw RpcException('invalid JSON-RPC request');
  }
  if (response is! Map ||
      response['jsonrpc'] != '2.0' ||
      !response.containsKey('id')) {
    throw RpcException('malformed JSON-RPC response');
  }
  final responseId = response['id'];
  final idMatches = switch (requestId) {
    int() => responseId is int && responseId == requestId,
    String() => responseId is String && responseId == requestId,
    _ => false,
  };
  if (!idMatches) {
    throw RpcException('malformed JSON-RPC response');
  }
  final hasResult = response.containsKey('result');
  final hasError = response.containsKey('error');
  if (hasResult == hasError || (hasError && response['error'] is! Map)) {
    throw RpcException('malformed JSON-RPC response');
  }
  return response;
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
