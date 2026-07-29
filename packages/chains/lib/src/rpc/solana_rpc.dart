import 'dart:convert';
import 'dart:typed_data';

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

  /// Sum of all SPL token accounts owned by [owner] for [mint].
  Future<BigInt> getTokenBalance(String owner, String mint) async {
    final accounts = await getTokenAccounts(owner, mint);
    var total = BigInt.zero;
    for (final account in accounts) {
      total += account.amount;
    }
    return total;
  }

  /// Parsed SPL token accounts owned by [owner] for [mint].
  Future<List<SolanaTokenAccount>> getTokenAccounts(
    String owner,
    String mint,
  ) async {
    final result = await _call('getTokenAccountsByOwner', [
      owner,
      {'mint': mint},
      {'encoding': 'jsonParsed', 'commitment': 'confirmed'},
    ]);
    final value = result is Map ? result['value'] : null;
    if (value is! List) throw RpcException('bad token account response');
    final accounts = <SolanaTokenAccount>[];
    for (final entry in value) {
      final pubkey = entry is Map ? entry['pubkey'] : null;
      final account = entry is Map ? entry['account'] : null;
      final data = account is Map ? account['data'] : null;
      final parsed = data is Map ? data['parsed'] : null;
      final info = parsed is Map ? parsed['info'] : null;
      final tokenAmount = info is Map ? info['tokenAmount'] : null;
      final amount = tokenAmount is Map ? tokenAmount['amount'] : null;
      if (pubkey is! String || amount is! String) {
        throw RpcException('bad token account');
      }
      accounts.add(
        SolanaTokenAccount(address: pubkey, amount: BigInt.parse(amount)),
      );
    }
    return List.unmodifiable(accounts);
  }

  /// Latest blockhash (needed to build a transaction; short-lived).
  Future<String> getLatestBlockhash() async {
    final result = await _call('getLatestBlockhash', [
      {'commitment': 'finalized'},
    ]);
    final value = result is Map ? result['value'] : null;
    if (value is! Map || value['blockhash'] is! String) {
      throw RpcException('bad blockhash');
    }
    return value['blockhash'] as String;
  }

  /// Fee in lamports for the exact serialized message.
  Future<BigInt> getFeeForMessage(Uint8List message) async {
    final result = await _call('getFeeForMessage', [
      base64Encode(message),
      {'commitment': 'confirmed'},
    ]);
    final value = result is Map ? result['value'] : null;
    if (value is! int) throw RpcException('fee unavailable for message');
    return BigInt.from(value);
  }

  /// Simulates the exact single-signer legacy transaction with a zeroed
  /// signature. Signature verification is disabled, but every instruction,
  /// account, balance and recent blockhash is checked by the node.
  Future<void> simulateMessage(Uint8List message) async {
    final transaction = Uint8List.fromList([
      1,
      ...List<int>.filled(64, 0),
      ...message,
    ]);
    final result = await _call('simulateTransaction', [
      base64Encode(transaction),
      {
        'encoding': 'base64',
        'sigVerify': false,
        'replaceRecentBlockhash': false,
        'commitment': 'processed',
      },
    ]);
    final value = result is Map ? result['value'] : null;
    if (value is! Map) throw RpcException('bad simulation response');
    if (value['err'] != null) {
      throw RpcException('simulation failed: ${value['err']}');
    }
  }

  Future<String> sendTransaction(String base64Tx) async {
    final result = await _call('sendTransaction', [
      base64Tx,
      {'encoding': 'base64'},
    ]);
    if (result is! String) throw RpcException('no signature returned');
    return result;
  }

  /// Confirmation status for a signature, or null if unknown.
  Future<String?> signatureStatus(String signature) async {
    return (await signatureResult(signature))?.confirmationStatus;
  }

  /// Full confirmation result for a signature. [failed] is sourced from the
  /// RPC's `err` field, so callers never mistake an included failed
  /// transaction for a successful confirmation.
  Future<SolanaSignatureStatus?> signatureResult(String signature) async {
    final result = await _call('getSignatureStatuses', [
      [signature],
      {'searchTransactionHistory': true},
    ]);
    final value = result is Map ? result['value'] : null;
    if (value is! List || value.isEmpty) return null;
    final entry = value.first;
    if (entry is! Map) return null;
    final status = entry['confirmationStatus'];
    if (status == null) return null;
    if (status is! String) throw RpcException('bad confirmationStatus');
    return SolanaSignatureStatus(
      confirmationStatus: status,
      failed: entry['err'] != null,
    );
  }
}

class SolanaSignatureStatus {
  const SolanaSignatureStatus({
    required this.confirmationStatus,
    required this.failed,
  });

  final String confirmationStatus;
  final bool failed;
}

class SolanaTokenAccount {
  const SolanaTokenAccount({required this.address, required this.amount});
  final String address;
  final BigInt amount;
}
