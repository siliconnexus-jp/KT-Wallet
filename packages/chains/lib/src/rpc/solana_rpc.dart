import 'transport.dart';

/// Solana JSON-RPC client (detailed-design.md §4.3).
class SolanaRpc {
  SolanaRpc({required this.url, required this.transport});
  final String url;
  final JsonRpcTransport transport;

  int _id = 0;

  Future<Object?> _call(String method, List<Object?> params) async {
    final resp = await transport.post(url, {
      'jsonrpc': '2.0',
      'id': ++_id,
      'method': method,
      'params': params,
    });
    if (resp is! Map) throw RpcException('malformed response');
    if (resp['error'] != null) {
      final err = resp['error'];
      throw RpcException(err is Map ? '${err['message']}' : '$err');
    }
    return resp['result'];
  }

  /// Lamport balance.
  Future<BigInt> getBalance(String address) async {
    final result = await _call('getBalance', [address]);
    if (result is! Map || result['value'] is! int) {
      throw RpcException('bad getBalance');
    }
    return BigInt.from(result['value'] as int);
  }

  /// Latest blockhash (needed to build a transaction; short-lived).
  Future<String> getLatestBlockhash() async {
    final result = await _call('getLatestBlockhash', [
      {'commitment': 'finalized'}
    ]);
    final value = result is Map ? result['value'] : null;
    if (value is! Map || value['blockhash'] is! String) {
      throw RpcException('bad blockhash');
    }
    return value['blockhash'] as String;
  }

  Future<String> sendTransaction(String base64Tx) async {
    final result = await _call('sendTransaction', [
      base64Tx,
      {'encoding': 'base64'}
    ]);
    if (result is! String) throw RpcException('no signature returned');
    return result;
  }

  /// Confirmation status for a signature, or null if unknown.
  Future<String?> signatureStatus(String signature) async {
    final result = await _call('getSignatureStatuses', [
      [signature]
    ]);
    final value = result is Map ? result['value'] : null;
    if (value is! List || value.isEmpty) return null;
    final entry = value.first;
    if (entry is! Map) return null;
    final status = entry['confirmationStatus'];
    if (status == null) return null;
    if (status is! String) throw RpcException('bad confirmationStatus');
    return status;
  }
}
