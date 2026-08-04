import 'dart:async';
import 'dart:convert';

import 'package:chains/chains.dart';
import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:core_crypto/core_crypto.dart' show ChainAddresses;
import 'package:kt_wallet/src/market/balance_service.dart';
import 'package:kt_wallet/src/market/gateway_client.dart';
import 'package:kt_wallet/src/market/market_controller.dart';
import 'package:kt_wallet/src/market/market_scope.dart';
import 'package:kt_wallet/src/market/price_service.dart';
import 'package:kt_wallet/src/screens/transfer_screens.dart';
import 'package:kt_wallet/src/state/networks.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/state/wallet_scope.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:kt_wallet/src/transfer/airgap_codec.dart';
import 'package:kt_wallet/src/transfer/chain_params_service.dart';
import 'package:kt_wallet/src/transfer/local_transfer_service.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';
import 'package:ui_kit/ui_kit.dart';

import 'support/test_wallet_scope.dart';

/// #nonce/gas: live EVM chain-state parameters — the service that fetches
/// them over an injectable transport, and the W6 wiring that builds the QR
/// only after the fetch (real values on success, documented demo constants +
/// fallback hint on failure).

final _gwei = BigInt.from(1000000000);
const _gatewayFrom = '0x1111111111111111111111111111111111111111';
const _gatewayTo = '0x2222222222222222222222222222222222222222';
const _gatewayToken = '0x3333333333333333333333333333333333333333';

String _hex(BigInt v) => '0x${v.toRadixString(16)}';

/// Scripted JSON-RPC transport: answers per method, records every call.
class _FakeJsonRpc implements JsonRpcTransport {
  _FakeJsonRpc(this.handlers);
  final Map<String, Object? Function(List<Object?> params)> handlers;
  final calls = <(String url, String method)>[];

  @override
  Future<Object?> post(String url, Object body) async {
    final map = body as Map;
    final method = map['method'] as String;
    calls.add((url, method));
    final handler = handlers[method];
    if (handler == null) {
      return {
        'jsonrpc': '2.0',
        'id': map['id'],
        'error': {'code': -32601, 'message': 'method not found'},
      };
    }
    return {
      'jsonrpc': '2.0',
      'id': map['id'],
      'result': handler((map['params'] as List?) ?? const []),
    };
  }
}

Map<String, Object? Function(List<Object?>)> _healthyHandlers({
  int nonce = 7,
}) => {
  'eth_getTransactionCount': (_) => _hex(BigInt.from(nonce)),
  // Latest base fee 30 gwei; percentile tips 1/2/3 gwei on every row.
  'eth_feeHistory': (_) => {
    'oldestBlock': '0x64',
    'baseFeePerGas': [
      _hex(BigInt.from(25) * _gwei),
      _hex(BigInt.from(30) * _gwei),
      _hex(BigInt.from(30) * _gwei),
    ],
    'gasUsedRatio': [0.5, 0.75],
    'reward': [
      [_hex(_gwei), _hex(BigInt.two * _gwei), _hex(BigInt.from(3) * _gwei)],
      [_hex(_gwei), _hex(BigInt.two * _gwei), _hex(BigInt.from(3) * _gwei)],
    ],
  },
};

TransferDraft _evmDraft({int feeTier = 1}) => TransferDraft(
  symbol: 'ETH',
  networkLabel: 'Ethereum',
  chain: Chain.ethereum,
  recipient: '0x925fEA1c0dbf3B011391bbed682E32861BE73213',
  amount: Amount.parse('0.5', 18, symbol: 'ETH'),
  feeTier: feeTier,
);

TransferDraft _erc20Draft() => TransferDraft(
  symbol: 'USDT',
  networkLabel: 'Ethereum · ERC-20',
  chain: Chain.ethereum,
  recipient: '0x925fEA1c0dbf3B011391bbed682E32861BE73213',
  amount: Amount.parse('2.5', 6, symbol: 'USDT'),
  feeTier: 1,
  tokenContract: '0xdAC17F958D2ee523a2206206994597C13D831ec7',
);

/// Test double whose fetch is scripted; never touches any transport.
class _FakeParamsService extends ChainParamsService {
  _FakeParamsService(
    this._fetch, {
    this.simulationError,
    EvmSpendableBalances? spendable,
    this.confirmedNonce = 6,
    this.pendingNonce = 7,
  }) : spendable =
           spendable ??
           EvmSpendableBalances(native: _hugeBalance, token: _hugeBalance),
       super(jsonRpcTransport: _FakeJsonRpc(const {}));
  static final _hugeBalance = BigInt.parse('1000000000000000000000000');
  final Future<EvmChainParams> Function(Chain chain, String from) _fetch;
  final RpcException? simulationError;
  final EvmSpendableBalances spendable;
  final int confirmedNonce;
  final int pendingNonce;
  Chain? calledChain;
  String? calledFrom;
  int callCount = 0;
  int simulationCount = 0;
  final simulatedBlockTags = <String>[];

  @override
  Future<EvmChainParams> fetchEvmParams(Chain chain, String fromAddress) {
    callCount++;
    calledChain = chain;
    calledFrom = fromAddress;
    return _fetch(chain, fromAddress);
  }

  @override
  Future<BigInt> estimateEvmGas(
    Chain chain, {
    required String from,
    required String to,
    required BigInt value,
    required String data,
  }) async => BigInt.from(21000);

  @override
  Future<void> simulateEvmTransfer(
    Chain chain, {
    required String from,
    required String to,
    required BigInt value,
    required String data,
    required bool tokenTransfer,
    String blockTag = 'pending',
  }) async {
    simulationCount++;
    simulatedBlockTags.add(blockTag);
    final error = simulationError;
    if (error != null && blockTag == 'pending') throw error;
  }

  @override
  Future<EvmNonceState> fetchEvmNonceState(
    Chain chain,
    String fromAddress,
  ) async => EvmNonceState(confirmed: confirmedNonce, pending: pendingNonce);

  @override
  Future<EvmSpendableBalances> fetchEvmSpendableBalances(
    Chain chain, {
    required String address,
    String? tokenContract,
  }) async => spendable;
}

/// Prices only — balances are irrelevant to the confirm screen's fiat line.
class _FakePriceService extends PriceService {
  _FakePriceService(this.prices);
  final Map<Coin, double>? prices;
  @override
  Future<Map<Coin, double>?> fetchUsdPrices() async => prices;
}

class _NoBalanceService extends BalanceService {
  @override
  Future<Map<Coin, BalanceResult>> fetchAll(
    ChainAddresses addresses, {
    BalanceResultCallback? onResult,
  }) async => {for (final c in Coin.values) c: const BalanceResult.error()};
}

Future<MarketController> _pricedMarket(
  Map<Coin, double>? prices, {
  bool Function(Coin coin)? isTestnet,
}) async {
  final controller = MarketController(
    wallets: WalletController(
      WalletManager(
        initial: [
          HotWallet(
            id: 'w1',
            name: '日常钱包',
            avatarColor: 0xFFF59E0B,
            addresses: const ChainAddresses(
              eth: '0xa',
              polygon: '0xa',
              tron: 'Ta',
              solana: 'Sa',
            ),
          ),
        ],
      ),
    ),
    balances: _NoBalanceService(),
    prices: _FakePriceService(prices),
    isTestnet: isTestnet,
  );
  await controller.refresh();
  return controller;
}

Widget _wrap(Widget child) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData(scaffoldBackgroundColor: WalletColors.bg),
  home: withTestWalletScope(child),
);

void main() {
  group('ChainParamsService', () {
    test(
      'EVM simulation and gas use gateway without touching direct RPC',
      () async {
        final methods = <String>[];
        final gateway = GatewayClient(
          baseUrl: 'https://gateway.example',
          advertisedNetworks: const {'eth-mainnet'},
          networks: (_) => 'eth-mainnet',
          client: MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, Object?>;
            final method = body['method']! as String;
            methods.add(method);
            final result = switch (method) {
              'kt_simulateEvmTransfer' => {
                'network': 'eth-mainnet',
                'from': _gatewayFrom,
                'to': _gatewayTo,
                'value': '0x1',
                'data': '0x',
                'blockTag': 'pending',
                'returnData': '0x',
              },
              'kt_estimateEvmGas' => {
                'network': 'eth-mainnet',
                'from': _gatewayFrom,
                'to': _gatewayTo,
                'value': '0x1',
                'data': '0x',
                'gas': '21000',
              },
              'kt_getEvmSpendableBalances' => {
                'network': 'eth-mainnet',
                'address': _gatewayFrom,
                'tokenContract': _gatewayToken,
                'native': '100000',
                'nativePending': '100000',
                'nativeLatest': '110000',
                'token': '2500',
                'pendingAvailable': true,
              },
              _ => throw StateError('unexpected $method'),
            };
            return http.Response(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': body['id'],
                'result': result,
              }),
              200,
            );
          }),
        );
        final direct = _FakeJsonRpc(const {});
        final service = ChainParamsService(
          jsonRpcTransport: direct,
          endpoints: (_) => 'https://blocked-direct.example',
          gateway: () => gateway,
        );

        await service.simulateEvmTransfer(
          Chain.ethereum,
          from: _gatewayFrom,
          to: _gatewayTo,
          value: BigInt.one,
          data: '0x',
          tokenTransfer: false,
        );
        expect(
          await service.estimateEvmGas(
            Chain.ethereum,
            from: _gatewayFrom,
            to: _gatewayTo,
            value: BigInt.one,
            data: '0x',
          ),
          BigInt.from(21000),
        );
        final balances = await service.fetchEvmSpendableBalances(
          Chain.ethereum,
          address: _gatewayFrom,
          tokenContract: _gatewayToken,
        );
        expect(balances.native, BigInt.from(100000));
        expect(balances.nativeLatest, BigInt.from(110000));
        expect(balances.token, BigInt.from(2500));
        expect(methods, [
          'kt_simulateEvmTransfer',
          'kt_estimateEvmGas',
          'kt_getEvmSpendableBalances',
        ]);
        expect(direct.calls, isEmpty);
      },
    );

    test('gateway preflight failure falls back to active direct RPC', () async {
      final gateway = GatewayClient(
        baseUrl: 'https://gateway.example',
        advertisedNetworks: const {'eth-mainnet'},
        networks: (_) => 'eth-mainnet',
        client: MockClient((request) async => http.Response('down', 503)),
      );
      final direct = _FakeJsonRpc({
        'eth_call': (_) => '0x',
        'eth_estimateGas': (_) => '0x5208',
        'eth_getBalance': (params) {
          expect(params.last, anyOf('pending', 'latest'));
          return '0x186a0';
        },
      });
      final service = ChainParamsService(
        jsonRpcTransport: direct,
        endpoints: (_) => 'https://direct.example',
        gateway: () => gateway,
      );

      await service.simulateEvmTransfer(
        Chain.ethereum,
        from: '0xfrom',
        to: '0xto',
        value: BigInt.zero,
        data: '0x',
        tokenTransfer: false,
      );
      expect(
        await service.estimateEvmGas(
          Chain.ethereum,
          from: '0xfrom',
          to: '0xto',
          value: BigInt.zero,
          data: '0x',
        ),
        BigInt.from(21000),
      );
      expect(
        (await service.fetchEvmSpendableBalances(
          Chain.ethereum,
          address: '0xfrom',
        )).native,
        BigInt.from(100000),
      );
      expect(direct.calls.map((call) => call.$2), [
        'eth_call',
        'eth_estimateGas',
        'eth_getBalance',
        'eth_getBalance',
      ]);
    });

    test(
      'explicitly unsupported pending block returns marked latest fallback',
      () async {
        final transport = _FakeJsonRpc({
          'eth_getBalance': (params) {
            if (params.last == 'latest') return '0x186a0';
            throw RpcException('state not available for pending block');
          },
        });
        final service = ChainParamsService(
          jsonRpcTransport: transport,
          endpoints: (_) => 'https://fuji.example',
        );

        final balances = await service.fetchEvmSpendableBalances(
          Chain.avalanche,
          address: '0xfrom',
        );
        expect(balances.native, BigInt.from(100000));
        expect(balances.nativeLatest, BigInt.from(100000));
        expect(balances.pendingAvailable, isFalse);
      },
    );

    test('ERC-20 preflight accepts true and rejects explicit false', () async {
      var response = '0x${'0' * 63}1';
      final transport = _FakeJsonRpc({'eth_call': (_) => response});
      final service = ChainParamsService(
        jsonRpcTransport: transport,
        endpoints: (_) => 'https://node.example',
      );

      await service.simulateEvmTransfer(
        Chain.ethereum,
        from: '0xfrom',
        to: '0xtoken',
        value: BigInt.zero,
        data: '0xa9059cbb',
        tokenTransfer: true,
      );
      response = '0x${'0' * 64}';
      await expectLater(
        service.simulateEvmTransfer(
          Chain.ethereum,
          from: '0xfrom',
          to: '0xtoken',
          value: BigInt.zero,
          data: '0xa9059cbb',
          tokenTransfer: true,
        ),
        throwsA(
          isA<RpcException>().having(
            (error) => error.message,
            'message',
            contains('returned false'),
          ),
        ),
      );
    });

    test('prepareEvm fails closed when preflight reverts', () async {
      final tier = GasFeeEstimateTier(
        maxPriorityFeePerGas: _gwei,
        maxFeePerGas: BigInt.from(30) * _gwei,
      );
      final params = _FakeParamsService(
        (_, _) async => EvmChainParams(
          nonce: 7,
          fees: GasFeeEstimate(slow: tier, standard: tier, fast: tier),
        ),
        simulationError: RpcException('execution reverted'),
      );
      final service = LocalTransferService(params: params);

      await expectLater(
        service.prepareEvm(
          draft: _evmDraft(),
          from: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
          evmChainId: 1,
        ),
        throwsA(
          isA<EvmPreflightFailed>().having(
            (error) => error.message,
            'message',
            contains('execution reverted'),
          ),
        ),
      );
      expect(params.simulationCount, 1);
    });

    test('prepareEvm rejects insufficient pending native balance', () async {
      final tier = GasFeeEstimateTier(
        maxPriorityFeePerGas: _gwei,
        maxFeePerGas: BigInt.from(30) * _gwei,
      );
      final params = _FakeParamsService(
        (_, _) async => EvmChainParams(
          nonce: 7,
          fees: GasFeeEstimate(slow: tier, standard: tier, fast: tier),
        ),
        spendable: EvmSpendableBalances(native: BigInt.zero),
      );

      await expectLater(
        LocalTransferService(params: params).prepareEvm(
          draft: _evmDraft(),
          from: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
          evmChainId: 1,
        ),
        throwsA(
          isA<EvmInsufficientFunds>().having(
            (error) => error.asset,
            'asset',
            'ETH',
          ),
        ),
      );
    });

    test(
      'new transfer rejects latest fallback when a queued nonce exists',
      () async {
        final tier = GasFeeEstimateTier(
          maxPriorityFeePerGas: _gwei,
          maxFeePerGas: BigInt.from(30) * _gwei,
        );
        final params = _FakeParamsService(
          (_, _) async => EvmChainParams(
            nonce: 7,
            fees: GasFeeEstimate(slow: tier, standard: tier, fast: tier),
          ),
          spendable: EvmSpendableBalances(
            native: BigInt.parse('1000000000000000000'),
            pendingAvailable: false,
          ),
        );

        await expectLater(
          LocalTransferService(params: params).prepareEvm(
            draft: _evmDraft(),
            from: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
            evmChainId: 1,
          ),
          throwsA(isA<EvmPreflightFailed>()),
        );
      },
    );

    test(
      'new transfer may use latest only when confirmed and pending nonce match',
      () async {
        final tier = GasFeeEstimateTier(
          maxPriorityFeePerGas: _gwei,
          maxFeePerGas: BigInt.from(30) * _gwei,
        );
        final params = _FakeParamsService(
          (_, _) async => EvmChainParams(
            nonce: 7,
            fees: GasFeeEstimate(slow: tier, standard: tier, fast: tier),
          ),
          simulationError: RpcException(
            'state not available for pending block',
          ),
          spendable: EvmSpendableBalances(
            native: BigInt.parse('1000000000000000000'),
            pendingAvailable: false,
          ),
          confirmedNonce: 7,
          pendingNonce: 7,
        );

        final prepared = await LocalTransferService(params: params).prepareEvm(
          draft: _evmDraft(),
          from: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
          evmChainId: 1,
        );

        expect(prepared.nonce, BigInt.from(7));
        expect(params.simulatedBlockTags, ['pending', 'latest']);
      },
    );

    test('prepareEvm rejects insufficient pending ERC-20 balance', () async {
      final tier = GasFeeEstimateTier(
        maxPriorityFeePerGas: _gwei,
        maxFeePerGas: BigInt.from(30) * _gwei,
      );
      final params = _FakeParamsService(
        (_, _) async => EvmChainParams(
          nonce: 7,
          fees: GasFeeEstimate(slow: tier, standard: tier, fast: tier),
        ),
        spendable: EvmSpendableBalances(
          native: BigInt.parse('1000000000000000000'),
          token: BigInt.from(2499999),
        ),
      );

      await expectLater(
        LocalTransferService(params: params).prepareEvm(
          draft: _erc20Draft(),
          from: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
          evmChainId: 1,
        ),
        throwsA(
          isA<EvmInsufficientFunds>().having(
            (error) => error.asset,
            'asset',
            'USDT',
          ),
        ),
      );
    });

    test(
      'success: nonce + fee tiers parsed, prefs-resolved endpoint used',
      () async {
        final transport = _FakeJsonRpc(_healthyHandlers(nonce: 42));
        final service = ChainParamsService(
          jsonRpcTransport: transport,
          endpoints: (coin) => coin == Coin.eth
              ? 'https://custom.example/rpc'
              : 'https://wrong.example',
        );

        final params = await service.fetchEvmParams(
          Chain.ethereum,
          _gatewayFrom,
        );
        expect(params.nonce, 42);
        // standard = 2 * next base fee (30 gwei) + mean p50 tip (2 gwei).
        expect(params.fees.standard.maxPriorityFeePerGas, BigInt.two * _gwei);
        expect(params.fees.standard.maxFeePerGas, BigInt.from(62) * _gwei);
        expect(params.tierFor(0).maxPriorityFeePerGas, _gwei);
        expect(params.tierFor(2).maxPriorityFeePerGas, BigInt.from(3) * _gwei);

        // Both calls went to the endpoint the resolver picked for Coin.eth.
        expect(transport.calls, hasLength(2));
        expect(transport.calls.map((c) => c.$1).toSet(), {
          'https://custom.example/rpc',
        });
        expect(transport.calls.map((c) => c.$2).toSet(), {
          'eth_getTransactionCount',
          'eth_feeHistory',
        });
      },
    );

    test('polygon resolves the polygon endpoint', () async {
      final transport = _FakeJsonRpc(_healthyHandlers());
      final service = ChainParamsService(
        jsonRpcTransport: transport,
        endpoints: (coin) => 'https://node.example/${coin.name}',
      );
      await service.fetchEvmParams(Chain.polygon, _gatewayFrom);
      expect(transport.calls.map((c) => c.$1).toSet(), {
        'https://node.example/polygon',
      });
    });

    test('BNB enforces the validator 0.1 gwei minimum tip', () async {
      final belowFloor = BigInt.from(80000000);
      final transport = _FakeJsonRpc({
        'eth_getTransactionCount': (_) => '0x7',
        'eth_feeHistory': (_) => {
          'oldestBlock': '0x64',
          'baseFeePerGas': ['0x0', '0x0'],
          'gasUsedRatio': [0.5],
          'reward': [
            [_hex(belowFloor), _hex(belowFloor), _hex(belowFloor)],
          ],
        },
      });
      final service = ChainParamsService(
        jsonRpcTransport: transport,
        endpoints: (_) => 'https://bsc-testnet.example',
      );

      final params = await service.fetchEvmParams(Chain.bnb, _gatewayFrom);
      final floor = BigInt.from(100000000);
      for (final tier in [
        params.fees.slow,
        params.fees.standard,
        params.fees.fast,
      ]) {
        expect(tier.maxPriorityFeePerGas, floor);
        expect(tier.maxFeePerGas, floor);
      }
    });

    test(
      'node error surfaces as a thrown RpcException (caller owns fallback)',
      () {
        final service = ChainParamsService(
          jsonRpcTransport: _FakeJsonRpc({
            // getNonce errors; feeHistory would succeed — one failure fails the fetch.
            'eth_feeHistory': _healthyHandlers()['eth_feeHistory']!,
          }),
          endpoints: (_) => 'https://node.example',
        );
        expect(
          () => service.fetchEvmParams(Chain.ethereum, _gatewayFrom),
          throwsA(isA<RpcException>()),
        );
      },
    );

    test('non-EVM chains are rejected: TRON/Solana never fetch', () {
      final transport = _FakeJsonRpc(_healthyHandlers());
      final service = ChainParamsService(
        jsonRpcTransport: transport,
        endpoints: (_) => 'https://node.example',
      );
      expect(
        () => service.fetchEvmParams(Chain.tron, 'T123'),
        throwsArgumentError,
      );
      expect(
        () => service.fetchEvmParams(Chain.solana, 'So123'),
        throwsArgumentError,
      );
      expect(transport.calls, isEmpty);
    });
  });

  group('W6 live EVM params wiring', () {
    testWidgets(
      'spinner while fetching, then the QR encodes the REAL nonce/fees',
      (tester) async {
        // Completer-gated fetch so the in-flight spinner state is observable.
        final completer = Completer<EvmChainParams>();
        final service = _FakeParamsService((_, _) => completer.future);
        final draft = _evmDraft(feeTier: 2); // fast tier
        final session = TransferSession()..draft = draft;
        await tester.pumpWidget(
          _wrap(
            TransferSessionScope(
              session: session,
              child: SignRequestQrScreen(paramsService: service),
            ),
          ),
        );

        // Fetch in flight: spinner, no QR, no outstanding request yet.
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.byType(KtQrCode), findsNothing);
        expect(session.request, isNull);

        completer.complete(
          EvmChainParams(
            nonce: 42,
            fees: GasFeeEstimate(
              slow: GasFeeEstimateTier(
                maxPriorityFeePerGas: _gwei,
                maxFeePerGas: BigInt.from(31) * _gwei,
              ),
              standard: GasFeeEstimateTier(
                maxPriorityFeePerGas: BigInt.two * _gwei,
                maxFeePerGas: BigInt.from(32) * _gwei,
              ),
              fast: GasFeeEstimateTier(
                maxPriorityFeePerGas: BigInt.from(3) * _gwei,
                maxFeePerGas: BigInt.from(33) * _gwei,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(KtQrCode), findsOneWidget);
        expect(service.calledChain, Chain.ethereum);

        // The registered request carries the fetched parameters (fast tier).
        final expected = rawTxFor(
          draft,
          from: service.calledFrom!,
          nonce: BigInt.from(42),
          maxPriorityFeePerGas: BigInt.from(3) * _gwei,
          maxFeePerGas: BigInt.from(33) * _gwei,
        );
        expect(session.request!.rawTx, expected);
        expect(
          session.request!.rawTx,
          isNot(equals(rawTxFor(draft, from: service.calledFrom!))),
        );
        // No fallback hint on success.
        expect(find.text('无法获取链上参数，已使用预设 nonce 与手续费'), findsNothing);
      },
    );

    testWidgets('fetch failure blocks QR generation instead of guessing fees', (
      tester,
    ) async {
      final service = _FakeParamsService(
        (_, _) async => throw RpcException('boom'),
      );
      final draft = _evmDraft();
      final session = TransferSession()..draft = draft;
      await tester.pumpWidget(
        _wrap(
          TransferSessionScope(
            session: session,
            child: SignRequestQrScreen(paramsService: service),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(KtQrCode), findsNothing);
      expect(session.request, isNull);
      expect(find.text('无法验证链上交易参数，签名已禁用。'), findsOneWidget);
    });

    testWidgets('simulation revert blocks cold-sign QR generation', (
      tester,
    ) async {
      final tier = GasFeeEstimateTier(
        maxPriorityFeePerGas: _gwei,
        maxFeePerGas: BigInt.from(30) * _gwei,
      );
      final service = _FakeParamsService(
        (_, _) async => EvmChainParams(
          nonce: 7,
          fees: GasFeeEstimate(slow: tier, standard: tier, fast: tier),
        ),
        simulationError: RpcException('execution reverted'),
      );
      final session = TransferSession()..draft = _evmDraft();

      await tester.pumpWidget(
        _wrap(
          TransferSessionScope(
            session: session,
            child: SignRequestQrScreen(paramsService: service),
          ),
        ),
      );
      await tester.pump();

      expect(service.simulationCount, 1);
      expect(find.byType(KtQrCode), findsNothing);
      expect(session.request, isNull);
      expect(find.text('无法验证链上交易参数，签名已禁用。'), findsOneWidget);
    });

    testWidgets('BNB cold-sign QR also fetches real nonce and gas', (
      tester,
    ) async {
      final service = _FakeParamsService(
        (_, _) async => EvmChainParams(
          nonce: 9,
          fees: GasFeeEstimate(
            slow: GasFeeEstimateTier(
              maxPriorityFeePerGas: _gwei,
              maxFeePerGas: _gwei,
            ),
            standard: GasFeeEstimateTier(
              maxPriorityFeePerGas: _gwei,
              maxFeePerGas: _gwei,
            ),
            fast: GasFeeEstimateTier(
              maxPriorityFeePerGas: _gwei,
              maxFeePerGas: _gwei,
            ),
          ),
        ),
      );
      final session = TransferSession()
        ..draft = TransferDraft(
          symbol: 'BNB',
          networkLabel: 'BNB Smart Chain',
          chain: Chain.bnb,
          recipient: '0x925fEA1c0dbf3B011391bbed682E32861BE73213',
          amount: Amount.parse('0.01', 18, symbol: 'BNB'),
          feeTier: 1,
        );

      await tester.pumpWidget(
        _wrap(
          TransferSessionScope(
            session: session,
            child: SignRequestQrScreen(paramsService: service),
          ),
        ),
      );
      await tester.pump();

      expect(service.calledChain, Chain.bnb);
      expect(session.request, isNotNull);
      expect(find.byType(KtQrCode), findsOneWidget);
    });

    testWidgets('TRON draft never fetches (only EVM chains do)', (
      tester,
    ) async {
      final service = _FakeParamsService(
        (_, _) async => throw StateError('must not fetch'),
      );
      final session = TransferSession()
        ..draft = TransferDraft(
          symbol: 'USDT',
          networkLabel: 'TRON · TRC-20',
          chain: Chain.tron,
          recipient: 'TWd4qCEUf3aVpXe2HKk9gJt6nMxR38uQz',
          amount: Amount.parse('88.5', 6, symbol: 'USDT'),
          feeTier: 1,
          tokenContract: usdtTronContract,
        );
      await tester.pumpWidget(
        _wrap(
          TransferSessionScope(
            session: session,
            child: SignRequestQrScreen(paramsService: service),
          ),
        ),
      );
      await tester.pump();

      expect(service.callCount, 0);
      expect(find.byType(KtQrCode), findsOneWidget);
      expect(session.request, isNotNull);
    });
  });

  group('W5/W29 confirm screen fee + fiat', () {
    GasFeeEstimate estimate() => GasFeeEstimate(
      slow: GasFeeEstimateTier(
        maxPriorityFeePerGas: _gwei,
        maxFeePerGas: BigInt.from(31) * _gwei,
      ),
      standard: GasFeeEstimateTier(
        maxPriorityFeePerGas: BigInt.two * _gwei,
        maxFeePerGas: BigInt.from(32) * _gwei,
      ),
      fast: GasFeeEstimateTier(
        maxPriorityFeePerGas: BigInt.from(3) * _gwei,
        maxFeePerGas: BigInt.from(33) * _gwei,
      ),
    );

    testWidgets('a live draft shows the REAL fee, never the demo schedule', (
      tester,
    ) async {
      final completer = Completer<EvmChainParams>();
      final service = _FakeParamsService((_, _) => completer.future);
      final session = TransferSession()..draft = _evmDraft();
      await tester.pumpWidget(
        _wrap(
          TransferSessionScope(
            session: session,
            child: TransferConfirmScreen(isHot: true, paramsService: service),
          ),
        ),
      );

      // While the chain-state fetch is in flight the fee is honestly pending —
      // not a number pulled from a static table.
      expect(find.text('估算中…'), findsOneWidget);
      expect(find.text('≈ 0.00042 ETH'), findsNothing); // demo standard tier
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认转账'))
            .onPressed,
        isNull,
      );

      completer.complete(EvmChainParams(nonce: 42, fees: estimate()));
      await tester.pump();

      // gasLimit 21000 x standard maxFeePerGas 32 gwei = 0.000672 ETH — the
      // very product LocalTransferService.prepareEvm signs.
      expect(find.text('≈ 0.000672 ETH（--）'), findsOneWidget);
      // Total spend adds the REAL fee to the native amount.
      expect(find.text('0.500672 ETH'), findsOneWidget);
      // No fiat source in this harness → '--', never the old 1:1 "≈ \$0.5".
      expect(find.text('≈ --'), findsOneWidget);
      expect(find.text('≈ \$0.5'), findsNothing);
      expect(session.preparedEvm, isNotNull);
      expect(session.preparedEvm!.maximumFee, BigInt.from(672000000000000));
      expect(session.preparedNetworkId, 'eth-mainnet');
      expect(session.preparedAtMs, isNotNull);
      // These rows are decoded from the exact EIP-1559 envelope, not copied
      // from a transport summary or reconstructed after confirmation.
      expect(find.text('预计资产变化'), findsOneWidget);
      expect(find.text('转出 ETH'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('expected-asset-change-outgoing')),
          matching: find.text('-0.5 ETH'),
        ),
        findsOneWidget,
      );
      expect(find.text('最高网络手续费'), findsOneWidget);
      expect(find.text('最多 -0.000672 ETH'), findsOneWidget);
      // The action stays enabled once a real fee is known.
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认转账'))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('ERC-20 preview separates token outflow from native max fee', (
      tester,
    ) async {
      final service = _FakeParamsService(
        (_, _) async => EvmChainParams(nonce: 1, fees: estimate()),
      );
      final session = TransferSession()..draft = _erc20Draft();
      await tester.pumpWidget(
        _wrap(
          TransferSessionScope(
            session: session,
            child: TransferConfirmScreen(isHot: true, paramsService: service),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('预计资产变化'), findsOneWidget);
      expect(find.text('转出 USDT'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('expected-asset-change-outgoing')),
          matching: find.text('-2.5 USDT'),
        ),
        findsOneWidget,
      );
      expect(find.text('最高网络手续费'), findsOneWidget);
      expect(find.text('最多 -0.000672 ETH'), findsOneWidget);
      expect(session.preparedEvm?.tokenContract, _erc20Draft().tokenContract);
    });

    testWidgets('verified token identity is blue and does not claim safety', (
      tester,
    ) async {
      final service = _FakeParamsService(
        (_, _) async => EvmChainParams(nonce: 1, fees: estimate()),
      );
      final session = TransferSession()..draft = _erc20Draft();
      await tester.pumpWidget(
        _wrap(
          TransferSessionScope(
            session: session,
            child: TransferConfirmScreen(
              isHot: true,
              paramsService: service,
              tokenRiskLookup: (_, _) async => const GatewayTokenRisk(
                status: GatewayTokenRiskStatus.safe,
                source: 'official_catalog',
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('官方 Token 身份已核对'), findsOneWidget);
      expect(find.textContaining('蓝勾仅确认身份'), findsOneWidget);
      expect(find.textContaining('安全 Token'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认转账'))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('unsafe token registry match blocks signing', (tester) async {
      final service = _FakeParamsService(
        (_, _) async => EvmChainParams(nonce: 1, fees: estimate()),
      );
      final session = TransferSession()..draft = _erc20Draft();
      await tester.pumpWidget(
        _wrap(
          TransferSessionScope(
            session: session,
            child: TransferConfirmScreen(
              isHot: true,
              paramsService: service,
              tokenRiskLookup: (_, _) async => const GatewayTokenRisk(
                status: GatewayTokenRiskStatus.unsafe,
                category: 'phishing',
                source: 'operator_registry',
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('检测到高风险 Token 合约'), findsOneWidget);
      expect(find.textContaining('本次签名已阻止'), findsOneWidget);
      expect(find.textContaining('暂时无法发送'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认转账'))
            .onPressed,
        isNull,
      );
    });

    testWidgets('unknown risk is explicit and never shown as verified', (
      tester,
    ) async {
      final service = _FakeParamsService(
        (_, _) async => EvmChainParams(nonce: 1, fees: estimate()),
      );
      final session = TransferSession()..draft = _erc20Draft();
      await tester.pumpWidget(
        _wrap(
          TransferSessionScope(
            session: session,
            child: TransferConfirmScreen(
              isHot: true,
              paramsService: service,
              tokenRiskLookup: (_, _) async => const GatewayTokenRisk(
                status: GatewayTokenRiskStatus.unknown,
                source: 'operator_registry',
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Token 风险状态无法确认'), findsOneWidget);
      expect(find.text('官方 Token 身份已核对'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认转账'))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('risk service failure remains unavailable, never safe', (
      tester,
    ) async {
      final service = _FakeParamsService(
        (_, _) async => EvmChainParams(nonce: 1, fees: estimate()),
      );
      final session = TransferSession()..draft = _erc20Draft();
      await tester.pumpWidget(
        _wrap(
          TransferSessionScope(
            session: session,
            child: TransferConfirmScreen(
              isHot: true,
              paramsService: service,
              tokenRiskLookup: (_, _) async => throw TimeoutException('down'),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('暂时无法检查 Token 风险'), findsOneWidget);
      expect(find.textContaining('无法确认该合约安全'), findsOneWidget);
      expect(find.text('官方 Token 身份已核对'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认转账'))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('an unfetchable fee is stated and blocks sending', (
      tester,
    ) async {
      final service = _FakeParamsService(
        (_, _) async => throw RpcException('boom'),
      );
      final session = TransferSession()..draft = _evmDraft();
      await tester.pumpWidget(
        _wrap(
          TransferSessionScope(
            session: session,
            child: TransferConfirmScreen(isHot: false, paramsService: service),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('无法获取网络费'), findsOneWidget);
      expect(find.text('无法估算网络费，暂时无法发送'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '生成待签名二维码'))
            .onPressed,
        isNull,
      );
    });

    testWidgets('without a draft the demo schedule still backs the gallery', (
      tester,
    ) async {
      final service = _FakeParamsService(
        (_, _) async => throw StateError('must not fetch'),
      );
      await tester.pumpWidget(
        _wrap(TransferConfirmScreen(isHot: true, paramsService: service)),
      );
      await tester.pump();

      expect(service.callCount, 0);
      expect(find.text('≈ 13.7 TRX（\$1.90）'), findsOneWidget);
      expect(find.text('≈ \$120.00'), findsOneWidget);
      expect(find.textContaining('尚未备份助记词'), findsOneWidget);
    });

    testWidgets('a backed-up hot wallet does not show the backup warning', (
      tester,
    ) async {
      final wallets = WalletController(
        WalletManager(
          initial: [
            HotWallet(
              id: 'backed-up-wallet',
              name: '测试钱包',
              avatarColor: 0xFF3155DD,
              addresses: const ChainAddresses(
                eth: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
                polygon: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
                tron: 'TNXoiAJ3dct8Fjg4M9fkLFh9S2v9TXc32G',
                solana: '2KW2XRd9kwqet15Aha2oK3tYvd3nWbTFH1MBiRAv1BE1',
              ),
              backedUp: true,
            ),
          ],
        ),
      );
      addTearDown(wallets.dispose);
      final service = _FakeParamsService(
        (_, _) async => EvmChainParams(nonce: 1, fees: estimate()),
      );
      final session = TransferSession()..draft = _evmDraft();

      await tester.pumpWidget(
        _wrap(
          WalletScope(
            controller: wallets,
            child: TransferSessionScope(
              session: session,
              child: TransferConfirmScreen(isHot: true, paramsService: service),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('尚未备份助记词'), findsNothing);
      expect(find.text('预计资产变化'), findsOneWidget);
    });

    testWidgets('fiat comes from the REAL spot price, not a 1:1 peg', (
      tester,
    ) async {
      final market = await _pricedMarket({Coin.eth: 2000.0});
      addTearDown(market.dispose);
      final service = _FakeParamsService(
        (_, _) async => EvmChainParams(nonce: 1, fees: estimate()),
      );
      final session = TransferSession()..draft = _evmDraft();
      await tester.pumpWidget(
        _wrap(
          MarketScope(
            controller: market,
            child: TransferSessionScope(
              session: session,
              child: TransferConfirmScreen(isHot: true, paramsService: service),
            ),
          ),
        ),
      );
      await tester.pump();

      // 0.5 ETH at \$2000 = \$1,000.00 (the old peg rendered "≈ \$0.5").
      expect(find.text('≈ \$1,000.00'), findsOneWidget);
      // 0.000672 ETH of gas at the same price = \$1.34.
      expect(find.text('≈ 0.000672 ETH（\$1.34）'), findsOneWidget);
    });

    testWidgets(
      'Sepolia confirm never values test ETH with the cached mainnet quote',
      (tester) async {
        final market = await _pricedMarket({
          Coin.eth: 2000.0,
        }, isTestnet: (coin) => coin == Coin.eth);
        addTearDown(market.dispose);
        final service = _FakeParamsService(
          (_, _) async => EvmChainParams(nonce: 1, fees: estimate()),
        );
        final session = TransferSession()..draft = _evmDraft();
        final networks = NetworkController(
          initialEnvironment: NetworkEnvironment.testnet,
        );

        await tester.pumpWidget(
          _wrap(
            NetworkScope(
              controller: networks,
              child: MarketScope(
                controller: market,
                child: TransferSessionScope(
                  session: session,
                  child: TransferConfirmScreen(
                    isHot: true,
                    paramsService: service,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('测试网资产无市场价格'), findsOneWidget);
        expect(
          find.text('≈ --'),
          findsNothing,
          reason: 'testnet price absence must be explained, not left blank',
        );
        expect(find.text('≈ 0.000672 ETH'), findsOneWidget);
        expect(find.text('≈ \$1,000.00'), findsNothing);
        expect(find.textContaining(r'$1.34'), findsNothing);
        expect(session.preparedNetworkId, 'eth-sepolia');
      },
    );
  });
}
