import 'dart:convert';
import 'dart:typed_data';

import 'package:chains/chains.dart' show Chain;
import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart' show ChainAddresses, Coin;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kt_wallet/src/market/balance_service.dart';
import 'package:kt_wallet/src/market/gateway_client.dart';
import 'package:kt_wallet/src/market/history_service.dart';
import 'package:kt_wallet/src/market/market_scope.dart';
import 'package:kt_wallet/src/market/price_service.dart';
import 'package:kt_wallet/src/market/token_balance_service.dart';
import 'package:kt_wallet/src/state/app_prefs.dart';
import 'package:kt_wallet/src/transfer/broadcast_service.dart';
import 'package:kt_wallet/src/transfer/chain_params_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gateway-mode integration of every service: gateway-first, per-call direct
/// fallback, and the guarantee that direct mode (blank URL) never touches the
/// gateway while gateway mode never touches the direct transports on success.

const _addresses = ChainAddresses(
  eth: '0xEthAddr',
  polygon: '0xPolyAddr',
  tron: 'TTronAddr',
  solana: 'SolAddr',
);

/// A scripted gateway: records every JSON-RPC call and answers per-method.
class _FakeGateway {
  _FakeGateway({this.results = const {}, this.errors = const {}});

  /// JSON-RPC `result` per method. A `List` value serves per-call answers in
  /// order (for methods called once per chain).
  final Map<String, Object?> results;
  final Map<String, Object?> errors;
  final calls = <(String method, Map<String, Object?> params)>[];
  final _served = <String, int>{};

  late final client = GatewayClient(
    baseUrl: 'https://gw.example',
    client: MockClient((request) async {
      expect(request.url.toString(), 'https://gw.example/rpc');
      final body = jsonDecode(request.body) as Map<String, Object?>;
      final method = body['method'] as String;
      calls.add((
        method,
        (body['params'] as Map?)?.cast<String, Object?>() ?? const {},
      ));
      final error = errors[method];
      if (error != null) {
        return http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'error': error}),
          200,
        );
      }
      var result = results[method];
      if (result is List) {
        final index = _served[method] ?? 0;
        _served[method] = index + 1;
        result = result[index < result.length ? index : result.length - 1];
      }
      return http.Response(
        jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': result}),
        200,
      );
    }),
  );

  List<Map<String, Object?>> paramsOf(String method) => [
    for (final (m, p) in calls)
      if (m == method) p,
  ];
}

/// A gateway whose transport always fails (gateway configured but down).
GatewayClient _deadGateway() => GatewayClient(
  baseUrl: 'https://gw.example',
  client: MockClient((request) async => http.Response('down', 503)),
);

/// JSON-RPC transport that fails the test if any request reaches it.
class _NoDirectJsonRpc implements JsonRpcTransport {
  @override
  Future<Object?> post(String url, Object body) async {
    fail('gateway mode must not contact direct JSON-RPC nodes ($url)');
  }
}

class _NoDirectRest implements RestTransport {
  @override
  Future<Object?> getJson(String url) async {
    fail('gateway mode must not contact direct REST nodes (GET $url)');
  }

  @override
  Future<Object?> postJson(String url, Object body) async {
    fail('gateway mode must not contact direct REST nodes (POST $url)');
  }
}

/// Scripted direct JSON-RPC transport (fallback assertions).
class _FakeJsonRpc implements JsonRpcTransport {
  _FakeJsonRpc(this.handler);
  final Future<Object?> Function(String url, Object body) handler;
  final calls = <(String, String)>[];
  @override
  Future<Object?> post(String url, Object body) {
    calls.add((url, (body as Map)['method'] as String));
    return handler(url, body);
  }
}

class _FakeRest implements RestTransport {
  _FakeRest({this.onGet});
  final Future<Object?> Function(String url)? onGet;
  final gets = <String>[];
  @override
  Future<Object?> getJson(String url) {
    gets.add(url);
    return onGet!(url);
  }

  @override
  Future<Object?> postJson(String url, Object body) =>
      throw UnimplementedError('these fetches never POST to TronGrid');
}

Map<String, Object?> _rpcResult(Object? result) => {
  'jsonrpc': '2.0',
  'id': 1,
  'result': result,
};

Map<String, Object?> _native(String raw, int decimals, String symbol) => {
  'native': {'raw': raw, 'decimals': decimals, 'symbol': symbol},
};

void main() {
  group('BalanceService gateway mode', () {
    test('one kt_getBalances per chain, direct transports untouched', () async {
      final gateway = _FakeGateway(
        results: {
          'kt_getBalances': [
            _native('1000000000000000000', 18, 'ETH'),
            _native('2000000000000000000', 18, 'POL'),
            _native('5000000', 6, 'TRX'),
            _native('500000000', 9, 'SOL'),
          ],
        },
      );
      final service = BalanceService(
        jsonRpcTransport: _NoDirectJsonRpc(),
        restTransport: _NoDirectRest(),
        gateway: () => gateway.client,
      );

      final results = await service.fetchAll(_addresses);
      for (final coin in _addresses.enabledCoins) {
        expect(results[coin]!.status, BalanceStatus.ok, reason: '$coin');
      }
      expect(results[Coin.eth]!.amount!.format(), '1');
      expect(results[Coin.eth]!.amount!.symbol, 'ETH');
      expect(results[Coin.solana]!.amount!.format(), '0.5');

      final params = gateway.paramsOf('kt_getBalances');
      expect(params, hasLength(4));
      expect(
        {for (final p in params) p['chain']},
        {'eth', 'polygon', 'tron', 'solana'},
      );
      expect(
        params.firstWhere((p) => p['chain'] == 'tron')['address'],
        'TTronAddr',
      );
      // Native-only calls: the token registry goes via TokenBalanceService.
      for (final p in params) {
        expect(p.containsKey('tokens'), isFalse);
      }
    });

    test('gateway failure falls back to the direct path per chain', () async {
      final direct = _FakeJsonRpc(
        (url, body) async => (body as Map)['method'] == 'getBalance'
            ? _rpcResult({'context': <String, Object?>{}, 'value': 0})
            : _rpcResult('0x0'),
      );
      final rest = _FakeRest(onGet: (url) async => {'data': <Object?>[]});
      final service = BalanceService(
        jsonRpcTransport: direct,
        restTransport: rest,
        gateway: _deadGateway,
      );

      final results = await service.fetchAll(_addresses);
      for (final coin in _addresses.enabledCoins) {
        expect(results[coin]!.status, BalanceStatus.ok, reason: '$coin');
      }
      // The direct nodes answered: 3 JSON-RPC chains + TronGrid REST.
      expect(direct.calls, hasLength(3));
      expect(rest.gets.single, '$defaultTronApiUrl/v1/accounts/TTronAddr');
    });

    test('direct mode (null resolver) never contacts the gateway', () async {
      final direct = _FakeJsonRpc(
        (url, body) async => (body as Map)['method'] == 'getBalance'
            ? _rpcResult({'context': <String, Object?>{}, 'value': 0})
            : _rpcResult('0x0'),
      );
      final service = BalanceService(
        jsonRpcTransport: direct,
        restTransport: _FakeRest(onGet: (url) async => {'data': <Object?>[]}),
        // A configured-but-blank prefs resolver: direct mode.
        gateway: () => null,
      );
      final results = await service.fetchAll(_addresses);
      expect(results[Coin.eth]!.status, BalanceStatus.ok);
      expect(direct.calls, hasLength(3));
    });
  });

  group('TokenBalanceService gateway mode', () {
    test(
      'one call per chain with its registry tokens; per-token errors map',
      () async {
        final gateway = _FakeGateway(
          results: {
            'kt_getBalances': {
              // Same shape works for every chain in this test: the USDT/USDC
              // contract rows are matched per chain below.
              'native': {'raw': '0', 'decimals': 18, 'symbol': 'X'},
              'tokens': [
                {
                  'contract': '0xdAC17F958D2ee523a2206206994597C13D831ec7',
                  'raw': '120500000',
                  'decimals': 6,
                  'symbol': 'USDT',
                },
                {
                  'contract': '0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359',
                  'raw': '99000000',
                  'decimals': 6,
                  'symbol': 'USDC',
                },
                {
                  'contract': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
                  'raw': '0',
                  'decimals': 6,
                  'symbol': 'USDT',
                  'error': 'account not found',
                },
              ],
            },
          },
        );
        final service = TokenBalanceService(
          jsonRpcTransport: _NoDirectJsonRpc(),
          restTransport: _NoDirectRest(),
          gateway: () => gateway.client,
        );

        final results = await service.fetchAll(_addresses);
        expect(results['usdt-eth']!.status, BalanceStatus.ok);
        expect(results['usdt-eth']!.amount!.format(), '120.5');
        expect(results['usdc-polygon']!.status, BalanceStatus.ok);
        expect(results['usdc-polygon']!.amount!.format(), '99');
        // The gateway's per-token error degrades ONLY that token.
        expect(results['usdt-tron']!.status, BalanceStatus.error);

        // One kt_getBalances per chain that has registry tokens, each
        // carrying that chain's token list. Avalanche and Solana joined when
        // USDT gained its deployments there.
        final params = gateway.paramsOf('kt_getBalances');
        expect(
          {for (final p in params) p['chain']},
          {
            'eth',
            'polygon',
            'base',
            'arbitrum',
            'avalanche',
            'bnb',
            'tron',
            'solana',
          },
        );
        final ethCall = params.firstWhere((p) => p['chain'] == 'eth');
        final ethTokens = ethCall['tokens'] as List<Object?>;
        expect(ethTokens, hasLength(11));
        final dai = ethTokens.cast<Map<String, Object?>>().firstWhere(
          (token) => token['symbol'] == 'DAI',
        );
        expect(dai['contract'], '0x6B175474E89094C44Da98b954EedeAC495271d0F');
        expect(dai['decimals'], 18);
      },
    );

    test(
      'gateway failure falls back to the direct path for that chain',
      () async {
        final direct = _FakeJsonRpc(
          (url, body) async => _rpcResult(
            '0x00000000000000000000000000000000000000000000000000000000072f2740',
          ),
        );
        final rest = _FakeRest(
          onGet: (url) async => {
            'data': [
              {
                'trc20': [
                  {'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t': '5000000'},
                ],
              },
            ],
          },
        );
        final service = TokenBalanceService(
          jsonRpcTransport: direct,
          restTransport: rest,
          gateway: _deadGateway,
        );
        final results = await service.fetchAll(_addresses);
        expect(results['usdt-eth']!.status, BalanceStatus.ok);
        expect(results['usdt-tron']!.status, BalanceStatus.ok);
        expect(results['usdt-tron']!.amount!.format(), '5');
        expect(
          direct.calls,
          hasLength(
            builtinTokens.where((token) => token.chain != Coin.tron).length,
          ),
        );
        expect(rest.gets, hasLength(1)); // tron account
      },
    );

    test('direct mode never contacts the gateway', () async {
      // A null-returning resolver is direct mode; a _forbiddenGateway client
      // would fail the test on ANY request, proving no contact happens even
      // if one were constructed.
      final direct = _FakeJsonRpc((url, body) async => _rpcResult('0x0'));
      final service = TokenBalanceService(
        jsonRpcTransport: direct,
        restTransport: _FakeRest(onGet: (url) async => {'data': <Object?>[]}),
        gateway: () => null,
      );
      final results = await service.fetchAll(_addresses);
      expect(results['usdt-eth']!.status, BalanceStatus.ok);
      expect(
        direct.calls,
        hasLength(
          builtinTokens.where((token) => token.chain != Coin.tron).length,
        ),
      );
    });
  });

  group('PriceService gateway mode', () {
    test(
      'kt_getPrices first: symbols asserted, CoinGecko never contacted',
      () async {
        final gateway = _FakeGateway(
          results: {
            'kt_getPrices': {
              'prices': {
                'ETH': {'usd': 2500.0, 'change24h': 2.5},
                'POL': {'usd': 0.4, 'change24h': -3.0},
                'TRX': {'usd': 0.12},
                'SOL': {'usd': 150, 'change24h': 1.0},
                'USDT': {'usd': 0.998, 'change24h': -0.1},
                'USDC': {'usd': 1.001, 'change24h': 0.05},
              },
              'cachedAtMs': 1753000000000,
            },
          },
        );
        final service = PriceService(
          client: MockClient(
            (request) async => fail(
              'gateway mode must not contact CoinGecko (${request.url})',
            ),
          ),
          gateway: () => gateway.client,
        );

        final prices = await service.fetchUsdPrices();
        expect(prices, isNotNull);
        expect(prices![Coin.eth], 2500.0);
        expect(prices[Coin.polygon], 0.4);
        expect(prices[Coin.tron], 0.12);
        expect(prices[Coin.solana], 150.0);
        expect(service.lastGoodUsd, prices);
        expect(service.tokenPriceUsd('USDT'), 0.998);
        expect(service.tokenPriceUsd('USDC'), 1.001);
        expect(service.change24hPercent(Coin.eth), 2.5);
        expect(service.change24hPercent(Coin.polygon), -3.0);
        expect(service.change24hPercent(Coin.tron), isNull);
        expect(service.tokenChange24hPercent('USDT'), -0.1);
        expect(service.tokenChange24hPercent('USDC'), 0.05);
        expect(gateway.paramsOf('kt_getPrices').single, {
          'symbols': [
            'ETH',
            'POL',
            'AVAX',
            'BNB',
            'TRX',
            'SOL',
            'USDT',
            'USDC',
            'BUSD',
            'DAI',
            'WETH',
            'WBTC',
            'LINK',
            'UNI',
            'SHIB',
            'PEPE',
            'JUP',
            'BONK',
            'PYUSD',
          ],
        });
      },
    );

    test('gateway failure falls back to direct CoinGecko', () async {
      var coinGeckoHits = 0;
      final service = PriceService(
        client: MockClient((request) async {
          coinGeckoHits++;
          expect(request.url.path, '/api/v3/simple/price');
          return http.Response(
            jsonEncode({
              'ethereum': {'usd': 2000.0},
            }),
            200,
          );
        }),
        gateway: _deadGateway,
      );
      final prices = await service.fetchUsdPrices();
      expect(prices![Coin.eth], 2000.0);
      expect(coinGeckoHits, 1);
    });

    test('an all-unknown-symbols gateway answer also falls back', () async {
      final gateway = _FakeGateway(
        results: {
          'kt_getPrices': {'prices': <String, Object?>{}, 'cachedAtMs': 0},
        },
      );
      final service = PriceService(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'tron': {'usd': 0.11},
            }),
            200,
          ),
        ),
        gateway: () => gateway.client,
      );
      final prices = await service.fetchUsdPrices();
      expect(prices![Coin.tron], 0.11);
    });

    test('direct mode never contacts the gateway', () async {
      final service = PriceService(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'solana': {'usd': 149.0},
            }),
            200,
          ),
        ),
        gateway: () => null,
      );
      final prices = await service.fetchUsdPrices();
      expect(prices![Coin.solana], 149.0);
    });
  });

  group('ChainParamsService gateway mode', () {
    test('kt_getChainParams first, direct transport untouched', () async {
      final gateway = _FakeGateway(
        results: {
          'kt_getChainParams': {
            'nonce': '7',
            'fees': {
              'slow': {'maxPriorityFeePerGas': '1', 'maxFeePerGas': '10'},
              'standard': {'maxPriorityFeePerGas': '2', 'maxFeePerGas': '20'},
              'fast': {'maxPriorityFeePerGas': '3', 'maxFeePerGas': '30'},
            },
          },
        },
      );
      final service = ChainParamsService(
        jsonRpcTransport: _NoDirectJsonRpc(),
        gateway: () => gateway.client,
      );

      final params = await service.fetchEvmParams(Chain.ethereum, '0xFrom');
      expect(params.nonce, 7);
      expect(params.tierFor(0).maxFeePerGas, BigInt.from(10));
      expect(params.tierFor(1).maxPriorityFeePerGas, BigInt.from(2));
      expect(params.tierFor(2).maxFeePerGas, BigInt.from(30));
      expect(gateway.paramsOf('kt_getChainParams').single, {
        'chain': 'eth',
        'address': '0xFrom',
      });
    });

    test(
      'gateway failure falls back to direct getNonce+estimateFees',
      () async {
        final direct = _FakeJsonRpc((url, body) async {
          final method = (body as Map)['method'];
          if (method == 'eth_getTransactionCount') return _rpcResult('0x2a');
          if (method == 'eth_feeHistory') {
            return _rpcResult({
              'baseFeePerGas': ['0x3b9aca00', '0x3b9aca00'],
              'reward': [
                ['0x3b9aca00', '0x3b9aca00', '0x3b9aca00'],
              ],
            });
          }
          return _rpcResult('0x3b9aca00'); // eth_maxPriorityFeePerGas etc.
        });
        final service = ChainParamsService(
          jsonRpcTransport: direct,
          gateway: _deadGateway,
        );
        final params = await service.fetchEvmParams(Chain.polygon, '0xFrom');
        expect(params.nonce, 42);
        expect(direct.calls, isNotEmpty);
        expect(direct.calls.first.$1, defaultPolygonRpcUrl);
      },
    );

    test(
      'both gateway and direct failing still throws (caller fallback)',
      () async {
        final service = ChainParamsService(
          jsonRpcTransport: _FakeJsonRpc(
            (url, body) async => throw RpcException('down'),
          ),
          gateway: _deadGateway,
        );
        await expectLater(
          service.fetchEvmParams(Chain.ethereum, '0xFrom'),
          throwsA(isA<RpcException>()),
        );
      },
    );
  });

  group('HistoryService gateway mode', () {
    test('UNLOCK: eth history returns ok records via the gateway', () async {
      final gateway = _FakeGateway(
        results: {
          'kt_getHistory': {
            'status': 'ok',
            'records': [
              {
                'id': '0xaaa',
                'hash': '0xaaa',
                'direction': 'out',
                'amountRaw': '1500000000000000000',
                'decimals': 18,
                'symbol': 'ETH',
                'verified': true,
                'timestampMs': 1753000000000,
                'status': 'ok',
              },
              {
                'id': '0xbbb:7',
                'hash': '0xbbb',
                'direction': 'in',
                'amountRaw': '2000000',
                'decimals': 6,
                'symbol': 'USDT',
                'contract': '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                'verified': false,
                'timestampMs': 1753000100000,
                'status': 'failed',
              },
            ],
          },
        },
      );
      final service = HistoryService(
        client: MockClient(
          (request) async =>
              fail('gateway mode must not contact TronGrid (${request.url})'),
        ),
        gateway: () => gateway.client,
      );

      final result = await service.fetch(Coin.eth, '0xEthAddr');
      expect(result.status, HistoryStatus.ok);
      expect(result.records, hasLength(2));
      // Newest first.
      expect(result.records[0].hash, '0xbbb');
      expect(result.records[0].outgoing, isFalse);
      expect(result.records[0].confirmed, isFalse); // status: failed
      expect(result.records[0].amountText, '2 USDT');
      expect(result.records[0].id, '0xbbb:7');
      expect(result.records[0].assetVerified, isFalse);
      expect(
        result.records[0].assetContract,
        '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
      expect(result.records[1].hash, '0xaaa');
      expect(result.records[1].outgoing, isTrue);
      expect(result.records[1].confirmed, isTrue);
      expect(result.records[1].amountText, '1.5 ETH');
      expect(result.records[1].assetVerified, isTrue);
      expect(gateway.paramsOf('kt_getHistory').single, {
        'chain': 'eth',
        'address': '0xEthAddr',
        'limit': HistoryService.pageSize,
      });
    });

    test('gateway-reported unsupported stays unsupported', () async {
      final gateway = _FakeGateway(
        results: {
          'kt_getHistory': {'status': 'unsupported', 'records': <Object?>[]},
        },
      );
      final service = HistoryService(
        client: MockClient((request) async => fail('no direct contact')),
        gateway: () => gateway.client,
      );
      final result = await service.fetch(Coin.solana, 'SolAddr');
      expect(result.status, HistoryStatus.unsupported);
    });

    test(
      'gateway failure: TRON falls back direct, eth surfaces error',
      () async {
        var tronGridHits = 0;
        final service = HistoryService(
          client: MockClient((request) async {
            tronGridHits++;
            expect(request.url.host, 'api.trongrid.io');
            return http.Response(jsonEncode({'data': <Object?>[]}), 200);
          }),
          gateway: _deadGateway,
        );

        final tron = await service.fetch(
          Coin.tron,
          'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
        );
        expect(tron.status, HistoryStatus.ok); // direct TronGrid answered
        expect(tronGridHits, 3); // trc20 + native + internal endpoints

        // No direct history source exists for the other chains: an honest
        // error (the gateway WAS configured), never a silent "unsupported".
        final eth = await service.fetch(Coin.eth, '0xEthAddr');
        expect(eth.status, HistoryStatus.error);
        final solana = await service.fetch(Coin.solana, 'SolAddr');
        expect(solana.status, HistoryStatus.error);
      },
    );

    test(
      'direct mode queries public history without gateway contact',
      () async {
        final service = HistoryService(
          client: MockClient((request) async {
            if (request.url.host.contains('blockscout')) {
              return http.Response(
                jsonEncode({
                  'status': '1',
                  'message': 'OK',
                  'result': <Object?>[],
                }),
                200,
              );
            }
            if (request.url.host.contains('solana')) {
              return http.Response(
                jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': <Object?>[]}),
                200,
              );
            }
            return http.Response(jsonEncode({'data': <Object?>[]}), 200);
          }),
          gateway: () => null,
        );
        expect((await service.fetch(Coin.eth, '0xA')).status, HistoryStatus.ok);
        expect(
          (await service.fetch(Coin.polygon, '0xA')).status,
          HistoryStatus.ok,
        );
        expect(
          (await service.fetch(Coin.solana, 'S')).status,
          HistoryStatus.ok,
        );
        expect(
          (await service.fetch(Coin.tron, 'TTronAddr')).status,
          HistoryStatus.ok,
        );
      },
    );
  });

  group('BroadcastService gateway mode', () {
    test(
      'kt_broadcast per chain with the contract payload encodings',
      () async {
        final gateway = _FakeGateway(
          results: {
            'kt_broadcast': [
              {'txHash': '0xevm'},
              {'txHash': 'solSig'},
              {'txHash': 'tronTxid'},
            ],
          },
        );
        final service = BroadcastService(
          jsonRpcTransport: _NoDirectJsonRpc(),
          restTransport: _NoDirectRest(),
          gateway: () => gateway.client,
        );

        final evm = await service.broadcast(
          Chain.ethereum,
          Uint8List.fromList([0x02, 0xab, 0x01]),
        );
        expect(evm.status, BroadcastStatus.ok);
        expect(evm.txHash, '0xevm');

        final solanaBytes = Uint8List.fromList([9, 8, 7]);
        final sol = await service.broadcast(Chain.solana, solanaBytes);
        expect(sol.txHash, 'solSig');

        final tronJson =
            '{"raw_data":{"ref_block_bytes":"1234"},"signature":["aa"]}';
        final tron = await service.broadcast(
          Chain.tron,
          Uint8List.fromList(utf8.encode(tronJson)),
        );
        expect(tron.txHash, 'tronTxid');

        final params = gateway.paramsOf('kt_broadcast');
        expect(params[0], {'chain': 'eth', 'payload': '0x02ab01'});
        expect(params[1], {
          'chain': 'solana',
          'payload': base64Encode(solanaBytes),
        });
        expect(params[2], {'chain': 'tron', 'payload': tronJson});
      },
    );

    test('-32000 node rejection: error with the node message, NO direct '
        're-post (one broadcast posts at most once)', () async {
      final gateway = _FakeGateway(
        errors: {
          'kt_broadcast': {
            'code': -32000,
            'message': 'upstream_error',
            'data': {'upstream': 'eth-node', 'message': 'nonce too low'},
          },
        },
      );
      final service = BroadcastService(
        jsonRpcTransport: _NoDirectJsonRpc(),
        restTransport: _NoDirectRest(),
        gateway: () => gateway.client,
      );
      final outcome = await service.broadcast(
        Chain.ethereum,
        Uint8List.fromList([0x02, 0x01]),
      );
      expect(outcome.status, BroadcastStatus.error);
      expect(outcome.message, 'nonce too low');
      expect(outcome.txHash, isNull);
      expect(gateway.calls, hasLength(1));
    });

    test(
      'gateway unreachable / unsupported: direct fallback posts the tx',
      () async {
        final direct = _FakeJsonRpc(
          (url, body) async => _rpcResult('0xdirecthash'),
        );
        final unreachable = BroadcastService(
          jsonRpcTransport: direct,
          gateway: _deadGateway,
        );
        final outcome = await unreachable.broadcast(
          Chain.ethereum,
          Uint8List.fromList([0x02, 0x01]),
        );
        expect(outcome.status, BroadcastStatus.ok);
        expect(outcome.txHash, '0xdirecthash');
        expect(direct.calls.single, (
          defaultEthRpcUrl,
          'eth_sendRawTransaction',
        ));

        // -32002 unsupported: the gateway never reached a node — direct is safe.
        final gateway = _FakeGateway(
          errors: {
            'kt_broadcast': {'code': -32002, 'message': 'unsupported'},
          },
        );
        final direct2 = _FakeJsonRpc((url, body) async => _rpcResult('sig'));
        final unsupported = BroadcastService(
          jsonRpcTransport: direct2,
          gateway: () => gateway.client,
        );
        final sol = await unsupported.broadcast(
          Chain.solana,
          Uint8List.fromList([1, 2]),
        );
        expect(sol.status, BroadcastStatus.ok);
        expect(sol.txHash, 'sig');
        expect(direct2.calls.single.$2, 'sendTransaction');
      },
    );

    test(
      'TRON non-JSON payload stays unsupported, gateway never called',
      () async {
        final gateway = _FakeGateway();
        final service = BroadcastService(
          jsonRpcTransport: _NoDirectJsonRpc(),
          restTransport: _NoDirectRest(),
          gateway: () => gateway.client,
        );
        final outcome = await service.broadcast(
          Chain.tron,
          Uint8List.fromList([0x0a, 0x02, 0xff]),
        );
        expect(outcome.status, BroadcastStatus.unsupported);
        expect(gateway.calls, isEmpty);
      },
    );
  });

  group('Official token catalog', () {
    test('search parses only server-verified token identities', () async {
      final gateway = _FakeGateway(
        results: {
          'kt_searchTokens': {
            'tokens': [
              {
                'network': 'eth-mainnet',
                'symbol': 'USDT',
                'name': 'Tether USD',
                'contract': '0xdac17f958d2ee523a2206206994597c13d831ec7',
                'decimals': 6,
                'popular': true,
                'verified': true,
              },
              {
                'network': 'eth-mainnet',
                'symbol': 'FAKE',
                'name': 'Untrusted',
                'contract': '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                'decimals': 18,
                'verified': false,
              },
            ],
          },
        },
      );

      final rows = await gateway.client.searchOfficialTokens(
        query: 'usdt',
        networks: const ['eth-mainnet'],
      );
      expect(rows, hasLength(1));
      expect(rows.single.symbol, 'USDT');
      expect(rows.single.popular, isTrue);
      expect(
        rows.single.identityKey,
        'eth-mainnet|0xdac17f958d2ee523a2206206994597c13d831ec7',
      );
      expect(gateway.paramsOf('kt_searchTokens').single, {
        'query': 'usdt',
        'networks': ['eth-mainnet'],
        'limit': 50,
      });
    });
  });

  group('prefsGatewayResolver (settings-driven mode switch)', () {
    test('production URL is default; blank flips to direct; custom URL flips '
        'back to gateway', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = AppPrefsController();
      await prefs.load();

      // An absent preference resolves to the production Gateway.
      final resolver = prefsGatewayResolver(prefs);
      expect(resolver()!.baseUrl, AppPrefsController.defaultGatewayUrl);

      await prefs.setGatewayUrl('   ');
      expect(resolver(), isNull);

      await prefs.setGatewayUrl('https://gw.example');
      final client = resolver();
      expect(client, isNotNull);
      expect(client!.baseUrl, 'https://gw.example');
      expect(identical(resolver(), client), isTrue); // cached per URL

      await prefs.setGatewayUrl('https://gw2.example');
      expect(resolver()!.baseUrl, 'https://gw2.example');

      await prefs.setGatewayUrl('   '); // blank = back to direct
      expect(resolver(), isNull);
      expect(prefs.gatewayUrl, isNull);
    });

    test(
      'after clearing the URL, a service takes the direct path again',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = AppPrefsController();
        await prefs.load();
        await prefs.setGatewayUrl('https://gw.example');

        // Direct transport that records; the gateway resolver resolves from
        // prefs on EVERY fetch, so the same service instance switches modes.
        final direct = _FakeJsonRpc(
          (url, body) async => (body as Map)['method'] == 'getBalance'
              ? _rpcResult({'context': <String, Object?>{}, 'value': 0})
              : _rpcResult('0x0'),
        );
        final rest = _FakeRest(onGet: (url) async => {'data': <Object?>[]});
        final gateway = _FakeGateway(
          results: {'kt_getBalances': _native('0', 18, 'ETH')},
        );
        final service = BalanceService(
          jsonRpcTransport: direct,
          restTransport: rest,
          gateway: () => prefs.gatewayUrl == null ? null : gateway.client,
        );

        await service.fetchAll(_addresses);
        expect(gateway.calls, hasLength(4)); // gateway mode
        expect(direct.calls, isEmpty);

        await prefs.setGatewayUrl(null); // user clears the field
        await service.fetchAll(_addresses);
        expect(gateway.calls, hasLength(4)); // unchanged: no new gateway calls
        expect(direct.calls, hasLength(3)); // direct mode again
        expect(rest.gets, hasLength(1));
      },
    );
  });
}
