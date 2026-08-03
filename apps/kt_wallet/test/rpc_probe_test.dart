import 'dart:convert';

import 'package:chains/chains.dart' show Chain;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kt_wallet/src/widgets/rpc_probe.dart';

void main() {
  test('custom EVM probe rejects a stale JSON-RPC response id', () async {
    final probe = RpcProbe(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': 2, 'result': '0x7a69'}),
          200,
        ),
      ),
    );

    expect(
      await probe.probe(
        chain: Chain.ethereum,
        rpcUrl: 'https://rpc.example',
        expectedChainId: 31337,
      ),
      isA<RpcProbeFailure>(),
    );
  });

  test('custom Solana probe rejects a versionless response', () async {
    final probe = RpcProbe(
      client: MockClient(
        (_) async =>
            http.Response(jsonEncode({'id': 1, 'result': 'genesis'}), 200),
      ),
    );

    expect(
      await probe.probe(chain: Chain.solana, rpcUrl: 'https://rpc.example'),
      isA<RpcProbeFailure>(),
    );
  });
}
