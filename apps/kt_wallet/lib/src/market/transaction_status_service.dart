import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:wallet_data/wallet_data.dart' as db;

import '../rpc/http_transport.dart';
import 'balance_service.dart' show RpcEndpointResolver, defaultRpcEndpointFor;
import 'gateway_client.dart';

/// Chain-authoritative state of a submitted transaction. `unknown` means the
/// queried node cannot currently find it; it is deliberately not equivalent
/// to dropped because another node may still have accepted the broadcast.
enum ChainTransactionStatus { confirmed, failed, pending, unknown }

/// Looks up a transaction by hash/signature, bypassing account-history
/// indexers. The configured KT Gateway is preferred so this remains usable
/// when public RPC endpoints are inaccessible from the device's network.
class TransactionStatusService {
  TransactionStatusService({
    RpcEndpointResolver? endpoints,
    GatewayResolver? gateway,
    JsonRpcTransport? jsonRpcTransport,
    RestTransport? restTransport,
  }) : _endpoints = endpoints ?? defaultRpcEndpointFor,
       _gateway = gateway ?? _noGateway,
       _jsonRpc = jsonRpcTransport ?? HttpJsonRpcTransport(),
       _rest = restTransport ?? HttpRestTransport();

  static GatewayClient? _noGateway() => null;

  final RpcEndpointResolver _endpoints;
  final GatewayResolver _gateway;
  final JsonRpcTransport _jsonRpc;
  final RestTransport _rest;

  Future<ChainTransactionStatus> check(db.Transaction transaction) async {
    final hash = transaction.hash;
    final coin = Coin.values
        .where((c) => c.name == transaction.coin)
        .firstOrNull;
    if (hash == null || hash.isEmpty || coin == null) {
      return ChainTransactionStatus.unknown;
    }

    final gateway = _gateway();
    if (gateway != null) {
      try {
        final status = await gateway.getTransactionStatus(
          chain: coin,
          hash: hash,
        );
        return switch (status) {
          GatewayTransactionStatus.confirmed =>
            ChainTransactionStatus.confirmed,
          GatewayTransactionStatus.failed => ChainTransactionStatus.failed,
          GatewayTransactionStatus.pending => ChainTransactionStatus.pending,
          GatewayTransactionStatus.unknown => ChainTransactionStatus.unknown,
        };
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
        Coin.bnb => await _evm(coin, hash),
        Coin.tron => await _tron(hash),
        Coin.solana => await _solana(hash),
      };
    } catch (_) {
      return ChainTransactionStatus.unknown;
    }
  }

  Future<ChainTransactionStatus> _evm(Coin coin, String hash) async {
    final rpc = EvmRpc(url: _endpoints(coin), transport: _jsonRpc);
    final receipt = await rpc.getTransactionReceipt(hash);
    if (receipt != null) {
      return receipt['status'] == '0x1'
          ? ChainTransactionStatus.confirmed
          : ChainTransactionStatus.failed;
    }
    final transaction = await rpc.getTransactionByHash(hash);
    return transaction == null
        ? ChainTransactionStatus.unknown
        : ChainTransactionStatus.pending;
  }

  Future<ChainTransactionStatus> _tron(String hash) async {
    final ok = await TronRpc(
      baseUrl: _endpoints(Coin.tron),
      transport: _rest,
    ).transactionSucceeded(hash);
    if (ok == null) return ChainTransactionStatus.unknown;
    return ok
        ? ChainTransactionStatus.confirmed
        : ChainTransactionStatus.failed;
  }

  Future<ChainTransactionStatus> _solana(String hash) async {
    final result = await SolanaRpc(
      url: _endpoints(Coin.solana),
      transport: _jsonRpc,
    ).signatureResult(hash);
    if (result == null) return ChainTransactionStatus.unknown;
    if (result.failed) return ChainTransactionStatus.failed;
    return switch (result.confirmationStatus) {
      'confirmed' || 'finalized' => ChainTransactionStatus.confirmed,
      _ => ChainTransactionStatus.pending,
    };
  }
}
