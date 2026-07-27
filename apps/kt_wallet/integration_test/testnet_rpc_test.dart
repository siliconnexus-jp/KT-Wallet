import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/src/state/networks.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('built-in testnet RPCs identify the expected live networks', () async {
    expect(
      await _jsonRpc(ethSepolia.rpcUrl, 'eth_chainId'),
      '0xaa36a7',
      reason: 'Sepolia chain id must be 11155111',
    );
    expect(
      await _jsonRpc(polygonAmoy.rpcUrl, 'eth_chainId'),
      '0x13882',
      reason: 'Amoy chain id must be 80002',
    );

    final solanaVersion =
        await _jsonRpc(solanaDevnet.rpcUrl, 'getVersion') as Map;
    expect(solanaVersion['solana-core'], isNotEmpty);

    final tronResponse = await http
        .post(
          Uri.parse('${tronNile.rpcUrl}/wallet/getnowblock'),
          headers: const {'content-type': 'application/json'},
          body: '{}',
        )
        .timeout(const Duration(seconds: 20));
    expect(tronResponse.statusCode, 200);
    final tronBlock = jsonDecode(tronResponse.body) as Map<String, Object?>;
    expect(
      tronBlock['blockID'],
      isA<String>().having((value) => value.length, 'length', 64),
    );
  });
}

Future<Object?> _jsonRpc(String endpoint, String method) async {
  final response = await http
      .post(
        Uri.parse(endpoint),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': method,
          'params': const <Object?>[],
        }),
      )
      .timeout(const Duration(seconds: 20));
  expect(response.statusCode, 200, reason: '$method at $endpoint');
  final decoded = jsonDecode(response.body) as Map<String, Object?>;
  expect(decoded['error'], isNull, reason: '$method at $endpoint');
  return decoded['result'];
}
