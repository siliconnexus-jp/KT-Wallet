import 'dart:convert';

import 'package:chains/chains.dart' show Chain;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kt_wallet/src/widgets/rpc_probe.dart';

void main() {
  const solanaGenesis = 'EtWTRABZaYq6iMfeYKouRu166VU2xqa1wcaWoxPkrZBG';
  const tronGenesis =
      '0000000000000000d698d4192c56cb6be724a558448e2684802de4d6cd8690dc';

  test(
    'custom EVM probe accepts and normalizes a canonical chain id',
    () async {
      final probe = RpcProbe(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': '0x7a69'}),
            200,
          ),
        ),
      );

      final result = await probe.probe(
        chain: Chain.ethereum,
        rpcUrl: 'https://rpc.example',
        expectedChainId: 31337,
      );

      expect(result, isA<RpcProbeOk>());
      expect((result as RpcProbeOk).identity, '31337');
    },
  );

  test(
    'custom Solana probe accepts a canonical 32-byte genesis hash',
    () async {
      final probe = RpcProbe(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': solanaGenesis}),
            200,
          ),
        ),
      );

      final result = await probe.probe(
        chain: Chain.solana,
        rpcUrl: 'https://rpc.example',
      );

      expect(result, isA<RpcProbeOk>());
      expect((result as RpcProbeOk).identity, solanaGenesis);
    },
  );

  test('custom TRON probe accepts canonical block-zero identity', () async {
    final probe = RpcProbe(
      client: MockClient(
        (_) async => http.Response(jsonEncode({'blockID': tronGenesis}), 200),
      ),
    );

    final result = await probe.probe(
      chain: Chain.tron,
      rpcUrl: 'https://rpc.example',
    );

    expect(result, isA<RpcProbeOk>());
    expect((result as RpcProbeOk).identity, tronGenesis);
  });

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

  test('custom EVM probe rejects duplicate result members', () async {
    final probe = RpcProbe(
      client: MockClient(
        (_) async => http.Response(
          '{"jsonrpc":"2.0","id":1,"result":"0x1",'
          '"result":"0x7a69"}',
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

  test('custom EVM probe rejects a non-canonical chain id', () async {
    final probe = RpcProbe(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': '0x07a69'}),
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

  test('custom Solana probe rejects a non-32-byte genesis hash', () async {
    final probe = RpcProbe(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': 'genesis'}),
          200,
        ),
      ),
    );

    expect(
      await probe.probe(chain: Chain.solana, rpcUrl: 'https://rpc.example'),
      isA<RpcProbeFailure>(),
    );
  });

  test('custom TRON probe rejects duplicate block identities', () async {
    final canonical = List<String>.filled(64, 'a').join();
    final probe = RpcProbe(
      client: MockClient(
        (_) async => http.Response(
          '{"blockID":"${List<String>.filled(64, 'b').join()}",'
          '"blockID":"$canonical"}',
          200,
        ),
      ),
    );

    expect(
      await probe.probe(chain: Chain.tron, rpcUrl: 'https://rpc.example'),
      isA<RpcProbeFailure>(),
    );
  });
}
