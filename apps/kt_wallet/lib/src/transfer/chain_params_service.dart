import 'dart:async';

import 'package:chains/chains.dart' show Chain;
import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart' show Coin;

import '../market/balance_service.dart'
    show RpcEndpointResolver, defaultRpcEndpointFor;
import '../market/gateway_client.dart';
import '../rpc/http_transport.dart';

/// The RPC-endpoint coin for a transfer chain (ETH and Polygon resolve to
/// their own endpoints even though they share an address).
Coin rpcCoinForChain(Chain chain) => switch (chain) {
      Chain.ethereum => Coin.eth,
      Chain.polygon => Coin.polygon,
      Chain.tron => Coin.tron,
      Chain.solana => Coin.solana,
    };

/// Live chain-state parameters needed to build a real EVM transaction: the
/// sender's pending nonce and the current EIP-1559 fee estimate.
class EvmChainParams {
  const EvmChainParams({required this.nonce, required this.fees});

  final int nonce;
  final GasFeeEstimate fees;

  /// The estimate tier matching the draft's fee selection
  /// (0 slow / 1 standard / 2 fast).
  GasFeeEstimateTier tierFor(int feeTier) => switch (feeTier) {
        0 => fees.slow,
        2 => fees.fast,
        _ => fees.standard,
      };
}

/// Fetches real chain-state parameters over the tested `chains/rpc` clients.
/// The transport is injectable (production defaults to the http-backed one,
/// which owns the 10s request timeouts) and endpoints resolve through the
/// same prefs-aware resolver the market services use, so a persisted RPC
/// override in network settings applies here too.
///
/// Only EVM chains fetch today — TRON/Solana transactions still use their
/// documented placeholder encodings, so there is nothing real to parameterize.
class ChainParamsService {
  ChainParamsService({
    JsonRpcTransport? jsonRpcTransport,
    RpcEndpointResolver? endpoints,
    GatewayResolver? gateway,
  })  : _jsonRpc = jsonRpcTransport ?? HttpJsonRpcTransport(),
        _endpoints = endpoints ?? defaultRpcEndpointFor,
        _gateway = gateway ?? _noGateway;

  static GatewayClient? _noGateway() => null;

  final JsonRpcTransport _jsonRpc;

  /// Resolved on every fetch (not cached at construction) so a persisted
  /// override saved in settings applies from the very next request.
  final RpcEndpointResolver _endpoints;

  /// Optional gateway (null in direct mode), resolved on every fetch.
  final GatewayResolver _gateway;

  /// Fetches [fromAddress]'s pending nonce and the current fee estimate
  /// concurrently. Throws on any failure (RPC error, timeout, malformed
  /// response) — the caller decides the fallback policy.
  ///
  /// GATEWAY SEMANTICS: with a gateway configured, `kt_getChainParams` is
  /// asked first; any gateway failure falls back to the direct EvmRpc pair
  /// (getNonce + estimateFees), and only a failure of BOTH paths throws.
  /// Direct mode never contacts the gateway.
  Future<EvmChainParams> fetchEvmParams(Chain chain, String fromAddress) async {
    if (chain != Chain.ethereum && chain != Chain.polygon) {
      throw ArgumentError('not an EVM chain: $chain');
    }
    final gateway = _gateway();
    if (gateway != null) {
      try {
        final params = await gateway.getChainParams(
            chain: rpcCoinForChain(chain), address: fromAddress);
        return EvmChainParams(nonce: params.nonce, fees: params.fees);
      } catch (_) {
        // GatewayException / transport failure: direct node path below.
      }
    }
    final rpc = EvmRpc(url: _endpoints(rpcCoinForChain(chain)), transport: _jsonRpc);
    // Future.wait (not records .wait) so the first failure propagates as-is
    // (RpcException / TimeoutException), not wrapped in a ParallelWaitError.
    final results = await Future.wait<Object>([
      rpc.getNonce(fromAddress),
      rpc.estimateFees(),
    ]);
    return EvmChainParams(
      nonce: results[0] as int,
      fees: results[1] as GasFeeEstimate,
    );
  }
}
