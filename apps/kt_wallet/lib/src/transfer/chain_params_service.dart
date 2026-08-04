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

class EvmSpendableBalances {
  const EvmSpendableBalances({
    required this.native,
    BigInt? nativeLatest,
    this.token,
    this.pendingAvailable = true,
  }) : nativeLatest = nativeLatest ?? native;

  /// Pending-state balance after the provider applies known mempool entries.
  final BigInt native;

  /// Latest mined balance before pending entries are applied.
  final BigInt nativeLatest;
  final BigInt? token;

  /// False only when the node explicitly reports that its pending block state
  /// is unsupported. An ordinary send may use [nativeLatest] only after the
  /// same node proves confirmed nonce == pending nonce == the chosen nonce;
  /// a replacement may use it only at the current confirmed nonce. Both paths
  /// still fail closed when an earlier queued liability cannot be accounted
  /// for.
  final bool pendingAvailable;
}

/// Fetches real chain-state parameters over the tested `chains/rpc` clients.
/// The transport is injectable (production defaults to the http-backed one,
/// which owns the 10s request timeouts) and endpoints resolve through the
/// same prefs-aware resolver the market services use, so a persisted RPC
/// override in network settings applies here too.
///
/// This service owns the EVM-specific parameter set. TRON and Solana obtain
/// their real reference block / blockhash, fees, simulation and spendable
/// balances through [LocalTransferService]'s protocol-specific preparation
/// paths rather than through this EVM-shaped API.
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
  }) async {
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
        return await gateway.estimateEvmGas(
          chain: rpcCoinForChain(chain),
          from: from,
          to: to,
          value: value,
          data: data,
        );
      } catch (_) {
        // Gateway transport/upstream failure: retry against the active direct
        // endpoint. A failure of both paths propagates below.
      }
    }
    return EvmRpc(
      url: _endpoints(rpcCoinForChain(chain)),
      transport: _jsonRpc,
    ).estimateGas(from: from, to: to, value: value, data: data);
  }

  /// Simulates the exact transfer before any native key access. New transfers
  /// default to `pending`; same-nonce replacements explicitly use `latest`
  /// because they are alternatives to the pending candidate. A node-side
  /// revert throws. For standard ERC-20 `transfer` calls, an explicit ABI
  /// `false` return is also a rejection; an empty return remains accepted for
  /// older non-standard tokens such as USDT.
  Future<void> simulateEvmTransfer(
    Chain chain, {
    required String from,
    required String to,
    required BigInt value,
    required String data,
    required bool tokenTransfer,
    String blockTag = 'pending',
  }) async {
    if (chain != Chain.ethereum &&
        chain != Chain.polygon &&
        chain != Chain.base &&
        chain != Chain.arbitrum &&
        chain != Chain.avalanche &&
        chain != Chain.bnb) {
      throw ArgumentError('not an EVM chain: $chain');
    }
    String result;
    final gateway = _gateway();
    if (gateway != null) {
      try {
        result = await gateway.simulateEvmTransfer(
          chain: rpcCoinForChain(chain),
          from: from,
          to: to,
          value: value,
          data: data,
          blockTag: blockTag,
        );
      } catch (_) {
        result = await _simulateDirect(
          chain,
          from: from,
          to: to,
          value: value,
          data: data,
          blockTag: blockTag,
        );
      }
    } else {
      result = await _simulateDirect(
        chain,
        from: from,
        to: to,
        value: value,
        data: data,
        blockTag: blockTag,
      );
    }
    if (!tokenTransfer || result == '0x') return;
    final encoded = result.substring(2);
    if (encoded.length != 64) {
      throw RpcException('malformed ERC-20 transfer result');
    }
    if (BigInt.parse(encoded, radix: 16) == BigInt.zero) {
      throw RpcException('token contract returned false');
    }
  }

  Future<String> _simulateDirect(
    Chain chain, {
    required String from,
    required String to,
    required BigInt value,
    required String data,
    required String blockTag,
  }) {
    return EvmRpc(
      url: _endpoints(rpcCoinForChain(chain)),
      transport: _jsonRpc,
    ).call(from: from, to: to, value: value, data: data, blockTag: blockTag);
  }

  /// Reads uncached pending-state balances used to authorize the exact EVM
  /// transfer. Gateway is preferred for restricted networks; failure falls
  /// back to the active direct endpoint. Failure of both paths propagates.
  Future<EvmSpendableBalances> fetchEvmSpendableBalances(
    Chain chain, {
    required String address,
    String? tokenContract,
  }) async {
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
        final balances = await gateway.getEvmSpendableBalances(
          chain: rpcCoinForChain(chain),
          address: address,
          tokenContract: tokenContract,
        );
        return EvmSpendableBalances(
          native: balances.native,
          nativeLatest: balances.nativeLatest,
          token: balances.token,
          pendingAvailable: balances.pendingAvailable,
        );
      } catch (_) {
        // Gateway failure: retry the same pending-state reads directly.
      }
    }

    final rpc = EvmRpc(
      url: _endpoints(rpcCoinForChain(chain)),
      transport: _jsonRpc,
    );
    final latest = await Future.wait<BigInt>([
      rpc.getBalance(address, blockTag: 'latest'),
      if (tokenContract != null)
        rpc.erc20Balance(tokenContract, address, blockTag: 'latest'),
    ]);
    try {
      final pending = await Future.wait<BigInt>([
        rpc.getBalance(address, blockTag: 'pending'),
        if (tokenContract != null)
          rpc.erc20Balance(tokenContract, address, blockTag: 'pending'),
      ]);
      return EvmSpendableBalances(
        native: pending[0],
        nativeLatest: latest[0],
        token: tokenContract == null ? null : pending[1],
      );
    } on RpcException catch (error) {
      if (!isEvmPendingStateUnavailable(error)) rethrow;
      return EvmSpendableBalances(
        native: latest[0],
        nativeLatest: latest[0],
        token: tokenContract == null ? null : latest[1],
        pendingAvailable: false,
      );
    }
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

/// True only for the narrow node capability error where `latest` remains
/// usable but a pending-state block view does not exist (Avalanche C-Chain is
/// the common case). Callers must additionally prove confirmed nonce equals
/// pending nonce before using latest state for a new transaction.
bool isEvmPendingStateUnavailable(RpcException error) {
  final message = error.message.toLowerCase();
  return message.contains('state not available for pending block') ||
      message.contains('pending block is not available');
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
