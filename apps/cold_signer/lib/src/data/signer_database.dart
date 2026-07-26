import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:drift/drift.dart';

import '../signing/sign_record_store.dart';

part 'signer_database.g.dart';

/// Anti-replay ledger (detailed-design.md §5.1 sign_records, §13.5): one row
/// per reqId this device has ever accepted, rejected or signed. Non-sensitive
/// fields only — never keys, mnemonics or seed material.
class SignRecords extends Table {
  /// The request id, hex-encoded (primary key — one outcome per request,
  /// forever).
  TextColumn get reqId => text()();
  TextColumn get walletId => text()();
  TextColumn get coin => text()();
  TextColumn get operation => text()();
  TextColumn get toAddress => text()();
  TextColumn get amount => text()();

  /// When the outcome was recorded (epoch seconds).
  IntColumn get signedAt => integer()();

  /// Chain tx hash for signed requests; null for rejected/expired ones.
  TextColumn get txHash => text().nullable()();

  /// [RequestStatus].name.
  TextColumn get status => text()();

  @override
  Set<Column<Object>> get primaryKey => {reqId};
}

@DriftDatabase(tables: [SignRecords])
class SignerDatabase extends _$SignerDatabase {
  SignerDatabase(super.e);

  /// v1: initial schema (sign_records only).
  @override
  int get schemaVersion => 1;
}

/// Drift-backed [SignRecordPersistence]: the durable store behind the C6 scan
/// validator's anti-replay check. The validator itself consumes the
/// synchronous [SignRecordStore] via [CachedSignRecordStore.load] over this.
class DriftSignRecordPersistence implements SignRecordPersistence {
  DriftSignRecordPersistence(this._db);

  final SignerDatabase _db;

  @override
  Future<void> put(SignatureRecord record) => _db.into(_db.signRecords).insertOnConflictUpdate(SignRecordsCompanion.insert(reqId: record.reqId, walletId: record.walletId ?? '', coin: record.coin, operation: record.operation, toAddress: record.toAddress, amount: record.amount, signedAt: record.date, txHash: Value(record.txHash), status: record.status.name));

  @override
  Future<SignatureRecord?> get(String reqIdHex) async {
    final row = await (_db.select(_db.signRecords)..where((t) => t.reqId.equals(reqIdHex))).getSingleOrNull();
    return row == null ? null : _toRecord(row);
  }

  @override
  Future<List<SignatureRecord>> all() async => [for (final row in await _db.select(_db.signRecords).get()) _toRecord(row)];

  @override
  Future<void> clear() => _db.delete(_db.signRecords).go();

  static SignatureRecord _toRecord(SignRecord row) => SignatureRecord(reqId: row.reqId, walletId: row.walletId, date: row.signedAt, coin: row.coin, operation: row.operation, toAddress: row.toAddress, amount: row.amount, txHash: row.txHash, status: RequestStatus.values.byName(row.status));
}
