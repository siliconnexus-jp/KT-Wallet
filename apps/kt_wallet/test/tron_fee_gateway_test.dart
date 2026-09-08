import 'dart:convert';

import 'package:chains/chains.dart';
import 'package:chains/rpc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kt_wallet/src/market/gateway_client.dart';
import 'package:kt_wallet/src/rpc/tron_fee_transport.dart';
import 'package:kt_wallet/src/transfer/fee_quote_failure.dart';
import 'package:kt_wallet/src/transfer/local_transfer_service.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';

const owner = 'TNXoiAJ3dct8Fjg4M9fkLFh9S2v9TXc32G';
const recipient = 'TJRabPrwbZy45sbavfcjinPJC18kjpRTv8';
const usdtContract = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';

class _Direct extends RestTransport {
  int calls = 0;
  @override
  Future<Object?> getJson(String url) async {
    calls++;
    return {'data': <Object?>[]};
  }

  @override
  Future<Object?> postJson(String url, Object body) async {
    calls++;
    return {};
  }
}

Map<String, Object?> feeData(Map<String, dynamic> p) =>
    switch (p['operation']) {
      'account' => {
        'data': [
          {'balance': 1000000000},
        ],
        'success': true,
      },
      'block' => {
        'blockID': '00' * 32,
        'block_header': {
          'raw_data': {'number': 101, 'timestamp': 1000000},
        },
      },
      'resources' => {'freeNetLimit': 10000},
      'parameters' => {
        'chainParameter': [
          {'key': 'getEnergyFee', 'value': 100},
          {'key': 'getTransactionFee', 'value': 1000},
        ],
      },
      'constant' when p['selector'] == 'transfer(address,uint256)' => {
        'result': {'result': true},
        'energy_used': 130000,
      },
      'constant' => {
        'result': {'result': true},
        'constant_result': [
          BigInt.from(100000000).toRadixString(16).padLeft(64, '0'),
        ],
        'transaction': {
          'visible': true,
          'raw_data': {
            'contract': [
              {
                'type': 'TriggerSmartContract',
                'parameter': {
                  'type_url':
                      'type.googleapis.com/protocol.TriggerSmartContract',
                  'value': {
                    'owner_address': p['address'],
                    'contract_address': p['contract'],
                    'data': '70a08231${p['parameter']}',
                  },
                },
              },
            ],
          },
        },
      },
      _ => throw StateError('unexpected operation'),
    };

GatewayClient gateway({
  int? error,
  String network = 'tron-mainnet',
  bool mismatch = false,
  List<String>? operations,
  Map<String, Object?> Function(Map<String, dynamic>)? dataOverride,
}) => GatewayClient(
  baseUrl: 'https://gateway.invalid',
  networks: (_) => network,
  advertisedNetworks: {'tron-mainnet', 'tron-nile'},
  client: MockClient((request) async {
    expect(request.url.toString(), 'https://gateway.invalid/rpc');
    expect(request.headers.containsKey('TRON-PRO-API-KEY'), isFalse);
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body['method'], 'kt_getTronFeeData');
    final p = body['params'] as Map<String, dynamic>;
    operations?.add(p['operation'] as String);
    return http.Response(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': body['id'],
        if (error != null)
          'error': {'code': error, 'message': 'untrusted provider text'}
        else
          'result': {
            ...p,
            if (mismatch) 'network': 'tron-nile',
            'data': dataOverride?.call(p) ?? feeData(p),
          },
      }),
      200,
    );
  }),
);

void main() {
  for (final contract in [null, usdtContract]) {
    test(
      'complete ${contract == null ? 'TRX' : 'USDT'} quote uses gateway without direct RPC',
      () async {
        final direct = _Direct();
        final operations = <String>[];
        final gw = gateway(operations: operations);
        final service = LocalTransferService(
          gateway: () => gw,
          restTransport: direct,
        );
        final prepared = await service.prepareTron(
          draft: TransferDraft(
            symbol: contract == null ? 'TRX' : 'USDT',
            networkLabel: 'TRON',
            chain: Chain.tron,
            recipient: recipient,
            amount: Amount.parse('1', 6),
            feeTier: 1,
            tokenContract: contract,
          ),
          from: owner,
          expectedNetworkIdentity: null,
        );
        expect(
          prepared.maximumFeeSun,
          BigInt.from(contract == null ? 0 : 15600000),
        );
        expect(prepared.referenceBlockHeight, 101);
        expect(direct.calls, 0);
        expect(operations.where((op) => op == 'resources').length, 1);
        expect(operations.where((op) => op == 'parameters').length, 1);
      },
    );
  }
  for (final scenario in [
    (0, 500000, false),
    (130000, 500000, false),
    (130000, 3500000, true),
    (200000, 500000, true),
  ]) {
    final (available, balance, succeeds) = scenario;
    test(
      'rented energy $available / balance $balance: budget and liquid fee are independent',
      () async {
        final direct = _Direct();
        final gw = gateway(
          dataOverride: (p) {
            if (p['operation'] == 'resources') {
              return {'EnergyLimit': available};
            }
            if (p['operation'] == 'account') {
              return {
                'data': [
                  {'balance': balance},
                ],
                'success': true,
              };
            }
            return feeData(p);
          },
        );
        final service = LocalTransferService(
          gateway: () => gw,
          restTransport: direct,
        );
        final quote = service.prepareTron(
          draft: TransferDraft(
            symbol: 'USDT',
            networkLabel: 'TRON',
            chain: Chain.tron,
            recipient: recipient,
            amount: Amount.parse('1', 6),
            feeTier: 1,
            tokenContract: usdtContract,
          ),
          from: owner,
          expectedNetworkIdentity: null,
        );
        if (!succeeds) {
          // Real energy shortfall plus Bandwidth must still have liquid backing.
          await expectLater(quote, throwsA(isA<TransferInsufficientFunds>()));
        } else {
          final prepared = await quote;
          final decoded = parseUnsignedTransfer(Chain.tron, prepared.rawTx);
          expect(decoded.maxFeeRaw, BigInt.from(15600000));
          expect(decoded.amountRaw, BigInt.from(1000000));
          expect(prepared.maximumFeeSun, greaterThan(BigInt.from(15600000)));
          expect(prepared.estimatedFeeSun, greaterThan(BigInt.zero));
          expect(
            prepared.estimatedFeeSun,
            lessThanOrEqualTo(BigInt.from(balance)),
          );
          expect(direct.calls, 0);
        }
      },
    );
  }

  test('old gateway and custom network retain direct mode', () async {
    for (final gw in [
      gateway(error: -32601),
      gateway(network: 'custom-tron'),
    ]) {
      final direct = _Direct();
      final transport = TronFeeTransport(
        baseUrl: 'https://node.invalid',
        gateway: gw,
        direct: direct,
      );
      await transport.getJson('https://node.invalid/v1/accounts/$owner');
      await transport.postJson(
        'https://node.invalid/wallet/getchainparameters',
        {},
      );
      expect(direct.calls, 2);
    }
  });
  test(
    'rate limit and unbound results fail closed without anonymous fallback',
    () async {
      for (final gw in [gateway(error: -32001), gateway(mismatch: true)]) {
        final direct = _Direct();
        final transport = TronFeeTransport(
          baseUrl: 'https://node.invalid',
          gateway: gw,
          direct: direct,
        );
        await expectLater(
          transport.getJson('https://node.invalid/v1/accounts/$owner'),
          throwsException,
        );
        expect(direct.calls, 0);
      }
    },
  );
  test('fee adapter cannot broadcast', () {
    final transport = TronFeeTransport(
      baseUrl: 'https://node.invalid',
      gateway: gateway(),
      direct: _Direct(),
    );
    expect(
      () => transport.postJson(
        'https://node.invalid/wallet/broadcasttransaction',
        {},
      ),
      throwsArgumentError,
    );
  });
  test('failure categories do not render arbitrary provider messages', () {
    expect(
      classifyFeeQuoteFailure(GatewayException(code: -32001)),
      FeeQuoteFailure.rateLimited,
    );
    expect(
      classifyFeeQuoteFailure(RpcException('secret', code: 429)),
      FeeQuoteFailure.rateLimited,
    );
    expect(
      classifyFeeQuoteFailure(const GatewayTransportException()),
      FeeQuoteFailure.network,
    );
    expect(
      classifyFeeQuoteFailure(RpcException('secret')),
      FeeQuoteFailure.unavailable,
    );
  });
}
