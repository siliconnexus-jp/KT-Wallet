import 'package:chains/chains.dart' show Chain;
import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/transfer/transaction_confirmation_service.dart';
import 'package:wallet_data/wallet_data.dart' show TxStatus;

class _JsonRpc implements JsonRpcTransport {
  _JsonRpc([Map<String, Object?>? results]) {
    if (results != null) this.results.addAll(results);
  }

  final results = <String, Object?>{};
  String? method;

  @override
  Future<Object?> post(String url, Object body) async {
    method = (body as Map)['method'] as String;
    return {'jsonrpc': '2.0', 'id': body['id'], 'result': results[method]};
  }
}

class _Rest implements RestTransport {
  _Rest([Map<String, Object?>? responses]) {
    if (responses != null) this.responses.addAll(responses);
  }

  final responses = <String, Object?>{};
  String? url;

  @override
  Future<Object?> getJson(String url) => throw UnimplementedError();

  @override
  Future<Object?> postJson(String url, Object body) async {
    this.url = url;
    for (final entry in responses.entries) {
      if (url.endsWith(entry.key)) return entry.value;
    }
    return null;
  }
}

String _endpoint(Coin coin) => 'https://rpc.example/${coin.name}';

const _evmHash =
    '0x1111111111111111111111111111111111111111111111111111111111111111';
const _otherEvmHash =
    '0x2222222222222222222222222222222222222222222222222222222222222222';
const _tronHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _otherTronHash =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _solanaSignature =
    '4cdd1oX7cfVALfr26tP52BZ6cSzrgnNGtYD7BFhm6FFeZV5sPTnRvg6NRn8yC6DbEikXcrNChBM5vVJnTgKhGhVu';

Map<String, Object?> _evmReceipt({
  String transactionHash = _evmHash,
  Object? status = '0x1',
}) => {
  'transactionHash': transactionHash,
  'blockHash':
      '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'blockNumber': '0x64',
  'transactionIndex': '0x0',
  'status': status,
};

void main() {
  group('TransactionConfirmationService', () {
    test('EVM remains pending before a receipt exists', () async {
      final json = _JsonRpc({'eth_getTransactionReceipt': null});
      final service = TransactionConfirmationService(
        endpoints: _endpoint,
        jsonRpcTransport: json,
        restTransport: _Rest(),
      );

      final result = await service.check(Chain.ethereum, _evmHash);
      expect(result.status, TxStatus.pending);
      expect(result.confirmations, 0);
      expect(json.method, 'eth_getTransactionReceipt');
    });

    test('EVM calculates live block confirmation depth', () async {
      final json = _JsonRpc({
        'eth_getTransactionReceipt': _evmReceipt(),
        'eth_blockNumber': '0x66',
      });
      final service = TransactionConfirmationService(
        endpoints: _endpoint,
        jsonRpcTransport: json,
        restTransport: _Rest(),
      );

      final confirmed = await service.check(Chain.ethereum, _evmHash);
      expect(confirmed.status, TxStatus.confirmed);
      expect(confirmed.confirmations, 3);

      json.results['eth_getTransactionReceipt'] = _evmReceipt(status: '0x0');
      json.results['eth_blockNumber'] = '0x67';
      final failed = await service.check(Chain.ethereum, _evmHash);
      expect(failed.status, TxStatus.failed);
      expect(failed.confirmations, 4);
    });

    test(
      'EVM preserves terminal receipt when depth enrichment fails',
      () async {
        final json = _JsonRpc({
          'eth_getTransactionReceipt': _evmReceipt(),
          'eth_blockNumber': 'not-a-canonical-quantity',
        });
        final service = TransactionConfirmationService(
          endpoints: _endpoint,
          jsonRpcTransport: json,
          restTransport: _Rest(),
        );

        final confirmed = await service.check(Chain.ethereum, _evmHash);
        expect(confirmed.status, TxStatus.confirmed);
        expect(confirmed.confirmations, isNull);

        json.results['eth_getTransactionReceipt'] = _evmReceipt(status: '0x0');
        final failed = await service.check(Chain.ethereum, _evmHash);
        expect(failed.status, TxStatus.failed);
        expect(failed.confirmations, isNull);
      },
    );

    test('EVM rejects mismatched or incomplete receipt evidence', () async {
      final json = _JsonRpc({
        'eth_getTransactionReceipt': _evmReceipt(
          transactionHash: _otherEvmHash,
        ),
        'eth_blockNumber': '0x66',
      });
      final service = TransactionConfirmationService(
        endpoints: _endpoint,
        jsonRpcTransport: json,
        restTransport: _Rest(),
      );

      await expectLater(
        service.check(Chain.ethereum, _evmHash),
        throwsA(isA<RpcException>()),
      );

      json.results['eth_getTransactionReceipt'] = {
        'transactionHash': _evmHash,
        'blockNumber': '0x64',
        'status': '0x1',
      };
      await expectLater(
        service.check(Chain.ethereum, _evmHash),
        throwsA(isA<RpcException>()),
      );
    });

    test('TRON calculates live block confirmation depth', () async {
      final rest = _Rest({
        '/wallet/gettransactioninfobyid': <Object?, Object?>{},
      });
      final service = TransactionConfirmationService(
        endpoints: _endpoint,
        jsonRpcTransport: _JsonRpc(),
        restTransport: rest,
      );

      final pending = await service.check(Chain.tron, _tronHash);
      expect(pending.status, TxStatus.pending);
      expect(pending.confirmations, 0);
      rest.responses['/wallet/gettransactioninfobyid'] = {
        'id': _tronHash,
        'blockNumber': 100,
        'receipt': {'result': 'SUCCESS'},
      };
      rest.responses['/wallet/getnowblock'] = {
        'blockID': List<String>.filled(32, '00').join(),
        'block_header': {
          'raw_data': {'number': 102, 'timestamp': 1780000000000},
        },
      };
      final confirmed = await service.check(Chain.tron, _tronHash);
      expect(confirmed.status, TxStatus.confirmed);
      expect(confirmed.confirmations, 3);

      rest.responses['/wallet/gettransactioninfobyid'] = {
        'id': _tronHash,
        'blockNumber': 101,
        'receipt': <String, Object?>{},
      };
      rest.responses['/wallet/gettransactionbyid'] = {
        'txID': _tronHash,
        'ret': [
          {'contractRet': 'SUCCESS'},
        ],
      };
      final nativeConfirmed = await service.check(Chain.tron, _tronHash);
      expect(nativeConfirmed.status, TxStatus.confirmed);
      expect(nativeConfirmed.confirmations, 2);
    });

    test(
      'TRON preserves terminal receipt when depth enrichment fails',
      () async {
        final rest = _Rest({
          '/wallet/gettransactioninfobyid': {
            'id': _tronHash,
            'blockNumber': 100,
            'receipt': {'result': 'SUCCESS'},
          },
          '/wallet/getnowblock': <String, Object?>{},
        });
        final service = TransactionConfirmationService(
          endpoints: _endpoint,
          jsonRpcTransport: _JsonRpc(),
          restTransport: rest,
        );

        final confirmed = await service.check(Chain.tron, _tronHash);
        expect(confirmed.status, TxStatus.confirmed);
        expect(confirmed.confirmations, isNull);

        rest.responses['/wallet/gettransactioninfobyid'] = {
          'id': _tronHash,
          'blockNumber': 100,
          'receipt': {'result': 'FAILED'},
        };
        final failed = await service.check(Chain.tron, _tronHash);
        expect(failed.status, TxStatus.failed);
        expect(failed.confirmations, isNull);
      },
    );

    test('TRON rejects mismatched or incomplete receipt evidence', () async {
      final rest = _Rest({
        '/wallet/gettransactioninfobyid': {
          'id': _otherTronHash,
          'blockNumber': 100,
          'receipt': {'result': 'SUCCESS'},
        },
        '/wallet/getnowblock': {
          'blockID': List<String>.filled(32, '00').join(),
          'block_header': {
            'raw_data': {'number': 102, 'timestamp': 1780000000000},
          },
        },
      });
      final service = TransactionConfirmationService(
        endpoints: _endpoint,
        jsonRpcTransport: _JsonRpc(),
        restTransport: rest,
      );

      await expectLater(
        service.check(Chain.tron, _tronHash),
        throwsA(isA<RpcException>()),
      );
      rest.responses['/wallet/gettransactioninfobyid'] = {
        'id': _tronHash,
        'blockNumber': 100,
        'receipt': <String, Object?>{},
      };
      rest.responses['/wallet/gettransactionbyid'] = {
        'txID': _otherTronHash,
        'ret': [
          {'contractRet': 'SUCCESS'},
        ],
      };
      await expectLater(
        service.check(Chain.tron, _tronHash),
        throwsA(isA<RpcException>()),
      );
    });

    test('Solana status maps pending, confirmed, and failed', () async {
      final json = _JsonRpc({
        'getSignatureStatuses': {
          'context': {'slot': 100},
          'value': [null],
        },
      });
      final service = TransactionConfirmationService(
        endpoints: _endpoint,
        jsonRpcTransport: json,
        restTransport: _Rest(),
      );

      final pending = await service.check(Chain.solana, _solanaSignature);
      expect(pending.status, TxStatus.pending);
      expect(pending.confirmations, 0);
      json.results['getSignatureStatuses'] = {
        'context': {'slot': 100},
        'value': [
          {
            'slot': 99,
            'err': null,
            'status': {'Ok': null},
            'confirmations': 7,
            'confirmationStatus': 'confirmed',
          },
        ],
      };
      final confirmed = await service.check(Chain.solana, _solanaSignature);
      expect(confirmed.status, TxStatus.confirmed);
      expect(confirmed.confirmations, 7);
      json.results['getSignatureStatuses'] = {
        'context': {'slot': 100},
        'value': [
          {
            'slot': 98,
            'err': {'InstructionError': 1},
            'status': {
              'Err': {'InstructionError': 1},
            },
            'confirmations': 8,
            'confirmationStatus': 'confirmed',
          },
        ],
      };
      final failed = await service.check(Chain.solana, _solanaSignature);
      expect(failed.status, TxStatus.failed);
      expect(failed.confirmations, 8);
      expect(json.method, 'getSignatureStatuses');
    });

    test('Solana confirmation rejects incomplete evidence', () async {
      final json = _JsonRpc({
        'getSignatureStatuses': {
          'value': [
            {
              'err': null,
              'confirmations': 7,
              'confirmationStatus': 'confirmed',
            },
          ],
        },
      });
      final service = TransactionConfirmationService(
        endpoints: _endpoint,
        jsonRpcTransport: json,
        restTransport: _Rest(),
      );

      await expectLater(
        service.check(Chain.solana, _solanaSignature),
        throwsA(isA<RpcException>()),
      );
    });
  });
}
