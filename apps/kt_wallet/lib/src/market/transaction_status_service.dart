import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:wallet_data/wallet_data.dart' as db;

import '../rpc/http_transport.dart';
import 'balance_service.dart' show RpcEndpointResolver, defaultRpcEndpointFor;
import 'gateway_client.dart';

/// Chain-authoritative state of a submitted transaction. `unknown` means the
/// queried node cannot currently find it; it is deliberately not equivalent
/// to dropped because another node may still have accepted the broadcast.
enum ChainTransactionStatus {
  confirmed,
  failed,
  pending,
  replaced,
  expired,
  unknown,
}

typedef EvmNonceObserver =
    Future<void> Function(db.Transaction transaction, String nonce);

/// Resolves an endpoint for the exact persisted network of a transaction.
/// Null means the id is deleted, unknown, or belongs to another chain family.
typedef TransactionNetworkEndpointResolver =
    String? Function(Coin coin, String networkId);

/// Looks up a transaction by hash/signature, bypassing account-history
/// indexers. The configured KT Gateway is preferred so this remains usable
/// when public RPC endpoints are inaccessible from the device's network.
class TransactionStatusService {
  TransactionStatusService({
    RpcEndpointResolver? endpoints,
    GatewayResolver? gateway,
    JsonRpcTransport? jsonRpcTransport,
    RestTransport? restTransport,
    this.networkEndpoints,
    this.onEvmNonceObserved,
  }) : _endpoints = endpoints ?? defaultRpcEndpointFor,
       _gateway = gateway ?? _noGateway,
       _jsonRpc = jsonRpcTransport ?? HttpJsonRpcTransport(),
       _rest = restTransport ?? HttpRestTransport();

  static GatewayClient? _noGateway() => null;

  final RpcEndpointResolver _endpoints;
  final GatewayResolver _gateway;
  final JsonRpcTransport _jsonRpc;
  final RestTransport _rest;
  final TransactionNetworkEndpointResolver? networkEndpoints;
  final EvmNonceObserver? onEvmNonceObserved;

  Future<ChainTransactionStatus> check(db.Transaction transaction) async {
    final hash = transaction.hash;
    final coin = Coin.values
        .where((c) => c.name == transaction.coin)
        .firstOrNull;
    if (hash == null || hash.isEmpty || coin == null) {
      return ChainTransactionStatus.unknown;
    }

    final persistedNetwork = transaction.networkId;
    final endpoint = networkEndpoints == null
        ? _endpoints(coin)
        : persistedNetwork == null || persistedNetwork.isEmpty
        ? null
        : networkEndpoints!(coin, persistedNetwork);
    // Once production network wiring is present, a legacy/deleted/cross-chain
    // network id must never fall back to the currently active RPC or mainnet.
    if (endpoint == null || endpoint.isEmpty) {
      return ChainTransactionStatus.unknown;
    }

    final gateway = _gateway();
    if (gateway != null) {
      try {
        final status = await gateway.getTransactionStatus(
          chain: coin,
          hash: hash,
          network: networkEndpoints == null ? null : persistedNetwork,
        );
        final mapped = switch (status) {
          GatewayTransactionStatus.confirmed =>
            ChainTransactionStatus.confirmed,
          GatewayTransactionStatus.failed => ChainTransactionStatus.failed,
          GatewayTransactionStatus.pending => ChainTransactionStatus.pending,
          GatewayTransactionStatus.unknown => ChainTransactionStatus.unknown,
        };
        // An account index or a single gateway node may not know a recently
        // submitted hash. `unknown` is therefore a prompt to try the active
        // chain RPC, never a terminal result by itself.
        final needsDirectEvidence =
            mapped == ChainTransactionStatus.pending &&
            ((coin == Coin.tron || coin == Coin.solana) ||
                (_isEvm(coin) && transaction.nonce == null));
        if (mapped != ChainTransactionStatus.unknown && !needsDirectEvidence) {
          return mapped;
        }
      } catch (_) {
        // Gateway unavailable or not yet upgraded: use the active direct RPC.
      }
    }

    try {
      return switch (coin) {
        Coin.eth ||
        Coin.polygon ||
        Coin.base ||
        Coin.arbitrum ||
        Coin.avalanche ||
        Coin.bnb => await _evm(coin, endpoint, hash, transaction),
        Coin.tron => await _tron(endpoint, hash, transaction),
        Coin.solana => await _solana(endpoint, hash, transaction),
      };
    } catch (_) {
      return ChainTransactionStatus.unknown;
    }
  }

  Future<ChainTransactionStatus> _evm(
    Coin coin,
    String endpoint,
    String hash,
    db.Transaction transaction,
  ) async {
    final rpc = EvmRpc(url: endpoint, transport: _jsonRpc);
    final receipt = await rpc.getTransactionReceipt(hash);
    if (receipt != null) {
      final evidence = parseEvmReceiptEvidence(
        receipt,
        expectedTransactionHash: hash,
      );
      return evidence.succeeded
          ? ChainTransactionStatus.confirmed
          : ChainTransactionStatus.failed;
    }
    final remoteTransaction = await rpc.getPendingTransactionEvidence(
      hash,
      expectedFrom: transaction.fromAddr,
    );
    if (remoteTransaction != null) {
      final observedNonce = remoteTransaction.nonce;
      final persistedNonce = BigInt.tryParse(transaction.nonce ?? '');
      if (persistedNonce != null && persistedNonce != observedNonce) {
        return ChainTransactionStatus.unknown;
      }
      if (transaction.nonce == null && onEvmNonceObserved != null) {
        try {
          await onEvmNonceObserved!(transaction, observedNonce.toString());
        } catch (_) {
          // Persistence failure cannot turn a chain-known transaction into a
          // false failure. It remains pending and may be backfilled next poll.
        }
      }
      return ChainTransactionStatus.pending;
    }

    // A missing hash alone proves nothing: nodes have different mempools and
    // providers can evict old entries. But if the chain's *confirmed* account
    // nonce has advanced beyond this exact persisted nonce, another
    // transaction has irreversibly consumed the slot and the original can no
    // longer be mined. That is a replacement, not a generic failure.
    final persistedNonce = int.tryParse(transaction.nonce ?? '');
    if (persistedNonce == null) return ChainTransactionStatus.unknown;
    final confirmedNonce = await rpc.getConfirmedNonce(transaction.fromAddr);
    return confirmedNonce > persistedNonce
        ? ChainTransactionStatus.replaced
        : ChainTransactionStatus.unknown;
  }

  Future<ChainTransactionStatus> _tron(
    String endpoint,
    String hash,
    db.Transaction transaction,
  ) async {
    final rpc = TronRpc(baseUrl: endpoint, transport: _rest);
    final ok = await rpc.transactionSucceeded(hash);
    if (ok == null) {
      final expiresAt = transaction.expiresAt;
      if (expiresAt == null || expiresAt <= 0) {
        return ChainTransactionStatus.unknown;
      }
      // Use canonical chain time, never the device clock. A hash missing from
      // this full node remains non-terminal until the chain itself has passed
      // the exact expiration embedded in the signed TRON transaction.
      final block = await rpc.getNowBlock();
      return block.timestamp > expiresAt
          ? ChainTransactionStatus.expired
          : ChainTransactionStatus.unknown;
    }
    return ok
        ? ChainTransactionStatus.confirmed
        : ChainTransactionStatus.failed;
  }

  Future<ChainTransactionStatus> _solana(
    String endpoint,
    String hash,
    db.Transaction transaction,
  ) async {
    final rpc = SolanaRpc(url: endpoint, transport: _jsonRpc);
    final result = await rpc.signatureResult(hash);
    if (result == null) {
      final lastValidBlockHeight = transaction.lastValidBlockHeight;
      if (lastValidBlockHeight == null || lastValidBlockHeight < 0) {
        return ChainTransactionStatus.unknown;
      }
      final currentBlockHeight = await rpc.getBlockHeight();
      return currentBlockHeight > lastValidBlockHeight
          ? ChainTransactionStatus.expired
          : ChainTransactionStatus.unknown;
    }
    if (result.failed) return ChainTransactionStatus.failed;
    return switch (result.confirmationStatus) {
      'confirmed' || 'finalized' => ChainTransactionStatus.confirmed,
      _ => ChainTransactionStatus.pending,
    };
  }

  bool _isEvm(Coin coin) => switch (coin) {
    Coin.eth ||
    Coin.polygon ||
    Coin.base ||
    Coin.arbitrum ||
    Coin.avalanche ||
    Coin.bnb => true,
    Coin.tron || Coin.solana => false,
  };
}
