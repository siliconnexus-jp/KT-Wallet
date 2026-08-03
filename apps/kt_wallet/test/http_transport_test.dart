import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:chains/rpc.dart';
import 'package:kt_wallet/src/rpc/http_transport.dart';

Map<String, Object?> _rpc(String method) => {
  'jsonrpc': '2.0',
  'id': 1,
  'method': method,
  'params': const <Object?>[],
};

Map<String, Object?> _rpcResult(Object? result, {Object id = 1}) => {
  'jsonrpc': '2.0',
  'id': id,
  'result': result,
};

void main() {
  test('identical concurrent read RPCs share one HTTP exchange', () async {
    final release = Completer<void>();
    var calls = 0;
    final transport = HttpJsonRpcTransport(
      client: MockClient((request) async {
        calls++;
        await release.future;
        return http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': '0x1'}),
          200,
        );
      }),
    );
    addTearDown(transport.close);

    final first = transport.post('https://rpc.example', _rpc('eth_chainId'));
    final second = transport.post('https://rpc.example', _rpc('eth_chainId'));
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);

    release.complete();
    expect(await first, await second);
  });

  test('broadcast methods are never deduplicated', () async {
    var calls = 0;
    final transport = HttpJsonRpcTransport(
      client: MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': '0xhash'}),
          200,
        );
      }),
    );
    addTearDown(transport.close);
    final body = _rpc('eth_sendRawTransaction');

    await Future.wait([
      transport.post('https://rpc.example', body),
      transport.post('https://rpc.example', body),
    ]);

    expect(calls, 2);
  });

  test('JSON-RPC responses must bind the exact request envelope', () async {
    final malformed = <Map<String, Object?>>[
      {'jsonrpc': '2.0', 'id': 2, 'result': '0x1'},
      {'jsonrpc': '2.0', 'id': 1.0, 'result': '0x1'},
      {'jsonrpc': '2.0', 'result': '0x1'},
      {'jsonrpc': '1.0', 'id': 1, 'result': '0x1'},
      {'jsonrpc': '2.0', 'id': 1, 'result': '0x1', 'error': null},
      {'jsonrpc': '2.0', 'id': 1},
    ];

    for (final response in malformed) {
      final transport = HttpJsonRpcTransport(
        client: MockClient(
          (_) async => http.Response(jsonEncode(response), 200),
        ),
      );
      addTearDown(transport.close);

      await expectLater(
        transport.post('https://rpc.example', _rpc('eth_getBalance')),
        throwsA(
          isA<RpcException>().having(
            (error) => error.message,
            'bounded public error',
            'malformed JSON-RPC response',
          ),
        ),
        reason: '$response must not be attributed to request id 1',
      );
    }
  });

  test(
    'JSON-RPC envelope accepts matching string ids and null results',
    () async {
      final transport = HttpJsonRpcTransport(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          return http.Response(
            jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': null}),
            200,
          );
        }),
      );
      addTearDown(transport.close);

      final response = await transport.post('https://rpc.example', {
        ..._rpc('eth_getTransactionReceipt'),
        'id': 'wallet-1',
      });
      expect(response, {'jsonrpc': '2.0', 'id': 'wallet-1', 'result': null});
    },
  );

  test(
    'a mismatched broadcast response stays outcome-unknown and single-shot',
    () async {
      var calls = 0;
      final transport = HttpJsonRpcTransport(
        client: MockClient((_) async {
          calls++;
          return http.Response(
            jsonEncode({'jsonrpc': '2.0', 'id': 2, 'result': '0xhash'}),
            200,
          );
        }),
      );
      addTearDown(transport.close);

      await expectLater(
        transport.post(
          'https://ethereum-sepolia-rpc.publicnode.com',
          _rpc('eth_sendRawTransaction'),
        ),
        throwsA(isA<RpcException>()),
      );
      expect(calls, 1);
    },
  );

  test(
    'unknown JSON-RPC methods default to one endpoint and one attempt',
    () async {
      final urls = <Uri>[];
      final transport = HttpJsonRpcTransport(
        client: MockClient((request) async {
          urls.add(request.url);
          return http.Response('response lost', 503);
        }),
      );
      addTearDown(transport.close);

      await expectLater(
        transport.post(
          'https://ethereum-sepolia-rpc.publicnode.com',
          _rpc('future_writeMethod'),
        ),
        throwsA(isA<RpcException>()),
      );

      expect(urls, [Uri.parse('https://ethereum-sepolia-rpc.publicnode.com')]);
    },
  );

  test('EVM broadcast HTTP failure never fails over to another RPC', () async {
    final urls = <Uri>[];
    final transport = HttpJsonRpcTransport(
      client: MockClient((request) async {
        urls.add(request.url);
        return http.Response('unavailable', 503);
      }),
    );
    addTearDown(transport.close);

    await expectLater(
      transport.post(
        'https://ethereum-sepolia-rpc.publicnode.com',
        _rpc('eth_sendRawTransaction'),
      ),
      throwsA(isA<RpcException>()),
    );

    expect(urls, [Uri.parse('https://ethereum-sepolia-rpc.publicnode.com')]);
  });

  test(
    'Solana broadcast HTTP failure never fails over to another RPC',
    () async {
      final urls = <Uri>[];
      final transport = HttpJsonRpcTransport(
        client: MockClient((request) async {
          urls.add(request.url);
          return http.Response('unavailable', 503);
        }),
      );
      addTearDown(transport.close);

      await expectLater(
        transport.post(
          'https://api.devnet.solana.com',
          _rpc('sendTransaction'),
        ),
        throwsA(isA<RpcException>()),
      );

      expect(urls, [Uri.parse('https://api.devnet.solana.com')]);
    },
  );

  test('TRON broadcast HTTP failure never fails over to TronStack', () async {
    final urls = <Uri>[];
    final transport = HttpRestTransport(
      client: MockClient((request) async {
        urls.add(request.url);
        return http.Response('unavailable', 503);
      }),
    );
    addTearDown(transport.close);

    await expectLater(
      transport.postJson(
        'https://nile.trongrid.io/wallet/broadcasttransaction',
        const {
          'signature': ['aa'],
        },
      ),
      throwsA(isA<RpcException>()),
    );

    expect(urls, [
      Uri.parse('https://nile.trongrid.io/wallet/broadcasttransaction'),
    ]);
  });

  test('unknown TRON POST defaults to one endpoint and one attempt', () async {
    final urls = <Uri>[];
    final transport = HttpRestTransport(
      client: MockClient((request) async {
        urls.add(request.url);
        return http.Response('response lost', 503);
      }),
    );
    addTearDown(transport.close);

    await expectLater(
      transport.postJson('https://nile.trongrid.io/wallet/futurewrite', const {
        'value': 1,
      }),
      throwsA(isA<RpcException>()),
    );

    expect(urls, [Uri.parse('https://nile.trongrid.io/wallet/futurewrite')]);
  });

  test('read RPC failures retain endpoint failover', () async {
    final urls = <Uri>[];
    final transport = HttpJsonRpcTransport(
      client: MockClient((request) async {
        urls.add(request.url);
        if (urls.length == 1) return http.Response('unavailable', 503);
        final body = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(
          jsonEncode(_rpcResult('0xaa36a7', id: body['id']!)),
          200,
        );
      }),
    );
    addTearDown(transport.close);

    final result = await transport.post(
      'https://ethereum-sepolia-rpc.publicnode.com',
      _rpc('eth_chainId'),
    );

    expect(result, isA<Map<Object?, Object?>>());
    // The fallback receives a chain-identity probe before the original read.
    expect(urls, hasLength(3));
    expect(urls.first.host, 'ethereum-sepolia-rpc.publicnode.com');
    expect(urls.last.host, 'rpc.sepolia.org');
  });

  test(
    'wrong-chain EVM fallback is skipped before wallet metadata is sent',
    () async {
      final calls = <(String host, String method)>[];
      final transport = HttpJsonRpcTransport(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          final method = body['method']! as String;
          calls.add((request.url.host, method));
          if (request.url.host == 'ethereum-sepolia-rpc.publicnode.com') {
            return http.Response('unavailable', 503);
          }
          if (request.url.host == 'rpc.sepolia.org') {
            expect(method, 'eth_chainId');
            return http.Response(
              jsonEncode(_rpcResult('0x1', id: body['id']!)),
              200,
            );
          }
          if (method == 'eth_chainId') {
            return http.Response(
              jsonEncode(_rpcResult('0xaa36a7', id: body['id']!)),
              200,
            );
          }
          return http.Response(
            jsonEncode(_rpcResult('0x2', id: body['id']!)),
            200,
          );
        }),
      );
      addTearDown(transport.close);

      final result = await transport.post(
        'https://ethereum-sepolia-rpc.publicnode.com',
        _rpc('eth_getBalance'),
      );

      expect((result as Map)['result'], '0x2');
      expect(calls, [
        ('ethereum-sepolia-rpc.publicnode.com', 'eth_getBalance'),
        ('rpc.sepolia.org', 'eth_chainId'),
        ('1rpc.io', 'eth_chainId'),
        ('1rpc.io', 'eth_getBalance'),
      ]);
    },
  );

  test(
    'BNB Testnet read has an independently operated verified fallback',
    () async {
      final calls = <(String host, String method)>[];
      final transport = HttpJsonRpcTransport(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          final method = body['method']! as String;
          calls.add((request.url.host, method));
          if (request.url.host == 'bsc-testnet-dataseed.bnbchain.org') {
            return http.Response('unavailable', 503);
          }
          return http.Response(
            jsonEncode(
              _rpcResult(
                method == 'eth_chainId' ? '0x61' : '0x5',
                id: body['id']!,
              ),
            ),
            200,
          );
        }),
      );
      addTearDown(transport.close);

      final result = await transport.post(
        'https://bsc-testnet-dataseed.bnbchain.org',
        _rpc('eth_getBalance'),
      );

      expect((result as Map)['result'], '0x5');
      expect(calls, [
        ('bsc-testnet-dataseed.bnbchain.org', 'eth_getBalance'),
        ('bsc-testnet.drpc.org', 'eth_chainId'),
        ('bsc-testnet.drpc.org', 'eth_getBalance'),
      ]);
    },
  );

  test('wrong Solana genesis is rejected before the address read', () async {
    final methods = <String>[];
    final transport = HttpJsonRpcTransport(
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        final method = body['method']! as String;
        methods.add(method);
        if (request.url.host == 'api.mainnet-beta.solana.com') {
          return http.Response('unavailable', 503);
        }
        expect(method, 'getGenesisHash');
        return http.Response(
          jsonEncode(_rpcResult('wrong-genesis', id: body['id']!)),
          200,
        );
      }),
    );
    addTearDown(transport.close);

    await expectLater(
      transport.post('https://api.mainnet-beta.solana.com', _rpc('getBalance')),
      throwsA(isA<RpcException>()),
    );
    expect(methods, ['getBalance', 'getGenesisHash']);
  });

  test('TRON fallback verifies block zero before sending an address', () async {
    final calls = <(String host, String method, String path)>[];
    final transport = HttpRestTransport(
      client: MockClient((request) async {
        calls.add((request.url.host, request.method, request.url.path));
        if (request.url.host == 'nile.trongrid.io') {
          return http.Response('unavailable', 503);
        }
        if (request.url.path == '/wallet/getblockbynum') {
          return http.Response(
            jsonEncode({
              'blockID':
                  '0000000000000000d698d4192c56cb6be724a558448e2684802de4d6cd8690dc',
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'data': <Object?>[]}), 200);
      }),
    );
    addTearDown(transport.close);

    final result = await transport.getJson(
      'https://nile.trongrid.io/v1/accounts/TAddress/transactions',
    );

    expect(result, isA<Map<Object?, Object?>>());
    expect(calls, [
      ('nile.trongrid.io', 'GET', '/v1/accounts/TAddress/transactions'),
      ('nile.tronstack.io', 'POST', '/wallet/getblockbynum'),
      ('nile.tronstack.io', 'GET', '/v1/accounts/TAddress/transactions'),
    ]);
  });

  test('wrong TRON genesis never receives the address request', () async {
    final paths = <String>[];
    final transport = HttpRestTransport(
      client: MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.host == 'nile.trongrid.io') {
          return http.Response('unavailable', 503);
        }
        return http.Response(jsonEncode({'blockID': 'wrong'}), 200);
      }),
    );
    addTearDown(transport.close);

    await expectLater(
      transport.getJson(
        'https://nile.trongrid.io/v1/accounts/TPrivate/transactions',
      ),
      throwsA(isA<RpcException>()),
    );
    expect(paths, [
      '/v1/accounts/TPrivate/transactions',
      '/wallet/getblockbynum',
    ]);
  });

  test('a completed read is not cached forever', () async {
    var calls = 0;
    final transport = HttpJsonRpcTransport(
      client: MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': calls}),
          200,
        );
      }),
    );
    addTearDown(transport.close);
    final body = _rpc('eth_getBalance');

    await transport.post('https://rpc.example', body);
    await transport.post('https://rpc.example', body);

    expect(calls, 2);
  });

  test(
    'JSON-RPC transport errors never expose credential-bearing URLs',
    () async {
      const canary = 'rpc-provider-secret-canary';
      final transport = HttpJsonRpcTransport(
        client: MockClient((request) async {
          throw http.ClientException('connection refused', request.url);
        }),
      );
      addTearDown(transport.close);

      Object? thrown;
      try {
        await transport.post(
          'https://rpc.example/v2/$canary',
          _rpc('eth_sendRawTransaction'),
        );
      } on Object catch (error) {
        thrown = error;
      }

      expect(thrown, isA<RpcException>());
      expect(thrown.toString(), isNot(contains(canary)));
      expect(thrown.toString(), isNot(contains('rpc.example')));
    },
  );

  test('REST transport errors never expose credential-bearing URLs', () async {
    const canary = 'tron-provider-secret-canary';
    final transport = HttpRestTransport(
      client: MockClient((request) async {
        throw http.ClientException('connection refused', request.url);
      }),
    );
    addTearDown(transport.close);

    Object? thrown;
    try {
      await transport.postJson(
        'https://tron.example/$canary/wallet/broadcasttransaction',
        const {
          'signature': <String>['aa'],
        },
      );
    } on Object catch (error) {
      thrown = error;
    }

    expect(thrown, isA<RpcException>());
    expect(thrown.toString(), isNot(contains(canary)));
    expect(thrown.toString(), isNot(contains('tron.example')));
  });
}
