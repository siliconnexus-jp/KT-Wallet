import 'dart:async';
import 'dart:convert';

import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kt_wallet/src/market/gateway_client.dart';

/// GatewayClient against the fixed protocol contract: exact request JSON
/// (JSON-RPC 2.0, no batches, `POST {url}/rpc`), typed result parsing per
/// method, and JSON-RPC error → [GatewayException] mapping.

/// Records every request body and serves scripted results/errors.
class _Recorder {
  final requests = <Map<String, Object?>>[];

  /// Scripted JSON-RPC `result` per method.
  Map<String, Object?> results = {};

  /// Scripted JSON-RPC `error` object per method (wins over [results]).
  Map<String, Object?> errors = {};

  late final client = MockClient((request) async {
    expect(request.method, 'POST');
    expect(request.url.toString(), 'https://gw.example/rpc');
    expect(request.headers['content-type'], startsWith('application/json'));
    final body = jsonDecode(request.body) as Map<String, Object?>;
    requests.add(body);
    final method = body['method'] as String;
    final error = errors[method];
    if (error != null) {
      return http.Response(
        jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'error': error}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': body['id'],
        'result': results[method],
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
}

void main() {
  group('GatewayClient request framing', () {
    test(
      'JSON-RPC 2.0 envelope: jsonrpc/id/method/params, POST {url}/rpc',
      () async {
        final recorder = _Recorder()
          ..results = {
            'kt_health': {'ok': true, 'version': '1.0.0'},
          };
        // Trailing slash is normalized away (requests still hit {url}/rpc).
        final client = GatewayClient(
          baseUrl: 'https://gw.example/',
          client: recorder.client,
        );

        expect(await client.health(), isTrue);
        expect(await client.health(), isTrue);

        expect(recorder.requests, hasLength(2));
        final first = recorder.requests[0];
        expect(first['jsonrpc'], '2.0');
        expect(first['method'], 'kt_health');
        expect(first['id'], isA<int>());
        expect(first.containsKey('params'), isFalse); // kt_health takes none
        // ids are unique per call (no batches, but still well-formed JSON-RPC).
        expect(recorder.requests[1]['id'], isNot(first['id']));
      },
    );

    test(
      'health(): false on {ok:false}, error answers and transport failure',
      () async {
        final recorder = _Recorder()
          ..results = {
            'kt_health': {'ok': false},
          };
        expect(
          await GatewayClient(
            baseUrl: 'https://gw.example',
            client: recorder.client,
          ).health(),
          isFalse,
        );

        recorder.errors = {
          'kt_health': {'code': -32601, 'message': 'method not found'},
        };
        expect(
          await GatewayClient(
            baseUrl: 'https://gw.example',
            client: recorder.client,
          ).health(),
          isFalse,
        );

        final dead = MockClient((request) async => http.Response('down', 503));
        expect(
          await GatewayClient(
            baseUrl: 'https://gw.example',
            client: dead,
          ).health(),
          isFalse,
        );
      },
    );

    test(
      'timeout surfaces as an exception (10s default is configurable)',
      () async {
        final slow = MockClient((request) async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          return http.Response('{}', 200);
        });
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: slow,
          timeout: const Duration(milliseconds: 1),
        );
        await expectLater(
          client.getPrices(const ['ETH']),
          throwsA(isA<TimeoutException>()),
        );
      },
    );

    test(
      'non-200 HTTP status throws (transport failure, not GatewayException)',
      () async {
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: MockClient((request) async => http.Response('oops', 502)),
        );
        await expectLater(
          client.getPrices(const ['ETH']),
          throwsA(isA<http.ClientException>()),
        );
      },
    );
  });

  group('kt_getBalances', () {
    test(
      'exact params and typed native + per-token rows (incl. errors)',
      () async {
        final recorder = _Recorder()
          ..results = {
            'kt_getBalances': {
              'native': {
                'raw': '1000000000000000000',
                'decimals': 18,
                'symbol': 'ETH',
              },
              'tokens': [
                {
                  'contract': '0xdAC17F958D2ee523a2206206994597C13D831ec7',
                  'raw': '120500000',
                  'decimals': 6,
                  'symbol': 'USDT',
                },
                {
                  'contract': '0xBadToken',
                  'raw': '0',
                  'decimals': 6,
                  'symbol': 'BAD',
                  'error': 'execution reverted',
                },
              ],
            },
          };
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
        );

        final balances = await client.getBalances(
          chain: Coin.eth,
          address: '0xEthAddr',
          tokens: const [
            GatewayTokenQuery(
              contract: '0xdAC17F958D2ee523a2206206994597C13D831ec7',
              decimals: 6,
              symbol: 'USDT',
            ),
            GatewayTokenQuery(
              contract: '0xBadToken',
              decimals: 6,
              symbol: 'BAD',
            ),
          ],
        );

        expect(recorder.requests.single['params'], {
          'chain': 'eth',
          'address': '0xEthAddr',
          'tokens': [
            {
              'contract': '0xdAC17F958D2ee523a2206206994597C13D831ec7',
              'decimals': 6,
              'symbol': 'USDT',
            },
            {'contract': '0xBadToken', 'decimals': 6, 'symbol': 'BAD'},
          ],
        });
        expect(balances.native.raw, BigInt.parse('1000000000000000000'));
        expect(balances.native.decimals, 18);
        expect(balances.native.symbol, 'ETH');
        expect(balances.tokens, hasLength(2));
        expect(balances.tokens[0].raw, BigInt.from(120500000));
        expect(balances.tokens[0].error, isNull);
        // Per-token error: no raw value, the error string is preserved.
        expect(balances.tokens[1].error, 'execution reverted');
        expect(balances.tokens[1].raw, isNull);
      },
    );

    test(
      'native-only call omits the tokens param; chain names match the enum',
      () async {
        final recorder = _Recorder()
          ..results = {
            'kt_getBalances': {
              'native': {'raw': '5000000', 'decimals': 6, 'symbol': 'TRX'},
            },
          };
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
        );
        final balances = await client.getBalances(
          chain: Coin.tron,
          address: 'TTronAddr',
        );
        expect(recorder.requests.single['params'], {
          'chain': 'tron',
          'address': 'TTronAddr',
        });
        expect(balances.native.raw, BigInt.from(5000000));
        expect(balances.tokens, isEmpty);
        // The wire names of every supported chain.
        expect(Coin.values.map(GatewayClient.chainName), [
          'eth',
          'polygon',
          'base',
          'arbitrum',
          'avalanche',
          'bnb',
          'tron',
          'solana',
        ]);
      },
    );

    test('malformed result (missing native) throws FormatException', () async {
      final recorder = _Recorder()
        ..results = {
          'kt_getBalances': {'tokens': <Object?>[]},
        };
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: recorder.client,
      );
      await expectLater(
        client.getBalances(chain: Coin.eth, address: '0xA'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('kt_getPrices', () {
    test(
      'exact params; unknown symbols omitted by the gateway stay absent',
      () async {
        final recorder = _Recorder()
          ..results = {
            'kt_getPrices': {
              'prices': {
                'ETH': {'usd': 2500.5, 'change24h': 3.25},
                'TRX': {'usd': 0.12, 'change24h': -1.5},
              },
              'cachedAtMs': 1753000000000,
            },
          };
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
        );
        final prices = await client.getPrices(const [
          'ETH',
          'POL',
          'TRX',
          'SOL',
        ]);

        expect(recorder.requests.single['params'], {
          'symbols': ['ETH', 'POL', 'TRX', 'SOL'],
        });
        expect(prices.usdBySymbol, {'ETH': 2500.5, 'TRX': 0.12});
        expect(prices.change24hBySymbol, {'ETH': 3.25, 'TRX': -1.5});
        expect(prices.cachedAtMs, 1753000000000);
      },
    );
  });

  group('kt_getChainParams', () {
    test(
      'decimal nonce and three fee tiers parse into chains/rpc types',
      () async {
        final recorder = _Recorder()
          ..results = {
            'kt_getChainParams': {
              'nonce': '42',
              'fees': {
                'slow': {
                  'maxPriorityFeePerGas': '1000000000',
                  'maxFeePerGas': '20000000000',
                },
                'standard': {
                  'maxPriorityFeePerGas': '2000000000',
                  'maxFeePerGas': '30000000000',
                },
                'fast': {
                  'maxPriorityFeePerGas': '3000000000',
                  'maxFeePerGas': '40000000000',
                },
              },
            },
          };
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
        );
        final params = await client.getChainParams(
          chain: Coin.polygon,
          address: '0xFrom',
        );

        expect(recorder.requests.single['params'], {
          'chain': 'polygon',
          'address': '0xFrom',
        });
        expect(params.nonce, 42);
        expect(params.fees.slow.maxPriorityFeePerGas, BigInt.from(1000000000));
        expect(params.fees.standard.maxFeePerGas, BigInt.from(30000000000));
        expect(params.fees.fast.maxPriorityFeePerGas, BigInt.from(3000000000));
      },
    );

    test('-32602 for a non-EVM chain surfaces as GatewayException', () async {
      final recorder = _Recorder()
        ..errors = {
          'kt_getChainParams': {'code': -32602, 'message': 'invalid params'},
        };
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: recorder.client,
      );
      await expectLater(
        client.getChainParams(chain: Coin.tron, address: 'T...'),
        throwsA(
          isA<GatewayException>()
              .having((e) => e.code, 'code', -32602)
              .having((e) => e.isUnsupported, 'isUnsupported', isFalse),
        ),
      );
    });
  });

  group('kt_getHistory', () {
    test('ok status with records; malformed rows are skipped', () async {
      final recorder = _Recorder()
        ..results = {
          'kt_getHistory': {
            'status': 'ok',
            'records': [
              {
                'hash': '0xaaa',
                'direction': 'out',
                'amountRaw': '1500000000000000000',
                'decimals': 18,
                'symbol': 'ETH',
                'timestampMs': 1753000000000,
                'status': 'ok',
              },
              {
                'hash': '0xbbb',
                'direction': 'in',
                'amountRaw': '2000000',
                'decimals': 6,
                'symbol': 'USDT',
                'timestampMs': 1752000000000,
                'status': 'failed',
              },
              {'direction': 'in', 'timestampMs': 1}, // no hash → skipped
            ],
          },
        };
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: recorder.client,
      );
      final history = await client.getHistory(
        chain: Coin.eth,
        address: '0xEthAddr',
        limit: 20,
      );

      expect(recorder.requests.single['params'], {
        'chain': 'eth',
        'address': '0xEthAddr',
        'limit': 20,
      });
      expect(history.unsupported, isFalse);
      expect(history.records, hasLength(2));
      expect(history.records[0].hash, '0xaaa');
      expect(history.records[0].outgoing, isTrue);
      expect(history.records[0].failed, isFalse);
      expect(history.records[0].amountRaw, BigInt.parse('1500000000000000000'));
      expect(history.records[1].outgoing, isFalse);
      expect(history.records[1].failed, isTrue);
    });

    test('status unsupported maps to the typed unsupported result', () async {
      final recorder = _Recorder()
        ..results = {
          'kt_getHistory': {'status': 'unsupported', 'records': <Object?>[]},
        };
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: recorder.client,
      );
      final history = await client.getHistory(
        chain: Coin.solana,
        address: 'SolAddr',
      );
      expect(history.unsupported, isTrue);
      expect(history.records, isEmpty);
    });
  });

  group('kt_broadcast and error mapping', () {
    test('payload passthrough and txHash back', () async {
      final recorder = _Recorder()
        ..results = {
          'kt_broadcast': {'txHash': '0xfeedbead'},
        };
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: recorder.client,
      );
      final hash = await client.broadcast(chain: Coin.eth, payload: '0x02ab01');
      expect(hash, '0xfeedbead');
      expect(recorder.requests.single['params'], {
        'chain': 'eth',
        'payload': '0x02ab01',
      });
    });

    test(
      '-32000 upstream_error surfaces the node message and upstream',
      () async {
        final recorder = _Recorder()
          ..errors = {
            'kt_broadcast': {
              'code': -32000,
              'message': 'upstream_error',
              'data': {'upstream': 'eth-node', 'message': 'nonce too low'},
            },
          };
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
        );
        await expectLater(
          client.broadcast(chain: Coin.eth, payload: '0x02'),
          throwsA(
            isA<GatewayException>()
                .having((e) => e.code, 'code', -32000)
                .having((e) => e.isUpstreamError, 'isUpstreamError', isTrue)
                .having((e) => e.message, 'message', 'upstream_error')
                .having((e) => e.upstream, 'upstream', 'eth-node')
                .having(
                  (e) => e.upstreamMessage,
                  'upstreamMessage',
                  'nonce too low',
                ),
          ),
        );
      },
    );

    test(
      '-32002 unsupported and -32001 rate_limited map onto the flags',
      () async {
        final recorder = _Recorder()
          ..errors = {
            'kt_getHistory': {'code': -32002, 'message': 'unsupported'},
            'kt_getPrices': {'code': -32001, 'message': 'rate_limited'},
          };
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
        );
        await expectLater(
          client.getHistory(chain: Coin.eth, address: '0xA'),
          throwsA(
            isA<GatewayException>()
                .having((e) => e.isUnsupported, 'isUnsupported', isTrue)
                .having((e) => e.isUpstreamError, 'isUpstreamError', isFalse),
          ),
        );
        await expectLater(
          client.getPrices(const ['ETH']),
          throwsA(
            isA<GatewayException>().having((e) => e.code, 'code', -32001),
          ),
        );
      },
    );
  });
}
