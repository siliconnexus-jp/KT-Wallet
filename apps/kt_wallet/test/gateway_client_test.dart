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

const _evmFrom = '0x1111111111111111111111111111111111111111';
const _evmTo = '0x2222222222222222222222222222222222222222';
const _evmToken = '0xdAC17F958D2ee523a2206206994597C13D831ec7';
const _evmHash =
    '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _tronHash =
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
const _solanaSignature =
    '1111111111111111111111111111111111111111111111111111111111111111';
const _tronOwner = 'TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH';
const _solanaOwner = '11111111111111111111111111111111';

Map<String, Object?> _chainParamsResult({
  String network = 'eth-mainnet',
  String address = _evmFrom,
  String nonce = '42',
}) => {
  'network': network,
  'address': address,
  'nonce': nonce,
  'fees': <String, Object?>{
    'slow': <String, Object?>{
      'maxPriorityFeePerGas': '1000000000',
      'maxFeePerGas': '20000000000',
    },
    'standard': <String, Object?>{
      'maxPriorityFeePerGas': '2000000000',
      'maxFeePerGas': '30000000000',
    },
    'fast': <String, Object?>{
      'maxPriorityFeePerGas': '3000000000',
      'maxFeePerGas': '40000000000',
    },
  },
};

Map<String, Object?> _healthyResult({
  List<String> networks = const ['eth-mainnet'],
  String version = '1.0.0',
}) => {
  'ok': true,
  'version': version,
  'networks': networks,
  'upstreams': {for (final network in networks) network: <String, Object?>{}},
};

void main() {
  group('GatewayClient request framing', () {
    test(
      'JSON-RPC 2.0 envelope: jsonrpc/id/method/params, POST {url}/rpc',
      () async {
        final recorder = _Recorder()..results = {'kt_health': _healthyResult()};
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

    test('health rejects ambiguous or authority-expanding results', () async {
      Map<String, Object?> valid() => {
        'ok': true,
        'version': '1.16.25',
        'networks': ['eth-mainnet', 'eth-sepolia'],
        'upstreams': {
          'eth-mainnet': <String, Object?>{},
          'eth-sepolia': <String, Object?>{},
        },
      };

      final additive = valid()..['admin'] = true;
      final duplicateNetwork = valid()
        ..['networks'] = ['eth-mainnet', 'eth-mainnet'];
      final unknownNetwork = valid()..['networks'] = ['custom-operator'];
      final nonStringNetwork = valid()..['networks'] = ['eth-mainnet', 1];
      final emptyNetworks = valid()..['networks'] = <String>[];
      final missingNetworks = valid()..remove('networks');
      final missingUpstreams = valid()..remove('upstreams');
      final badVersion = valid()..['version'] = 'latest';
      final oversizedVersion = valid()
        ..['version'] = '1.0.0+${List<String>.filled(59, 'a').join()}';
      final unknownUpstream = valid()
        ..['upstreams'] = {'custom-operator': <String, Object?>{}};
      final malformedUpstream = valid()..['upstreams'] = {'eth-mainnet': true};

      for (final result in <Map<String, Object?>>[
        additive,
        duplicateNetwork,
        unknownNetwork,
        nonStringNetwork,
        emptyNetworks,
        missingNetworks,
        missingUpstreams,
        badVersion,
        oversizedVersion,
        unknownUpstream,
        malformedUpstream,
      ]) {
        final recorder = _Recorder()..results = {'kt_health': result};
        expect(
          await GatewayClient(
            baseUrl: 'https://gw.example',
            client: recorder.client,
          ).health(),
          isFalse,
          reason: '$result',
        );
      }
    });

    test('timeout becomes a privacy-safe transport exception', () async {
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
        throwsA(isA<GatewayTransportException>()),
      );
    });

    test('non-200 status becomes a privacy-safe transport exception', () async {
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: MockClient((request) async => http.Response('oops', 502)),
      );
      await expectLater(
        client.getPrices(const ['ETH']),
        throwsA(isA<GatewayTransportException>()),
      );
    });

    test('a stale response id is never attributed to a gateway call', () async {
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': (body['id']! as int) + 1,
              'result': {
                'prices': {
                  'ETH': {'usd': 2500},
                },
              },
            }),
            200,
          );
        }),
      );

      await expectLater(
        client.getPrices(const ['ETH']),
        throwsA(isA<GatewayTransportException>()),
      );
    });

    test(
      'duplicate JSON members are rejected before envelope binding',
      () async {
        final responses = <String Function(int)>[
          (id) =>
              '{"jsonrpc":"2.0","id":$id,'
              '"result":{"prices":{"ETH":{"usd":1}}},'
              '"result":{"prices":{"ETH":{"usd":2}}}}',
          (id) =>
              '{"jsonrpc":"2.0","id":$id,'
              '"result":{"prices":{"ETH":{"usd":1}}},'
              r'"re\u0073ult":{"prices":{"ETH":{"usd":2}}}}',
          (id) =>
              '{"jsonrpc":"2.0","id":${id + 1},"id":$id,'
              '"result":{"prices":{"ETH":{"usd":1}}}}',
          (id) =>
              '{"jsonrpc":"2.0","id":$id,"error":{'
              '"code":-32000,"code":-32003,'
              '"message":"submission_unknown"}}',
        ];

        for (final rawResponse in responses) {
          final client = GatewayClient(
            baseUrl: 'https://gw.example',
            client: MockClient((request) async {
              final body = jsonDecode(request.body) as Map<String, Object?>;
              return http.Response(rawResponse(body['id']! as int), 200);
            }),
          );

          await expectLater(
            client.getPrices(const ['ETH']),
            throwsA(isA<GatewayTransportException>()),
          );
        }
      },
    );
  });

  group('kt_getBalances', () {
    test(
      'rejects a balance result bound to another network and owner',
      () async {
        final recorder = _Recorder()
          ..results = {
            'kt_getBalances': {
              'chain': 'polygon',
              'network': 'polygon-mainnet',
              'address': _evmTo,
              'native': {
                'raw': '1000000000000000000',
                'decimals': 18,
                'symbol': 'ETH',
              },
              'tokens': const <Object?>[],
            },
          };
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
        );

        await expectLater(
          client.getBalances(chain: Coin.eth, address: _evmFrom),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test(
      'exact params and typed native + per-token rows (incl. errors)',
      () async {
        final recorder = _Recorder()
          ..results = {
            'kt_getBalances': {
              'chain': 'eth',
              'network': 'eth-mainnet',
              'address': _evmFrom,
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
                  'contract': _evmTo,
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
          address: _evmFrom,
          tokens: const [
            GatewayTokenQuery(
              contract: '0xdAC17F958D2ee523a2206206994597C13D831ec7',
              decimals: 6,
              symbol: 'USDT',
            ),
            GatewayTokenQuery(contract: _evmTo, decimals: 6, symbol: 'BAD'),
          ],
        );

        expect(recorder.requests.single['params'], {
          'chain': 'eth',
          'address': _evmFrom,
          'tokens': [
            {
              'contract': '0xdAC17F958D2ee523a2206206994597C13D831ec7',
              'decimals': 6,
              'symbol': 'USDT',
            },
            {'contract': _evmTo, 'decimals': 6, 'symbol': 'BAD'},
          ],
        });
        expect(balances.native.raw, BigInt.parse('1000000000000000000'));
        expect(balances.native.decimals, 18);
        expect(balances.native.symbol, 'ETH');
        expect(balances.tokens, hasLength(2));
        expect(balances.tokens[0].raw, BigInt.from(120500000));
        expect(balances.tokens[0].error, isNull);
        // Per-token failure keeps only a local stable category.
        expect(balances.tokens[1].error, GatewayTokenBalance.unavailableError);
        expect(balances.tokens[1].raw, isNull);
      },
    );

    test(
      'native-only call omits the tokens param; chain names match the enum',
      () async {
        final recorder = _Recorder()
          ..results = {
            'kt_getBalances': {
              'chain': 'tron',
              'network': 'tron-mainnet',
              'address': _tronOwner,
              'native': {'raw': '5000000', 'decimals': 6, 'symbol': 'TRX'},
              'tokens': const <Object?>[],
            },
          };
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
        );
        final balances = await client.getBalances(
          chain: Coin.tron,
          address: _tronOwner,
        );
        expect(recorder.requests.single['params'], {
          'chain': 'tron',
          'address': _tronOwner,
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

    test('per-token failures never retain provider-controlled text', () async {
      final providerCanary = <String>[
        'provider',
        'token_balance_body_secret',
      ].join('_');
      final recorder = _Recorder()
        ..results = {
          'kt_getBalances': {
            'chain': 'eth',
            'network': 'eth-mainnet',
            'address': _evmFrom,
            'native': {'raw': '1', 'decimals': 18, 'symbol': 'ETH'},
            'tokens': [
              {
                'contract': _evmTo,
                'raw': '0',
                'decimals': 6,
                'symbol': 'BAD',
                'error': providerCanary,
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
        address: _evmFrom,
        tokens: const [
          GatewayTokenQuery(contract: _evmTo, decimals: 6, symbol: 'BAD'),
        ],
      );

      expect(
        balances.tokens.single.error,
        GatewayTokenBalance.unavailableError,
      );
      expect(balances.tokens.single.error, isNot(contains(providerCanary)));
    });

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

    test(
      'rejects unknown fields, non-canonical money and token identity drift',
      () async {
        Map<String, Object?> result({
          String nativeRaw = '1',
          String tokenContract = _evmToken,
          String tokenRaw = '2',
          int tokenDecimals = 6,
          String tokenSymbol = 'USDT',
        }) => <String, Object?>{
          'chain': 'eth',
          'network': 'eth-mainnet',
          'address': _evmFrom,
          'native': <String, Object?>{
            'raw': nativeRaw,
            'decimals': 18,
            'symbol': 'ETH',
          },
          'tokens': <Object?>[
            <String, Object?>{
              'contract': tokenContract,
              'raw': tokenRaw,
              'decimals': tokenDecimals,
              'symbol': tokenSymbol,
            },
          ],
        };

        final extraTop = result()..['trusted'] = true;
        final extraNative = result();
        (extraNative['native'] as Map<String, Object?>)['display'] = '1 ETH';
        final extraToken = result();
        ((extraToken['tokens'] as List).single as Map<String, Object?>)['usd'] =
            1;
        final missingToken = result()..['tokens'] = const <Object?>[];
        final cases = <Map<String, Object?>>[
          extraTop,
          extraNative,
          extraToken,
          missingToken,
          result(nativeRaw: '01'),
          result(tokenRaw: '-1'),
          result(tokenContract: _evmTo),
          result(tokenDecimals: 18),
          result(tokenSymbol: 'USDC'),
        ];

        for (final response in cases) {
          final recorder = _Recorder()..results = {'kt_getBalances': response};
          final client = GatewayClient(
            baseUrl: 'https://gw.example',
            client: recorder.client,
          );
          await expectLater(
            client.getBalances(
              chain: Coin.eth,
              address: _evmFrom,
              tokens: const [
                GatewayTokenQuery(
                  contract: _evmToken,
                  decimals: 6,
                  symbol: 'USDT',
                ),
              ],
            ),
            throwsA(isA<FormatException>()),
          );
          client.close();
        }
      },
    );

    test(
      'rejects native decimals or symbol that contradict the chain',
      () async {
        for (final native in <Map<String, Object?>>[
          {'raw': '1000000000000000000', 'decimals': 0, 'symbol': 'ETH'},
          {'raw': '1000000000000000000', 'decimals': 18, 'symbol': 'BTC'},
        ]) {
          final recorder = _Recorder()
            ..results = {
              'kt_getBalances': {'native': native},
            };
          final client = GatewayClient(
            baseUrl: 'https://gw.example',
            client: recorder.client,
          );
          await expectLater(
            client.getBalances(chain: Coin.eth, address: '0xA'),
            throwsA(isA<FormatException>()),
            reason: 'gateway metadata must not rescale or relabel native money',
          );
        }
      },
    );
  });

  group('kt_getPortfolio', () {
    test('rejects a portfolio row bound to another owner', () async {
      final recorder = _Recorder()
        ..results = {
          'kt_getPortfolio': {
            'accounts': [
              {
                'chain': 'eth',
                'network': 'eth-mainnet',
                'address': _evmTo,
                'result': {
                  'chain': 'eth',
                  'network': 'eth-mainnet',
                  'address': _evmTo,
                  'native': {
                    'raw': '1000000000000000000',
                    'decimals': 18,
                    'symbol': 'ETH',
                  },
                  'tokens': const <Object?>[],
                },
              },
            ],
          },
        };
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: recorder.client,
      );

      await expectLater(
        client.getPortfolio(const [
          GatewayPortfolioQuery(chain: Coin.eth, address: _evmFrom),
        ]),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'rejects additive portfolio fields and duplicate chain requests',
      () async {
        final recorder = _Recorder()
          ..results = {
            'kt_getPortfolio': {
              'accounts': [
                {
                  'chain': 'eth',
                  'network': 'eth-mainnet',
                  'address': _evmFrom,
                  'error': 'upstream unavailable',
                  'trusted': true,
                },
              ],
            },
          };
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
        );
        await expectLater(
          client.getPortfolio(const [
            GatewayPortfolioQuery(chain: Coin.eth, address: _evmFrom),
          ]),
          throwsA(isA<FormatException>()),
        );

        final before = recorder.requests.length;
        await expectLater(
          client.getPortfolio(const [
            GatewayPortfolioQuery(chain: Coin.eth, address: _evmFrom),
            GatewayPortfolioQuery(chain: Coin.eth, address: _evmTo),
          ]),
          throwsA(isA<FormatException>()),
        );
        expect(recorder.requests, hasLength(before));
        client.close();
      },
    );

    test('parses per-chain results and preserves partial failures', () async {
      final recorder = _Recorder()
        ..results = {
          'kt_getPortfolio': {
            'accounts': [
              {
                'chain': 'eth',
                'network': 'eth-mainnet',
                'address': _evmFrom,
                'result': {
                  'chain': 'eth',
                  'network': 'eth-mainnet',
                  'address': _evmFrom,
                  'native': {
                    'raw': '1000000000000000000',
                    'decimals': 18,
                    'symbol': 'ETH',
                  },
                  'tokens': const <Object?>[],
                },
              },
              {
                'chain': 'solana',
                'network': 'sol-mainnet',
                'address': _solanaOwner,
                'error': 'upstream unavailable',
              },
            ],
          },
        };
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: recorder.client,
      );

      final result = await client.getPortfolio(const [
        GatewayPortfolioQuery(chain: Coin.eth, address: _evmFrom),
        GatewayPortfolioQuery(chain: Coin.solana, address: _solanaOwner),
      ]);

      expect(
        result.balances[Coin.eth]!.native.raw,
        BigInt.parse('1000000000000000000'),
      );
      expect(result.failedChains, contains(Coin.solana));
      expect(recorder.requests.single['method'], 'kt_getPortfolio');
      final params = recorder.requests.single['params'] as Map<String, Object?>;
      expect(params['accounts'], hasLength(2));
    });

    test(
      'isolates a portfolio row with contradictory native metadata',
      () async {
        final recorder = _Recorder()
          ..results = {
            'kt_getPortfolio': {
              'accounts': [
                {
                  'chain': 'eth',
                  'network': 'eth-mainnet',
                  'address': _evmFrom,
                  'result': {
                    'chain': 'eth',
                    'network': 'eth-mainnet',
                    'address': _evmFrom,
                    'native': {
                      'raw': '1000000000000000000',
                      'decimals': 6,
                      'symbol': 'ETH',
                    },
                  },
                },
              ],
            },
          };
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
        );

        final result = await client.getPortfolio(const [
          GatewayPortfolioQuery(chain: Coin.eth, address: _evmFrom),
        ]);

        expect(result.balances, isEmpty);
        expect(result.failedChains, {Coin.eth});
      },
    );
  });

  group('kt_getPrices', () {
    test(
      'exact params; unknown symbols omitted by the gateway stay absent',
      () async {
        final cachedAtMs = DateTime.now().millisecondsSinceEpoch;
        final recorder = _Recorder()
          ..results = {
            'kt_getPrices': {
              'prices': {
                'ETH': {'usd': 2500.5, 'change24h': 3.25},
                'TRX': {'usd': 0.12, 'change24h': -1.5},
              },
              'fiatPerUsd': {'USD': 1, 'CNY': 7.2, 'JPY': 151.5},
              'cachedAtMs': cachedAtMs,
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
        expect(prices.fiatPerUsd, {'USD': 1, 'CNY': 7.2, 'JPY': 151.5});
        expect(prices.cachedAtMs, cachedAtMs);
      },
    );

    test(
      'normalizes symbols and rejects invalid or duplicate requests',
      () async {
        final cachedAtMs = DateTime.now().millisecondsSinceEpoch;
        final recorder = _Recorder()
          ..results = {
            'kt_getPrices': {
              'prices': {
                'ETH': {'usd': 2500.0},
              },
              'fiatPerUsd': {'USD': 1, 'CNY': 7.2, 'JPY': 151.5},
              'cachedAtMs': cachedAtMs,
            },
          };
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
        );

        expect((await client.getPrices(const [' eth '])).usdBySymbol, {
          'ETH': 2500.0,
        });
        expect(recorder.requests.single['params'], {
          'symbols': ['ETH'],
        });
        final before = recorder.requests.length;
        await expectLater(
          client.getPrices(const ['ETH', 'eth']),
          throwsArgumentError,
        );
        await expectLater(
          client.getPrices(const ['ETH/USD']),
          throwsArgumentError,
        );
        await expectLater(client.getPrices(const []), throwsArgumentError);
        expect(recorder.requests, hasLength(before));
      },
    );

    test(
      'rejects any malformed quote instead of displaying a partial set',
      () async {
        final cachedAtMs = DateTime.now().millisecondsSinceEpoch;
        final recorder = _Recorder()
          ..results = {
            'kt_getPrices': {
              'prices': {
                'ETH': {'usd': -2500, 'change24h': 1.5},
                'POL': {'usd': 0, 'change24h': -2},
                'TRX': {'usd': 0.12, 'change24h': 3.25},
              },
              'fiatPerUsd': {'USD': 0, 'CNY': -7.2, 'JPY': 151.5},
              'cachedAtMs': cachedAtMs,
            },
          };
        await expectLater(
          GatewayClient(
            baseUrl: 'https://gw.example',
            client: recorder.client,
          ).getPrices(const ['ETH', 'POL', 'TRX']),
          throwsFormatException,
        );
      },
    );

    test('rejects unbound, additive and incomplete price results', () async {
      final cachedAtMs = DateTime.now().millisecondsSinceEpoch;
      final cases = <Map<String, Object?>>[
        {
          'prices': {
            'ETH': {'usd': 2500.0},
          },
          'fiatPerUsd': {'USD': 1},
          'cachedAtMs': cachedAtMs,
          'accepted': true,
        },
        {
          'prices': {
            'ETH': {'usd': 2500.0, 'provider': 'trusted'},
          },
          'fiatPerUsd': {'USD': 1},
          'cachedAtMs': cachedAtMs,
        },
        {
          'prices': {
            'BTC': {'usd': 100000.0},
          },
          'fiatPerUsd': {'USD': 1},
          'cachedAtMs': cachedAtMs,
        },
        {
          'prices': {
            'ETH': {'usd': 2500.0},
          },
          'fiatPerUsd': {'USD': 1, 'EUR': 0.9},
          'cachedAtMs': cachedAtMs,
        },
        {
          'prices': {
            'ETH': {'usd': 2500.0},
          },
          'fiatPerUsd': {'USD': 1},
        },
        {
          'prices': {
            'ETH': {'usd': 2500.0},
          },
          'fiatPerUsd': {'USD': 1, 'CNY': 7.2, 'JPY': 151.5},
          'cachedAtMs': DateTime.now()
              .subtract(const Duration(minutes: 16))
              .millisecondsSinceEpoch,
        },
      ];
      for (final result in cases) {
        final recorder = _Recorder()..results = {'kt_getPrices': result};
        await expectLater(
          GatewayClient(
            baseUrl: 'https://gw.example',
            client: recorder.client,
          ).getPrices(const ['ETH']),
          throwsFormatException,
        );
      }
    });
  });

  group('kt_getChainParams', () {
    test(
      'decimal nonce and three fee tiers parse into chains/rpc types',
      () async {
        final recorder = _Recorder()
          ..results = {
            'kt_getChainParams': _chainParamsResult(network: 'polygon-mainnet'),
          };
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
        );
        final params = await client.getChainParams(
          chain: Coin.polygon,
          address: _evmFrom,
        );

        expect(recorder.requests.single['params'], {
          'chain': 'polygon',
          'address': _evmFrom,
        });
        expect(params.nonce, 42);
        expect(params.fees.slow.maxPriorityFeePerGas, BigInt.from(1000000000));
        expect(params.fees.standard.maxFeePerGas, BigInt.from(30000000000));
        expect(params.fees.fast.maxPriorityFeePerGas, BigInt.from(3000000000));
      },
    );

    test('rejects unbound, unknown or impossible signing parameters', () async {
      final unknownResult = {
        ..._chainParamsResult(),
        'authorization': 'approved',
      };
      final unknownFees = _chainParamsResult();
      (unknownFees['fees']! as Map<String, Object?>)['baseFee'] = '1';
      final invalidTier = _chainParamsResult();
      final invalidSlow =
          ((invalidTier['fees']! as Map<String, Object?>)['slow']!
              as Map<String, Object?>);
      invalidSlow['maxPriorityFeePerGas'] = '30000000000';
      final nonMonotonic = _chainParamsResult();
      final nonMonotonicFees = nonMonotonic['fees']! as Map<String, Object?>;
      (nonMonotonicFees['slow']! as Map<String, Object?>)['maxFeePerGas'] =
          '50000000000';

      for (final result in <Map<String, Object?>>[
        unknownResult,
        unknownFees,
        _chainParamsResult(address: _evmTo),
        _chainParamsResult(nonce: '-1'),
        invalidTier,
        nonMonotonic,
      ]) {
        final recorder = _Recorder()..results = {'kt_getChainParams': result};
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
        );

        await expectLater(
          client.getChainParams(chain: Coin.eth, address: _evmFrom),
          throwsFormatException,
        );
      }
    });

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

  group('EVM preflight', () {
    test(
      'simulation and gas estimation carry exact network-scoped call',
      () async {
        final recorder = _Recorder()
          ..results = {
            'kt_health': {
              ..._healthyResult(networks: const ['polygon-amoy']),
            },
            'kt_simulateEvmTransfer': {
              'network': 'polygon-amoy',
              'from': _evmFrom,
              'to': _evmTo,
              'value': '0xf',
              'data': '0xa9059cbb',
              'blockTag': 'latest',
              'returnData': '0x${'0' * 63}1',
            },
            'kt_estimateEvmGas': {
              'network': 'polygon-amoy',
              'from': _evmFrom,
              'to': _evmTo,
              'value': '0xf',
              'data': '0xa9059cbb',
              'gas': '65432',
            },
          };
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
          networks: (_) => 'polygon-amoy',
        );
        final args = (
          chain: Coin.polygon,
          from: _evmFrom,
          to: _evmTo,
          value: BigInt.from(15),
          data: '0xa9059cbb',
        );

        expect(
          await client.simulateEvmTransfer(
            chain: args.chain,
            from: args.from,
            to: args.to,
            value: args.value,
            data: args.data,
            blockTag: 'latest',
          ),
          '0x${'0' * 63}1',
        );
        expect(
          await client.estimateEvmGas(
            chain: args.chain,
            from: args.from,
            to: args.to,
            value: args.value,
            data: args.data,
          ),
          BigInt.from(65432),
        );

        final calls = recorder.requests.where(
          (r) => r['method'] != 'kt_health',
        );
        expect(calls, hasLength(2));
        expect(calls.first['params'], {
          'chain': 'polygon',
          'network': 'polygon-amoy',
          'from': _evmFrom,
          'to': _evmTo,
          'value': '15',
          'data': '0xa9059cbb',
          'blockTag': 'latest',
        });
        expect(calls.last['params'], {
          'chain': 'polygon',
          'network': 'polygon-amoy',
          'from': _evmFrom,
          'to': _evmTo,
          'value': '15',
          'data': '0xa9059cbb',
        });
      },
    );

    test('malformed simulation and zero gas fail closed', () async {
      final recorder = _Recorder()
        ..results = {
          'kt_simulateEvmTransfer': {'returnData': 'not-hex'},
          'kt_estimateEvmGas': {'gas': '0'},
        };
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: recorder.client,
      );
      await expectLater(
        client.simulateEvmTransfer(
          chain: Coin.eth,
          from: '0xFrom',
          to: '0xTo',
          value: BigInt.zero,
          data: '0x',
        ),
        throwsFormatException,
      );
      recorder.results['kt_simulateEvmTransfer'] = {
        'network': 'eth-mainnet',
        'from': _evmFrom,
        'to': _evmTo,
        'value': '0x0',
        'data': '0x',
        'blockTag': 'pending',
        'returnData': '0x',
        'authorization': true,
      };
      await expectLater(
        client.simulateEvmTransfer(
          chain: Coin.eth,
          from: _evmFrom,
          to: _evmTo,
          value: BigInt.zero,
          data: '0x',
        ),
        throwsFormatException,
      );
      await expectLater(
        client.estimateEvmGas(
          chain: Coin.eth,
          from: '0xFrom',
          to: '0xTo',
          value: BigInt.zero,
          data: '0x',
        ),
        throwsFormatException,
      );
      recorder.results['kt_estimateEvmGas'] = {
        'network': 'eth-mainnet',
        'from': _evmFrom,
        'to': _evmTo,
        'value': '0x0',
        'data': '0x',
        'gas': '21000',
        'authorization': true,
      };
      await expectLater(
        client.estimateEvmGas(
          chain: Coin.eth,
          from: _evmFrom,
          to: _evmTo,
          value: BigInt.zero,
          data: '0x',
        ),
        throwsFormatException,
      );
    });

    test('preflight results must echo the exact normalized request', () async {
      final recorder = _Recorder()
        ..results = {
          'kt_simulateEvmTransfer': {
            'network': 'eth-mainnet',
            'from': _evmTo,
            'to': _evmTo,
            'value': '0x0',
            'data': '0x',
            'blockTag': 'pending',
            'returnData': '0x',
          },
          'kt_estimateEvmGas': {
            'network': 'eth-mainnet',
            'from': _evmFrom,
            'to': _evmTo,
            'value': '0x1',
            'data': '0x',
            'gas': '21000',
          },
        };
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: recorder.client,
      );

      await expectLater(
        client.simulateEvmTransfer(
          chain: Coin.eth,
          from: _evmFrom,
          to: _evmTo,
          value: BigInt.zero,
          data: '0x',
        ),
        throwsFormatException,
      );
      await expectLater(
        client.estimateEvmGas(
          chain: Coin.eth,
          from: _evmFrom,
          to: _evmTo,
          value: BigInt.zero,
          data: '0x',
        ),
        throwsFormatException,
      );
    });

    test(
      'uncached spendable balances parse and carry token contract',
      () async {
        final recorder = _Recorder()
          ..results = {
            'kt_getEvmSpendableBalances': {
              'network': 'eth-mainnet',
              'address': _evmFrom,
              'tokenContract': _evmTo,
              'native': '900000000000000000',
              'nativePending': '900000000000000000',
              'nativeLatest': '1000000000000000000',
              'token': '2500000',
              'pendingAvailable': false,
            },
          };
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
        );

        final balances = await client.getEvmSpendableBalances(
          chain: Coin.eth,
          address: _evmFrom,
          tokenContract: _evmTo,
        );
        expect(balances.native, BigInt.parse('900000000000000000'));
        expect(balances.nativeLatest, BigInt.parse('1000000000000000000'));
        expect(balances.token, BigInt.from(2500000));
        expect(balances.pendingAvailable, isFalse);
        expect(recorder.requests.single['params'], {
          'chain': 'eth',
          'address': _evmFrom,
          'tokenContract': _evmTo,
        });
      },
    );

    test('spendable balances bind account, token and native alias', () async {
      final valid = <String, Object?>{
        'network': 'eth-mainnet',
        'address': _evmFrom,
        'tokenContract': _evmTo,
        'native': '1',
        'nativePending': '1',
        'nativeLatest': '2',
        'token': '3',
        'pendingAvailable': true,
      };
      for (final result in <Map<String, Object?>>[
        {...valid, 'address': _evmTo},
        {...valid, 'tokenContract': _evmFrom},
        {...valid, 'native': '999'},
        {...valid, 'authorization': true},
      ]) {
        final recorder = _Recorder()
          ..results = {'kt_getEvmSpendableBalances': result};
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
        );

        await expectLater(
          client.getEvmSpendableBalances(
            chain: Coin.eth,
            address: _evmFrom,
            tokenContract: _evmTo,
          ),
          throwsFormatException,
        );
      }
    });

    test(
      'native-only spendable result excludes token identity and value',
      () async {
        final recorder = _Recorder()
          ..results = {
            'kt_getEvmSpendableBalances': {
              'network': 'eth-mainnet',
              'address': _evmFrom,
              'native': '1',
              'nativePending': '1',
              'nativeLatest': '2',
              'pendingAvailable': true,
            },
          };
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
        );

        final balances = await client.getEvmSpendableBalances(
          chain: Coin.eth,
          address: _evmFrom,
        );
        expect(balances.native, BigInt.one);
        expect(balances.nativeLatest, BigInt.two);
        expect(balances.token, isNull);
      },
    );

    test('missing requested token balance fails closed', () async {
      final recorder = _Recorder()
        ..results = {
          'kt_getEvmSpendableBalances': {'native': '1'},
        };
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: recorder.client,
      );
      await expectLater(
        client.getEvmSpendableBalances(
          chain: Coin.eth,
          address: '0xFrom',
          tokenContract: '0xToken',
        ),
        throwsFormatException,
      );
    });
  });

  group('kt_getHistory', () {
    test('rejects history bound to another network and owner', () async {
      final hash = '0x${'a' * 64}';
      final recorder = _Recorder()
        ..results = {
          'kt_getHistory': {
            'chain': 'eth',
            'network': 'eth-sepolia',
            'address': _evmTo,
            'status': 'ok',
            'records': [
              {
                'id': hash,
                'hash': hash,
                'direction': 'out',
                'from': _evmFrom,
                'to': _evmTo,
                'amountRaw': '1',
                'decimals': 18,
                'symbol': 'ETH',
                'verified': true,
                'timestampMs': 1753000000000,
                'status': 'ok',
              },
            ],
          },
        };
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: recorder.client,
      );

      await expectLater(
        client.getHistory(chain: Coin.eth, address: _evmFrom),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'rejects an additive field instead of accepting a partial page',
      () async {
        final hash = '0x${'b' * 64}';
        final recorder = _Recorder()
          ..results = {
            'kt_getHistory': {
              'chain': 'eth',
              'network': 'eth-mainnet',
              'address': _evmFrom,
              'status': 'ok',
              'records': [
                {
                  'id': hash,
                  'hash': hash,
                  'direction': 'in',
                  'from': _evmTo,
                  'to': _evmFrom,
                  'amountRaw': '1',
                  'decimals': 18,
                  'symbol': 'ETH',
                  'verified': true,
                  'timestampMs': 1753000000000,
                  'status': 'ok',
                  'memo': 'unreviewed',
                },
              ],
            },
          };
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
        );

        await expectLater(
          client.getHistory(chain: Coin.eth, address: _evmFrom),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test('ok status requires and parses a fully bound exact page', () async {
      final nativeHash = '0x${'c' * 64}';
      final tokenHash = '0x${'d' * 64}';
      final recorder = _Recorder()
        ..results = {
          'kt_getHistory': {
            'chain': 'eth',
            'network': 'eth-mainnet',
            'address': _evmFrom,
            'status': 'ok',
            'records': [
              {
                'id': nativeHash,
                'hash': nativeHash,
                'direction': 'out',
                'from': _evmFrom,
                'to': _evmTo,
                'amountRaw': '1500000000000000000',
                'decimals': 18,
                'symbol': 'ETH',
                'verified': true,
                'timestampMs': 1753000000000,
                'status': 'ok',
              },
              {
                'id': '$tokenHash:7',
                'hash': tokenHash,
                'direction': 'in',
                'from': _evmTo,
                'to': _evmFrom,
                'amountRaw': '2000000',
                'decimals': 6,
                'symbol': 'USDT',
                'contract': _evmToken,
                'verified': true,
                'timestampMs': 1752000000000,
                'status': 'failed',
              },
            ],
          },
        };
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: recorder.client,
      );
      final history = await client.getHistory(
        chain: Coin.eth,
        address: _evmFrom,
        limit: 20,
      );

      expect(recorder.requests.single['params'], {
        'chain': 'eth',
        'address': _evmFrom,
        'limit': 20,
      });
      expect(history.unsupported, isFalse);
      expect(history.records, hasLength(2));
      expect(history.records[0].hash, nativeHash);
      expect(history.records[0].outgoing, isTrue);
      expect(history.records[0].fromAddress, _evmFrom);
      expect(history.records[0].toAddress, _evmTo);
      expect(history.records[0].status, GatewayTransactionStatus.confirmed);
      expect(history.records[0].amountRaw, BigInt.parse('1500000000000000000'));
      expect(history.records[1].outgoing, isFalse);
      expect(history.records[1].status, GatewayTransactionStatus.failed);
    });

    test('status unsupported maps to the typed unsupported result', () async {
      final recorder = _Recorder()
        ..results = {
          'kt_getHistory': {
            'chain': 'solana',
            'network': 'sol-mainnet',
            'address': _solanaOwner,
            'status': 'unsupported',
            'records': <Object?>[],
          },
        };
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: recorder.client,
      );
      final history = await client.getHistory(
        chain: Coin.solana,
        address: _solanaOwner,
      );
      expect(history.unsupported, isTrue);
      expect(history.records, isEmpty);
    });

    test('rejects malformed money, identity and status semantics', () async {
      final hash = '0x${'e' * 64}';
      final valid = <String, Object?>{
        'id': hash,
        'hash': hash,
        'direction': 'out',
        'from': _evmFrom,
        'to': _evmTo,
        'amountRaw': '1',
        'decimals': 18,
        'symbol': 'ETH',
        'verified': true,
        'timestampMs': 1753000000000,
        'status': 'ok',
      };
      final mutations = <String, Map<String, Object?>>{
        'non-canonical hash': {...valid, 'hash': '0x1234'},
        'owner is not sender': {...valid, 'from': _evmTo},
        'leading-zero amount': {...valid, 'amountRaw': '01'},
        'unsupported precision': {...valid, 'decimals': 37},
        'unreviewed symbol': {...valid, 'symbol': 'eth'},
        'legacy status alias': {...valid, 'status': 'confirmed'},
      };

      for (final entry in mutations.entries) {
        final recorder = _Recorder()
          ..results = {
            'kt_getHistory': {
              'chain': 'eth',
              'network': 'eth-mainnet',
              'address': _evmFrom,
              'status': 'ok',
              'records': [entry.value],
            },
          };
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
        );
        await expectLater(
          client.getHistory(chain: Coin.eth, address: _evmFrom),
          throwsA(isA<FormatException>()),
          reason: entry.key,
        );
      }
    });

    test('rejects duplicate ids and unsupported pages with rows', () async {
      final hash = '0x${'f' * 64}';
      final row = <String, Object?>{
        'id': hash,
        'hash': hash,
        'direction': 'in',
        'from': _evmTo,
        'to': _evmFrom,
        'amountRaw': '1',
        'decimals': 18,
        'symbol': 'ETH',
        'verified': true,
        'timestampMs': 1753000000000,
        'status': 'ok',
      };
      for (final (status, rows) in <(String, List<Object?>)>[
        ('ok', [row, row]),
        ('unsupported', [row]),
      ]) {
        final recorder = _Recorder()
          ..results = {
            'kt_getHistory': {
              'chain': 'eth',
              'network': 'eth-mainnet',
              'address': _evmFrom,
              'status': status,
              'records': rows,
            },
          };
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
        );
        await expectLater(
          client.getHistory(chain: Coin.eth, address: _evmFrom),
          throwsA(isA<FormatException>()),
        );
      }
    });
  });

  group('kt_getTransactionStatus', () {
    test('maps chain-authoritative status and sends the exact hash', () async {
      final hash = '0x${'a' * 64}';
      final recorder = _Recorder()
        ..results = {
          'kt_getTransactionStatus': {
            'network': 'avalanche-mainnet',
            'hash': hash,
            'status': 'confirmed',
          },
        };
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: recorder.client,
      );

      final status = await client.getTransactionStatus(
        chain: Coin.avalanche,
        hash: hash,
      );

      expect(status, GatewayTransactionStatus.confirmed);
      expect(recorder.requests.single['params'], {
        'chain': 'avalanche',
        'hash': hash,
      });
    });

    test('rejects a status bound to another network or hash', () async {
      final recorder = _Recorder()
        ..results = {
          'kt_getTransactionStatus': {
            'network': 'eth-mainnet',
            'hash': '0x${'b' * 64}',
            'status': 'confirmed',
          },
        };
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: recorder.client,
      );

      await expectLater(
        client.getTransactionStatus(
          chain: Coin.avalanche,
          hash: '0x${'a' * 64}',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects unreviewed fields in a transaction status result', () async {
      final hash = '0x${'a' * 64}';
      final recorder = _Recorder()
        ..results = {
          'kt_getTransactionStatus': {
            'network': 'eth-mainnet',
            'hash': hash,
            'status': 'confirmed',
            'final': true,
          },
        };
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: recorder.client,
      );

      await expectLater(
        client.getTransactionStatus(chain: Coin.eth, hash: hash),
        throwsA(isA<FormatException>()),
      );
    });

    test('requires a canonical TRON transaction id', () async {
      final hash = 'a' * 64;
      final recorder = _Recorder()
        ..results = {
          'kt_getTransactionStatus': {
            'network': 'tron-mainnet',
            'hash': hash,
            'status': 'pending',
          },
        };
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: recorder.client,
      );

      expect(
        await client.getTransactionStatus(chain: Coin.tron, hash: hash),
        GatewayTransactionStatus.pending,
      );
      recorder.results['kt_getTransactionStatus'] = {
        'network': 'tron-mainnet',
        'hash': 'not-a-transaction-id',
        'status': 'pending',
      };
      await expectLater(
        client.getTransactionStatus(chain: Coin.tron, hash: hash),
        throwsA(isA<FormatException>()),
      );
    });

    test('requires a canonical 64-byte Solana signature', () async {
      const signature =
          '5KtPn3E1Z9ezPTVYPQ7V2FZx5zRW2aYw5gCz6tNQ8crShXKQ3Fd6ztqQmDN7Hjz3EN3YHhuYxqUjQK4rDgVjSxqR';
      final recorder = _Recorder()
        ..results = {
          'kt_getTransactionStatus': {
            'network': 'sol-mainnet',
            'hash': signature,
            'status': 'confirmed',
          },
        };
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: recorder.client,
      );

      expect(
        await client.getTransactionStatus(chain: Coin.solana, hash: signature),
        GatewayTransactionStatus.confirmed,
      );
      recorder.results['kt_getTransactionStatus'] = {
        'network': 'sol-mainnet',
        'hash': '11111111111111111111111111111111',
        'status': 'confirmed',
      };
      await expectLater(
        client.getTransactionStatus(chain: Coin.solana, hash: signature),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects an unknown status instead of assuming pending', () async {
      final hash = '0x${'a' * 64}';
      final recorder = _Recorder()
        ..results = {
          'kt_getTransactionStatus': {
            'network': 'eth-mainnet',
            'hash': hash,
            'status': 'indexed-later',
          },
        };
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: recorder.client,
      );

      await expectLater(
        client.getTransactionStatus(chain: Coin.eth, hash: hash),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('kt_getEvmTokenApprovals', () {
    test('requires consent and parses the complete typed approval row', () async {
      final recorder = _Recorder()
        ..results = {
          'kt_health': {..._healthyResult()},
          'kt_getEvmTokenApprovals': {
            'status': 'ok',
            'source': 'goplus',
            'network': 'eth-mainnet',
            'approvals': [
              {
                'tokenAddress': '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                'tokenName': 'Token',
                'tokenSymbol': 'TOK',
                'decimals': 18,
                'balance': '5',
                'spender': '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
                'spenderName': 'Router',
                'spenderTag': 'Example',
                'spenderTrusted': false,
                'amount': 'Unlimited',
                'unlimited': true,
                'approvedAt': 1700000000,
                'transaction':
                    '0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
                'risk': 'unsafe',
              },
            ],
          },
        };
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: recorder.client,
        networks: (_) => 'eth-mainnet',
      );

      await expectLater(
        client.getEvmTokenApprovals(
          chain: Coin.eth,
          address: '0x85f6be9460291e86e0fb49b07d0a83cc5f7206cd',
          privacyConsent: false,
        ),
        throwsArgumentError,
      );
      expect(recorder.requests, isEmpty);

      final result = await client.getEvmTokenApprovals(
        chain: Coin.eth,
        address: '0x85f6be9460291e86e0fb49b07d0a83cc5f7206cd',
        privacyConsent: true,
      );
      expect(result.network, 'eth-mainnet');
      expect(result.source, 'goplus');
      expect(result.approvals, hasLength(1));
      expect(result.approvals.single.unlimited, isTrue);
      expect(result.approvals.single.risk, GatewayTokenApprovalRisk.unsafe);
      expect(recorder.requests.last['params'], {
        'chain': 'eth',
        'network': 'eth-mainnet',
        'address': '0x85f6be9460291e86e0fb49b07d0a83cc5f7206cd',
        'privacyConsent': true,
      });
    });

    test(
      'malformed rows fail closed instead of becoming an empty list',
      () async {
        final recorder = _Recorder()
          ..results = {
            'kt_getEvmTokenApprovals': {
              'status': 'ok',
              'source': 'goplus',
              'network': 'eth-mainnet',
              'approvals': [
                {'tokenAddress': 'missing-fields'},
              ],
            },
          };
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
        );
        await expectLater(
          client.getEvmTokenApprovals(
            chain: Coin.eth,
            address: '0x85f6be9460291e86e0fb49b07d0a83cc5f7206cd',
            privacyConsent: true,
          ),
          throwsFormatException,
        );
      },
    );

    test(
      'binds approval responses to the requested network and source',
      () async {
        Map<String, Object?> response({
          String network = 'eth-mainnet',
          String source = 'goplus',
        }) => {
          'status': 'ok',
          'source': source,
          'network': network,
          'approvals': <Object?>[],
        };

        for (final result in <Map<String, Object?>>[
          response(network: 'polygon-mainnet'),
          response(source: 'operator-override'),
        ]) {
          final recorder = _Recorder()
            ..results = {'kt_getEvmTokenApprovals': result};
          final client = GatewayClient(
            baseUrl: 'https://gw.example',
            client: recorder.client,
            networks: (_) => 'eth-mainnet',
            advertisedNetworks: const {'eth-mainnet'},
          );
          await expectLater(
            client.getEvmTokenApprovals(
              chain: Coin.eth,
              address: '0x85f6be9460291e86e0fb49b07d0a83cc5f7206cd',
              privacyConsent: true,
            ),
            throwsFormatException,
          );
        }
      },
    );

    test(
      'rejects approval rows that could change revocation semantics',
      () async {
        Map<String, Object?> validRow() => {
          'tokenAddress': '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          'tokenName': 'Token',
          'tokenSymbol': 'TOK',
          'decimals': 18,
          'balance': '5',
          'spender': '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          'spenderName': 'Router',
          'spenderTag': 'Example',
          'spenderTrusted': false,
          'amount': 'Unlimited',
          'unlimited': true,
          'approvedAt': 1700000000,
          'transaction':
              '0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
          'risk': 'unsafe',
        };

        final invalidRows = <Map<String, Object?>>[
          validRow()..['tokenAddress'] = '0x1234',
          validRow()..['spender'] = '0x1234',
          validRow()..['decimals'] = 37,
          validRow()..['balance'] = '-1',
          validRow()
            ..['amount'] = '1'
            ..['unlimited'] = true,
          validRow()..['approvedAt'] = -1,
          validRow()
            ..['approvedAt'] =
                DateTime.now()
                    .add(const Duration(days: 2))
                    .millisecondsSinceEpoch ~/
                1000,
          validRow()..['approvedAt'] = 8640000000001,
          validRow()..['transaction'] = '0x1234',
          validRow()..['tokenSymbol'] = 'T' * 33,
          validRow()..['tokenName'] = 'USDT\u202eTDSU',
          validRow()..['unexpectedSecurityOverride'] = true,
        ];
        for (final row in invalidRows) {
          final recorder = _Recorder()
            ..results = {
              'kt_getEvmTokenApprovals': {
                'status': 'ok',
                'source': 'goplus',
                'network': 'eth-mainnet',
                'approvals': [row],
              },
            };
          final client = GatewayClient(
            baseUrl: 'https://gw.example',
            client: recorder.client,
            networks: (_) => 'eth-mainnet',
            advertisedNetworks: const {'eth-mainnet'},
          );
          await expectLater(
            client.getEvmTokenApprovals(
              chain: Coin.eth,
              address: '0x85f6be9460291e86e0fb49b07d0a83cc5f7206cd',
              privacyConsent: true,
            ),
            throwsFormatException,
            reason: 'invalid row must not become a revocation draft: $row',
          );
        }
      },
    );

    test('rejects duplicate and oversized approval lists', () async {
      final row = <String, Object?>{
        'tokenAddress': '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'tokenName': 'Token',
        'tokenSymbol': 'TOK',
        'decimals': 18,
        'balance': '5',
        'spender': '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        'spenderName': 'Router',
        'spenderTag': 'Example',
        'spenderTrusted': false,
        'amount': '1',
        'unlimited': false,
        'approvedAt': 1700000000,
        'transaction': '',
        'risk': 'unknown',
      };
      for (final approvals in <List<Object?>>[
        [row, Map<String, Object?>.from(row)],
        List<Object?>.generate(501, (_) => row),
      ]) {
        final recorder = _Recorder()
          ..results = {
            'kt_getEvmTokenApprovals': {
              'status': 'ok',
              'source': 'goplus',
              'network': 'eth-mainnet',
              'approvals': approvals,
            },
          };
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
          networks: (_) => 'eth-mainnet',
          advertisedNetworks: const {'eth-mainnet'},
        );
        await expectLater(
          client.getEvmTokenApprovals(
            chain: Coin.eth,
            address: '0x85f6be9460291e86e0fb49b07d0a83cc5f7206cd',
            privacyConsent: true,
          ),
          throwsFormatException,
        );
      }
    });
  });

  group('kt_broadcast and error mapping', () {
    test('payload passthrough and txHash back', () async {
      final recorder = _Recorder()
        ..results = {
          'kt_broadcast': {
            'chain': 'eth',
            'network': 'eth-mainnet',
            'txHash': _evmHash,
          },
        };
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: recorder.client,
      );
      final hash = await client.broadcast(chain: Coin.eth, payload: '0x02ab01');
      expect(hash, _evmHash);
      expect(recorder.requests.single['params'], {
        'chain': 'eth',
        'payload': '0x02ab01',
      });
    });

    test('accepts canonical TRON and Solana transaction identities', () async {
      for (final row in <(Coin, String, String, String)>[
        (Coin.tron, 'tron', 'tron-mainnet', _tronHash),
        (Coin.solana, 'solana', 'sol-mainnet', _solanaSignature),
      ]) {
        final recorder = _Recorder()
          ..results = {
            'kt_broadcast': {
              'chain': row.$2,
              'network': row.$3,
              'txHash': row.$4,
            },
          };
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
        );

        expect(
          await client.broadcast(chain: row.$1, payload: 'signed-payload'),
          row.$4,
        );
      }
    });

    test('rejects unbound, additive and malformed broadcast results', () async {
      final cases = <Map<String, Object?>>[
        {'chain': 'polygon', 'network': 'eth-mainnet', 'txHash': _evmHash},
        {'chain': 'eth', 'network': 'polygon-mainnet', 'txHash': _evmHash},
        {
          'chain': 'eth',
          'network': 'eth-mainnet',
          'txHash': _evmHash,
          'accepted': true,
        },
        {'chain': 'eth', 'network': 'eth-mainnet', 'txHash': '0x1234'},
      ];
      for (final result in cases) {
        final recorder = _Recorder()..results = {'kt_broadcast': result};
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
        );
        await expectLater(
          client.broadcast(chain: Coin.eth, payload: '0x02ab01'),
          throwsFormatException,
        );
      }
    });

    test('rejects malformed TRON and Solana transaction identities', () async {
      for (final row in <(Coin, String, String, String)>[
        (Coin.tron, 'tron', 'tron-mainnet', 'abcd'),
        (Coin.solana, 'solana', 'sol-mainnet', 'not-a-signature'),
      ]) {
        final recorder = _Recorder()
          ..results = {
            'kt_broadcast': {
              'chain': row.$2,
              'network': row.$3,
              'txHash': row.$4,
            },
          };
        final client = GatewayClient(
          baseUrl: 'https://gw.example',
          client: recorder.client,
        );

        await expectLater(
          client.broadcast(chain: row.$1, payload: 'signed-payload'),
          throwsFormatException,
        );
      }
    });

    test(
      '-32000 maps to a stable category without retaining node text',
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
                .having((e) => e.message, 'message', 'upstream_error'),
          ),
        );
      },
    );

    test('gateway errors never retain provider-controlled text', () async {
      final bodyCanary = <String>[
        'alch',
        'gateway_error_body_secret',
      ].join('_');
      final upstreamCanary = <String>[
        'https://rpc.example',
        bodyCanary,
      ].join('/');
      final recorder = _Recorder()
        ..errors = {
          'kt_getPrices': {
            'code': -32000,
            'message': bodyCanary,
            'data': {
              'upstream': upstreamCanary,
              'message': 'wallet address and $bodyCanary',
            },
          },
        };
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        client: recorder.client,
      );

      try {
        await client.getPrices(const ['ETH']);
        fail('request should fail');
      } on GatewayException catch (error) {
        expect(error.code, -32000);
        expect(error.message, 'upstream_error');
        expect(error.toString(), isNot(contains(bodyCanary)));
        expect(error.toString(), isNot(contains(upstreamCanary)));
      }
    });

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

    test(
      'transport failures never expose a credential-bearing gateway URL',
      () async {
        const canary = 'gateway-client-secret-canary';
        final client = GatewayClient(
          baseUrl: 'https://gateway.example/v1/$canary',
          client: MockClient((request) async {
            throw http.ClientException('connection refused', request.url);
          }),
        );

        Object? thrown;
        try {
          await client.broadcast(chain: Coin.eth, payload: '0x02');
        } on Object catch (error) {
          thrown = error;
        }

        expect(thrown, isA<GatewayTransportException>());
        expect(thrown.toString(), isNot(contains(canary)));
        expect(thrown.toString(), isNot(contains('gateway.example')));
      },
    );
  });
}
