import 'dart:convert';

import 'package:http/http.dart' as http;

/// 1 SOL — the fixed amount the receive screen's one-tap faucet requests.
const lamportsPerSol = 1000000000;

/// Airdrop failure with a user-showable reason (the node's JSON-RPC error
/// message when there is one — e.g. devnet's rate-limit message — otherwise
/// the transport failure).
class AirdropException implements Exception {
  const AirdropException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Real Solana devnet/testnet faucet: JSON-RPC `requestAirdrop` against the
/// ACTIVE network's own RPC endpoint (devnet's faucet *is* the RPC call — no
/// external site involved). The client is injectable so widget tests assert
/// the exact request; production constructs its own and [close]s it.
class AirdropService {
  AirdropService(
      {http.Client? client, this.timeout = const Duration(seconds: 10)})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;

  /// Closes the internally-created client; a no-op for injected clients.
  void close() {
    if (_ownsClient) _client.close();
  }

  /// Requests [lamports] (default 1 SOL) for [address] via [rpcUrl] and
  /// returns the airdrop transaction signature. Throws [AirdropException]
  /// with the node's message on any failure.
  Future<String> requestAirdrop({
    required String rpcUrl,
    required String address,
    int lamports = lamportsPerSol,
  }) async {
    final http.Response resp;
    try {
      resp = await _client
          .post(
            Uri.parse(rpcUrl.trim()),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'method': 'requestAirdrop',
              'params': [address, lamports],
            }),
          )
          .timeout(timeout);
    } catch (e) {
      throw AirdropException('$e');
    }
    if (resp.statusCode != 200) {
      throw AirdropException('HTTP ${resp.statusCode}');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(resp.body);
    } on FormatException {
      throw const AirdropException('malformed response');
    }
    if (decoded is! Map) throw const AirdropException('malformed response');
    final error = decoded['error'];
    if (error is Map) {
      throw AirdropException(error['message']?.toString() ?? 'RPC error');
    }
    final result = decoded['result'];
    if (result is! String) throw const AirdropException('malformed response');
    return result;
  }
}
