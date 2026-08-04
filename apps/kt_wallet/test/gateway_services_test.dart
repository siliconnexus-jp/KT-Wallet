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

const _evmFrom = '0x1111111111111111111111111111111111111111';
const _evmTo = '0x2222222222222222222222222222222222222222';
const _tronOwner = 'TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH';
const _evmBroadcastHash =
    '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _solanaBroadcastSignature =
    '1111111111111111111111111111111111111111111111111111111111111111';
const _tronBroadcastTxID =
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
const _addresses = ChainAddresses(
  eth: _evmFrom,
  polygon: _evmFrom,
  tron: _tronOwner,
  solana: '47eFuHR9ste9kopiJ9eRxcwahmE62JovbKe5r7AjANut',
);

Map<String, Object?> _completeCoinGeckoResponse({
  Map<String, double> usd = const {},
}) {
  final ids = {
    ...PriceService.coinGeckoIds.values,
    ...PriceService.coinGeckoTokenIds.values,
  };
  final sourceTime = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  return {
    for (final id in ids)
      id: {
        'usd': usd[id] ?? 1.0,
        'usd_24h_change': null,
        'cny': (usd[id] ?? 1.0) * 7,
        'cny_24h_change': null,
        'jpy': (usd[id] ?? 1.0) * 150,
        'jpy_24h_change': null,
        'last_updated_at': sourceTime,
      },
  };
}

Map<String, Object?> _completeGatewayPriceResult({
  Map<String, double> usd = const {},
  Map<String, double?> change24h = const {},
}) {
  final symbols = {
    for (final coin in Coin.values) BalanceService.symbolFor[coin]!,
    ...PriceService.coinGeckoTokenIds.keys,
  };
  return {
    'prices': {
      for (final symbol in symbols)
        symbol: {
          'usd': usd[symbol] ?? 1.0,
          if (change24h.containsKey(symbol)) 'change24h': change24h[symbol],
        },
    },
    'fiatPerUsd': {'USD': 1, 'CNY': 7, 'JPY': 150},
    'cachedAtMs': DateTime.now().millisecondsSinceEpoch,
  };
}

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
        if (method == 'kt_getBalances') {
          final chain = calls.last.$2['chain'];
          final expectedSymbol = switch (chain) {
            'eth' || 'base' || 'arbitrum' => 'ETH',
            'polygon' => 'POL',
            'avalanche' => 'AVAX',
            'bnb' => 'BNB',
            'tron' => 'TRX',
            'solana' => 'SOL',
            _ => null,
          };
          result = result.whereType<Map<Object?, Object?>>().firstWhere(
            (row) =>
                (row['native'] as Map<Object?, Object?>?)?['symbol'] ==
                expectedSymbol,
          );
        } else {
          final index = _served[method] ?? 0;
          _served[method] = index + 1;
          result = result[index < result.length ? index : result.length - 1];
        }
      }
      result = _bindBalanceResult(method, result, calls.last.$2);
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

Map<String, Object?> _zeroNative(Coin coin, {List<Object?>? tokens}) {
  final (decimals, symbol) = switch (coin) {
    Coin.eth => (18, 'ETH'),
    Coin.polygon => (18, 'POL'),
    Coin.base => (18, 'ETH'),
    Coin.arbitrum => (18, 'ETH'),
    Coin.avalanche => (18, 'AVAX'),
    Coin.bnb => (18, 'BNB'),
    Coin.tron => (6, 'TRX'),
    Coin.solana => (9, 'SOL'),
  };
  return {
    'native': {'raw': '0', 'decimals': decimals, 'symbol': symbol},
    'tokens': ?tokens,
  };
}

Object? _bindBalanceResult(
  String method,
  Object? result,
  Map<String, Object?> params,
) {
  if (result is! Map) return result;
  if (method != 'kt_getBalances' && method != 'kt_getHistory') return result;
  final chain = params['chain'] as String;
  final mainnet = switch (chain) {
    'solana' => 'sol-mainnet',
    _ => '$chain-mainnet',
  };
  if (method == 'kt_getHistory') {
    return <String, Object?>{
      'chain': chain,
      'network': params['network'] ?? mainnet,
      'address': params['address'],
      ...result.cast<String, Object?>(),
    };
  }
  final requestedTokens = (params['tokens'] as List?) ?? const <Object?>[];
  final scriptedTokens = (result['tokens'] as List?) ?? const <Object?>[];
  final boundTokens = <Object?>[
    for (final requested in requestedTokens)
      if (requested is Map<Object?, Object?>)
        scriptedTokens
            .cast<Object?>()
            .whereType<Map<Object?, Object?>>()
            .firstWhere(
              (row) => row['contract'] == requested['contract'],
              orElse: () => <String, Object?>{
                'contract': requested['contract'],
                'raw': '0',
                'decimals': requested['decimals'],
                'symbol': requested['symbol'],
              },
            ),
  ];
  return <String, Object?>{
    'chain': chain,
    'network': params['network'] ?? mainnet,
    'address': params['address'],
    'native': result['native'],
    'tokens': boundTokens,
  };
}

void main() {
  group('Gateway network identity', () {
    test('parses exact EVM, TRON and Solana mainnet identities', () async {
      const tronGenesis =
          '00000000000000001ebf88508a03865c71d452e25f4d51194196a1d22b6653dc';
      const solanaGenesis = '5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d';
      final gateway = _FakeGateway(
        results: {
          'kt_getNetworkIdentity': [
            {'network': 'eth-mainnet', 'identity': '1'},
            {'network': 'tron-mainnet', 'identity': tronGenesis},
            {'network': 'sol-mainnet', 'identity': solanaGenesis},
          ],
        },
      );

      expect(await gateway.client.getNetworkIdentity(chain: Coin.eth), '1');
      expect(
        await gateway.client.getNetworkIdentity(chain: Coin.tron),
        tronGenesis,
      );
      expect(
        await gateway.client.getNetworkIdentity(chain: Coin.solana),
        solanaGenesis,
      );
    });

    test('rejects network mismatch and additive response fields', () async {
      final wrongNetwork = _FakeGateway(
        results: {
          'kt_getNetworkIdentity': {'network': 'eth-sepolia', 'identity': '1'},
        },
      );
      await expectLater(
        wrongNetwork.client.getNetworkIdentity(chain: Coin.eth),
        throwsA(isA<FormatException>()),
      );

      final extraField = _FakeGateway(
        results: {
          'kt_getNetworkIdentity': {
            'network': 'eth-mainnet',
            'identity': '1',
            'trusted': true,
          },
        },
      );
      await expectLater(
        extraField.client.getNetworkIdentity(chain: Coin.eth),
        throwsA(isA<FormatException>()),
      );
    });
  });

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
        _tronOwner,
      );
      // Native-only calls: the token registry goes via TokenBalanceService.
      for (final p in params) {
        expect(p.containsKey('tokens'), isFalse);
      }
    });

    test('gateway failure falls back to the direct path per chain', () async {
      final direct = _FakeJsonRpc(
        (url, body) async => (body as Map)['method'] == 'getBalance'
            ? _rpcResult({
                'context': <String, Object?>{'slot': 1},
                'value': 0,
              })
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
      expect(rest.gets.single, '$defaultTronApiUrl/v1/accounts/$_tronOwner');
    });

    test('direct mode (null resolver) never contacts the gateway', () async {
      final direct = _FakeJsonRpc(
        (url, body) async => (body as Map)['method'] == 'getBalance'
            ? _rpcResult({
                'context': <String, Object?>{'slot': 1},
                'value': 0,
              })
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
      'exact portfolio response serves every chain without per-chain calls',
      () async {
        const tokens = [
          TokenInfo(
            id: 'test-usdt-eth',
            symbol: 'USDT',
            chain: Coin.eth,
            contract: '0xdAC17F958D2ee523a2206206994597C13D831ec7',
            decimals: 6,
            network: 'Ethereum',
          ),
          TokenInfo(
            id: 'test-usdc-polygon',
            symbol: 'USDC',
            chain: Coin.polygon,
            contract: '0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359',
            decimals: 6,
            network: 'Polygon',
          ),
        ];
        final gateway = _FakeGateway(
          results: {
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
                    'tokens': [
                      {
                        'contract':
                            '0xdAC17F958D2ee523a2206206994597C13D831ec7',
                        'raw': '120500000',
                        'decimals': 6,
                        'symbol': 'USDT',
                      },
                    ],
                  },
                },
                {
                  'chain': 'polygon',
                  'network': 'polygon-mainnet',
                  'address': _evmFrom,
                  'result': {
                    'chain': 'polygon',
                    'network': 'polygon-mainnet',
                    'address': _evmFrom,
                    'native': {
                      'raw': '2000000000000000000',
                      'decimals': 18,
                      'symbol': 'POL',
                    },
                    'tokens': [
                      {
                        'contract':
                            '0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359',
                        'raw': '99000000',
                        'decimals': 6,
                        'symbol': 'USDC',
                      },
                    ],
                  },
                },
              ],
            },
          },
        );
        final service = TokenBalanceService(
          jsonRpcTransport: _NoDirectJsonRpc(),
          restTransport: _NoDirectRest(),
          gateway: () => gateway.client,
          tokens: tokens,
        );

        final batch = await service.fetchAllWithNative(_addresses);

        expect(batch.tokens['test-usdt-eth']!.amount!.format(), '120.5');
        expect(batch.tokens['test-usdc-polygon']!.amount!.format(), '99');
        expect(batch.native[Coin.eth]!.amount!.format(), '1');
        expect(batch.native[Coin.polygon]!.amount!.format(), '2');
        expect(batch.gatewayFailedChains, isEmpty);
        expect(gateway.paramsOf('kt_getPortfolio'), hasLength(1));
        expect(gateway.paramsOf('kt_getBalances'), isEmpty);
      },
    );

    test(
      'one call per chain with its registry tokens; per-token errors map',
      () async {
        final tokenRows = <Object?>[
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
        ];
        final gateway = _FakeGateway(
          results: {
            'kt_getBalances': [
              for (final coin in Coin.values)
                _zeroNative(coin, tokens: tokenRows),
            ],
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
      final direct = _FakeJsonRpc(
        (url, body) async => _rpcResult('0x${'0' * 64}'),
      );
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
        final cachedAtMs = DateTime.now().millisecondsSinceEpoch;
        final gateway = _FakeGateway(
          results: {
            'kt_getPrices': _completeGatewayPriceResult(
              usd: const {
                'ETH': 2500,
                'POL': 0.4,
                'TRX': 0.12,
                'SOL': 150,
                'USDT': 0.998,
                'USDC': 1.001,
              },
              change24h: const {
                'ETH': 2.5,
                'POL': -3,
                'SOL': 1,
                'USDT': -0.1,
                'USDC': 0.05,
              },
            )..['cachedAtMs'] = cachedAtMs,
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
        expect(service.fiatPerUsd('CNY'), 7);
        expect(service.fiatPerUsd('JPY'), 150);
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
            jsonEncode(
              _completeCoinGeckoResponse(usd: const {'ethereum': 2000}),
            ),
            200,
          );
        }),
        gateway: _deadGateway,
      );
      final prices = await service.fetchUsdPrices();
      expect(prices![Coin.eth], 2000.0);
      expect(coinGeckoHits, 1);
    });

    test(
      'a partial known-symbol gateway answer falls back as one unit',
      () async {
        var coinGeckoHits = 0;
        final gateway = _FakeGateway(
          results: {
            'kt_getPrices': _completeGatewayPriceResult()
              ..['prices'] = {
                'ETH': {'usd': 999999.0},
              },
          },
        );
        final service = PriceService(
          client: MockClient((_) async {
            coinGeckoHits++;
            return http.Response(
              jsonEncode(
                _completeCoinGeckoResponse(usd: const {'ethereum': 2000}),
              ),
              200,
            );
          }),
          gateway: () => gateway.client,
        );

        final prices = await service.fetchUsdPrices();

        expect(coinGeckoHits, 1);
        expect(prices![Coin.eth], 2000.0);
        expect(service.lastGoodUsd![Coin.eth], 2000.0);
      },
    );

    test('an all-unknown-symbols gateway answer also falls back', () async {
      final gateway = _FakeGateway(
        results: {
          'kt_getPrices': {
            'prices': <String, Object?>{},
            'fiatPerUsd': {'USD': 1},
            'cachedAtMs': DateTime.now().millisecondsSinceEpoch,
          },
        },
      );
      final service = PriceService(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode(_completeCoinGeckoResponse(usd: const {'tron': 0.11})),
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
            jsonEncode(
              _completeCoinGeckoResponse(usd: const {'solana': 149.0}),
            ),
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
            'network': 'eth-mainnet',
            'address': _evmFrom,
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

      final params = await service.fetchEvmParams(Chain.ethereum, _evmFrom);
      expect(params.nonce, 7);
      expect(params.tierFor(0).maxFeePerGas, BigInt.from(10));
      expect(params.tierFor(1).maxPriorityFeePerGas, BigInt.from(2));
      expect(params.tierFor(2).maxFeePerGas, BigInt.from(30));
      expect(gateway.paramsOf('kt_getChainParams').single, {
        'chain': 'eth',
        'address': _evmFrom,
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
              'oldestBlock': '0x64',
              'baseFeePerGas': ['0x3b9aca00', '0x3b9aca00'],
              'gasUsedRatio': [0.5],
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
      final nativeHash = '0x${'a' * 64}';
      final tokenHash = '0x${'b' * 64}';
      final gateway = _FakeGateway(
        results: {
          'kt_getHistory': {
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

      final result = await service.fetch(Coin.eth, _evmFrom);
      expect(result.status, HistoryStatus.ok);
      expect(result.records, hasLength(2));
      // Newest first.
      expect(result.records[0].hash, tokenHash);
      expect(result.records[0].outgoing, isFalse);
      expect(result.records[0].fromAddress, _evmTo);
      expect(result.records[0].toAddress, _evmFrom);
      expect(result.records[0].confirmed, isFalse); // status: failed
      expect(result.records[0].amountText, '2 USDT');
      expect(result.records[0].id, '$tokenHash:7');
      expect(result.records[0].assetVerified, isFalse);
      expect(
        result.records[0].assetContract,
        '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
      expect(result.records[1].hash, nativeHash);
      expect(result.records[1].outgoing, isTrue);
      expect(result.records[1].confirmed, isTrue);
      expect(result.records[1].amountText, '1.5 ETH');
      expect(result.records[1].assetVerified, isTrue);
      expect(gateway.paramsOf('kt_getHistory').single, {
        'chain': 'eth',
        'address': _evmFrom,
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
      final result = await service.fetch(
        Coin.solana,
        '47eFuHR9ste9kopiJ9eRxcwahmE62JovbKe5r7AjANut',
      );
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
            return http.Response(
              jsonEncode({'data': <Object?>[], 'success': true}),
              200,
            );
          }),
          gateway: _deadGateway,
        );

        final tron = await service.fetch(
          Coin.tron,
          'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
        );
        expect(tron.status, HistoryStatus.ok); // direct TronGrid answered
        expect(tronGridHits, 3); // trc20 + native + internal endpoints

        // Invalid direct-fallback addresses remain an honest error after the
        // gateway fails, never a silent "unsupported" or network request.
        final eth = await service.fetch(Coin.eth, '0xEthAddr');
        expect(eth.status, HistoryStatus.error);
        final solana = await service.fetch(
          Coin.solana,
          '47eFuHR9ste9kopiJ9eRxcwahmE62JovbKe5r7AjANut',
        );
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
              final payload = jsonDecode(request.body) as Map<String, dynamic>;
              final result = payload['method'] == 'getTokenAccountsByOwner'
                  ? {
                      'context': {'slot': 1},
                      'value': <Object?>[],
                    }
                  : <Object?>[];
              return http.Response(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'id': payload['id'],
                  'result': result,
                }),
                200,
              );
            }
            return http.Response(
              jsonEncode({'data': <Object?>[], 'success': true}),
              200,
            );
          }),
          gateway: () => null,
        );
        const evmAddress = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
        expect(
          (await service.fetch(Coin.eth, evmAddress)).status,
          HistoryStatus.ok,
        );
        expect(
          (await service.fetch(Coin.polygon, evmAddress)).status,
          HistoryStatus.ok,
        );
        expect(
          (await service.fetch(
            Coin.solana,
            '47eFuHR9ste9kopiJ9eRxcwahmE62JovbKe5r7AjANut',
          )).status,
          HistoryStatus.ok,
        );
        expect(
          (await service.fetch(
            Coin.tron,
            'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
          )).status,
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
              {
                'chain': 'eth',
                'network': 'eth-mainnet',
                'txHash': _evmBroadcastHash,
              },
              {
                'chain': 'solana',
                'network': 'sol-mainnet',
                'txHash': _solanaBroadcastSignature,
              },
              {
                'chain': 'tron',
                'network': 'tron-mainnet',
                'txHash': _tronBroadcastTxID,
              },
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
          expectedTxHash: _evmBroadcastHash.toUpperCase(),
        );
        expect(evm.status, BroadcastStatus.ok);
        expect(evm.txHash, _evmBroadcastHash.toUpperCase());

        final solanaBytes = Uint8List.fromList([9, 8, 7]);
        final sol = await service.broadcast(
          Chain.solana,
          solanaBytes,
          expectedTxHash: _solanaBroadcastSignature,
        );
        expect(sol.txHash, _solanaBroadcastSignature);

        final tronJson =
            '{"raw_data":{"ref_block_bytes":"1234"},"signature":["aa"]}';
        final tron = await service.broadcast(
          Chain.tron,
          Uint8List.fromList(utf8.encode(tronJson)),
          expectedTxHash: _tronBroadcastTxID.toUpperCase(),
        );
        expect(tron.txHash, _tronBroadcastTxID.toUpperCase());

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
        expectedTxHash: '0xlocal',
      );
      expect(outcome.status, BroadcastStatus.error);
      expect(outcome.message, 'transaction nonce is too low');
      expect(outcome.txHash, isNull);
      expect(gateway.calls, hasLength(1));
    });

    test('-32003 submission unknown: preserve local reconciliation and never '
        'direct re-post', () async {
      final gateway = _FakeGateway(
        errors: {
          'kt_broadcast': {
            'code': -32003,
            'message': 'submission_unknown',
            'data': {
              'upstream': 'eth-node',
              'message': 'upstream returned HTTP 503',
            },
          },
        },
      );
      final direct = _FakeJsonRpc(
        (url, body) async => _rpcResult('0xmust-not-be-used'),
      );
      final service = BroadcastService(
        jsonRpcTransport: direct,
        gateway: () => gateway.client,
      );

      final outcome = await service.broadcast(
        Chain.ethereum,
        Uint8List.fromList([0x02, 0x01]),
        expectedTxHash: '0xlocal',
      );
      expect(outcome.status, BroadcastStatus.unknown);
      expect(outcome.txHash, isNull);
      expect(gateway.calls, hasLength(1));
      expect(direct.calls, isEmpty);
    });

    test(
      'answered preflight-looking errors never re-post signed bytes directly',
      () async {
        for (final error in <Map<String, Object?>>[
          {
            'code': -32002,
            'message': 'unsupported',
            'data': {
              'upstream': 'eth-node',
              'message': 'request may have been forwarded',
            },
          },
          {'code': -32001, 'message': 'rate_limited'},
        ]) {
          final gateway = _FakeGateway(errors: {'kt_broadcast': error});
          final direct = _FakeJsonRpc(
            (url, body) async => _rpcResult(_evmBroadcastHash),
          );
          final service = BroadcastService(
            jsonRpcTransport: direct,
            gateway: () => gateway.client,
          );

          final outcome = await service.broadcast(
            Chain.ethereum,
            Uint8List.fromList([0x02, 0x01]),
            expectedTxHash: _evmBroadcastHash,
          );

          expect(outcome.status, BroadcastStatus.unknown, reason: '$error');
          expect(outcome.txHash, isNull, reason: '$error');
          expect(gateway.calls, hasLength(1), reason: '$error');
          expect(direct.calls, isEmpty, reason: '$error');
        }
      },
    );

    test(
      'gateway response loss and answered unsupported both stay unknown',
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
          expectedTxHash: '0xlocal',
        );
        expect(outcome.status, BroadcastStatus.unknown);
        expect(outcome.txHash, isNull);
        expect(direct.calls, isEmpty);

        // A remote -32002 is only a claim. It cannot prove that a proxy or
        // stale Gateway instance did not already forward the signed bytes.
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
          expectedTxHash: 'sig',
        );
        expect(sol.status, BroadcastStatus.unknown);
        expect(sol.txHash, isNull);
        expect(direct2.calls, isEmpty);
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
          expectedTxHash: 'tronTxid',
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

    for (final (label, result) in <(String, Map<String, Object?>)>[
      (
        'wrong requested network',
        {
          'tokens': [
            {
              'network': 'polygon-mainnet',
              'symbol': 'USDT',
              'name': 'Tether USD',
              'contract': '0xc2132d05d31c914a87c6611c10748aeb04b58e8f',
              'decimals': 6,
              'verified': true,
            },
          ],
        },
      ),
      (
        'query mismatch',
        {
          'tokens': [
            {
              'network': 'eth-mainnet',
              'symbol': 'USDC',
              'name': 'USD Coin',
              'contract': '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48',
              'decimals': 6,
              'verified': true,
            },
          ],
        },
      ),
      (
        'unknown row field',
        {
          'tokens': [
            {
              'network': 'eth-mainnet',
              'symbol': 'USDT',
              'name': 'Tether USD',
              'contract': '0xdac17f958d2ee523a2206206994597c13d831ec7',
              'decimals': 6,
              'verified': true,
              'trustedBy': 'remote',
            },
          ],
        },
      ),
      (
        'invalid contract identity',
        {
          'tokens': [
            {
              'network': 'eth-mainnet',
              'symbol': 'USDT',
              'name': 'Tether USD',
              'contract': '0xnot-an-address',
              'decimals': 6,
              'verified': true,
            },
          ],
        },
      ),
      ('unknown result field', {'tokens': <Object?>[], 'source': 'remote'}),
      (
        'duplicate official identity',
        {
          'tokens': [
            for (var i = 0; i < 2; i++)
              {
                'network': 'eth-mainnet',
                'symbol': 'USDT',
                'name': 'Tether USD',
                'contract': '0xdac17f958d2ee523a2206206994597c13d831ec7',
                'decimals': 6,
                'verified': true,
              },
          ],
        },
      ),
    ]) {
      test('search fails closed on $label', () async {
        final gateway = _FakeGateway(results: {'kt_searchTokens': result});
        await expectLater(
          gateway.client.searchOfficialTokens(
            query: 'usdt',
            networks: const ['eth-mainnet'],
          ),
          throwsA(isA<FormatException>()),
        );
      });
    }
  });

  group('Token risk assessment', () {
    test('parses safe, unsafe and unknown without elevating unknown', () async {
      const requestedEvmContract = '0xAaAaAaAaAaAaAaAaAaAaAaAaAaAaAaAaAaAaAaAa';
      final gateway = _FakeGateway(
        results: {
          'kt_checkTokenRisk': {
            'status': 'unsafe',
            'category': 'phishing',
            'source': 'operator_registry',
            'network': 'eth-mainnet',
            'contract': '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          },
        },
      );

      final risk = await gateway.client.checkTokenRisk(
        chain: Coin.eth,
        contract: requestedEvmContract,
      );
      expect(risk.status, GatewayTokenRiskStatus.unsafe);
      expect(risk.category, 'phishing');
      expect(risk.source, 'operator_registry');
      expect(gateway.paramsOf('kt_checkTokenRisk').single, {
        'chain': 'eth',
        'contract': requestedEvmContract,
      });

      gateway.results['kt_checkTokenRisk'] = {
        'status': 'unknown',
        'source': 'operator_registry',
        'network': 'sol-mainnet',
        'contract': '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU',
      };
      final unknown = await gateway.client.checkTokenRisk(
        chain: Coin.solana,
        contract: '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU',
      );
      expect(unknown.status, GatewayTokenRiskStatus.unknown);
      expect(unknown.category, isNull);

      const tronContract = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';
      gateway.results['kt_checkTokenRisk'] = {
        'status': 'unknown',
        'source': 'operator_registry',
        'network': 'tron-mainnet',
        'contract': tronContract,
      };
      final tron = await gateway.client.checkTokenRisk(
        chain: Coin.tron,
        contract: tronContract,
      );
      expect(tron.status, GatewayTokenRiskStatus.unknown);
    });

    test('malformed and unsupported service answers fail closed', () async {
      for (final response in <Map<String, Object?>>[
        {'status': 'safe'},
        {'status': 'green', 'source': 'operator_registry'},
        {'status': 'safe', 'source': 42},
      ]) {
        final gateway = _FakeGateway(results: {'kt_checkTokenRisk': response});
        await expectLater(
          gateway.client.checkTokenRisk(
            chain: Coin.eth,
            contract: '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          ),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test(
      'risk answers are bound to the requested identity and source semantics',
      () async {
        const contract = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
        final responses = <Map<String, Object?>>[
          {
            'status': 'safe',
            'source': 'official_catalog',
            'network': 'polygon-mainnet',
            'contract': contract,
          },
          {
            'status': 'safe',
            'source': 'official_catalog',
            'network': 'eth-mainnet',
            'contract': '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          },
          {
            'status': 'safe',
            'source': 'goplus',
            'network': 'eth-mainnet',
            'contract': contract,
          },
          {
            'status': 'unknown',
            'source': 'official_catalog',
            'network': 'eth-mainnet',
            'contract': contract,
          },
          {
            'status': 'safe',
            'category': 'phishing',
            'source': 'official_catalog',
            'network': 'eth-mainnet',
            'contract': contract,
          },
          {
            'status': 'safe',
            'source': 'official_catalog',
            'network': 'eth-mainnet',
            'contract': contract,
            'remoteSecurityOverride': true,
          },
        ];
        for (final response in responses) {
          final gateway = _FakeGateway(
            results: {'kt_checkTokenRisk': response},
          );
          await expectLater(
            gateway.client.checkTokenRisk(chain: Coin.eth, contract: contract),
            throwsFormatException,
            reason: 'remote risk identity must fail closed: $response',
          );
        }

        const solanaMint = '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU';
        final solanaGateway = _FakeGateway(
          results: {
            'kt_checkTokenRisk': {
              'status': 'safe',
              'source': 'official_catalog',
              'network': 'sol-mainnet',
              'contract': '${solanaMint.substring(0, 43)}V',
            },
          },
        );
        await expectLater(
          solanaGateway.client.checkTokenRisk(
            chain: Coin.solana,
            contract: solanaMint,
          ),
          throwsFormatException,
          reason: 'Solana mint identity must remain case-sensitive',
        );
      },
    );
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
      expect(
        identical(resolver(), prefsGatewayResolver(prefs)()),
        isTrue,
        reason: 'all app surfaces should reuse one gateway connection pool',
      );

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
              ? _rpcResult({
                  'context': <String, Object?>{'slot': 1},
                  'value': 0,
                })
              : _rpcResult('0x0'),
        );
        final rest = _FakeRest(onGet: (url) async => {'data': <Object?>[]});
        final gateway = _FakeGateway(
          results: {
            'kt_getBalances': [
              for (final coin in _addresses.enabledCoins) _zeroNative(coin),
            ],
          },
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
