import 'dart:convert';

import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kt_wallet/src/market/gateway_client.dart';
import 'package:kt_wallet/src/market/transaction_status_service.dart';
import 'package:wallet_data/wallet_data.dart';

class _JsonRpc implements JsonRpcTransport {
  _JsonRpc(this.responses);

  final Map<String, Object?> responses;
  final List<String> methods = [];
  final List<String> urls = [];

  @override
  Future<Object?> post(String url, Object body) async {
    urls.add(url);
    final request = body as Map;
    final method = request['method'] as String;
    methods.add(method);
    return {'jsonrpc': '2.0', 'id': request['id'], 'result': responses[method]};
  }
}

class _Rest implements RestTransport {
  _Rest(this.response) : onPost = null;
  _Rest.onPost(this.onPost) : response = null;

  final Object? response;
  final Object? Function(String url, Object body)? onPost;

  @override
  Future<Object?> getJson(String url) async => response;

  @override
  Future<Object?> postJson(String url, Object body) async =>
      onPost?.call(url, body) ?? response;
}

const _evmHash =
    '0x1111111111111111111111111111111111111111111111111111111111111111';
const _otherEvmHash =
    '0x2222222222222222222222222222222222222222222222222222222222222222';
const _evmFrom = '0x3333333333333333333333333333333333333333';
const _tronHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _otherTronHash =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _solanaSignature =
    '4cdd1oX7cfVALfr26tP52BZ6cSzrgnNGtYD7BFhm6FFeZV5sPTnRvg6NRn8yC6DbEikXcrNChBM5vVJnTgKhGhVu';

Map<String, Object?> _evmReceipt({
  String transactionHash = _evmHash,
  Object? status = '0x1',
}) => {
  'transactionHash': transactionHash,
  'blockHash':
      '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'blockNumber': '0x64',
  'transactionIndex': '0x0',
  'status': status,
};

Transaction _tx(
  String coin,
  String hash, {
  String? networkId,
  String? nonce,
  int? expiresAt,
  int? lastValidBlockHeight,
  String fromAddr = 'from',
}) => Transaction(
  id: 'tx',
  walletId: 'wallet',
  coin: coin,
  networkId: networkId ?? '$coin-mainnet',
  operation: TxOperationKind.transfer,
  direction: TxDirection.outgoing,
  fromAddr: fromAddr,
  toAddr: 'to',
  amountRaw: '1',
  hash: hash,
  status: TxStatus.pending,
  signMode: SignMode.local,
  createdAt: 1,
  nonce: nonce,
  expiresAt: expiresAt,
  lastValidBlockHeight: lastValidBlockHeight,
);

void main() {
  test('EVM receipt confirms immediately without account history', () async {
    final rpc = _JsonRpc({'eth_getTransactionReceipt': _evmReceipt()});
    final service = TransactionStatusService(
      endpoints: (_) => 'https://rpc.example',
      jsonRpcTransport: rpc,
      restTransport: _Rest(null),
    );

    expect(
      await service.check(_tx(Coin.avalanche.name, _evmHash)),
      ChainTransactionStatus.confirmed,
    );
    expect(rpc.methods, ['eth_getTransactionReceipt']);
  });

  test('EVM receipt for another hash is unknown, never confirmed', () async {
    final rpc = _JsonRpc({
      'eth_getTransactionReceipt': _evmReceipt(transactionHash: _otherEvmHash),
    });
    final service = TransactionStatusService(
      endpoints: (_) => 'https://rpc.example',
      jsonRpcTransport: rpc,
      restTransport: _Rest(null),
    );

    expect(
      await service.check(_tx(Coin.eth.name, _evmHash)),
      ChainTransactionStatus.unknown,
    );
  });

  test('EVM receipt without complete block evidence is unknown', () async {
    final rpc = _JsonRpc({
      'eth_getTransactionReceipt': {
        'transactionHash': _evmHash,
        'blockNumber': '0x64',
        'status': '0x1',
      },
    });
    final service = TransactionStatusService(
      endpoints: (_) => 'https://rpc.example',
      jsonRpcTransport: rpc,
      restTransport: _Rest(null),
    );

    expect(
      await service.check(_tx(Coin.eth.name, _evmHash)),
      ChainTransactionStatus.unknown,
    );
  });

  test(
    'persisted network selects the exact RPC instead of the active network',
    () async {
      final requested = <String>[];
      final rpc = _JsonRpc({'eth_getTransactionReceipt': _evmReceipt()});
      final service = TransactionStatusService(
        endpoints: (_) => 'https://mainnet.example',
        networkEndpoints: (coin, networkId) {
          requested.add('${coin.name}:$networkId');
          return networkId == 'eth-sepolia' ? 'https://sepolia.example' : null;
        },
        jsonRpcTransport: rpc,
        restTransport: _Rest(null),
      );

      expect(
        await service.check(
          _tx(Coin.eth.name, _evmHash, networkId: 'eth-sepolia'),
        ),
        ChainTransactionStatus.confirmed,
      );
      expect(requested, ['eth:eth-sepolia']);
      expect(rpc.urls, ['https://sepolia.example']);
    },
  );

  test(
    'unknown persisted network never touches gateway or direct RPC',
    () async {
      var gatewayCalls = 0;
      final gateway = GatewayClient(
        baseUrl: 'https://gateway.example',
        advertisedNetworks: const {'eth-mainnet', 'eth-sepolia'},
        client: MockClient((request) async {
          gatewayCalls++;
          return http.Response('{}', 500);
        }),
      );
      final rpc = _JsonRpc({
        'eth_getTransactionReceipt': {'status': '0x1'},
      });
      final service = TransactionStatusService(
        endpoints: (_) => 'https://mainnet.example',
        networkEndpoints: (_, _) => null,
        gateway: () => gateway,
        jsonRpcTransport: rpc,
        restTransport: _Rest(null),
      );

      expect(
        await service.check(
          _tx(Coin.eth.name, '0xhash', networkId: 'deleted-custom'),
        ),
        ChainTransactionStatus.unknown,
      );
      expect(gatewayCalls, 0);
      expect(rpc.methods, isEmpty);
    },
  );

  test('gateway status override follows the transaction network', () async {
    final hash = '0x${'a' * 64}';
    String? observedNetwork;
    final gateway = GatewayClient(
      baseUrl: 'https://gateway.example',
      advertisedNetworks: const {'eth-mainnet', 'eth-sepolia'},
      networks: (_) => 'eth-mainnet',
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        final params = body['params'] as Map<String, Object?>;
        observedNetwork = params['network'] as String?;
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': body['id'],
            'result': {
              'network': 'eth-sepolia',
              'hash': hash,
              'status': 'confirmed',
            },
          }),
          200,
        );
      }),
    );
    final service = TransactionStatusService(
      endpoints: (_) => 'https://mainnet.example',
      networkEndpoints: (_, networkId) =>
          networkId == 'eth-sepolia' ? 'https://sepolia.example' : null,
      gateway: () => gateway,
      jsonRpcTransport: _JsonRpc(const {}),
      restTransport: _Rest(null),
    );

    expect(
      await service.check(_tx(Coin.eth.name, hash, networkId: 'eth-sepolia')),
      ChainTransactionStatus.confirmed,
    );
    expect(observedNetwork, 'eth-sepolia');
  });

  test('EVM known transaction without receipt remains pending', () async {
    final rpc = _JsonRpc({
      'eth_getTransactionReceipt': null,
      'eth_getTransactionByHash': {
        'hash': _evmHash,
        'from': _evmFrom,
        'nonce': '0x7',
      },
    });
    String? observedNonce;
    final service = TransactionStatusService(
      endpoints: (_) => 'https://rpc.example',
      jsonRpcTransport: rpc,
      restTransport: _Rest(null),
      onEvmNonceObserved: (transaction, nonce) async {
        observedNonce = nonce;
      },
    );

    expect(
      await service.check(_tx(Coin.bnb.name, _evmHash, fromAddr: _evmFrom)),
      ChainTransactionStatus.pending,
    );
    expect(observedNonce, '7');
  });

  test(
    'gateway pending EVM backfills missing nonce from direct evidence',
    () async {
      final gateway = GatewayClient(
        baseUrl: 'https://gateway.example',
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': body['id'],
              'result': {'status': 'pending'},
            }),
            200,
          );
        }),
      );
      final rpc = _JsonRpc({
        'eth_getTransactionReceipt': null,
        'eth_getTransactionByHash': {
          'hash': _evmHash,
          'from': _evmFrom,
          'nonce': '0x9',
        },
      });
      String? observedNonce;
      final service = TransactionStatusService(
        endpoints: (_) => 'https://rpc.example',
        gateway: () => gateway,
        jsonRpcTransport: rpc,
        restTransport: _Rest(null),
        onEvmNonceObserved: (transaction, nonce) async {
          observedNonce = nonce;
        },
      );

      expect(
        await service.check(_tx(Coin.eth.name, _evmHash, fromAddr: _evmFrom)),
        ChainTransactionStatus.pending,
      );
      expect(observedNonce, '9');
      expect(rpc.methods, [
        'eth_getTransactionReceipt',
        'eth_getTransactionByHash',
      ]);
    },
  );

  test(
    'EVM remote nonce mismatch is unknown and never overwrites evidence',
    () async {
      final rpc = _JsonRpc({
        'eth_getTransactionReceipt': null,
        'eth_getTransactionByHash': {
          'hash': _evmHash,
          'from': _evmFrom,
          'nonce': '0x7',
        },
      });
      var callbackCalled = false;
      final service = TransactionStatusService(
        endpoints: (_) => 'https://rpc.example',
        jsonRpcTransport: rpc,
        restTransport: _Rest(null),
        onEvmNonceObserved: (transaction, nonce) async {
          callbackCalled = true;
        },
      );

      expect(
        await service.check(
          _tx(Coin.eth.name, _evmHash, nonce: '8', fromAddr: _evmFrom),
        ),
        ChainTransactionStatus.unknown,
      );
      expect(callbackCalled, isFalse);
    },
  );

  test(
    'malformed EVM pending nonce stays unknown and is never persisted',
    () async {
      final rpc = _JsonRpc({
        'eth_getTransactionReceipt': null,
        'eth_getTransactionByHash': {
          'hash': _evmHash,
          'from': _evmFrom,
          'nonce': '0x-1',
        },
      });
      var callbackCalled = false;
      final service = TransactionStatusService(
        endpoints: (_) => 'https://rpc.example',
        jsonRpcTransport: rpc,
        restTransport: _Rest(null),
        onEvmNonceObserved: (transaction, nonce) async {
          callbackCalled = true;
        },
      );

      expect(
        await service.check(_tx(Coin.eth.name, _evmHash, fromAddr: _evmFrom)),
        ChainTransactionStatus.unknown,
      );
      expect(callbackCalled, isFalse);
    },
  );

  test('EVM malformed receipt status is unknown, never failed', () async {
    final rpc = _JsonRpc({
      'eth_getTransactionReceipt': _evmReceipt(status: null),
    });
    final service = TransactionStatusService(
      endpoints: (_) => 'https://rpc.example',
      jsonRpcTransport: rpc,
      restTransport: _Rest(null),
    );

    expect(
      await service.check(_tx(Coin.eth.name, _evmHash)),
      ChainTransactionStatus.unknown,
    );
  });

  test(
    'missing EVM hash is replaced only after confirmed nonce advances',
    () async {
      final rpc = _JsonRpc({
        'eth_getTransactionReceipt': null,
        'eth_getTransactionByHash': null,
        'eth_getTransactionCount': '0x8',
      });
      final service = TransactionStatusService(
        endpoints: (_) => 'https://rpc.example',
        jsonRpcTransport: rpc,
        restTransport: _Rest(null),
      );

      expect(
        await service.check(
          _tx(Coin.eth.name, _evmHash, nonce: '7', fromAddr: _evmFrom),
        ),
        ChainTransactionStatus.replaced,
      );
    },
  );

  test('missing EVM hash without nonce evidence remains unknown', () async {
    final rpc = _JsonRpc({
      'eth_getTransactionReceipt': null,
      'eth_getTransactionByHash': null,
    });
    final service = TransactionStatusService(
      endpoints: (_) => 'https://rpc.example',
      jsonRpcTransport: rpc,
      restTransport: _Rest(null),
    );

    expect(
      await service.check(_tx(Coin.eth.name, _evmHash, fromAddr: _evmFrom)),
      ChainTransactionStatus.unknown,
    );
    expect(rpc.methods, isNot(contains('eth_getTransactionCount')));
  });

  test('Solana execution error is failed, not confirmed', () async {
    final rpc = _JsonRpc({
      'getSignatureStatuses': {
        'context': {'slot': 82},
        'value': [
          {
            'slot': 48,
            'confirmations': null,
            'confirmationStatus': 'finalized',
            'err': {'InstructionError': 0},
            'status': {
              'Err': {'InstructionError': 0},
            },
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
      await service.check(_tx(Coin.solana.name, _solanaSignature)),
      ChainTransactionStatus.failed,
    );
  });

  test('processed Solana execution error is not terminal yet', () async {
    final rpc = _JsonRpc({
      'getSignatureStatuses': {
        'context': {'slot': 82},
        'value': [
          {
            'slot': 81,
            'confirmations': 0,
            'confirmationStatus': 'processed',
            'err': {'InstructionError': 0},
            'status': {
              'Err': {'InstructionError': 0},
            },
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
      await service.check(_tx(Coin.solana.name, _solanaSignature)),
      ChainTransactionStatus.pending,
    );
  });

  test(
    'malformed Solana status stays unknown and never invents confirmation',
    () async {
      final rpc = _JsonRpc({
        'getSignatureStatuses': {
          'value': [
            {'confirmationStatus': 'finalized', 'err': null},
          ],
        },
        'getBlockHeight': 101,
      });
      final service = TransactionStatusService(
        endpoints: (_) => 'https://rpc.example',
        jsonRpcTransport: rpc,
        restTransport: _Rest(null),
      );

      expect(
        await service.check(
          _tx(Coin.solana.name, _solanaSignature, lastValidBlockHeight: 100),
        ),
        ChainTransactionStatus.unknown,
      );
      expect(rpc.methods, ['getSignatureStatuses']);
    },
  );

  test(
    'known Solana status with nullable confirmation never expires as missing',
    () async {
      final rpc = _JsonRpc({
        'getSignatureStatuses': {
          'context': {'slot': 82},
          'value': [
            {
              'slot': 48,
              'confirmations': 0,
              'confirmationStatus': null,
              'err': null,
              'status': {'Ok': null},
            },
          ],
        },
        'getBlockHeight': 101,
      });
      final service = TransactionStatusService(
        endpoints: (_) => 'https://rpc.example',
        jsonRpcTransport: rpc,
        restTransport: _Rest(null),
      );

      expect(
        await service.check(
          _tx(Coin.solana.name, _solanaSignature, lastValidBlockHeight: 100),
        ),
        ChainTransactionStatus.pending,
      );
      expect(rpc.methods, ['getSignatureStatuses']);
    },
  );

  test(
    'missing Solana signature expires only beyond persisted block height',
    () async {
      final rpc = _JsonRpc({
        'getSignatureStatuses': {
          'context': {'slot': 100},
          'value': [null],
        },
        'getBlockHeight': 101,
      });
      final service = TransactionStatusService(
        endpoints: (_) => 'https://rpc.example',
        jsonRpcTransport: rpc,
        restTransport: _Rest(null),
      );

      expect(
        await service.check(
          _tx(Coin.solana.name, _solanaSignature, lastValidBlockHeight: 100),
        ),
        ChainTransactionStatus.expired,
      );
      expect(rpc.methods, ['getSignatureStatuses', 'getBlockHeight']);
    },
  );

  test('Solana remains unknown at its last valid block height', () async {
    final rpc = _JsonRpc({
      'getSignatureStatuses': {
        'context': {'slot': 100},
        'value': [null],
      },
      'getBlockHeight': 100,
    });
    final service = TransactionStatusService(
      endpoints: (_) => 'https://rpc.example',
      jsonRpcTransport: rpc,
      restTransport: _Rest(null),
    );

    expect(
      await service.check(
        _tx(Coin.solana.name, _solanaSignature, lastValidBlockHeight: 100),
      ),
      ChainTransactionStatus.unknown,
    );
  });

  test('TRON full-node receipt confirms without TronGrid history', () async {
    final service = TransactionStatusService(
      endpoints: (_) => 'https://tron.example',
      jsonRpcTransport: _JsonRpc(const {}),
      restTransport: _Rest({
        'id': _tronHash,
        'blockNumber': 42,
        'receipt': {'result': 'SUCCESS'},
      }),
    );

    expect(
      await service.check(_tx(Coin.tron.name, _tronHash)),
      ChainTransactionStatus.confirmed,
    );
  });

  test('TRON receipt for another txID is unknown, never confirmed', () async {
    final service = TransactionStatusService(
      endpoints: (_) => 'https://tron.example',
      jsonRpcTransport: _JsonRpc(const {}),
      restTransport: _Rest({
        'id': _otherTronHash,
        'blockNumber': 42,
        'receipt': {'result': 'SUCCESS'},
      }),
    );

    expect(
      await service.check(_tx(Coin.tron.name, _tronHash)),
      ChainTransactionStatus.unknown,
    );
  });

  test(
    'TRON native transfer verifies omitted receipt result via tx ret',
    () async {
      final rest = _Rest.onPost((url, _) {
        if (url.endsWith('/wallet/gettransactioninfobyid')) {
          return {
            'id': _tronHash,
            'blockNumber': 42,
            'receipt': <String, Object?>{},
          };
        }
        if (url.endsWith('/wallet/gettransactionbyid')) {
          return {
            'txID': _tronHash,
            'ret': [
              {'contractRet': 'SUCCESS'},
            ],
          };
        }
        return null;
      });
      final service = TransactionStatusService(
        endpoints: (_) => 'https://tron.example',
        jsonRpcTransport: _JsonRpc(const {}),
        restTransport: rest,
      );

      expect(
        await service.check(_tx(Coin.tron.name, _tronHash)),
        ChainTransactionStatus.confirmed,
      );
    },
  );

  test('missing TRON hash expires against canonical block time', () async {
    final service = TransactionStatusService(
      endpoints: (_) => 'https://tron.example',
      jsonRpcTransport: _JsonRpc(const {}),
      restTransport: _Rest.onPost((url, body) {
        if (url.endsWith('/wallet/gettransactioninfobyid')) return {};
        if (url.endsWith('/wallet/getnowblock')) {
          return {
            'blockID': List<String>.filled(32, '00').join(),
            'block_header': {
              'raw_data': {'number': 99, 'timestamp': 2001},
            },
          };
        }
        throw StateError(url);
      }),
    );

    expect(
      await service.check(_tx(Coin.tron.name, 'hash', expiresAt: 2000)),
      ChainTransactionStatus.expired,
    );
  });

  test('missing TRON hash remains unknown before expiration', () async {
    final service = TransactionStatusService(
      endpoints: (_) => 'https://tron.example',
      jsonRpcTransport: _JsonRpc(const {}),
      restTransport: _Rest.onPost((url, body) {
        if (url.endsWith('/wallet/gettransactioninfobyid')) return {};
        return {
          'blockID': List<String>.filled(32, '00').join(),
          'block_header': {
            'raw_data': {'number': 99, 'timestamp': 2000},
          },
        };
      }),
    );

    expect(
      await service.check(_tx(Coin.tron.name, 'hash', expiresAt: 2000)),
      ChainTransactionStatus.unknown,
    );
  });
}
