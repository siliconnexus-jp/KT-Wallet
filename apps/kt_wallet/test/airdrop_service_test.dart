import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kt_wallet/src/market/airdrop_service.dart';

void main() {
  Future<AirdropException> failureFor(
    http.Response Function(http.Request request) response,
  ) async {
    final service = AirdropService(
      client: MockClient((request) async {
        return response(request);
      }),
    );
    try {
      await service.requestAirdrop(
        rpcUrl: 'https://rpc.example/alch_airdrop_test_secret',
        address: 'SolanaAddress',
      );
      fail('request should fail');
    } on AirdropException catch (error) {
      return error;
    }
  }

  test('HTTP status maps to bounded failure categories', () async {
    expect(
      (await failureFor((_) => http.Response('', 429))).kind,
      AirdropFailureKind.rateLimited,
    );
    expect(
      (await failureFor((_) => http.Response('', 503))).kind,
      AirdropFailureKind.unavailable,
    );
    expect(
      (await failureFor((_) => http.Response('', 400))).kind,
      AirdropFailureKind.invalidRequest,
    );
    expect(
      (await failureFor((_) => http.Response('', 403))).kind,
      AirdropFailureKind.rejected,
    );
  });

  test('RPC errors are classified without retaining provider text', () async {
    final error = await failureFor(
      (_) => http.Response(
        jsonEncode({
          'jsonrpc': '2.0',
          'error': {
            'code': -32000,
            'message': 'faucet has insufficient funds; alch_rpc_body_secret',
          },
        }),
        200,
      ),
    );

    expect(error.kind, AirdropFailureKind.insufficientFunds);
    expect(error.toString(), isNot(contains('alch_rpc_body_secret')));
  });

  test('malformed responses have a stable category', () async {
    final error = await failureFor((_) => http.Response('{broken', 200));
    expect(error.kind, AirdropFailureKind.malformedResponse);
  });

  test('transport errors do not retain a credential-bearing URI', () async {
    final service = AirdropService(
      client: MockClient((request) async {
        throw http.ClientException('offline', request.url);
      }),
    );

    Object? thrown;
    try {
      await service.requestAirdrop(
        rpcUrl: 'https://rpc.example/alch_airdrop_transport_secret',
        address: 'SolanaAddress',
      );
    } catch (error) {
      thrown = error;
    }

    expect(thrown, isA<AirdropException>());
    expect((thrown! as AirdropException).kind, AirdropFailureKind.unavailable);
    expect(thrown.toString(), isNot(contains('alch_airdrop_transport_secret')));
  });
}
