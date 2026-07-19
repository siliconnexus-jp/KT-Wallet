import 'transport.dart';

/// TRON TronGrid REST client (detailed-design.md §4.3). Broadcast is NOT
/// retried automatically (double-spend safety) — that policy is enforced by
/// the caller; this client just posts once.
class TronRpc {
  TronRpc({required this.baseUrl, required this.transport});
  final String baseUrl;
  final RestTransport transport;

  /// TRX balance in SUN.
  Future<BigInt> getTrxBalance(String address) async {
    final resp = await transport.getJson('$baseUrl/v1/accounts/$address');
    if (resp is! Map) throw RpcException('bad account response');
    final data = resp['data'];
    if (data is! List || data.isEmpty) return BigInt.zero; // unactivated account
    final account = data.first;
    if (account is! Map) throw RpcException('bad account entry');
    final balance = account['balance'];
    // Absent balance = 0 (valid for a fresh account); a present-but-non-int
    // value is a malformed response, not a zero balance.
    if (balance == null) return BigInt.zero;
    if (balance is! int) throw RpcException('non-integer balance');
    return BigInt.from(balance);
  }

  /// Latest block ref (refBlockBytes/refBlockHash) for transaction expiration.
  Future<TronBlockRef> getNowBlock() async {
    final resp = await transport.postJson('$baseUrl/wallet/getnowblock', {});
    if (resp is! Map) throw RpcException('bad block');
    final header = resp['block_header'];
    final raw = header is Map ? header['raw_data'] : null;
    if (raw is! Map) throw RpcException('bad block header');
    final number = raw['number'];
    final txTrieRoot = raw['txTrieRoot'];
    if (number is! int || txTrieRoot is! String) {
      throw RpcException('missing block fields');
    }
    return TronBlockRef(number: number, txTrieRoot: txTrieRoot);
  }

  /// Broadcasts a signed transaction (hex). Returns the txid on success.
  Future<String> broadcast(Object signedTx) async {
    final resp = await transport.postJson('$baseUrl/wallet/broadcasttransaction', signedTx);
    if (resp is! Map) throw RpcException('bad broadcast response');
    if (resp['result'] == true && resp['txid'] is String) {
      return resp['txid'] as String;
    }
    final message = resp['message'];
    throw RpcException('broadcast rejected: ${message ?? resp['code']}');
  }
}

class TronBlockRef {
  const TronBlockRef({required this.number, required this.txTrieRoot});
  final int number;
  final String txTrieRoot;
}
