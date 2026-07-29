import 'dart:convert';
import 'dart:io';

/// Live, read-only verification of every checked-in token deployment's
/// smallest-unit precision against its own chain.
///
/// Run from the repository root:
///   dart run tool/audit_token_decimals.dart
///
/// The app registry is separately locked to this gateway catalog by
/// `token_balance_service_test.dart`; the gateway's compiled defaults are
/// locked to it by `official_tokens_consistency_test.go`.
Future<void> main(List<String> arguments) async {
  final catalogPath = arguments.isEmpty
      ? 'backend/gateway/config/official-tokens.json'
      : arguments.single;
  final decoded = jsonDecode(await File(catalogPath).readAsString());
  if (decoded is! List) {
    stderr.writeln('Token catalog must be a JSON array.');
    exitCode = 2;
    return;
  }

  final failures = <String>[];
  var checked = 0;
  for (final raw in decoded) {
    if (raw is! Map) {
      failures.add('malformed catalog row: $raw');
      continue;
    }
    final network = raw['network'];
    final symbol = raw['symbol'];
    final contract = raw['contract'];
    final expected = raw['decimals'];
    if (network is! String ||
        symbol is! String ||
        contract is! String ||
        expected is! int) {
      failures.add('malformed catalog row: $raw');
      continue;
    }

    try {
      final actual = await _onChainDecimals(network, contract);
      checked++;
      if (actual != expected) {
        failures.add(
          '$network $symbol $contract: on-chain=$actual catalog=$expected',
        );
        stdout.writeln(
          'MISMATCH $network $symbol on-chain=$actual catalog=$expected',
        );
      } else {
        stdout.writeln('OK $network $symbol decimals=$actual');
      }
    } catch (error) {
      failures.add('$network $symbol $contract: $error');
      stdout.writeln('ERROR $network $symbol: $error');
    }
  }

  stdout.writeln(
    'Checked $checked/${decoded.length} deployments; '
    '${failures.length} failure(s).',
  );
  if (failures.isNotEmpty) {
    stderr.writeln(failures.join('\n'));
    exitCode = 1;
  }
}

const _endpoints = <String, String>{
  'eth-mainnet': 'https://ethereum-rpc.publicnode.com',
  'eth-sepolia': 'https://ethereum-sepolia-rpc.publicnode.com',
  'polygon-mainnet': 'https://polygon-bor-rpc.publicnode.com',
  'polygon-amoy': 'https://polygon-amoy-bor-rpc.publicnode.com',
  'base-mainnet': 'https://mainnet.base.org',
  'base-sepolia': 'https://sepolia.base.org',
  'arbitrum-mainnet': 'https://arb1.arbitrum.io/rpc',
  'arbitrum-sepolia': 'https://sepolia-rollup.arbitrum.io/rpc',
  'avalanche-mainnet': 'https://api.avax.network/ext/bc/C/rpc',
  'avalanche-fuji': 'https://api.avax-test.network/ext/bc/C/rpc',
  'bnb-mainnet': 'https://bsc-dataseed.bnbchain.org',
  'bnb-testnet': 'https://bsc-testnet-dataseed.bnbchain.org',
  'tron-mainnet': 'https://api.trongrid.io',
  'tron-nile': 'https://nile.trongrid.io',
  'sol-mainnet': 'https://api.mainnet-beta.solana.com',
  'sol-devnet': 'https://api.devnet.solana.com',
};

Future<int> _onChainDecimals(String network, String contract) {
  final endpoint = _endpoints[network];
  if (endpoint == null) {
    throw StateError('no endpoint for $network');
  }
  if (network.startsWith('tron-')) {
    return _tronDecimals(endpoint, contract);
  }
  if (network.startsWith('sol-')) {
    return _solanaDecimals(endpoint, contract);
  }
  return _evmDecimals(endpoint, contract);
}

Future<int> _evmDecimals(String endpoint, String contract) async {
  final body = await _postJson(endpoint, {
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'eth_call',
    'params': [
      {'to': contract, 'data': '0x313ce567'},
      'latest',
    ],
  });
  if (body is! Map || body['error'] != null || body['result'] is! String) {
    throw FormatException('bad eth_call response: $body');
  }
  final result = body['result'] as String;
  if (!result.startsWith('0x') || result.length <= 2) {
    throw FormatException('invalid decimals result: $result');
  }
  return BigInt.parse(result.substring(2), radix: 16).toInt();
}

Future<int> _tronDecimals(String endpoint, String contract) async {
  final body = await _postJson('$endpoint/wallet/triggerconstantcontract', {
    'owner_address': contract,
    'contract_address': contract,
    'function_selector': 'decimals()',
    'visible': true,
  });
  if (body is! Map || body['result'] is! Map) {
    throw FormatException('bad TRON response: $body');
  }
  final result = body['result'] as Map;
  final values = body['constant_result'];
  if (result['result'] != true ||
      values is! List ||
      values.isEmpty ||
      values.first is! String) {
    throw FormatException('TRON decimals call failed: $body');
  }
  return BigInt.parse(values.first as String, radix: 16).toInt();
}

Future<int> _solanaDecimals(String endpoint, String mint) async {
  final body = await _postJson(endpoint, {
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'getAccountInfo',
    'params': [
      mint,
      {'encoding': 'jsonParsed', 'commitment': 'finalized'},
    ],
  });
  if (body is! Map || body['error'] != null) {
    throw FormatException('bad Solana response: $body');
  }
  final result = body['result'];
  final value = result is Map ? result['value'] : null;
  final data = value is Map ? value['data'] : null;
  final parsed = data is Map ? data['parsed'] : null;
  final info = parsed is Map ? parsed['info'] : null;
  final decimals = info is Map ? info['decimals'] : null;
  if (decimals is! int) {
    throw FormatException('missing mint decimals: $body');
  }
  return decimals;
}

Future<Object?> _postJson(String url, Object request) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
  try {
    final httpRequest = await client
        .postUrl(Uri.parse(url))
        .timeout(const Duration(seconds: 15));
    httpRequest.headers.contentType = ContentType.json;
    httpRequest.write(jsonEncode(request));
    final response = await httpRequest.close().timeout(
      const Duration(seconds: 20),
    );
    final text = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}: $text');
    }
    return jsonDecode(text);
  } finally {
    client.close(force: true);
  }
}
