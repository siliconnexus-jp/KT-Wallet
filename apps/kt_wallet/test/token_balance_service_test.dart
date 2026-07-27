import 'dart:async';

import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart' show ChainAddresses, Coin;
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/market/balance_service.dart';
import 'package:kt_wallet/src/market/token_balance_service.dart';

/// Routes JSON-RPC posts by URL so one fake serves both EVM chains.
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
      throw UnimplementedError('token balance fetches never POST to TronGrid');
}

const _addresses = ChainAddresses(
  eth: '0xEthAddr',
  polygon: '0xPolyAddr',
  tron: 'TTronAddr',
  solana: 'SolAddr',
);

// Registry contracts (see the provenance comments in the registry itself).
const _usdtEth = '0xdAC17F958D2ee523a2206206994597C13D831ec7';
const _usdcPolygon = '0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359';
const _usdtTron = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';

Map<String, Object?> _rpcResult(Object? result) => {
  'jsonrpc': '2.0',
  'id': 1,
  'result': result,
};

String _hex(int value) => '0x${BigInt.from(value).toRadixString(16)}';

void main() {
  test('protected symbols require a known official contract identity', () {
    expect(isProtectedTokenSymbol('usdt'), isTrue);
    expect(isKnownOfficialTokenIdentity('USDT', usdtEthToken.contract), isTrue);
    expect(
      isKnownOfficialTokenIdentity('USDT', usdtTronToken.contract),
      isTrue,
    );
    expect(isKnownOfficialTokenIdentity('USDT', '0x${'a' * 40}'), isFalse);
    expect(
      isKnownOfficialTokenIdentity('BUSD', officialBusdEthereumContract),
      isTrue,
    );
  });

  test('the default static registry carries canonical stablecoins', () {
    expect(builtinTokens.map((t) => t.id).toSet(), {
      'usdt-eth',
      'usdc-polygon',
      'usdt-tron',
      'usdt-polygon',
      'usdt-base',
      'usdt-arbitrum',
      'usdt-avalanche',
      'usdt-solana',
    });
    for (final token in builtinTokens) {
      expect(token.decimals, 6, reason: token.id);
    }
    final byId = {for (final t in builtinTokens) t.id: t};
    expect(byId['usdt-eth']!.chain, Coin.eth);
    expect(byId['usdt-eth']!.contract, _usdtEth);
    expect(byId['usdc-polygon']!.chain, Coin.polygon);
    expect(byId['usdc-polygon']!.contract, _usdcPolygon);
    expect(byId['usdt-tron']!.chain, Coin.tron);
    expect(byId['usdt-tron']!.contract, _usdtTron);
  });

  test(
    'fetches ERC-20 (eth_call balanceOf) and TRC-20 balances (success)',
    () async {
      final service = TokenBalanceService(
        jsonRpcTransport: _FakeJsonRpc((url, body) async {
          final map = body as Map;
          expect(map['method'], 'eth_call');
          final call = (map['params'] as List).first as Map;
          if (url == defaultEthRpcUrl) {
            expect(call['to'], _usdtEth);
            // balanceOf(address) selector + owner left-padded to 32 bytes.
            expect(call['data'], '0x70a08231${'0' * 24}EthAddr');
            return _rpcResult(_hex(25000000)); // 25 USDT
          }
          if (url == defaultPolygonRpcUrl) {
            expect(call['to'], _usdcPolygon);
            return _rpcResult(_hex(10000000)); // 10 USDC
          }
          fail('unexpected url $url');
        }),
        restTransport: _FakeRest(
          onGet: (url) async {
            expect(url, '$defaultTronApiUrl/v1/accounts/TTronAddr');
            return {
              'data': [
                {
                  'balance': 5000000,
                  'trc20': [
                    {'TOtherContract': '1'},
                    {_usdtTron: '12345678'},
                  ],
                },
              ],
            };
          },
        ),
      );

      final results = await service.fetchAll(_addresses);
      expect(results.length, builtinTokens.length);
      expect(results['usdt-eth']!.status, BalanceStatus.ok);
      expect(results['usdt-eth']!.amount!.format(), '25');
      expect(results['usdt-eth']!.amount!.symbol, 'USDT');
      expect(results['usdc-polygon']!.status, BalanceStatus.ok);
      expect(results['usdc-polygon']!.amount!.format(), '10');
      expect(results['usdc-polygon']!.amount!.symbol, 'USDC');
      expect(results['usdt-tron']!.status, BalanceStatus.ok);
      expect(results['usdt-tron']!.amount!.format(), '12.345678');
      expect(results['usdt-tron']!.amount!.decimals, 6);
    },
  );

  test('one failing endpoint degrades only that token', () async {
    final service = TokenBalanceService(
      jsonRpcTransport: _FakeJsonRpc((url, body) async {
        if (url == defaultEthRpcUrl) {
          // Node rejects the call — must become error, not throw.
          return {
            'jsonrpc': '2.0',
            'id': 1,
            'error': {'code': -32000, 'message': 'execution reverted'},
          };
        }
        return _rpcResult(_hex(10000000));
      }),
      restTransport: _FakeRest(
        onGet: (url) => throw TimeoutException('rest timeout'),
      ),
    );

    final results = await service.fetchAll(_addresses);
    expect(results['usdt-eth']!.status, BalanceStatus.error);
    expect(results['usdt-eth']!.amount, isNull);
    expect(results['usdc-polygon']!.status, BalanceStatus.ok);
    expect(results['usdt-tron']!.status, BalanceStatus.error);
  });

  test(
    'unactivated account / missing trc20 entry read as a real zero',
    () async {
      Future<Map<String, BalanceResult>> fetchWith(Object? tronBody) {
        final service = TokenBalanceService(
          jsonRpcTransport: _FakeJsonRpc(
            (url, body) async => _rpcResult('0x0'),
          ),
          restTransport: _FakeRest(onGet: (url) async => tronBody),
        );
        return service.fetchAll(_addresses);
      }

      // Unactivated account: TronGrid returns an empty data list.
      var results = await fetchWith({'data': <Object?>[]});
      expect(results['usdt-tron']!.status, BalanceStatus.ok);
      expect(results['usdt-tron']!.amount!.raw, BigInt.zero);

      // Activated account that never touched any TRC-20 (no trc20 key).
      results = await fetchWith({
        'data': [
          {'balance': 42},
        ],
      });
      expect(results['usdt-tron']!.status, BalanceStatus.ok);
      expect(results['usdt-tron']!.amount!.raw, BigInt.zero);

      // trc20 array present but without the registry contract.
      results = await fetchWith({
        'data': [
          {
            'trc20': [
              {'TOtherContract': '9'},
            ],
          },
        ],
      });
      expect(results['usdt-tron']!.status, BalanceStatus.ok);
      expect(results['usdt-tron']!.amount!.raw, BigInt.zero);
    },
  );

  test('malformed responses surface as error status (never throw)', () async {
    final service = TokenBalanceService(
      jsonRpcTransport: _FakeJsonRpc((url, body) async => 'not a map'),
      restTransport: _FakeRest(
        onGet: (url) async {
          return {
            'data': [
              {
                'trc20': [
                  {
                    _usdtTron: 12345678,
                  }, // non-string value: malformed, not zero
                ],
              },
            ],
          };
        },
      ),
    );
    final results = await service.fetchAll(_addresses);
    for (final token in builtinTokens) {
      expect(results[token.id]!.status, BalanceStatus.error, reason: token.id);
      expect(results[token.id]!.amount, isNull);
    }
  });

  test('endpoint resolver overrides the URLs the transports see', () async {
    final seenJsonUrls = <String>[];
    final seenRestUrls = <String>[];
    final service = TokenBalanceService(
      endpoints: (coin) => 'https://custom-${coin.name}.example',
      jsonRpcTransport: _FakeJsonRpc((url, body) async {
        seenJsonUrls.add(url);
        return _rpcResult('0x0');
      }),
      restTransport: _FakeRest(
        onGet: (url) async {
          seenRestUrls.add(url);
          return {'data': <Object?>[]};
        },
      ),
    );

    await service.fetchAll(_addresses);
    expect(
      seenJsonUrls,
      containsAll([
        'https://custom-eth.example',
        'https://custom-polygon.example',
      ]),
    );
    expect(
      seenRestUrls.single,
      'https://custom-tron.example/v1/accounts/TTronAddr',
    );
  });
}
