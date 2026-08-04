// Read-only funding readiness gate for the real eight-chain E2E matrix.
//
// This tool accepts public addresses only. It never reads the local E2E
// mnemonic, native key storage, PIN, signed payloads or transaction history.
//
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'e2e_funding_preflight_model.dart';

const _defaultGateway = 'https://gateway.kt-wallet.com';

Future<void> main(List<String> arguments) async {
  try {
    final options = _Options.parse(arguments);
    if (options.help) {
      print(_usage);
      return;
    }
    final addresses = E2eFundingAddresses(
      evm: options.required('evm'),
      tron: options.required('tron'),
      solana: options.required('solana'),
    );
    final gatewayUrl = options.value('gateway') ?? _defaultGateway;
    final gatewayUri = _safeGateway(gatewayUrl);
    final batchId = options.value('batch-id');
    if (batchId != null &&
        !RegExp(r'^[A-Za-z0-9_.-]{1,80}$').hasMatch(batchId)) {
      throw const FormatException('invalid batch id');
    }
    final client = http.Client();
    try {
      const requestId = 1;
      late final FundingPortfolio portfolio;
      try {
        final decoded = await _postBounded(
          client,
          gatewayUri.replace(path: '${gatewayUri.path}/rpc'),
          jsonEncode({
            'jsonrpc': '2.0',
            'id': requestId,
            'method': 'kt_getPortfolio',
            'params': {
              'accounts': [
                for (final requirement in e2eFundingRequirements)
                  requirement.accountQuery(addresses.forCoin(requirement.coin)),
              ],
            },
          }),
        );
        portfolio = parseGatewayFundingResponse(
          decoded,
          expectedId: requestId,
          expectedAddresses: addresses,
        );
      } on FormatException {
        throw const _GatewayUnavailable();
      }
      final report = evaluateE2eFunding(
        addresses: addresses,
        portfolio: portfolio,
      );
      final encoded = const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 1,
        'checkedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'batchId': ?batchId,
        'gatewayHost': gatewayUri.host,
        'addresses': addresses.toJson(),
        ...report.toJson(),
      });
      final output = options.value('output');
      if (output == null) {
        print(encoded);
      } else {
        _writeNewReport(output, '$encoded\n');
        print('Funding report written: $output');
      }
      exitCode = switch (report.readiness) {
        FundingReadiness.ready => 0,
        FundingReadiness.insufficient => 2,
        FundingReadiness.unavailable => 3,
      };
    } finally {
      client.close();
    }
  } on _GatewayUnavailable {
    stderr.writeln(
      'Funding preflight unavailable (invalid Gateway response). No signing '
      'or broadcast was attempted.',
    );
    exitCode = 3;
  } on FormatException catch (error) {
    stderr.writeln('Funding preflight configuration error: ${error.message}');
    stderr.writeln(_usage);
    exitCode = 64;
  } on Object catch (error) {
    // Gateway exceptions can contain provider text. Keep the CLI error closed
    // and bounded; the JSON report is not produced when the query is not
    // authoritative.
    stderr.writeln(
      'Funding preflight unavailable (${error.runtimeType}). No signing or '
      'broadcast was attempted.',
    );
    exitCode = 3;
  }
}

class _GatewayUnavailable implements Exception {
  const _GatewayUnavailable();
}

Future<Object?> _postBounded(
  http.Client client,
  Uri endpoint,
  String body,
) async {
  const maximumBytes = 1024 * 1024;
  final request = http.Request('POST', endpoint)
    ..headers['content-type'] = 'application/json'
    ..body = body;
  final response = await client
      .send(request)
      .timeout(const Duration(seconds: 30));
  if (response.statusCode != 200) {
    throw const FormatException('Gateway returned a non-success status');
  }
  final declared = response.contentLength;
  if (declared != null && declared > maximumBytes) {
    throw const FormatException('Gateway response exceeds size limit');
  }
  final bytes = <int>[];
  await for (final chunk in response.stream.timeout(
    const Duration(seconds: 30),
  )) {
    if (bytes.length + chunk.length > maximumBytes) {
      throw const FormatException('Gateway response exceeds size limit');
    }
    bytes.addAll(chunk);
  }
  try {
    return decodeGatewayFundingJson(utf8.decode(bytes, allowMalformed: false));
  } on Object {
    throw const FormatException('Gateway returned invalid JSON');
  }
}

Uri _safeGateway(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null ||
      !uri.hasAuthority ||
      uri.userInfo.isNotEmpty ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty) {
    throw const FormatException('invalid Gateway URL');
  }
  final loopback =
      uri.host == '127.0.0.1' || uri.host == 'localhost' || uri.host == '::1';
  if (uri.scheme != 'https' && !(uri.scheme == 'http' && loopback)) {
    throw const FormatException('Gateway must use HTTPS or loopback HTTP');
  }
  return uri.replace(path: uri.path.replaceAll(RegExp(r'/+$'), ''));
}

void _writeNewReport(String path, String contents) {
  final type = FileSystemEntity.typeSync(path, followLinks: false);
  if (type != FileSystemEntityType.notFound) {
    throw const FormatException('output already exists');
  }
  final parent = File(path).parent;
  if (!parent.existsSync()) {
    throw const FormatException('output directory does not exist');
  }
  File(path).writeAsStringSync(contents, flush: true);
}

class _Options {
  _Options(this._values, this.help);

  factory _Options.parse(List<String> arguments) {
    final values = <String, String>{};
    var help = false;
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (argument == '--help' || argument == '-h') {
        help = true;
        continue;
      }
      if (!argument.startsWith('--')) {
        throw FormatException('unexpected argument: $argument');
      }
      final key = argument.substring(2);
      if (!const {
        'evm',
        'tron',
        'solana',
        'gateway',
        'batch-id',
        'output',
      }.contains(key)) {
        throw FormatException('unknown option: --$key');
      }
      if (values.containsKey(key) || index + 1 >= arguments.length) {
        throw FormatException('missing or duplicate value: --$key');
      }
      final value = arguments[++index];
      if (value.startsWith('--') || value.isEmpty) {
        throw FormatException('missing value: --$key');
      }
      values[key] = value;
    }
    return _Options(values, help);
  }

  final Map<String, String> _values;
  final bool help;

  String? value(String key) => _values[key];

  String required(String key) {
    final result = value(key);
    if (result == null) throw FormatException('missing option: --$key');
    return result;
  }
}

const _usage = '''
Usage:
  dart run tool/e2e_funding_preflight.dart \\
    --evm <public-address> \\
    --tron <public-address> \\
    --solana <public-address> \\
    [--batch-id <public-batch-id>] \\
    [--output <new-json-file>]

Exit codes: 0 ready, 2 insufficient, 3 unavailable, 64 invalid input.
The tool is read-only and never accepts a mnemonic, private key or PIN.
''';
