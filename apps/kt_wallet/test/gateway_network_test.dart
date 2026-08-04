import 'dart:convert';
import 'dart:typed_data';

import 'package:chains/chains.dart' show Chain;
import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart' show ChainAddresses, Coin;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kt_wallet/src/market/balance_service.dart';
import 'package:kt_wallet/src/market/gateway_client.dart';
import 'package:kt_wallet/src/market/history_service.dart';
import 'package:kt_wallet/src/market/market_controller.dart';
import 'package:kt_wallet/src/market/market_scope.dart';
import 'package:kt_wallet/src/market/token_balance_service.dart';
import 'package:kt_wallet/src/state/app_prefs.dart';
import 'package:kt_wallet/src/state/networks.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/transfer/broadcast_service.dart';
import 'package:kt_wallet/src/transfer/chain_params_service.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// RELEASE-BLOCKER REGRESSION: gateway mode used to omit the `network` param,
/// so the Go service resolved every call to the chain family's MAINNET. On
/// Sepolia that meant mainnet balances, a mainnet nonce baked into a testnet
/// transaction, and a testnet-signed payload posted to a mainnet node (whose
/// -32000 rejection then blocked the direct retry, per INV-15).
///
/// These tests pin: the active network id on the wire for every chain-scoped
/// method, testnet ids instead of mainnet, and the custom-network policy —
/// a network the gateway does not advertise is never sent, the gateway is
/// bypassed and the direct path answers.

const _addresses = ChainAddresses(
  eth: '0xEthAddr',
  polygon: '0xPolyAddr',
  tron: 'TTronAddr',
  solana: '47eFuHR9ste9kopiJ9eRxcwahmE62JovbKe5r7AjANut',
);
const _evmFrom = '0x1111111111111111111111111111111111111111';

/// Every network id the current Go service advertises via `kt_health`.
const _advertised = [
  'eth-mainnet',
  'eth-sepolia',
  'polygon-mainnet',
  'polygon-amoy',
  'base-mainnet',
  'base-sepolia',
  'arbitrum-mainnet',
  'arbitrum-sepolia',
  'avalanche-mainnet',
  'avalanche-fuji',
  'tron-mainnet',
  'tron-nile',
  'sol-mainnet',
  'sol-devnet',
];

/// A scripted gateway that answers `kt_health` (with a configurable
/// `networks` array) and records every request body verbatim.
class _FakeGateway {
  _FakeGateway({
    this.results = const {},
    this.errors = const {},
    this.advertisedNetworks = _advertised,
    this.healthy = true,
  });

  final Map<String, Object?> results;
  final Map<String, Object?> errors;

  /// The `networks` array `kt_health` answers with; null omits the field
  /// entirely (a gateway deployed before network support).
  final List<String>? advertisedNetworks;

  /// When false `kt_health` answers `{ok: false}` (gateway present but not
  /// serving).
  bool healthy;

  final calls = <(String method, Map<String, Object?> params)>[];
  final _served = <String, int>{};

  late final client = GatewayClient(
    baseUrl: 'https://gw.example',
    client: MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      final method = body['method'] as String;
      calls.add((
        method,
        (body['params'] as Map?)?.cast<String, Object?>() ?? const {},
      ));
      if (method == 'kt_health') {
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': body['id'],
            'result': {
              'ok': healthy,
              'version': '1.0.0',
              if (advertisedNetworks != null) 'networks': advertisedNetworks,
            },
          }),
          200,
        );
      }
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
    networks: networkIds,
  );

  /// Mutable per-chain active network ids, read on every call.
  final Map<Coin, String> networkOf = {};
  String? networkIds(Coin coin) => networkOf[coin];

  List<String> get methods => [for (final (m, _) in calls) m];

  List<Map<String, Object?>> paramsOf(String method) => [
    for (final (m, p) in calls)
      if (m == method) p,
  ];
}

Map<String, Object?> _rpcResult(Object? result) => {
  'jsonrpc': '2.0',
  'id': 1,
  'result': result,
};

Map<String, Object?> _native(String raw, int decimals, String symbol) => {
  'native': {'raw': raw, 'decimals': decimals, 'symbol': symbol},
};

class _FakeJsonRpc implements JsonRpcTransport {
  _FakeJsonRpc(this.handler);
  final Future<Object?> Function(String url, Object body) handler;
  final calls = <(String url, String method)>[];
  @override
  Future<Object?> post(String url, Object body) {
    calls.add((url, (body as Map)['method'] as String));
    return handler(url, body);
  }
}

class _FakeRest implements RestTransport {
  _FakeRest(this.onGet);
  final Future<Object?> Function(String url) onGet;
  final gets = <String>[];
  @override
  Future<Object?> getJson(String url) {
    gets.add(url);
    return onGet(url);
  }

  @override
  Future<Object?> postJson(String url, Object body) =>
      throw UnimplementedError('these fetches never POST');
}

void main() {
  group('GatewayClient network scoping', () {
    test('every chain-scoped method sends the ACTIVE network id', () async {
      final gateway =
          _FakeGateway(
              results: {
                'kt_getBalances': _native('1', 18, 'ETH'),
                'kt_getChainParams': {
                  'network': 'polygon-amoy',
                  'address': _evmFrom,
                  'nonce': '7',
                  'fees': {
                    'slow': {'maxPriorityFeePerGas': '1', 'maxFeePerGas': '10'},
                    'standard': {
                      'maxPriorityFeePerGas': '2',
                      'maxFeePerGas': '20',
                    },
                    'fast': {'maxPriorityFeePerGas': '3', 'maxFeePerGas': '30'},
                  },
                },
                'kt_getHistory': {'status': 'ok', 'records': <Object?>[]},
                'kt_broadcast': {'txHash': '0xhash'},
              },
            )
            ..networkOf.addAll({
              Coin.eth: 'eth-sepolia',
              Coin.polygon: 'polygon-amoy',
              Coin.base: 'base-sepolia',
              Coin.tron: 'tron-nile',
              Coin.solana: 'sol-devnet',
            });
      final client = gateway.client;

      await client.getBalances(
        chain: Coin.eth,
        address: '0xEthAddr',
        tokens: const [
          GatewayTokenQuery(contract: '0xTok', decimals: 6, symbol: 'USDT'),
        ],
      );
      await client.getChainParams(chain: Coin.polygon, address: _evmFrom);
      await client.getHistory(
        chain: Coin.tron,
        address: 'TTronAddr',
        limit: 20,
      );
      await client.broadcast(chain: Coin.base, payload: '0x02ab');

      expect(gateway.paramsOf('kt_getBalances').single, {
        'chain': 'eth',
        'network': 'eth-sepolia',
        'address': '0xEthAddr',
        'tokens': [
          {'contract': '0xTok', 'decimals': 6, 'symbol': 'USDT'},
        ],
      });
      expect(gateway.paramsOf('kt_getChainParams').single, {
        'chain': 'polygon',
        'network': 'polygon-amoy',
        'address': _evmFrom,
      });
      expect(gateway.paramsOf('kt_getHistory').single, {
        'chain': 'tron',
        'network': 'tron-nile',
        'address': 'TTronAddr',
        'limit': 20,
      });
      expect(gateway.paramsOf('kt_broadcast').single, {
        'chain': 'base',
        'network': 'base-sepolia',
        'payload': '0x02ab',
      });

      // The advertised set is learned once per client, not per call.
      expect(gateway.paramsOf('kt_health'), hasLength(1));
    });

    test('a concurrent refresh probes kt_health exactly once', () async {
      final gateway = _FakeGateway(
        results: {'kt_getBalances': _native('1', 18, 'ETH')},
      );
      for (final coin in Coin.values) {
        gateway.networkOf[coin] = 'eth-mainnet';
      }
      await Future.wait([
        for (var i = 0; i < 7; i++)
          gateway.client.getBalances(chain: Coin.eth, address: '0xA'),
      ]);
      expect(gateway.paramsOf('kt_health'), hasLength(1));
      expect(gateway.paramsOf('kt_getBalances'), hasLength(7));
    });

    test(
      'testnet environment sends the sepolia id, never the mainnet one',
      () async {
        SharedPreferences.setMockInitialValues({});
        final networks = NetworkController(
          initialEnvironment: NetworkEnvironment.testnet,
        );
        final gateway = _FakeGateway(
          results: {'kt_getBalances': _native('1', 18, 'ETH')},
        );

        // Bind the live controller exactly as production does.
        gateway.networkOf[Coin.eth] = networks.activeFor(Chain.ethereum).id;
        await gateway.client.getBalances(chain: Coin.eth, address: '0xA');
        expect(
          gateway.paramsOf('kt_getBalances').single['network'],
          'eth-sepolia',
        );

        // Switching back to mainnet is picked up on the next call.
        await networks.setEnvironment(NetworkEnvironment.mainnet);
        gateway.networkOf[Coin.eth] = networks.activeFor(Chain.ethereum).id;
        await gateway.client.getBalances(chain: Coin.eth, address: '0xA');
        expect(
          gateway.paramsOf('kt_getBalances').last['network'],
          'eth-mainnet',
        );
      },
    );

    test('no network source: no network param and no health probe', () async {
      final gateway = _FakeGateway(
        results: {'kt_getBalances': _native('1', 18, 'ETH')},
      );
      await gateway.client.getBalances(chain: Coin.eth, address: '0xA');
      expect(gateway.paramsOf('kt_getBalances').single, {
        'chain': 'eth',
        'address': '0xA',
      });
      expect(gateway.methods, ['kt_getBalances']); // never probed
    });

    // A gateway-side JSON-RPC error must not swallow the scoping: the request
    // still carries the active network (so the operator can see WHICH chain
    // failed), and the typed error reaches the caller instead of a silent
    // mainnet answer. Exercises the fake's error-injection path.
    test(
      'a gateway error still carries the network and surfaces typed',
      () async {
        final gateway = _FakeGateway(
          errors: {
            'kt_getBalances': {
              'code': -32000,
              'message': 'upstream_error',
              'data': {'upstream': 'eth-sepolia', 'message': 'node down'},
            },
          },
        )..networkOf[Coin.eth] = 'eth-sepolia';
        await expectLater(
          gateway.client.getBalances(chain: Coin.eth, address: '0xA'),
          throwsA(
            isA<GatewayException>()
                .having((e) => e.code, 'code', -32000)
                .having(
                  (e) => e.upstreamMessage,
                  'upstreamMessage',
                  'node down',
                ),
          ),
        );
        expect(
          gateway.paramsOf('kt_getBalances').single['network'],
          'eth-sepolia',
        );
      },
    );

    test('CUSTOM network: bypassed, never sent, never mainnet', () async {
      final gateway = _FakeGateway(
        results: {'kt_getBalances': _native('999', 18, 'ETH')},
      )..networkOf[Coin.eth] = 'custom-1753000000000000';

      await expectLater(
        gateway.client.getBalances(chain: Coin.eth, address: '0xA'),
        throwsA(
          isA<GatewayNetworkUnsupported>().having(
            (e) => e.networkId,
            'networkId',
            'custom-1753000000000000',
          ),
        ),
      );
      // Only the discovery probe went out — no chain-scoped call, so the
      // gateway had no chance to answer with mainnet data.
      expect(gateway.methods, ['kt_health']);
    });

    test('every chain-scoped method bypasses a custom network', () async {
      final gateway = _FakeGateway();
      for (final coin in Coin.values) {
        gateway.networkOf[coin] = 'custom-1';
      }
      final client = gateway.client;
      await expectLater(
        client.getBalances(chain: Coin.eth, address: '0xA'),
        throwsA(isA<GatewayNetworkUnsupported>()),
      );
      await expectLater(
        client.getChainParams(chain: Coin.eth, address: '0xA'),
        throwsA(isA<GatewayNetworkUnsupported>()),
      );
      await expectLater(
        client.getHistory(chain: Coin.eth, address: '0xA'),
        throwsA(isA<GatewayNetworkUnsupported>()),
      );
      await expectLater(
        client.broadcast(chain: Coin.eth, payload: '0x02'),
        throwsA(isA<GatewayNetworkUnsupported>()),
      );
      expect(gateway.methods, ['kt_health']);
    });

    test(
      'a family the deployed gateway does not advertise is bypassed',
      () async {
        // An older gateway that predates base/arbitrum/avalanche.
        final gateway =
            _FakeGateway(
                results: {'kt_getBalances': _native('1', 18, 'ETH')},
                advertisedNetworks: const ['eth-mainnet', 'eth-sepolia'],
              )
              ..networkOf[Coin.base] = 'base-mainnet'
              ..networkOf[Coin.eth] = 'eth-sepolia';

        await expectLater(
          gateway.client.getBalances(chain: Coin.base, address: '0xA'),
          throwsA(isA<GatewayNetworkUnsupported>()),
        );
        // The advertised network still goes through.
        await gateway.client.getBalances(chain: Coin.eth, address: '0xA');
        expect(
          gateway.paramsOf('kt_getBalances').single['network'],
          'eth-sepolia',
        );
      },
    );

    test('legacy gateway (no networks field): mainnet only', () async {
      final gateway = _FakeGateway(
        results: {'kt_getBalances': _native('1', 18, 'ETH')},
        advertisedNetworks: null,
      )..networkOf[Coin.eth] = 'eth-mainnet';

      // A legacy gateway ignores the unknown param and answers for mainnet,
      // which is exactly what the id says — safe to send.
      await gateway.client.getBalances(chain: Coin.eth, address: '0xA');
      expect(
        gateway.paramsOf('kt_getBalances').single['network'],
        'eth-mainnet',
      );

      gateway.networkOf[Coin.eth] = 'eth-sepolia';
      await expectLater(
        gateway.client.getBalances(chain: Coin.eth, address: '0xA'),
        throwsA(isA<GatewayNetworkUnsupported>()),
      );
    });

    test('unhealthy gateway bypasses, then re-probes once healthy', () async {
      final gateway = _FakeGateway(
        results: {'kt_getBalances': _native('1', 18, 'ETH')},
        healthy: false,
      )..networkOf[Coin.eth] = 'eth-sepolia';

      await expectLater(
        gateway.client.getBalances(chain: Coin.eth, address: '0xA'),
        throwsA(isA<GatewayNetworkUnsupported>()),
      );
      expect(gateway.methods, ['kt_health']);

      // A failed probe is never cached: the next call tries again.
      gateway.healthy = true;
      await gateway.client.getBalances(chain: Coin.eth, address: '0xA');
      expect(gateway.paramsOf('kt_health'), hasLength(2));
      expect(
        gateway.paramsOf('kt_getBalances').single['network'],
        'eth-sepolia',
      );
    });

    test(
      'health() refreshes the advertised set without a second call',
      () async {
        final gateway = _FakeGateway(
          results: {'kt_getBalances': _native('1', 18, 'ETH')},
        )..networkOf[Coin.eth] = 'eth-sepolia';

        expect(await gateway.client.health(), isTrue);
        await gateway.client.getBalances(chain: Coin.eth, address: '0xA');
        // The settings-screen probe already populated the set.
        expect(gateway.paramsOf('kt_health'), hasLength(1));
      },
    );

    test('a seeded advertised set skips discovery entirely', () async {
      var healthCalls = 0;
      final client = GatewayClient(
        baseUrl: 'https://gw.example',
        advertisedNetworks: const {'eth-sepolia'},
        networks: (coin) => 'eth-sepolia',
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          if (body['method'] == 'kt_health') healthCalls++;
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': body['id'],
              'result': _native('1', 18, 'ETH'),
            }),
            200,
          );
        }),
      );
      await client.getBalances(chain: Coin.eth, address: '0xA');
      expect(healthCalls, 0);
    });
  });

  group('services on a network the gateway cannot serve', () {
    test('BalanceService falls back to the direct node', () async {
      final gateway = _FakeGateway(
        results: {'kt_getBalances': _native('999', 18, 'ETH')},
      );
      for (final coin in Coin.values) {
        gateway.networkOf[coin] = 'custom-42';
      }
      final direct = _FakeJsonRpc(
        (url, body) async => (body as Map)['method'] == 'getBalance'
            ? _rpcResult({
                'context': <String, Object?>{'slot': 1},
                'value': 0,
              })
            : _rpcResult('0x2a'),
      );
      final service = BalanceService(
        jsonRpcTransport: direct,
        restTransport: _FakeRest((url) async => {'data': <Object?>[]}),
        gateway: () => gateway.client,
      );

      final results = await service.fetchAll(_addresses);
      expect(results[Coin.eth]!.status, BalanceStatus.ok);
      expect(results[Coin.eth]!.amount!.raw, BigInt.from(42)); // direct answer
      expect(gateway.methods, ['kt_health']); // no balance call was made
      expect(direct.calls, hasLength(3));
    });

    test('TokenBalanceService falls back to the direct node', () async {
      final gateway = _FakeGateway(
        results: {'kt_getBalances': _native('0', 18, 'ETH')},
      );
      for (final coin in Coin.values) {
        gateway.networkOf[coin] = 'custom-42';
      }
      final direct = _FakeJsonRpc(
        (url, body) async => _rpcResult(
          '0x00000000000000000000000000000000000000000000000000000000072f2740',
        ),
      );
      final service = TokenBalanceService(
        jsonRpcTransport: direct,
        restTransport: _FakeRest(
          (url) async => {
            'data': [
              {
                'trc20': [
                  {'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t': '5000000'},
                ],
              },
            ],
          },
        ),
        gateway: () => gateway.client,
      );
      final results = await service.fetchAll(_addresses);
      expect(results['usdt-eth']!.status, BalanceStatus.ok);
      expect(results['usdt-tron']!.amount!.format(), '5');
      expect(gateway.paramsOf('kt_getBalances'), isEmpty);
    });

    test('ChainParamsService falls back to direct nonce + fees', () async {
      final gateway = _FakeGateway(
        results: {
          'kt_getChainParams': {
            'nonce': '999',
            'fees': {
              'slow': {'maxPriorityFeePerGas': '1', 'maxFeePerGas': '10'},
              'standard': {'maxPriorityFeePerGas': '2', 'maxFeePerGas': '20'},
              'fast': {'maxPriorityFeePerGas': '3', 'maxFeePerGas': '30'},
            },
          },
        },
      )..networkOf[Coin.eth] = 'custom-42';
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
        return _rpcResult('0x3b9aca00');
      });
      final service = ChainParamsService(
        jsonRpcTransport: direct,
        gateway: () => gateway.client,
      );
      final params = await service.fetchEvmParams(Chain.ethereum, '0xFrom');
      // 42 from the direct node, NOT the gateway's mainnet 999.
      expect(params.nonce, 42);
      expect(gateway.paramsOf('kt_getChainParams'), isEmpty);
    });

    test('BroadcastService posts directly, exactly once', () async {
      final gateway = _FakeGateway(
        results: {
          'kt_broadcast': {'txHash': '0xgatewayhash'},
        },
      )..networkOf[Coin.eth] = 'custom-42';
      final direct = _FakeJsonRpc(
        (url, body) async => _rpcResult('0xdirecthash'),
      );
      final service = BroadcastService(
        jsonRpcTransport: direct,
        gateway: () => gateway.client,
      );
      final outcome = await service.broadcast(
        Chain.ethereum,
        Uint8List.fromList([0x02, 0x01]),
        expectedTxHash: '0xDIRECTHASH',
      );
      expect(outcome.status, BroadcastStatus.ok);
      expect(outcome.txHash, '0xDIRECTHASH');
      // A bypass happens BEFORE any post: the gateway never saw the payload
      // and the direct node saw it exactly once (INV-15).
      expect(gateway.paramsOf('kt_broadcast'), isEmpty);
      expect(direct.calls, hasLength(1));
      expect(direct.calls.single.$2, 'eth_sendRawTransaction');
    });

    test('HistoryService falls back to the public chain API', () async {
      final gateway = _FakeGateway(
        results: {
          'kt_getHistory': {'status': 'ok', 'records': <Object?>[]},
        },
      )..networkOf[Coin.tron] = 'custom-42';
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
        gateway: () => gateway.client,
      );
      final result = await service.fetch(
        Coin.tron,
        'TJmmqjb1DK9TTZbQXzRQ2AuA94z4gKAPFh',
      );
      expect(result.status, HistoryStatus.ok);
      expect(tronGridHits, 3); // trc20 + native + internal
      expect(gateway.paramsOf('kt_getHistory'), isEmpty);
    });
  });

  group('prefsGatewayResolver network wiring', () {
    test('an explicitly passed controller scopes the client', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = AppPrefsController();
      await prefs.load();
      await prefs.setGatewayUrl('https://gw.example');
      final networks = NetworkController();

      final client = prefsGatewayResolver(prefs, networks)()!;
      expect(client.activeNetworkId(Coin.eth), 'eth-mainnet');
      expect(client.activeNetworkId(Coin.base), 'base-mainnet');

      // Resolved per call: an environment switch needs no new client.
      await networks.setEnvironment(NetworkEnvironment.testnet);
      expect(client.activeNetworkId(Coin.eth), 'eth-sepolia');
      expect(client.activeNetworkId(Coin.avalanche), 'avalanche-fuji');

      // A per-chain pin (including a custom network) wins.
      final custom = await networks.addCustom(
        chain: Chain.ethereum,
        name: 'My node',
        rpcUrl: 'http://127.0.0.1:8545',
        symbol: 'ETH',
        evmChainId: 31337,
      );
      await networks.setOverride(Chain.ethereum, custom.id);
      expect(client.activeNetworkId(Coin.eth), custom.id);
      expect(custom.id, startsWith('custom-'));
    });

    testWidgets('a mounted MarketScopeHost scopes prefs-only resolvers', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = AppPrefsController();
      await prefs.load();
      await prefs.setGatewayUrl('https://gw.example');
      final networks = NetworkController(
        initialEnvironment: NetworkEnvironment.testnet,
      );
      final wallets = WalletController(
        WalletManager(
          initial: [
            HotWallet(
              id: 'w1',
              name: 'w',
              avatarColor: 0xFFF59E0B,
              addresses: _addresses,
              backedUp: true,
            ),
          ],
        ),
      );
      final controller = MarketController(wallets: wallets);

      // Without a host, a prefs-only resolver has no network source and keeps
      // the pre-fix behavior (no network param).
      expect(prefsGatewayResolver(prefs)()!.activeNetworkId(Coin.eth), isNull);

      await tester.pumpWidget(
        MaterialApp(
          home: NetworkScope(
            controller: networks,
            child: AppPrefsScope(
              controller: prefs,
              child: MarketScopeHost(
                wallets: wallets,
                prefs: prefs,
                controller: controller,
                child: const SizedBox(),
              ),
            ),
          ),
        ),
      );

      // The host published the active-network source: the very same call site
      // the screens use is now network-scoped.
      final client = prefsGatewayResolver(prefs)()!;
      expect(client.activeNetworkId(Coin.eth), 'eth-sepolia');
      expect(client.activeNetworkId(Coin.tron), 'tron-nile');

      await tester.pumpWidget(const SizedBox());
      // Unmounting unlinks it again — no state leaks into later resolvers.
      expect(prefsGatewayResolver(prefs)()!.activeNetworkId(Coin.eth), isNull);
      controller.dispose();
    });
  });
}
