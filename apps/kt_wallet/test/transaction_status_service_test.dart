import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/market/transaction_status_service.dart';
import 'package:wallet_data/wallet_data.dart';

class _JsonRpc implements JsonRpcTransport {
  _JsonRpc(this.responses);

  final Map<String, Object?> responses;
  final List<String> methods = [];

  @override
  Future<Object?> post(String url, Object body) async {
    final request = body as Map;
    final method = request['method'] as String;
    methods.add(method);
    return {'jsonrpc': '2.0', 'id': request['id'], 'result': responses[method]};
  }
}

class _Rest implements RestTransport {
  _Rest(this.response);

  final Object? response;

  @override
  Future<Object?> getJson(String url) async => response;

  @override
  Future<Object?> postJson(String url, Object body) async => response;
}

Transaction _tx(String coin, String hash) => Transaction(
  id: 'tx',
  walletId: 'wallet',
  coin: coin,
  networkId: '$coin-mainnet',
  direction: TxDirection.outgoing,
  fromAddr: 'from',
  toAddr: 'to',
  amountRaw: '1',
  hash: hash,
  status: TxStatus.pending,
  signMode: SignMode.local,
  createdAt: 1,
);

void main() {
  test('EVM receipt confirms immediately without account history', () async {
    final rpc = _JsonRpc({
      'eth_getTransactionReceipt': {'status': '0x1'},
    });
    final service = TransactionStatusService(
      endpoints: (_) => 'https://rpc.example',
      jsonRpcTransport: rpc,
      restTransport: _Rest(null),
    );

    expect(
      await service.check(_tx(Coin.avalanche.name, '0xhash')),
      ChainTransactionStatus.confirmed,
    );
    expect(rpc.methods, ['eth_getTransactionReceipt']);
  });

  test('EVM known transaction without receipt remains pending', () async {
    final rpc = _JsonRpc({
      'eth_getTransactionReceipt': null,
      'eth_getTransactionByHash': {'hash': '0xhash'},
    });
    final service = TransactionStatusService(
      endpoints: (_) => 'https://rpc.example',
      jsonRpcTransport: rpc,
      restTransport: _Rest(null),
    );

    expect(
      await service.check(_tx(Coin.bnb.name, '0xhash')),
      ChainTransactionStatus.pending,
    );
  });

  test('Solana execution error is failed, not confirmed', () async {
    final rpc = _JsonRpc({
      'getSignatureStatuses': {
        'value': [
          {
            'confirmationStatus': 'finalized',
            'err': {'InstructionError': 0},
          },
        ],
      },
    });
    final service = TransactionStatusService(
      endpoints: (_) => 'https://rpc.example',
      jsonRpcTransport: rpc,
      restTransport: _Rest(null),
    );

    expect(
      await service.check(_tx(Coin.solana.name, 'signature')),
      ChainTransactionStatus.failed,
    );
  });

  test('TRON full-node receipt confirms without TronGrid history', () async {
    final service = TransactionStatusService(
      endpoints: (_) => 'https://tron.example',
      jsonRpcTransport: _JsonRpc(const {}),
      restTransport: _Rest({
        'id': 'hash',
        'receipt': {'result': 'SUCCESS'},
      }),
    );

    expect(
      await service.check(_tx(Coin.tron.name, 'hash')),
      ChainTransactionStatus.confirmed,
    );
  });
}
