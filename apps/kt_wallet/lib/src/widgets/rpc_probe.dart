import 'dart:convert';

import 'package:chains/chains.dart' show Chain;
import 'package:http/http.dart' as http;

import '../rpc/bounded_http_client.dart';
import '../rpc/json_rpc_envelope.dart';

/// Outcome of probing a candidate RPC endpoint before it is persisted as a
/// custom network.
sealed class RpcProbeResult {
  const RpcProbeResult();
}

/// The endpoint answered the family-appropriate liveness call (and, for EVM
/// families, reported exactly the chain id the user typed).
class RpcProbeOk extends RpcProbeResult {
  const RpcProbeOk(this.identity);

  /// Stable identity returned by the node: decimal chain id for EVM,
  /// genesis hash for Solana, block-0 id for TRON.
  final String identity;
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
/// - TRON: block 0 must return a non-empty `blockID`, which is persisted and
///   re-checked before every transfer.
/// - Solana: `getGenesisHash` must return a non-empty hash, likewise pinned.
///
/// The client is injectable so widget tests drive the probe with fakes;
/// production constructs its own and [close]s it after the call.
class RpcProbe {
  RpcProbe({http.Client? client, this.timeout = const Duration(seconds: 10)})
    : _client = BoundedHttpClient(client ?? http.Client()),
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
        case Chain.bnb:
          final result = await _jsonRpcResult(url, 'eth_chainId');
          if (result is! String || !result.startsWith('0x')) {
            return const RpcProbeFailure();
          }
          final actual = int.tryParse(result.substring(2), radix: 16);
          if (actual == null) return const RpcProbeFailure();
          if (expectedChainId != null && actual != expectedChainId) {
            return RpcProbeChainIdMismatch(actual);
          }
          return RpcProbeOk('$actual');
        case Chain.tron:
          var base = url;
          while (base.endsWith('/')) {
            base = base.substring(0, base.length - 1);
          }
          final resp = await _client
              .post(
                Uri.parse('$base/wallet/getblockbynum'),
                headers: const {'content-type': 'application/json'},
                body: jsonEncode(const {'num': 0}),
              )
              .timeout(timeout);
          if (resp.statusCode != 200) return const RpcProbeFailure();
          final decoded = jsonDecode(resp.body);
          final identity = decoded is Map ? decoded['blockID'] : null;
          return identity is String && identity.isNotEmpty
              ? RpcProbeOk(identity)
              : const RpcProbeFailure();
        case Chain.solana:
          final identity = await _jsonRpcResult(url, 'getGenesisHash');
          return identity is String && identity.isNotEmpty
              ? RpcProbeOk(identity)
              : const RpcProbeFailure();
      }
    } catch (_) {
      // Unreachable host, TLS/format errors, timeout: all one honest failure.
      return const RpcProbeFailure();
    }
  }

  Future<Object?> _jsonRpcResult(String url, String method) async {
    final request = <String, Object?>{
      'jsonrpc': '2.0',
      'id': 1,
      'method': method,
      'params': const <Object?>[],
    };
    final response = await _client
        .post(
          Uri.parse(url),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode(request),
        )
        .timeout(timeout);
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body);
    if (!isBoundJsonRpcResponse(request, decoded) ||
        decoded is! Map ||
        decoded.containsKey('error')) {
      return null;
    }
    return decoded['result'];
  }
}
