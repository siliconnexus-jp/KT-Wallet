import 'dart:convert';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:chains/chains.dart' show Amount, Chain;
import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/market/gateway_client.dart';
import 'package:kt_wallet/src/observability/experience_metrics.dart';
import 'package:kt_wallet/src/screens/transfer_screens.dart';
import 'package:kt_wallet/src/transfer/airgap_codec.dart';
import 'package:kt_wallet/src/transfer/broadcast_service.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';
import 'package:ui_kit/ui_kit.dart';

import 'support/test_wallet_scope.dart';

/// #broadcast: the pipe from a cryptographically verified SignResult to the
/// chain's node. Production has no simulated-success broadcast path.

/// JSON-RPC transport scripted per method; records calls.
class _FakeJsonRpc implements JsonRpcTransport {
  _FakeJsonRpc({this.results = const {}, this.errors = const {}});
  final Map<String, Object?> results;
  final Map<String, (String, int)> errors;
  final calls = <(String url, String method, List<Object?> params)>[];

  @override
  Future<Object?> post(String url, Object body) async {
    final map = body as Map;
    final method = map['method'] as String;
    calls.add((url, method, (map['params'] as List?) ?? const []));
    final err = errors[method];
    if (err != null) {
      return {
        'jsonrpc': '2.0',
        'id': map['id'],
        'error': {'message': err.$1, 'code': err.$2},
      };
    }
    return {'jsonrpc': '2.0', 'id': map['id'], 'result': results[method]};
  }
}

class _FakeRest implements RestTransport {
  _FakeRest([this.postResponse]);
  Object? postResponse;
  final posts = <(String url, Object body)>[];

  @override
  Future<Object?> getJson(String url) async => throw UnimplementedError();

  @override
  Future<Object?> postJson(String url, Object body) async {
    posts.add((url, body));
    return postResponse;
  }
}

class _ThrowingJsonRpc implements JsonRpcTransport {
  _ThrowingJsonRpc(this.error);
  final Object error;
  int calls = 0;

  @override
  Future<Object?> post(String url, Object body) async {
    calls++;
    throw error;
  }
}

class _ThrowingRest implements RestTransport {
  _ThrowingRest(this.error);
  final Object error;
  int calls = 0;

  @override
  Future<Object?> getJson(String url) async => throw UnimplementedError();

  @override
  Future<Object?> postJson(String url, Object body) async {
    calls++;
    throw error;
  }
}

String _endpoint(Coin coin) => 'https://node.example/${coin.name}';

TransferSession _broadcastSession(SignResult result) {
  final draft = TransferDraft(
    symbol: 'ETH',
    networkLabel: 'Ethereum',
    chain: Chain.ethereum,
    recipient: '0x0000000000000000000000000000000000000001',
    amount: Amount(
      raw: BigInt.from(1000000000000000),
      decimals: 18,
      symbol: 'ETH',
    ),
    feeTier: 1,
  );
  final request = SignRequest(
    reqId: Uint8List.fromList(result.reqId),
    walletId: result.walletId,
    coin: result.coin,
    rawTx: Uint8List.fromList(const [1]),
    summary: {
      SummaryKeys.amount: draft.amountText,
      SummaryKeys.network: draft.networkLabel,
      SummaryKeys.recipient: draft.recipient,
    },
    createdAt: 100,
    expiresAt: 200,
  );
  return TransferSession()
    ..begin(draft)
    ..request = request
    ..result = result;
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('fonts/Inter.ttf'))).load();
    await (FontLoader(
      'JetBrains Mono',
    )..addFont(rootBundle.load('fonts/JetBrainsMono.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  group('BroadcastService', () {
    setUp(ExperienceMetrics.instance.clear);

    test(
      'EVM success: hex-encoded bytes to eth_sendRawTransaction, node hash back',
      () async {
        final transport = _FakeJsonRpc(
          results: {'eth_sendRawTransaction': '0xfeedbead'},
        );
        final service = BroadcastService(
          jsonRpcTransport: transport,
          endpoints: _endpoint,
        );

        final outcome = await service.broadcast(
          Chain.ethereum,
          Uint8List.fromList([0x02, 0xab, 0x01]),
        );
        expect(outcome.status, BroadcastStatus.ok);
        expect(outcome.txHash, '0xfeedbead');
        final (url, method, params) = transport.calls.single;
        expect(url, 'https://node.example/eth'); // prefs-style resolver honored
        expect(method, 'eth_sendRawTransaction');
        expect(params.single, '0x02ab01');
        final metric = ExperienceMetrics.instance.recent.single;
        expect(metric.name, ExperienceMetricNames.transactionBroadcast);
        expect(metric.success, isTrue);
      },
    );

    test('EVM node rejection maps to error with the node message', () async {
      final transport = _FakeJsonRpc(
        errors: {'eth_sendRawTransaction': ('nonce too low', -32000)},
      );
      final service = BroadcastService(
        jsonRpcTransport: transport,
        endpoints: _endpoint,
      );

      final outcome = await service.broadcast(
        Chain.polygon,
        Uint8List.fromList([0x02, 0x01]),
      );
      expect(outcome.status, BroadcastStatus.error);
      expect(outcome.message, 'transaction nonce is too low');
      expect(outcome.rejectionKind, RpcRejectionKind.nonceTooLow);
      expect(outcome.txHash, isNull);
      expect(transport.calls.single.$1, 'https://node.example/polygon');
      final metric = ExperienceMetrics.instance.recent.single;
      expect(metric.name, ExperienceMetricNames.transactionBroadcast);
      expect(metric.success, isFalse);
    });

    test('EVM response loss maps to unknown, never to rejected', () async {
      final transport = _ThrowingJsonRpc(
        RpcException('connection closed after request write'),
      );
      final service = BroadcastService(
        jsonRpcTransport: transport,
        endpoints: _endpoint,
      );

      final outcome = await service.broadcast(
        Chain.ethereum,
        Uint8List.fromList([0x02, 0x01]),
      );

      expect(outcome.status, BroadcastStatus.unknown);
      expect(outcome.message, 'RPC response unavailable');
      expect(outcome.txHash, isNull);
      expect(transport.calls, 1);
    });

    test(
      'a mismatched Gateway acknowledgement stays unknown without direct retry',
      () async {
        var gatewayPosts = 0;
        final gateway = GatewayClient(
          baseUrl: 'https://gw.example',
          client: MockClient((request) async {
            gatewayPosts++;
            final body = jsonDecode(request.body) as Map<String, Object?>;
            return http.Response(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': (body['id']! as int) + 1,
                'result': {'txHash': '0xstale'},
              }),
              200,
            );
          }),
        );
        final direct = _FakeJsonRpc(
          results: {'eth_sendRawTransaction': '0xdirect'},
        );
        final service = BroadcastService(
          gateway: () => gateway,
          jsonRpcTransport: direct,
          endpoints: _endpoint,
        );

        final outcome = await service.broadcast(
          Chain.ethereum,
          Uint8List.fromList([0x02, 0x01]),
        );

        expect(outcome.status, BroadcastStatus.unknown);
        expect(outcome.txHash, isNull);
        expect(gatewayPosts, 1);
        expect(direct.calls, isEmpty);
      },
    );

    test(
      'unexpected transport text never reaches the broadcast outcome',
      () async {
        const canary = 'https://rpc.example/v2/private-provider-key';
        final transport = _ThrowingJsonRpc(StateError(canary));
        final service = BroadcastService(
          jsonRpcTransport: transport,
          endpoints: _endpoint,
        );

        final outcome = await service.broadcast(
          Chain.ethereum,
          Uint8List.fromList([0x02, 0x01]),
        );

        expect(outcome.status, BroadcastStatus.unknown);
        expect(outcome.message, 'RPC response unavailable');
        expect(outcome.message, isNot(contains('private-provider-key')));
        expect(transport.calls, 1);
      },
    );

    test(
      'Solana success: base64 bytes to sendTransaction, signature back',
      () async {
        final transport = _FakeJsonRpc(results: {'sendTransaction': 'sig123'});
        final service = BroadcastService(
          jsonRpcTransport: transport,
          endpoints: _endpoint,
        );

        final bytes = Uint8List.fromList([9, 8, 7]);
        final outcome = await service.broadcast(Chain.solana, bytes);
        expect(outcome.status, BroadcastStatus.ok);
        expect(outcome.txHash, 'sig123');
        final (url, method, params) = transport.calls.single;
        expect(url, 'https://node.example/solana');
        expect(method, 'sendTransaction');
        expect(params.first, base64Encode(bytes));
      },
    );

    test('Solana and TRON response loss both remain unknown', () async {
      final solTransport = _ThrowingJsonRpc(RpcException('socket closed'));
      final solService = BroadcastService(
        jsonRpcTransport: solTransport,
        endpoints: _endpoint,
      );
      final sol = await solService.broadcast(
        Chain.solana,
        Uint8List.fromList([1, 2, 3]),
      );
      expect(sol.status, BroadcastStatus.unknown);
      expect(solTransport.calls, 1);

      final tronTransport = _ThrowingRest(RpcException('socket closed'));
      final tronService = BroadcastService(
        restTransport: tronTransport,
        endpoints: _endpoint,
      );
      final tron = await tronService.broadcast(
        Chain.tron,
        Uint8List.fromList(utf8.encode('{"signature":["aa"]}')),
      );
      expect(tron.status, BroadcastStatus.unknown);
      expect(tronTransport.calls, 1);
    });

    test(
      'TRON success: TronGrid JSON payload posts to broadcasttransaction',
      () async {
        final rest = _FakeRest({'result': true, 'txid': 'abc123'});
        final service = BroadcastService(
          restTransport: rest,
          endpoints: _endpoint,
        );

        final txJson = {
          'raw_data': {'ref_block_bytes': '1234'},
          'signature': ['aa'],
        };
        final outcome = await service.broadcast(
          Chain.tron,
          Uint8List.fromList(utf8.encode(json.encode(txJson))),
        );
        expect(outcome.status, BroadcastStatus.ok);
        expect(outcome.txHash, 'abc123');
        final (url, body) = rest.posts.single;
        expect(url, 'https://node.example/tron/wallet/broadcasttransaction');
        expect(body, txJson);
      },
    );

    test('TRON rejection surfaces a safe normalized error', () async {
      final rest = _FakeRest({
        'result': false,
        'code': 'SIGERROR',
        'message': 'bad sig',
      });
      final service = BroadcastService(
        restTransport: rest,
        endpoints: _endpoint,
      );
      final outcome = await service.broadcast(
        Chain.tron,
        Uint8List.fromList(utf8.encode('{"signature":["aa"]}')),
      );
      expect(outcome.status, BroadcastStatus.error);
      expect(outcome.message, 'transaction signature is invalid');
      expect(outcome.rejectionKind, RpcRejectionKind.invalidSignature);
    });

    test('TRON non-JSON signed payload: unsupported, nothing posted', () async {
      // TronRpc only posts the TronGrid JSON body; a raw (e.g. protobuf) blob
      // honestly cannot be submitted until real TRON signing produces JSON.
      final rest = _FakeRest();
      final service = BroadcastService(
        restTransport: rest,
        endpoints: _endpoint,
      );
      final outcome = await service.broadcast(
        Chain.tron,
        Uint8List.fromList([0x0a, 0x02, 0xff]),
      );
      expect(outcome.status, BroadcastStatus.unsupported);
      expect(outcome.message, isNotNull);
      expect(rest.posts, isEmpty);
    });
  });

  group('W8 broadcast wiring', () {
    Widget app(
      TransferSession session,
      BroadcastService service, {
      Locale locale = const Locale('zh'),
    }) {
      final router = GoRouter(
        initialLocation: '/broadcast-confirm',
        routes: [
          GoRoute(
            path: '/broadcast-confirm',
            builder: (c, s) => BroadcastConfirmScreen(broadcaster: service),
          ),
          GoRoute(
            path: '/broadcast-result',
            builder: (c, s) => const BroadcastResultScreen(),
          ),
        ],
      );
      return MaterialApp.router(
        debugShowCheckedModeBanner: false,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          fontFamily: 'Inter',
          scaffoldBackgroundColor: WalletColors.bg,
        ),
        routerConfig: router,
        builder: (c, child) => withTestWalletScope(
          TransferSessionScope(session: session, child: child!),
        ),
      );
    }

    testWidgets('real signature + node acceptance: W9 shows the node hash', (
      tester,
    ) async {
      final jsonRpc = _FakeJsonRpc(
        results: {'eth_sendRawTransaction': '0xfeedbead'},
      );
      final service = BroadcastService(
        jsonRpcTransport: jsonRpc,
        endpoints: _endpoint,
      );
      final result = SignResult(
        reqId: Uint8List.fromList(List.filled(AirgapLimits.reqIdLength, 3)),
        walletId: 'w1',
        coin: 60,
        signedTx: Uint8List.fromList([0x02, 0xab, 0x01]),
        signer: '0x925fEA1c0dbf3B011391bbed682E32861BE73213',
        txHash: 'prebroadcast-hash',
      );
      final session = _broadcastSession(result);

      await tester.pumpWidget(app(session, service));
      await tester.pump();
      await tester.tap(find.byType(KtPrimaryButton));
      await tester.pumpAndSettle();

      expect(find.text('交易已提交'), findsOneWidget); // W9
      expect(session.broadcastTxHash, '0xfeedbead');
      expect(
        find.text(truncateMiddle('0xfeedbead', head: 6, tail: 6)),
        findsOneWidget,
      );
      expect(find.text('确认中'), findsOneWidget);
      expect(find.textContaining(RegExp(r'\(\d+/\d+\)')), findsNothing);
      expect(jsonRpc.calls, hasLength(1));
    });

    testWidgets(
      'real signature + node rejection: stays on W8 with a localized reason',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        final transport = _FakeJsonRpc(
          errors: {'eth_sendRawTransaction': ('nonce too low', -32000)},
        );
        final service = BroadcastService(
          jsonRpcTransport: transport,
          endpoints: _endpoint,
        );
        // A non-demo signature (as the wallet-core integration will produce).
        final session = _broadcastSession(
          SignResult(
            reqId: Uint8List.fromList(List.filled(AirgapLimits.reqIdLength, 7)),
            walletId: 'w1',
            coin: 60, // SLIP-44 ethereum
            signedTx: Uint8List.fromList([0x02, 0x01, 0x02]),
            signer: '0x925fEA1c0dbf3B011391bbed682E32861BE73213',
            txHash: 'aabbcc',
          ),
        );

        await tester.pumpWidget(
          app(session, service, locale: const Locale('en')),
        );
        await tester.pump();
        await tester.tap(find.byType(KtPrimaryButton));
        await tester.pumpAndSettle();

        // broadcastError → failed: no navigation, structured reason localized,
        // manual retry only. The transport sentence is replaced with the
        // locale-owned actionable copy rather than interpolated verbatim.
        expect(find.text('Transaction submitted'), findsNothing);
        expect(
          find.text(
            'Broadcast failed: The transaction nonce is too low. '
            'Refresh and try again.',
          ),
          findsOneWidget,
        );
        expect(find.text('transaction nonce is too low'), findsNothing);
        expect(
          transport.calls,
          hasLength(1),
        ); // posted exactly once, no auto-retry
        expect(session.broadcastTxHash, isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/broadcast/rejected-en.png'),
        );
      },
    );

    testWidgets(
      'response loss opens honest reconciliation UI and forbids a second post',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        final transport = _ThrowingJsonRpc(
          RpcException('connection closed after request write'),
        );
        final service = BroadcastService(
          jsonRpcTransport: transport,
          endpoints: _endpoint,
        );
        final result = SignResult(
          reqId: Uint8List.fromList(List.filled(AirgapLimits.reqIdLength, 9)),
          walletId: 'w1',
          coin: 60,
          signedTx: Uint8List.fromList([0x02, 0x01, 0x02]),
          signer: '0x925fEA1c0dbf3B011391bbed682E32861BE73213',
          txHash: 'locally-derived-hash',
        );
        final session = _broadcastSession(result);

        await tester.pumpWidget(
          app(session, service, locale: const Locale('en')),
        );
        await tester.pump();
        await tester.tap(find.byType(KtPrimaryButton));
        await tester.pumpAndSettle();

        expect(find.text('Broadcast result unknown'), findsOneWidget);
        expect(find.textContaining('Do not send it again'), findsOneWidget);
        expect(session.broadcastTxHash, 'locally-derived-hash');
        expect(session.broadcastOutcomeUnknown, isTrue);
        expect(transport.calls, 1);
        expect(find.textContaining('Broadcast failed'), findsNothing);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/broadcast/unknown-en.png'),
        );
      },
    );
  });
}
