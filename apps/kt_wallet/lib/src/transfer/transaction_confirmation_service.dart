import 'package:chains/chains.dart';
import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:wallet_data/wallet_data.dart' show TxStatus;

import '../market/balance_service.dart' show RpcEndpointResolver;
import '../rpc/http_transport.dart';
import 'chain_params_service.dart' show rpcCoinForChain;

class TransactionConfirmation {
  const TransactionConfirmation({
    required this.status,
    required this.confirmations,
    this.finalized = false,
  });

  final TxStatus status;

  /// Number of blocks/slots that currently confirm the transaction. Null
  /// means the chain reports finality without an exact numeric depth.
  final int? confirmations;

  /// True when the chain explicitly reports irreversible/finalized state.
  final bool finalized;
}

/// Read-only confirmation lookup for a transaction that has already been
/// broadcast. This never submits or retries a transaction.
class TransactionConfirmationService {
  TransactionConfirmationService({
    required this.endpoints,
    JsonRpcTransport? jsonRpcTransport,
    RestTransport? restTransport,
  }) : _jsonRpc = jsonRpcTransport ?? HttpJsonRpcTransport(),
       _rest = restTransport ?? HttpRestTransport(),
       _ownsJsonRpc = jsonRpcTransport == null,
       _ownsRest = restTransport == null;

  final RpcEndpointResolver endpoints;
  final JsonRpcTransport _jsonRpc;
  final RestTransport _rest;
  final bool _ownsJsonRpc;
  final bool _ownsRest;
  int _requestId = 0;

  Future<TransactionConfirmation> check(Chain chain, String hash) =>
      switch (chain) {
        Chain.ethereum ||
        Chain.polygon ||
        Chain.base ||
        Chain.arbitrum ||
        Chain.avalanche ||
        Chain.bnb => _checkEvm(chain, hash),
        Chain.tron => _checkTron(hash),
        Chain.solana => _checkSolana(hash),
      };

  Future<TransactionConfirmation> _checkEvm(Chain chain, String hash) async {
    final rpc = EvmRpc(
      url: endpoints(rpcCoinForChain(chain)),
      transport: _jsonRpc,
    );
    final receipt = await rpc.getTransactionReceipt(hash);
    if (receipt == null) {
      return const TransactionConfirmation(
        status: TxStatus.pending,
        confirmations: 0,
      );
    }
    final evidence = parseEvmReceiptEvidence(
      receipt,
      expectedTransactionHash: hash,
    );
    final status = evidence.succeeded ? TxStatus.confirmed : TxStatus.failed;
    final includedAt = evidence.blockNumber;
    final latest = await rpc.getBlockNumber();
    final depth = latest - includedAt + BigInt.one;
    if (depth < BigInt.one) {
      throw RpcException('EVM receipt is ahead of the latest block');
    }
    return TransactionConfirmation(
      status: status,
      confirmations: depth.toInt(),
    );
  }

  Future<TransactionConfirmation> _checkTron(String hash) async {
    final response = await _rest.postJson(
      '${endpoints(Coin.tron)}/wallet/gettransactioninfobyid',
      {'value': hash},
    );
    if (response is! Map) {
      throw RpcException('malformed TRON transaction info');
    }
    if (response.isEmpty) {
      return const TransactionConfirmation(
        status: TxStatus.pending,
        confirmations: 0,
      );
    }
    final receipt = response['receipt'];
    final blockNumber = response['blockNumber'];
    if (receipt is! Map ||
        receipt['result'] is! String ||
        blockNumber is! int) {
      throw RpcException('malformed TRON receipt');
    }
    final rpc = TronRpc(baseUrl: endpoints(Coin.tron), transport: _rest);
    final latest = (await rpc.getNowBlock()).number;
    final confirmations = latest - blockNumber + 1;
    if (confirmations < 1) {
      throw RpcException('TRON receipt is ahead of the latest block');
    }
    return TransactionConfirmation(
      status: receipt['result'] == 'SUCCESS'
          ? TxStatus.confirmed
          : TxStatus.failed,
      confirmations: confirmations,
    );
  }

  Future<TransactionConfirmation> _checkSolana(String hash) async {
    final response = await _jsonRpc.post(endpoints(Coin.solana), {
      'jsonrpc': '2.0',
      'id': ++_requestId,
      'method': 'getSignatureStatuses',
      'params': [
        [hash],
        {'searchTransactionHistory': true},
      ],
    });
    if (response is! Map || response['error'] != null) {
      throw RpcException('malformed Solana signature status');
    }
    final result = response['result'];
    final values = result is Map ? result['value'] : null;
    if (values is! List || values.length != 1) {
      throw RpcException('malformed Solana signature status');
    }
    final status = values.single;
    if (status == null) {
      return const TransactionConfirmation(
        status: TxStatus.pending,
        confirmations: 0,
      );
    }
    if (status is! Map) {
      throw RpcException('malformed Solana signature entry');
    }
    final confirmationStatus = status['confirmationStatus'];
    final confirmations = status['confirmations'];
    if (confirmations != null && confirmations is! int) {
      throw RpcException('malformed Solana confirmation count');
    }
    final txStatus = status['err'] != null
        ? TxStatus.failed
        : switch (confirmationStatus) {
            'confirmed' || 'finalized' => TxStatus.confirmed,
            _ => TxStatus.pending,
          };
    return TransactionConfirmation(
      status: txStatus,
      confirmations: confirmations as int?,
      finalized: confirmationStatus == 'finalized',
    );
  }

  void close() {
    if (_ownsJsonRpc && _jsonRpc is HttpJsonRpcTransport) {
      _jsonRpc.close();
    }
    if (_ownsRest && _rest is HttpRestTransport) {
      _rest.close();
    }
  }
}
