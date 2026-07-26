import 'package:airgap_protocol/airgap_protocol.dart';

/// Persistent record of every request the device has seen, keyed by reqId, so
/// the same request cannot be signed twice across app restarts
/// (detailed-design.md §5.1 sign_records, §13.5). Holds ONLY non-sensitive
/// fields — never keys, mnemonics or seed.
class SignatureRecord {
  const SignatureRecord({required this.reqId, required this.date, required this.coin, required this.operation, required this.toAddress, required this.amount, required this.status, this.txHash, this.walletId});

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
  Future<void> put(SignatureRecord record);
  Future<SignatureRecord?> get(String reqIdHex);
  Future<List<SignatureRecord>> all();

  /// Erases every record (C21 delete-wallet wipe).
  Future<void> clear();
}

/// In-memory persistence for tests.
class InMemorySignRecordPersistence implements SignRecordPersistence {
  final Map<String, SignatureRecord> _rows = {};

  @override
  Future<void> put(SignatureRecord record) async => _rows[record.reqId] = record;

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
/// This is a point-in-time snapshot. The Cold Signer is single-user and does
/// NOT run concurrent scan sessions, so a reqId recorded elsewhere cannot
/// appear mid-session; if that assumption ever changes, reload before each
/// validate or query the store directly (TOCTOU).
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
