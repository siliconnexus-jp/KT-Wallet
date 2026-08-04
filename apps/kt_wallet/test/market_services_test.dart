import 'dart:async';
import 'dart:convert';

import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart' show ChainAddresses, Coin;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kt_wallet/src/market/balance_service.dart';
import 'package:kt_wallet/src/market/price_service.dart';

/// Routes JSON-RPC posts by URL so one fake serves eth/polygon/solana.
class _FakeJsonRpc implements JsonRpcTransport {
  _FakeJsonRpc(this.handler);
  final Future<Object?> Function(String url, Object body) handler;
  @override
  Future<Object?> post(String url, Object body) => handler(url, body);
}

class _FakeRest implements RestTransport {
  _FakeRest({this.onGet});
  final Future<Object?> Function(String url)? onGet;
  @override
  Future<Object?> getJson(String url) => onGet!(url);
  @override
  Future<Object?> postJson(String url, Object body) =>
      throw UnimplementedError('balance fetches never POST to TronGrid');
}

const _addresses = ChainAddresses(
  eth: '0xEthAddr',
  polygon: '0xPolyAddr',
  tron: 'TTronAddr',
  solana: '47eFuHR9ste9kopiJ9eRxcwahmE62JovbKe5r7AjANut',
);

Map<String, Object?> _rpcResult(Object? result) => {
  'jsonrpc': '2.0',
  'id': 1,
  'result': result,
};

Map<String, Object?> _completeCoinGeckoResponse({
  Map<String, double> usd = const {},
  Map<String, double?> change24h = const {},
  int? updatedAt,
}) {
  final ids = {
    ...PriceService.coinGeckoIds.values,
    ...PriceService.coinGeckoTokenIds.values,
  };
  final sourceTime =
      updatedAt ?? DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  return {
    for (final id in ids)
      id: {
        'usd': usd[id] ?? 1.0,
        'usd_24h_change': change24h[id],
        'cny': (usd[id] ?? 1.0) * 7,
        'cny_24h_change': change24h[id],
        'jpy': (usd[id] ?? 1.0) * 150,
        'jpy_24h_change': change24h[id],
        'last_updated_at': sourceTime,
      },
  };
}

void main() {
  group('BalanceService', () {
    test('fetches all four native balances (success)', () async {
      final service = BalanceService(
        jsonRpcTransport: _FakeJsonRpc((url, body) async {
          final method = (body as Map)['method'];
          if (url == defaultEthRpcUrl) {
            expect(method, 'eth_getBalance');
            return _rpcResult('0xde0b6b3a7640000'); // 1 ETH in wei
          }
          if (url == defaultPolygonRpcUrl) {
            return _rpcResult('0x1bc16d674ec80000'); // 2 POL in wei
          }
          if (url == defaultSolanaRpcUrl) {
            expect(method, 'getBalance');
            return _rpcResult({
              'context': <String, Object?>{'slot': 1},
              'value': 500000000,
            }); // 0.5 SOL
          }
          fail('unexpected url $url');
        }),
        restTransport: _FakeRest(
          onGet: (url) async {
            expect(url, '$defaultTronApiUrl/v1/accounts/TTronAddr');
            return {
              'data': [
                {'balance': 5000000}, // 5 TRX in SUN
              ],
            };
          },
        ),
      );

      final results = await service.fetchAll(_addresses);
      expect(results.length, _addresses.enabledCoins.length);
      for (final coin in _addresses.enabledCoins) {
        expect(results[coin]!.status, BalanceStatus.ok, reason: '$coin');
      }
      expect(results[Coin.eth]!.amount!.format(), '1');
      expect(results[Coin.eth]!.amount!.symbol, 'ETH');
      expect(results[Coin.polygon]!.amount!.format(), '2');
      expect(results[Coin.tron]!.amount!.format(), '5');
      expect(results[Coin.tron]!.amount!.decimals, 6);
      expect(results[Coin.solana]!.amount!.format(), '0.5');
      expect(results[Coin.solana]!.amount!.decimals, 9);
    });

    test('an RPC error on one chain degrades only that chain', () async {
      final service = BalanceService(
        jsonRpcTransport: _FakeJsonRpc((url, body) async {
          if (url == defaultEthRpcUrl) {
            // Node rejects the demo mock address — must become error, not throw.
            return {
              'jsonrpc': '2.0',
              'id': 1,
              'error': {'code': -32000, 'message': 'invalid address'},
            };
          }
          if (url == defaultPolygonRpcUrl) return _rpcResult('0x0');
          return _rpcResult({
            'context': <String, Object?>{'slot': 1},
            'value': 0,
          });
        }),
        restTransport: _FakeRest(onGet: (url) async => {'data': <Object?>[]}),
      );

      final results = await service.fetchAll(_addresses);
      expect(results[Coin.eth]!.status, BalanceStatus.error);
      expect(results[Coin.eth]!.amount, isNull);
      expect(results[Coin.polygon]!.status, BalanceStatus.ok);
      expect(results[Coin.polygon]!.amount!.raw, BigInt.zero);
      // Unactivated TRON account reads as a real zero balance.
      expect(results[Coin.tron]!.status, BalanceStatus.ok);
      expect(results[Coin.tron]!.amount!.raw, BigInt.zero);
      expect(results[Coin.solana]!.status, BalanceStatus.ok);
    });

    test('transport timeout surfaces as error status (never throws)', () async {
      final service = BalanceService(
        jsonRpcTransport: _FakeJsonRpc(
          (url, body) => throw TimeoutException('rpc timeout'),
        ),
        restTransport: _FakeRest(
          onGet: (url) => throw TimeoutException('rest timeout'),
        ),
      );
      final results = await service.fetchAll(_addresses);
      for (final coin in _addresses.enabledCoins) {
        expect(results[coin]!.status, BalanceStatus.error, reason: '$coin');
        expect(results[coin]!.amount, isNull);
      }
    });

    test('malformed responses surface as error status', () async {
      final service = BalanceService(
        jsonRpcTransport: _FakeJsonRpc((url, body) async => 'not a map'),
        restTransport: _FakeRest(onGet: (url) async => 'not a map'),
      );
      final results = await service.fetchAll(_addresses);
      for (final coin in _addresses.enabledCoins) {
        expect(results[coin]!.status, BalanceStatus.error, reason: '$coin');
      }
    });

    test(
      'an injected endpoint resolver overrides the URLs the transports see',
      () async {
        final seenJsonUrls = <String>[];
        final seenRestUrls = <String>[];
        final service = BalanceService(
          endpoints: (coin) => 'https://custom-${coin.name}.example',
          jsonRpcTransport: _FakeJsonRpc((url, body) async {
            seenJsonUrls.add(url);
            return (body as Map)['method'] == 'getBalance'
                ? _rpcResult({
                    'context': <String, Object?>{'slot': 1},
                    'value': 0,
                  })
                : _rpcResult('0x0');
          }),
          restTransport: _FakeRest(
            onGet: (url) async {
              seenRestUrls.add(url);
              return {'data': <Object?>[]};
            },
          ),
        );

        final results = await service.fetchAll(_addresses);
        for (final coin in _addresses.enabledCoins) {
          expect(results[coin]!.status, BalanceStatus.ok, reason: '$coin');
        }
        expect(
          seenJsonUrls,
          containsAll([
            'https://custom-eth.example',
            'https://custom-polygon.example',
            'https://custom-solana.example',
          ]),
        );
        expect(
          seenRestUrls.single,
          'https://custom-tron.example/v1/accounts/TTronAddr',
        );
        // And the default resolver maps each chain to the built-in consts.
        expect(defaultRpcEndpointFor(Coin.eth), defaultEthRpcUrl);
        expect(defaultRpcEndpointFor(Coin.polygon), defaultPolygonRpcUrl);
        expect(defaultRpcEndpointFor(Coin.tron), defaultTronApiUrl);
        expect(defaultRpcEndpointFor(Coin.solana), defaultSolanaRpcUrl);
      },
    );
  });

  group('PriceService', () {
    test('parses CoinGecko simple/price and caches last-good', () async {
      final service = PriceService(
        client: MockClient((request) async {
          expect(request.url.path, '/api/v3/simple/price');
          expect(request.url.queryParameters['vs_currencies'], 'usd,cny,jpy');
          expect(request.url.queryParameters['include_24hr_change'], 'true');
          expect(
            request.url.queryParameters['include_last_updated_at'],
            'true',
          );
          expect(request.url.queryParameters['precision'], 'full');
          return http.Response(
            jsonEncode(
              _completeCoinGeckoResponse(
                usd: const {
                  'ethereum': 2500,
                  'polygon-ecosystem-token': 0.4,
                  'tron': 0.12,
                  'solana': 150,
                  'tether': 0.997,
                  'usd-coin': 1.001,
                },
                change24h: const {
                  'ethereum': 2.5,
                  'polygon-ecosystem-token': -3,
                  'tron': null,
                  'solana': 1,
                  'tether': -0.1,
                  'usd-coin': 0.05,
                },
              ),
            ),
            200,
          );
        }),
      );

      final prices = await service.fetchUsdPrices();
      expect(prices, isNotNull);
      expect(prices![Coin.eth], 2500.0);
      expect(prices[Coin.polygon], 0.4);
      expect(prices[Coin.tron], 0.12);
      expect(prices[Coin.solana], 150.0);
      expect(service.lastGoodUsd, prices);
      expect(service.tokenPriceUsd('USDT'), 0.997);
      expect(service.tokenPriceUsd('USDC'), 1.001);
      expect(service.change24hPercent(Coin.eth), 2.5);
      expect(service.change24hPercent(Coin.polygon), -3.0);
      expect(service.change24hPercent(Coin.tron), isNull);
      expect(service.tokenChange24hPercent('USDT'), -0.1);
      expect(service.tokenChange24hPercent('USDC'), 0.05);
      expect(service.fiatPerUsd('CNY'), 7);
      expect(service.fiatPerUsd('JPY'), 150);
    });

    test('non-200 → null, keeping the previous last-good cache', () async {
      var fail = false;
      final service = PriceService(
        client: MockClient(
          (request) async => fail
              ? http.Response('rate limited', 429)
              : http.Response(
                  jsonEncode(
                    _completeCoinGeckoResponse(usd: const {'ethereum': 2000}),
                  ),
                  200,
                ),
        ),
      );
      final first = await service.fetchUsdPrices();
      expect(first![Coin.eth], 2000.0);

      fail = true;
      expect(await service.fetchUsdPrices(), isNull);
      expect(service.lastGoodUsd![Coin.eth], 2000.0);
    });

    test('one malformed direct quote rejects the whole valuation', () async {
      final service = PriceService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'ethereum': {
                'usd': -2000,
                'cny': -14000,
                'jpy': 0,
                'usd_24h_change': 4,
              },
              'tron': {'usd': 0.12, 'usd_24h_change': -1.25},
              'tether': {'usd': 0, 'usd_24h_change': 2},
            }),
            200,
          ),
        ),
      );

      expect(await service.fetchUsdPrices(), isNull);
      expect(service.change24hPercent(Coin.eth), isNull);
      expect(service.change24hPercent(Coin.tron), isNull);
      expect(service.tokenPriceUsd('USDT'), isNull);
      expect(service.tokenChange24hPercent('USDT'), isNull);
      expect(service.lastGoodFiatPerUsd, {'USD': 1});
    });

    test(
      'direct CoinGecko rejects duplicate, additive, partial and stale truth',
      () async {
        Map<String, Object?> freshResponse() =>
            jsonDecode(jsonEncode(_completeCoinGeckoResponse()))
                as Map<String, Object?>;

        final validJson = jsonEncode(freshResponse());
        final duplicateEthereum =
            '{"ethereum":${jsonEncode(freshResponse()['ethereum'])},'
            '${validJson.substring(1)}';

        final additiveQuote = freshResponse();
        (additiveQuote['ethereum'] as Map<String, Object?>)['unexpected'] =
            true;

        final additiveTopLevel = freshResponse()
          ..['unrequested-coin'] = freshResponse()['ethereum'];

        final partial = freshResponse()..remove('ethereum');

        final stale = freshResponse();
        (stale['ethereum'] as Map<String, Object?>)['last_updated_at'] =
            DateTime.now()
                .subtract(const Duration(minutes: 16))
                .millisecondsSinceEpoch ~/
            1000;

        final inconsistentFx = freshResponse();
        (inconsistentFx['tron'] as Map<String, Object?>)['cny'] = 1.0;

        final bodies = <String>[
          duplicateEthereum,
          jsonEncode(additiveQuote),
          jsonEncode(additiveTopLevel),
          jsonEncode(partial),
          jsonEncode(stale),
          jsonEncode(inconsistentFx),
        ];
        for (final body in bodies) {
          final service = PriceService(
            client: MockClient((_) async => http.Response(body, 200)),
          );
          expect(await service.fetchUsdPrices(), isNull, reason: body);
          expect(service.lastGoodUsd, isNull);
        }
      },
    );

    test('timeout → null', () async {
      final service = PriceService(
        timeout: const Duration(milliseconds: 1),
        client: MockClient((request) async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          return http.Response('{}', 200);
        }),
      );
      expect(await service.fetchUsdPrices(), isNull);
      expect(service.lastGoodUsd, isNull);
    });

    test(
      'malformed body → null; stablecoin prices remain unavailable',
      () async {
        final service = PriceService(
          client: MockClient((request) async => http.Response('[]', 200)),
        );
        expect(await service.fetchUsdPrices(), isNull);
        expect(service.tokenPriceUsd('USDT'), isNull);
        expect(service.tokenPriceUsd('USDC'), isNull);
      },
    );
  });
}
