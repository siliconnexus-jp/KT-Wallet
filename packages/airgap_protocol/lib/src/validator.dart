import 'payload.dart';

/// Outcome of a request already recorded on the offline device.
enum RequestStatus { scanned, signed, rejected, expired }

/// Persistence for reqId → status, so the same request cannot be signed twice
/// (detailed-design.md §3.4 step 4, §13.5). Implemented by the Cold Signer app
/// over its local DB; injected here for testability.
abstract class SignRecordStore {
  RequestStatus? statusFor(String reqIdHex);
}

/// A simple in-memory store for tests.
class InMemorySignRecordStore implements SignRecordStore {
  final Map<String, RequestStatus> _records = {};
  void put(String reqIdHex, RequestStatus status) =>
      _records[reqIdHex] = status;
  @override
  RequestStatus? statusFor(String reqIdHex) => _records[reqIdHex];
}

/// Whether the parsed transaction type is allowed to be signed in V1. The
/// `chains` package performs the real parse; the validator only needs the
/// boolean verdict (kept as a callback to avoid a chains dependency here, which
/// would violate the offline dependency firewall).
typedef TransactionAllowed = bool Function(SignRequest request);

enum ValidationCode {
  ok,
  badWallet,
  expired,
  clockSkew,
  duplicate,
  unsupportedTransaction,
}

class ValidationResult {
  const ValidationResult(this.code, [this.detail]);
  final ValidationCode code;
  final String? detail;
  bool get isOk => code == ValidationCode.ok;
}

/// Runs the six-step acceptance check for an incoming sign-request
/// (detailed-design.md §3.4). Version/type/schema were already enforced by
/// [AirgapPayload.decode]; this covers steps 2–6.
class SignRequestValidator {
  SignRequestValidator({
    required this.localWalletId,
    required this.records,
    required this.transactionAllowed,
    this.clockSkewSeconds = 600,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final String localWalletId;
  final SignRecordStore records;
  final TransactionAllowed transactionAllowed;
  final int clockSkewSeconds;
  final DateTime Function() _now;

  ValidationResult validate(SignRequest request) {
    // Step 2: wallet id matches this device.
    if (request.walletId != localWalletId) {
      return const ValidationResult(ValidationCode.badWallet);
    }
    // Step 3: not expired, createdAt within clock tolerance.
    final nowSec = _now().millisecondsSinceEpoch ~/ 1000;
    if (nowSec >= request.expiresAt) {
      return const ValidationResult(ValidationCode.expired);
    }
    if (request.createdAt - clockSkewSeconds > nowSec) {
      return const ValidationResult(ValidationCode.clockSkew);
    }
    // Step 4: reqId not already scanned/signed/rejected/expired. Read once —
    // a mutable/async store could change between two reads.
    final prior = records.statusFor(request.reqIdHex);
    if (prior != null) {
      return ValidationResult(ValidationCode.duplicate, prior.name);
    }
    // Steps 5 & 6: rawTx parses to an allowed transaction type. (The parse and
    // summary-mismatch highlighting are done by the caller via [chains];
    // display always uses the parse result, never the summary field.)
    if (!transactionAllowed(request)) {
      return const ValidationResult(ValidationCode.unsupportedTransaction);
    }
    return const ValidationResult(ValidationCode.ok);
  }
}
