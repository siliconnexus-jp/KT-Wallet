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
  Chain.base => Coin.base,
  Chain.arbitrum => Coin.arbitrum,
  Chain.avalanche => Coin.avalanche,
  Chain.bnb => Coin.bnb,
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

class EvmNonceState {
  const EvmNonceState({required this.confirmed, required this.pending});

  /// First nonce not yet consumed by a mined transaction.
  final int confirmed;

  /// First nonce not already represented in the node's pending pool.
  final int pending;
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
  }) : _jsonRpc = jsonRpcTransport ?? HttpJsonRpcTransport(),
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
    if (chain != Chain.ethereum &&
        chain != Chain.polygon &&
        chain != Chain.base &&
        chain != Chain.arbitrum &&
        chain != Chain.avalanche &&
        chain != Chain.bnb) {
      throw ArgumentError('not an EVM chain: $chain');
    }
    final gateway = _gateway();
    if (gateway != null) {
      try {
        final params = await gateway.getChainParams(
          chain: rpcCoinForChain(chain),
          address: fromAddress,
        );
        return EvmChainParams(
          nonce: params.nonce,
          fees: _applyChainFeeFloor(chain, params.fees),
        );
      } catch (_) {
        // GatewayException / transport failure: direct node path below.
      }
    }
    final rpc = EvmRpc(
      url: _endpoints(rpcCoinForChain(chain)),
      transport: _jsonRpc,
    );
    // Future.wait (not records .wait) so the first failure propagates as-is
    // (RpcException / TimeoutException), not wrapped in a ParallelWaitError.
    final results = await Future.wait<Object>([
      rpc.getNonce(fromAddress),
      rpc.estimateFees(),
    ]);
    return EvmChainParams(
      nonce: results[0] as int,
      fees: _applyChainFeeFloor(chain, results[1] as GasFeeEstimate),
    );
  }

  Future<BigInt> estimateEvmGas(
    Chain chain, {
    required String from,
    required String to,
    required BigInt value,
    required String data,
  }) {
    if (chain != Chain.ethereum &&
        chain != Chain.polygon &&
        chain != Chain.base &&
        chain != Chain.arbitrum &&
        chain != Chain.avalanche &&
        chain != Chain.bnb) {
      throw ArgumentError('not an EVM chain: $chain');
    }
    return EvmRpc(
      url: _endpoints(rpcCoinForChain(chain)),
      transport: _jsonRpc,
    ).estimateGas(from: from, to: to, value: value, data: data);
  }

  /// Fetches both mined and mempool nonce views from the same direct node.
  /// Replacement flows use [EvmNonceState.confirmed] to reject an attempt
  /// after the original nonce has already been consumed on-chain.
  Future<EvmNonceState> fetchEvmNonceState(
    Chain chain,
    String fromAddress,
  ) async {
    if (chain != Chain.ethereum &&
        chain != Chain.polygon &&
        chain != Chain.base &&
        chain != Chain.arbitrum &&
        chain != Chain.avalanche &&
        chain != Chain.bnb) {
      throw ArgumentError('not an EVM chain: $chain');
    }
    final rpc = EvmRpc(
      url: _endpoints(rpcCoinForChain(chain)),
      transport: _jsonRpc,
    );
    final values = await Future.wait<int>([
      rpc.getConfirmedNonce(fromAddress),
      rpc.getNonce(fromAddress),
    ]);
    return EvmNonceState(confirmed: values[0], pending: values[1]);
  }
}

GasFeeEstimate _applyChainFeeFloor(Chain chain, GasFeeEstimate fees) {
  if (chain != Chain.polygon && chain != Chain.arbitrum && chain != Chain.bnb) {
    return fees;
  }
  // Polygon nodes require a 25 gwei priority floor. Arbitrum Sepolia can
  // return maxFee equal to the sampled base fee; a tiny next-block increase
  // then rejects an otherwise valid transaction, so retain a 0.05 gwei
  // safety floor there. BNB Chain validators enforce a 0.1 gwei minimum tip,
  // while feeHistory can briefly report 0.08 gwei; normalize before signing
  // so the exact same envelope is accepted across RPC nodes.
  final floor = switch (chain) {
    Chain.polygon => BigInt.from(25000000000),
    Chain.bnb => BigInt.from(100000000),
    _ => BigInt.from(50000000),
  };
  GasFeeEstimateTier normalize(GasFeeEstimateTier tier) {
    final enforceTip = chain == Chain.polygon || chain == Chain.bnb;
    final tip = enforceTip && tier.maxPriorityFeePerGas < floor
        ? floor
        : tier.maxPriorityFeePerGas;
    final minimumMaxFee = switch (chain) {
      Chain.polygon => tip + BigInt.from(5000000000),
      Chain.bnb => tip,
      _ => floor,
    };
    final maxFee = tier.maxFeePerGas < minimumMaxFee
        ? minimumMaxFee
        : tier.maxFeePerGas;
    return GasFeeEstimateTier(maxPriorityFeePerGas: tip, maxFeePerGas: maxFee);
  }

  return GasFeeEstimate(
    slow: normalize(fees.slow),
    standard: normalize(fees.standard),
    fast: normalize(fees.fast),
  );
}
