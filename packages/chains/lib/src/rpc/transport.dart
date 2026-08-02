/// Transport abstraction so `chains` never depends on an HTTP library directly
/// — that keeps the offline signer's dependency tree network-free even though
/// it links `chains` for transaction parsing (tech-plan.md §4). The online app
/// injects a concrete http-backed implementation.
abstract class JsonRpcTransport {
  /// POSTs a JSON body to [url] and returns the decoded JSON response.
  Future<Object?> post(String url, Object body);
}

/// REST GET/POST transport (TronGrid).
abstract class RestTransport {
  Future<Object?> getJson(String url);
  Future<Object?> postJson(String url, Object body);
}

class RpcException implements Exception {
  RpcException(this.message, {this.code});
  final String message;
  final int? code;
  @override
  String toString() => 'RpcException($code): $message';
}

/// A bounded reason code for a node-level transaction rejection.
///
/// Provider error strings are untrusted and may contain URLs, credentials or
/// control text. Online UI code must localize this enum instead of displaying
/// [RpcException.message].
enum RpcRejectionKind {
  insufficientFunds,
  nonceTooLow,
  nonceTooHigh,
  replacementFeeTooLow,
  feeTooLow,
  gasLimitTooLow,
  blockGasLimitExceeded,
  feeCapBelowBaseFee,
  alreadyKnown,
  executionReverted,
  invalidSender,
  expiredReference,
  accountInUse,
  simulationFailed,
  invalidSignature,
  rejected,
}

/// A syntactically valid node response that explicitly rejected an RPC call.
///
/// This is deliberately distinct from transport timeouts, HTTP failures and
/// malformed responses. Broadcast callers may mark this transaction as
/// rejected; every other failure after a write began is outcome-unknown.
class RpcRejectedException extends RpcException {
  RpcRejectedException(String message, {int? code})
    : kind = publicRpcRejectionKind(message),
      super(publicRpcRejectionMessage(message), code: code);

  final RpcRejectionKind kind;
}

/// Converts an untrusted node rejection into a bounded, actionable vocabulary.
/// RPC servers can return arbitrary strings; keeping those strings in an
/// exception lets a provider inject URLs/control text into wallet UI and logs.
String publicRpcRejectionMessage(Object? message) {
  if (message is RpcRejectionKind) return _rpcRejectionMessage(message);
  return _rpcRejectionMessage(publicRpcRejectionKind(message));
}

String _rpcRejectionMessage(RpcRejectionKind kind) {
  return switch (kind) {
    RpcRejectionKind.insufficientFunds => 'insufficient funds for transaction',
    RpcRejectionKind.nonceTooLow => 'transaction nonce is too low',
    RpcRejectionKind.nonceTooHigh => 'transaction nonce is too high',
    RpcRejectionKind.replacementFeeTooLow =>
      'replacement transaction fee is too low',
    RpcRejectionKind.feeTooLow => 'transaction fee is too low',
    RpcRejectionKind.gasLimitTooLow => 'transaction gas limit is too low',
    RpcRejectionKind.blockGasLimitExceeded =>
      'transaction exceeds the block gas limit',
    RpcRejectionKind.feeCapBelowBaseFee =>
      'transaction fee cap is below the network base fee',
    RpcRejectionKind.alreadyKnown =>
      'transaction is already known by the network',
    RpcRejectionKind.executionReverted => 'transaction execution reverted',
    RpcRejectionKind.invalidSender => 'transaction sender is invalid',
    RpcRejectionKind.expiredReference =>
      'transaction block reference is no longer valid',
    RpcRejectionKind.accountInUse => 'transaction account is currently in use',
    RpcRejectionKind.simulationFailed => 'transaction simulation failed',
    RpcRejectionKind.invalidSignature => 'transaction signature is invalid',
    RpcRejectionKind.rejected => 'transaction rejected by network',
  };
}

/// Classifies untrusted provider text without retaining it.
RpcRejectionKind publicRpcRejectionKind(Object? message) {
  if (message is RpcRejectionKind) return message;
  final lower = '$message'.toLowerCase();
  const known = <(String, RpcRejectionKind)>[
    ('insufficient funds', RpcRejectionKind.insufficientFunds),
    ('nonce too low', RpcRejectionKind.nonceTooLow),
    ('nonce too high', RpcRejectionKind.nonceTooHigh),
    (
      'replacement transaction underpriced',
      RpcRejectionKind.replacementFeeTooLow,
    ),
    ('transaction underpriced', RpcRejectionKind.feeTooLow),
    ('intrinsic gas too low', RpcRejectionKind.gasLimitTooLow),
    ('exceeds block gas limit', RpcRejectionKind.blockGasLimitExceeded),
    ('fee cap less than block base fee', RpcRejectionKind.feeCapBelowBaseFee),
    ('already known', RpcRejectionKind.alreadyKnown),
    ('execution reverted', RpcRejectionKind.executionReverted),
    ('invalid sender', RpcRejectionKind.invalidSender),
    ('blockhash not found', RpcRejectionKind.expiredReference),
    ('blockhash expired', RpcRejectionKind.expiredReference),
    ('tapos', RpcRejectionKind.expiredReference),
    ('account in use', RpcRejectionKind.accountInUse),
    ('transaction simulation failed', RpcRejectionKind.simulationFailed),
    ('signature verification failed', RpcRejectionKind.invalidSignature),
    ('validate signature', RpcRejectionKind.invalidSignature),
    ('signature error', RpcRejectionKind.invalidSignature),
    ('bad sig', RpcRejectionKind.invalidSignature),
  ];
  // The mapper sits at more than one defense boundary (RPC parser and final
  // UI outcome), so it must be idempotent for its own public vocabulary.
  for (final (_, kind) in known) {
    if (lower == _rpcRejectionMessage(kind)) return kind;
  }
  if (lower == 'transaction rejected by network') {
    return RpcRejectionKind.rejected;
  }
  for (final (needle, kind) in known) {
    if (lower.contains(needle)) return kind;
  }
  return RpcRejectionKind.rejected;
}
