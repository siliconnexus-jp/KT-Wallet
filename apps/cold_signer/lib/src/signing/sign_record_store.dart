import 'package:airgap_protocol/airgap_protocol.dart';

/// Persistent record of every request the device has seen, keyed by reqId, so
/// the same request cannot be signed twice across app restarts
/// (detailed-design.md §5.1 sign_records, §13.5). Holds ONLY non-sensitive
/// fields — never keys, mnemonics or seed.
class SignatureRecord {
  const SignatureRecord({
    required this.reqId,
    required this.date,
    required this.coin,
    required this.operation,
    required this.toAddress,
    required this.amount,
    required this.status,
    this.txHash,
    this.walletId,
  });

  final String reqId;
  final int date; // epoch seconds
  final String coin;
  final String operation;
  final String toAddress;
  final String amount;
  final RequestStatus status;

  /// Chain tx hash for signed requests; null for rejected/expired ones.
  final String? txHash;

  /// The wallet the request addressed (audit trail; null in older callers).
  final String? walletId;
}

/// Backing persistence contract (the drift sign_records table in the app,
/// see data/signer_database.dart). Kept as an interface so the anti-replay
/// logic is testable without a database.
abstract class SignRecordPersistence {
  /// Atomically consumes a request before native signing starts.
  ///
  /// Returns false when [record.reqId] already exists. Implementations must
  /// never overwrite an existing row: this is the final anti-replay boundary,
  /// not a best-effort scan-time cache.
  Future<bool> reserve(SignatureRecord record);

  /// Replaces this process' [RequestStatus.scanned] reservation with the final
  /// signed outcome. Returns false if the reservation is absent, belongs to a
  /// different wallet, or is no longer in the reserved state.
  Future<bool> finalizeReservation(SignatureRecord record);

  Future<SignatureRecord?> get(String reqIdHex);
  Future<List<SignatureRecord>> all();

  /// Erases every record (C21 delete-wallet wipe).
  Future<void> clear();
}

/// In-memory persistence for tests.
class InMemorySignRecordPersistence implements SignRecordPersistence {
  final Map<String, SignatureRecord> _rows = {};

  @override
  Future<bool> reserve(SignatureRecord record) async {
    if (record.status != RequestStatus.scanned) {
      throw ArgumentError.value(
        record.status,
        'record.status',
        'reservation must use RequestStatus.scanned',
      );
    }
    if (_rows.containsKey(record.reqId)) return false;
    // There is no await between the check and write. On a Dart isolate this is
    // one atomic turn, so concurrent callers cannot both reserve the reqId.
    _rows[record.reqId] = record;
    return true;
  }

  @override
  Future<bool> finalizeReservation(SignatureRecord record) async {
    if (record.status != RequestStatus.signed) {
      throw ArgumentError.value(
        record.status,
        'record.status',
        'final outcome must use RequestStatus.signed',
      );
    }
    final reserved = _rows[record.reqId];
    if (reserved == null ||
        reserved.status != RequestStatus.scanned ||
        reserved.walletId != record.walletId) {
      return false;
    }
    _rows[record.reqId] = record;
    return true;
  }

  @override
  Future<SignatureRecord?> get(String reqIdHex) async => _rows[reqIdHex];

  @override
  Future<List<SignatureRecord>> all() async => _rows.values.toList();

  @override
  Future<void> clear() async => _rows.clear();
}

/// Adapts [SignRecordPersistence] to the synchronous [SignRecordStore] the
/// validator needs, by caching the loaded status set. Load once per scan
/// session before validating.
///
/// This is intentionally only an early, point-in-time UX check. The final
/// signing boundary must still call [SignRecordPersistence.reserve] because
/// authentication can outlive the scan session and callbacks can race.
class CachedSignRecordStore implements SignRecordStore {
  CachedSignRecordStore(this._cache);
  final Map<String, RequestStatus> _cache;

  static Future<CachedSignRecordStore> load(SignRecordPersistence p) async {
    final rows = await p.all();
    return CachedSignRecordStore({for (final r in rows) r.reqId: r.status});
  }

  @override
  RequestStatus? statusFor(String reqIdHex) => _cache[reqIdHex];
}
