import 'dart:async';

import 'package:chains/chains.dart';
import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/screens/transfer_screens.dart';
import 'package:kt_wallet/src/transfer/airgap_codec.dart';
import 'package:kt_wallet/src/transfer/chain_params_service.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';
import 'package:ui_kit/ui_kit.dart';

/// #nonce/gas: live EVM chain-state parameters — the service that fetches
/// them over an injectable transport, and the W6 wiring that builds the QR
/// only after the fetch (real values on success, documented demo constants +
/// fallback hint on failure).

final _gwei = BigInt.from(1000000000);

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
      return {'jsonrpc': '2.0', 'id': map['id'], 'error': {'code': -32601, 'message': 'method not found'}};
    }
    return {'jsonrpc': '2.0', 'id': map['id'], 'result': handler((map['params'] as List?) ?? const [])};
  }
}

Map<String, Object? Function(List<Object?>)> _healthyHandlers({int nonce = 7}) => {
      'eth_getTransactionCount': (_) => _hex(BigInt.from(nonce)),
      // Latest base fee 30 gwei; percentile tips 1/2/3 gwei on every row.
      'eth_feeHistory': (_) => {
            'baseFeePerGas': [_hex(BigInt.from(25) * _gwei), _hex(BigInt.from(30) * _gwei)],
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
      decimals: 18,
      recipient: '0x925fEA1c0dbf3B011391bbed682E32861BE73213',
      amount: Amount.parse('0.5', 18, symbol: 'ETH'),
      feeTier: feeTier,
    );

/// Test double whose fetch is scripted; never touches any transport.
class _FakeParamsService extends ChainParamsService {
  _FakeParamsService(this._fetch) : super(jsonRpcTransport: _FakeJsonRpc(const {}));
  final Future<EvmChainParams> Function(Chain chain, String from) _fetch;
  Chain? calledChain;
  String? calledFrom;
  int callCount = 0;

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
}

Widget _wrap(Widget child) => MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(scaffoldBackgroundColor: WalletColors.bg),
      home: child,
    );

void main() {
  group('ChainParamsService', () {
    test('success: nonce + fee tiers parsed, prefs-resolved endpoint used', () async {
      final transport = _FakeJsonRpc(_healthyHandlers(nonce: 42));
      final service = ChainParamsService(
        jsonRpcTransport: transport,
        endpoints: (coin) => coin == Coin.eth ? 'https://custom.example/rpc' : 'https://wrong.example',
      );

      final params = await service.fetchEvmParams(Chain.ethereum, '0xabc');
      expect(params.nonce, 42);
      // standard = latest base fee (30 gwei) + mean 50th-percentile tip (2 gwei).
      expect(params.fees.standard.maxPriorityFeePerGas, BigInt.two * _gwei);
      expect(params.fees.standard.maxFeePerGas, BigInt.from(32) * _gwei);
      expect(params.tierFor(0).maxPriorityFeePerGas, _gwei);
      expect(params.tierFor(2).maxPriorityFeePerGas, BigInt.from(3) * _gwei);

      // Both calls went to the endpoint the resolver picked for Coin.eth.
      expect(transport.calls, hasLength(2));
      expect(transport.calls.map((c) => c.$1).toSet(), {'https://custom.example/rpc'});
      expect(transport.calls.map((c) => c.$2).toSet(),
          {'eth_getTransactionCount', 'eth_feeHistory'});
    });

    test('polygon resolves the polygon endpoint', () async {
      final transport = _FakeJsonRpc(_healthyHandlers());
      final service = ChainParamsService(
        jsonRpcTransport: transport,
        endpoints: (coin) => 'https://node.example/${coin.name}',
      );
      await service.fetchEvmParams(Chain.polygon, '0xabc');
      expect(transport.calls.map((c) => c.$1).toSet(), {'https://node.example/polygon'});
    });

    test('node error surfaces as a thrown RpcException (caller owns fallback)', () {
      final service = ChainParamsService(
        jsonRpcTransport: _FakeJsonRpc({
          // getNonce errors; feeHistory would succeed — one failure fails the fetch.
          'eth_feeHistory': _healthyHandlers()['eth_feeHistory']!,
        }),
        endpoints: (_) => 'https://node.example',
      );
      expect(() => service.fetchEvmParams(Chain.ethereum, '0xabc'),
          throwsA(isA<RpcException>()));
    });

    test('non-EVM chains are rejected: TRON/Solana never fetch', () {
      final transport = _FakeJsonRpc(_healthyHandlers());
      final service = ChainParamsService(
          jsonRpcTransport: transport, endpoints: (_) => 'https://node.example');
      expect(() => service.fetchEvmParams(Chain.tron, 'T123'), throwsArgumentError);
      expect(() => service.fetchEvmParams(Chain.solana, 'So123'), throwsArgumentError);
      expect(transport.calls, isEmpty);
    });
  });

  group('W6 live EVM params wiring', () {
    testWidgets('spinner while fetching, then the QR encodes the REAL nonce/fees', (tester) async {
      // Completer-gated fetch so the in-flight spinner state is observable.
      final completer = Completer<EvmChainParams>();
      final service = _FakeParamsService((_, _) => completer.future);
      final draft = _evmDraft(feeTier: 2); // fast tier
      final session = TransferSession()..draft = draft;
      await tester.pumpWidget(_wrap(TransferSessionScope(
          session: session, child: SignRequestQrScreen(paramsService: service))));

      // Fetch in flight: spinner, no QR, no outstanding request yet.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(KtQrCode), findsNothing);
      expect(session.request, isNull);

      completer.complete(EvmChainParams(
        nonce: 42,
        fees: GasFeeEstimate(
          slow: GasFeeEstimateTier(maxPriorityFeePerGas: _gwei, maxFeePerGas: BigInt.from(31) * _gwei),
          standard: GasFeeEstimateTier(maxPriorityFeePerGas: BigInt.two * _gwei, maxFeePerGas: BigInt.from(32) * _gwei),
          fast: GasFeeEstimateTier(maxPriorityFeePerGas: BigInt.from(3) * _gwei, maxFeePerGas: BigInt.from(33) * _gwei),
        ),
      ));
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
      expect(session.request!.rawTx, isNot(equals(rawTxFor(draft, from: service.calledFrom!))));
      // No fallback hint on success.
      expect(find.text('无法获取链上参数，已使用预设 nonce 与手续费'), findsNothing);
    });

    testWidgets('fetch failure blocks QR generation instead of guessing fees', (tester) async {
      final service = _FakeParamsService((_, _) async => throw RpcException('boom'));
      final draft = _evmDraft();
      final session = TransferSession()..draft = draft;
      await tester.pumpWidget(_wrap(TransferSessionScope(
          session: session, child: SignRequestQrScreen(paramsService: service))));
      await tester.pump();

      expect(find.byType(KtQrCode), findsNothing);
      expect(session.request, isNull);
      expect(
        find.text(
          'Unable to estimate the network fee. Sending is disabled.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('TRON draft never fetches (only EVM chains do)', (tester) async {
      final service = _FakeParamsService((_, _) async => throw StateError('must not fetch'));
      final session = TransferSession()
        ..draft = TransferDraft(
          symbol: 'USDT',
          networkLabel: 'TRON · TRC-20',
          chain: Chain.tron,
          decimals: 6,
          recipient: 'TWd4qCEUf3aVpXe2HKk9gJt6nMxR38uQz',
          amount: Amount.parse('88.5', 6, symbol: 'USDT'),
          feeTier: 1,
          tokenContract: usdtTronContract,
        );
      await tester.pumpWidget(_wrap(TransferSessionScope(
          session: session, child: SignRequestQrScreen(paramsService: service))));
      await tester.pump();

      expect(service.callCount, 0);
      expect(find.byType(KtQrCode), findsOneWidget);
      expect(session.request, isNotNull);
    });
  });
}
