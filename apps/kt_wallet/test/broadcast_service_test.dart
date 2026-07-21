import 'dart:convert';
import 'dart:typed_data';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:chains/chains.dart' show Chain, sha256;
import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/testing.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/market/gateway_client.dart';
import 'package:kt_wallet/src/screens/transfer_screens.dart';
import 'package:kt_wallet/src/transfer/airgap_codec.dart';
import 'package:kt_wallet/src/transfer/broadcast_service.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';
import 'package:ui_kit/ui_kit.dart';

/// #broadcast: the pipe from a decoded SignResult to the chain's node — with
/// the hard gate that demo `SIGNED-V1:` signatures NEVER touch the network.

Uint8List _demoSigned([List<int> tail = const [1, 2, 3]]) =>
    Uint8List.fromList([...utf8.encode('SIGNED-V1:'), ...tail]);

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
      return {'jsonrpc': '2.0', 'id': map['id'], 'error': {'message': err.$1, 'code': err.$2}};
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

/// Transport that fails the test if any request reaches it.
class _NoNetworkJsonRpc implements JsonRpcTransport {
  int calls = 0;
  @override
  Future<Object?> post(String url, Object body) async {
    calls++;
    fail('demo signatures must never reach the network (posted to $url)');
  }
}

class _NoNetworkRest implements RestTransport {
  int calls = 0;
  @override
  Future<Object?> getJson(String url) async {
    calls++;
    fail('demo signatures must never reach the network (GET $url)');
  }

  @override
  Future<Object?> postJson(String url, Object body) async {
    calls++;
    fail('demo signatures must never reach the network (POST $url)');
  }
}

String _endpoint(Coin coin) => 'https://node.example/${coin.name}';

void main() {
  group('BroadcastService', () {
    test('GATE: demo SIGNED-V1 signature short-circuits, zero network calls', () async {
      final jsonRpc = _NoNetworkJsonRpc();
      final rest = _NoNetworkRest();
      final service = BroadcastService(
          jsonRpcTransport: jsonRpc, restTransport: rest, endpoints: _endpoint);

      final signed = _demoSigned();
      for (final chain in Chain.values) {
        final outcome = await service.broadcast(chain, signed);
        expect(outcome.status, BroadcastStatus.simulated);
        // Same hash the simulated signer put in the SignResult.
        expect(outcome.txHash, hexEncode(sha256(signed)));
      }
      expect(jsonRpc.calls, 0);
      expect(rest.calls, 0);
    });

    test('GATE holds with a gateway configured: demo signature never reaches '
        'the gateway either', () async {
      final jsonRpc = _NoNetworkJsonRpc();
      final rest = _NoNetworkRest();
      var gatewayHits = 0;
      // A resolver that returns a client whose transport fails the test on
      // any request: the demo short-circuit must fire BEFORE gateway logic.
      final gateway = GatewayClient(
        baseUrl: 'https://gw.example',
        client: MockClient((request) async {
          gatewayHits++;
          fail('demo signatures must never reach the gateway (${request.url})');
        }),
      );
      final service = BroadcastService(
        jsonRpcTransport: jsonRpc,
        restTransport: rest,
        endpoints: _endpoint,
        gateway: () => gateway,
      );

      final signed = _demoSigned();
      for (final chain in Chain.values) {
        final outcome = await service.broadcast(chain, signed);
        expect(outcome.status, BroadcastStatus.simulated);
        expect(outcome.txHash, hexEncode(sha256(signed)));
      }
      expect(gatewayHits, 0);
      expect(jsonRpc.calls, 0);
      expect(rest.calls, 0);
    });

    test('EVM success: hex-encoded bytes to eth_sendRawTransaction, node hash back', () async {
      final transport = _FakeJsonRpc(results: {'eth_sendRawTransaction': '0xfeedbead'});
      final service = BroadcastService(jsonRpcTransport: transport, endpoints: _endpoint);

      final outcome = await service.broadcast(
          Chain.ethereum, Uint8List.fromList([0x02, 0xab, 0x01]));
      expect(outcome.status, BroadcastStatus.ok);
      expect(outcome.txHash, '0xfeedbead');
      final (url, method, params) = transport.calls.single;
      expect(url, 'https://node.example/eth'); // prefs-style resolver honored
      expect(method, 'eth_sendRawTransaction');
      expect(params.single, '0x02ab01');
    });

    test('EVM node rejection maps to error with the node message', () async {
      final transport = _FakeJsonRpc(
          errors: {'eth_sendRawTransaction': ('nonce too low', -32000)});
      final service = BroadcastService(jsonRpcTransport: transport, endpoints: _endpoint);

      final outcome =
          await service.broadcast(Chain.polygon, Uint8List.fromList([0x02, 0x01]));
      expect(outcome.status, BroadcastStatus.error);
      expect(outcome.message, 'nonce too low');
      expect(outcome.txHash, isNull);
      expect(transport.calls.single.$1, 'https://node.example/polygon');
    });

    test('Solana success: base64 bytes to sendTransaction, signature back', () async {
      final transport = _FakeJsonRpc(results: {'sendTransaction': 'sig123'});
      final service = BroadcastService(jsonRpcTransport: transport, endpoints: _endpoint);

      final bytes = Uint8List.fromList([9, 8, 7]);
      final outcome = await service.broadcast(Chain.solana, bytes);
      expect(outcome.status, BroadcastStatus.ok);
      expect(outcome.txHash, 'sig123');
      final (url, method, params) = transport.calls.single;
      expect(url, 'https://node.example/solana');
      expect(method, 'sendTransaction');
      expect(params.first, base64Encode(bytes));
    });

    test('TRON success: TronGrid JSON payload posts to broadcasttransaction', () async {
      final rest = _FakeRest({'result': true, 'txid': 'abc123'});
      final service = BroadcastService(restTransport: rest, endpoints: _endpoint);

      final txJson = {'raw_data': {'ref_block_bytes': '1234'}, 'signature': ['aa']};
      final outcome = await service.broadcast(
          Chain.tron, Uint8List.fromList(utf8.encode(json.encode(txJson))));
      expect(outcome.status, BroadcastStatus.ok);
      expect(outcome.txHash, 'abc123');
      final (url, body) = rest.posts.single;
      expect(url, 'https://node.example/tron/wallet/broadcasttransaction');
      expect(body, txJson);
    });

    test('TRON rejection surfaces the node message as error', () async {
      final rest = _FakeRest({'result': false, 'code': 'SIGERROR', 'message': 'bad sig'});
      final service = BroadcastService(restTransport: rest, endpoints: _endpoint);
      final outcome = await service.broadcast(
          Chain.tron, Uint8List.fromList(utf8.encode('{"signature":["aa"]}')));
      expect(outcome.status, BroadcastStatus.error);
      expect(outcome.message, contains('bad sig'));
    });

    test('TRON non-JSON signed payload: unsupported, nothing posted', () async {
      // TronRpc only posts the TronGrid JSON body; a raw (e.g. protobuf) blob
      // honestly cannot be submitted until real TRON signing produces JSON.
      final rest = _FakeRest();
      final service = BroadcastService(restTransport: rest, endpoints: _endpoint);
      final outcome = await service.broadcast(
          Chain.tron, Uint8List.fromList([0x0a, 0x02, 0xff]));
      expect(outcome.status, BroadcastStatus.unsupported);
      expect(outcome.message, isNotNull);
      expect(rest.posts, isEmpty);
    });
  });

  group('W8 broadcast wiring', () {
    Widget app(TransferSession session, BroadcastService service) {
      final router = GoRouter(initialLocation: '/broadcast-confirm', routes: [
        GoRoute(
            path: '/broadcast-confirm',
            builder: (c, s) => BroadcastConfirmScreen(broadcaster: service)),
        GoRoute(path: '/broadcast-result', builder: (c, s) => const BroadcastResultScreen()),
      ]);
      return MaterialApp.router(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(scaffoldBackgroundColor: WalletColors.bg),
        routerConfig: router,
        builder: (c, child) => TransferSessionScope(session: session, child: child!),
      );
    }

    testWidgets('demo result: simulated success path, no network, W9 shows the hash', (tester) async {
      final jsonRpc = _NoNetworkJsonRpc();
      final rest = _NoNetworkRest();
      final service = BroadcastService(
          jsonRpcTransport: jsonRpc, restTransport: rest, endpoints: _endpoint);
      final request = buildSignRequest(walletId: 'w1', fromAddress: demoFromAddress);
      final result = buildDemoSignResult(request, signer: demoFromAddress);
      final session = TransferSession()
        ..request = request
        ..result = result;

      await tester.pumpWidget(app(session, service));
      await tester.pump();
      await tester.tap(find.byType(KtPrimaryButton));
      await tester.pumpAndSettle();

      expect(find.text('交易已提交'), findsOneWidget); // W9
      expect(session.broadcastTxHash, result.txHash);
      expect(find.text(truncateMiddle(result.txHash, head: 6, tail: 6)), findsOneWidget);
      expect(jsonRpc.calls, 0);
      expect(rest.calls, 0);
    });

    testWidgets('real signature + node rejection: stays on W8, failed UI shows the node message', (tester) async {
      final transport =
          _FakeJsonRpc(errors: {'eth_sendRawTransaction': ('nonce too low', -32000)});
      final service = BroadcastService(jsonRpcTransport: transport, endpoints: _endpoint);
      // A non-demo signature (as the wallet-core integration will produce).
      final session = TransferSession()
        ..result = SignResult(
          reqId: Uint8List.fromList(List.filled(AirgapLimits.reqIdLength, 7)),
          walletId: 'w1',
          coin: 60, // SLIP-44 ethereum
          signedTx: Uint8List.fromList([0x02, 0x01, 0x02]),
          signer: '0x925fEA1c0dbf3B011391bbed682E32861BE73213',
          txHash: 'aabbcc',
        );

      await tester.pumpWidget(app(session, service));
      await tester.pump();
      await tester.tap(find.byType(KtPrimaryButton));
      await tester.pumpAndSettle();

      // broadcastError → failed: no navigation, message surfaced, manual retry only.
      expect(find.text('交易已提交'), findsNothing);
      expect(find.text('广播失败：nonce too low'), findsOneWidget);
      expect(transport.calls, hasLength(1)); // posted exactly once, no auto-retry
      expect(session.broadcastTxHash, isNull);
    });
  });
}
