import 'dart:convert';

import 'package:http/http.dart' as http;

import '../rpc/bounded_http_client.dart';

/// 1 SOL — the fixed amount the receive screen's one-tap faucet requests.
const lamportsPerSol = 1000000000;

/// Stable, localizable faucet failure categories. Provider text and transport
/// exceptions are deliberately discarded because they may contain a custom
/// RPC credential URL or attacker-controlled content.
enum AirdropFailureKind {
  rateLimited,
  unavailable,
  invalidRequest,
  insufficientFunds,
  rejected,
  malformedResponse,
}

class AirdropException implements Exception {
  const AirdropException(this.kind);
  final AirdropFailureKind kind;

  @override
  String toString() => 'AirdropException(${kind.name})';
}

AirdropFailureKind _classifyRpcFailure(Object? code, Object? message) {
  final normalized = message?.toString().toLowerCase() ?? '';
  if (code == 429 ||
      normalized.contains('rate limit') ||
      normalized.contains('too many request') ||
      normalized.contains('airdrop limit')) {
    return AirdropFailureKind.rateLimited;
  }
  if (code == -32602 ||
      normalized.contains('invalid param') ||
      normalized.contains('invalid address')) {
    return AirdropFailureKind.invalidRequest;
  }
  if (normalized.contains('insufficient') ||
      normalized.contains('faucet empty') ||
      normalized.contains('faucet balance')) {
    return AirdropFailureKind.insufficientFunds;
  }
  if (normalized.contains('unavailable') ||
      normalized.contains('disabled') ||
      normalized.contains('maintenance') ||
      normalized.contains('temporarily')) {
    return AirdropFailureKind.unavailable;
  }
  return AirdropFailureKind.rejected;
}

/// Real Solana devnet/testnet faucet: JSON-RPC `requestAirdrop` against the
/// ACTIVE network's own RPC endpoint (devnet's faucet *is* the RPC call — no
/// external site involved). The client is injectable so widget tests assert
/// the exact request; production constructs its own and [close]s it.
class AirdropService {
  AirdropService({
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = BoundedHttpClient(client ?? http.Client()),
       _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;

  /// Closes the internally-created client; a no-op for injected clients.
  void close() {
    if (_ownsClient) _client.close();
  }

  /// Requests [lamports] (default 1 SOL) for [address] via [rpcUrl] and
  /// returns the airdrop transaction signature. Provider and transport error
  /// text never crosses this boundary.
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
    } catch (_) {
      throw const AirdropException(AirdropFailureKind.unavailable);
    }
    if (resp.statusCode != 200) {
      final kind = switch (resp.statusCode) {
        429 => AirdropFailureKind.rateLimited,
        400 || 404 || 422 => AirdropFailureKind.invalidRequest,
        >= 500 => AirdropFailureKind.unavailable,
        _ => AirdropFailureKind.rejected,
      };
      throw AirdropException(kind);
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(resp.body);
    } on FormatException {
      throw const AirdropException(AirdropFailureKind.malformedResponse);
    }
    if (decoded is! Map) {
      throw const AirdropException(AirdropFailureKind.malformedResponse);
    }
    final error = decoded['error'];
    if (error is Map) {
      throw AirdropException(
        _classifyRpcFailure(error['code'], error['message']),
      );
    }
    final result = decoded['result'];
    if (result is! String) {
      throw const AirdropException(AirdropFailureKind.malformedResponse);
    }
    return result;
  }
}
