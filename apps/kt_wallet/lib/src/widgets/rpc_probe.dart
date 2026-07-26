import 'dart:convert';

import 'package:chains/chains.dart' show Chain;
import 'package:http/http.dart' as http;

/// Outcome of probing a candidate RPC endpoint before it is persisted as a
/// custom network.
sealed class RpcProbeResult {
  const RpcProbeResult();
}

/// The endpoint answered the family-appropriate liveness call (and, for EVM
/// families, reported exactly the chain id the user typed).
class RpcProbeOk extends RpcProbeResult {
  const RpcProbeOk();
}

/// EVM only: the node is alive but reports a different chain id than typed.
/// [actual] is the node's decimal chain id, surfaced verbatim in the form's
/// inline error so the user can correct either side.
class RpcProbeChainIdMismatch extends RpcProbeResult {
  const RpcProbeChainIdMismatch(this.actual);
  final int actual;
}

/// Transport failure, non-200, timeout, or a malformed/erroneous response.
class RpcProbeFailure extends RpcProbeResult {
  const RpcProbeFailure();
}

/// Liveness probe for a candidate network RPC, run before [addCustom] persists
/// anything — a network that never answered once would be a dead row forever.
///
/// Per family:
/// - EVM (ethereum/polygon): JSON-RPC `eth_chainId` must succeed AND the
///   decoded id must equal the typed one (wrong-chain signatures are invalid,
///   so a silent mismatch would brick every transfer on the new network).
/// - TRON: `GET {url}/wallet/getnowblock` must return 200 (TronGrid-style
///   REST, same shape the balance service uses).
/// - Solana: JSON-RPC `getHealth` must succeed with a non-error result.
///
/// The client is injectable so widget tests drive the probe with fakes;
/// production constructs its own and [close]s it after the call.
class RpcProbe {
  RpcProbe({http.Client? client, this.timeout = const Duration(seconds: 10)})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;

  /// Closes the internally-created client; a no-op for injected clients.
  void close() {
    if (_ownsClient) _client.close();
  }

  Future<RpcProbeResult> probe({
    required Chain chain,
    required String rpcUrl,
    int? expectedChainId,
  }) async {
    final url = rpcUrl.trim();
    try {
      switch (chain) {
        case Chain.ethereum:
        case Chain.polygon:
        case Chain.base:
        case Chain.arbitrum:
        case Chain.avalanche:
          final resp = await _jsonRpc(url, 'eth_chainId');
          if (resp.statusCode != 200) return const RpcProbeFailure();
          final decoded = jsonDecode(resp.body);
          final result = decoded is Map ? decoded['result'] : null;
          if (result is! String || !result.startsWith('0x')) {
            return const RpcProbeFailure();
          }
          final actual = int.tryParse(result.substring(2), radix: 16);
          if (actual == null) return const RpcProbeFailure();
          if (expectedChainId != null && actual != expectedChainId) {
            return RpcProbeChainIdMismatch(actual);
          }
          return const RpcProbeOk();
        case Chain.tron:
          var base = url;
          while (base.endsWith('/')) {
            base = base.substring(0, base.length - 1);
          }
          final resp = await _client
              .get(Uri.parse('$base/wallet/getnowblock'))
              .timeout(timeout);
          return resp.statusCode == 200
              ? const RpcProbeOk()
              : const RpcProbeFailure();
        case Chain.solana:
          final resp = await _jsonRpc(url, 'getHealth');
          if (resp.statusCode != 200) return const RpcProbeFailure();
          final decoded = jsonDecode(resp.body);
          return (decoded is Map &&
                  decoded['error'] == null &&
                  decoded['result'] != null)
              ? const RpcProbeOk()
              : const RpcProbeFailure();
      }
    } catch (_) {
      // Unreachable host, TLS/format errors, timeout: all one honest failure.
      return const RpcProbeFailure();
    }
  }

  Future<http.Response> _jsonRpc(String url, String method) => _client
      .post(
        Uri.parse(url),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': method,
          'params': [],
        }),
      )
      .timeout(timeout);
}
