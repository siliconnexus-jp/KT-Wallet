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

void main() {
  group('TransactionConfirmationService', () {
    test('EVM remains pending before a receipt exists', () async {
      final json = _JsonRpc({'eth_getTransactionReceipt': null});
      final service = TransactionConfirmationService(
        endpoints: _endpoint,
        jsonRpcTransport: json,
        restTransport: _Rest(),
      );

      final result = await service.check(Chain.ethereum, '0xhash');
      expect(result.status, TxStatus.pending);
      expect(result.confirmations, 0);
      expect(json.method, 'eth_getTransactionReceipt');
    });

    test('EVM calculates live block confirmation depth', () async {
      final json = _JsonRpc({
        'eth_getTransactionReceipt': {'status': '0x1', 'blockNumber': '0x64'},
        'eth_blockNumber': '0x66',
      });
      final service = TransactionConfirmationService(
        endpoints: _endpoint,
        jsonRpcTransport: json,
        restTransport: _Rest(),
      );

      final confirmed = await service.check(Chain.ethereum, '0xhash');
      expect(confirmed.status, TxStatus.confirmed);
      expect(confirmed.confirmations, 3);

      json.results['eth_getTransactionReceipt'] = {
        'status': '0x0',
        'blockNumber': '0x64',
      };
      json.results['eth_blockNumber'] = '0x67';
      final failed = await service.check(Chain.ethereum, '0xhash');
      expect(failed.status, TxStatus.failed);
      expect(failed.confirmations, 4);
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

      final pending = await service.check(Chain.tron, 'hash');
      expect(pending.status, TxStatus.pending);
      expect(pending.confirmations, 0);
      rest.responses['/wallet/gettransactioninfobyid'] = {
        'blockNumber': 100,
        'receipt': {'result': 'SUCCESS'},
      };
      rest.responses['/wallet/getnowblock'] = {
        'blockID': List<String>.filled(32, '00').join(),
        'block_header': {
          'raw_data': {'number': 102},
        },
      };
      final confirmed = await service.check(Chain.tron, 'hash');
      expect(confirmed.status, TxStatus.confirmed);
      expect(confirmed.confirmations, 3);
    });

    test('Solana status maps pending, confirmed, and failed', () async {
      final json = _JsonRpc({
        'getSignatureStatuses': {
          'value': [null],
        },
      });
      final service = TransactionConfirmationService(
        endpoints: _endpoint,
        jsonRpcTransport: json,
        restTransport: _Rest(),
      );

      final pending = await service.check(Chain.solana, 'sig');
      expect(pending.status, TxStatus.pending);
      expect(pending.confirmations, 0);
      json.results['getSignatureStatuses'] = {
        'value': [
          {'err': null, 'confirmations': 7, 'confirmationStatus': 'confirmed'},
        ],
      };
      final confirmed = await service.check(Chain.solana, 'sig');
      expect(confirmed.status, TxStatus.confirmed);
      expect(confirmed.confirmations, 7);
      json.results['getSignatureStatuses'] = {
        'value': [
          {
            'err': {'InstructionError': 1},
            'confirmations': 8,
            'confirmationStatus': 'confirmed',
          },
        ],
      };
      final failed = await service.check(Chain.solana, 'sig');
      expect(failed.status, TxStatus.failed);
      expect(failed.confirmations, 8);
      expect(json.method, 'getSignatureStatuses');
    });
  });
}
