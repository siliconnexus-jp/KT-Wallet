import 'dart:typed_data';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:cold_signer/src/data/signer_database.dart';
import 'package:cold_signer/src/signing/sign_record_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The drift-backed anti-replay ledger. "Re-open" is modeled by handing the
/// SAME in-memory database instance to a brand-new store object — the drift
/// layer is what persists, the store objects are throwaway views.
void main() {
  const reqIdHex = '7f3a2c915ed408b6';

  SignatureRecord signedRecord() => const SignatureRecord(
    reqId: reqIdHex,
    walletId: 'WLT-A1B2C3D4',
    date: 1786000000,
    coin: 'slip44:195',
    operation: 'Token Transfer（TRC-20）',
    toAddress: 'TWd4qCEUYAJgLtSpQ2dK7wY9nMxR38uQz',
    amount: '120.00 USDT',
    txHash: '5c1f0e6a94d2b7c8130fa6e2d9b45871',
    status: RequestStatus.signed,
  );

  SignatureRecord reservedRecord() => const SignatureRecord(
    reqId: reqIdHex,
    walletId: 'WLT-A1B2C3D4',
    date: 1786000000,
    coin: 'slip44:195',
    operation: 'tokenTransfer',
    toAddress: 'TWd4qCEUYAJgLtSpQ2dK7wY9nMxR38uQz',
    amount: '120000000 base units',
    status: RequestStatus.scanned,
  );

  Future<void> signRecord(DriftSignRecordPersistence store) async {
    expect(await store.reserve(reservedRecord()), isTrue);
    expect(await store.finalizeReservation(signedRecord()), isTrue);
  }

  test('roundtrips a record through the sign_records table', () async {
    final db = SignerDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = DriftSignRecordPersistence(db);

    expect(await store.get(reqIdHex), isNull);
    await signRecord(store);

    final row = (await store.get(reqIdHex))!;
    expect(row.reqId, reqIdHex);
    expect(row.walletId, 'WLT-A1B2C3D4');
    expect(row.date, 1786000000);
    expect(row.coin, 'slip44:195');
    expect(row.operation, 'Token Transfer（TRC-20）');
    expect(row.toAddress, 'TWd4qCEUYAJgLtSpQ2dK7wY9nMxR38uQz');
    expect(row.amount, '120.00 USDT');
    expect(row.txHash, '5c1f0e6a94d2b7c8130fa6e2d9b45871');
    expect(row.status, RequestStatus.signed);
    expect(await store.all(), hasLength(1));
  });

  test('record → duplicate detected across a store re-open', () async {
    final db = SignerDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // Session 1 signs and records.
    await signRecord(DriftSignRecordPersistence(db));

    // Session 2: NEW store object over the same database — the validator's
    // acceptance check must now flag the same reqId as a duplicate.
    final reopened = DriftSignRecordPersistence(db);
    final cache = await CachedSignRecordStore.load(reopened);
    expect(cache.statusFor(reqIdHex), RequestStatus.signed);

    final verdict =
        SignRequestValidator(
          localWalletId: 'WLT-A1B2C3D4',
          records: cache,
          transactionAllowed: (_) => true,
          clock: () => DateTime.fromMillisecondsSinceEpoch(1786000000 * 1000),
        ).validate(
          SignRequest(
            reqId: Uint8List.fromList(const [
              0x7f,
              0x3a,
              0x2c,
              0x91,
              0x5e,
              0xd4,
              0x08,
              0xb6,
            ]),
            walletId: 'WLT-A1B2C3D4',
            coin: 195,
            rawTx: Uint8List.fromList(const [0xde, 0xad]),
            createdAt: 1786000000,
            expiresAt: 1786000600,
          ),
        );
    expect(verdict.code, ValidationCode.duplicate);
    expect(verdict.detail, 'signed');
  });

  test('a reserved request remains consumed across a store re-open', () async {
    final db = SignerDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    expect(
      await DriftSignRecordPersistence(db).reserve(reservedRecord()),
      isTrue,
    );

    final reopened = DriftSignRecordPersistence(db);
    final cache = await CachedSignRecordStore.load(reopened);
    expect(cache.statusFor(reqIdHex), RequestStatus.scanned);
    expect(await reopened.reserve(reservedRecord()), isFalse);
  });

  test('an existing reservation cannot be overwritten', () async {
    final db = SignerDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = DriftSignRecordPersistence(db);
    expect(await store.reserve(reservedRecord()), isTrue);
    expect(await store.reserve(reservedRecord()), isFalse);
    expect(await store.all(), hasLength(1));
    expect((await store.get(reqIdHex))!.status, RequestStatus.scanned);
  });

  test('concurrent reservations atomically admit exactly one signer', () async {
    final db = SignerDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = DriftSignRecordPersistence(db);

    final admitted = await Future.wait([
      for (var i = 0; i < 16; i++) store.reserve(reservedRecord()),
    ]);

    expect(admitted.where((value) => value), hasLength(1));
    expect(await store.all(), hasLength(1));
    expect((await store.get(reqIdHex))!.status, RequestStatus.scanned);
  });

  test('only the matching reservation can be finalized', () async {
    final db = SignerDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = DriftSignRecordPersistence(db);

    expect(await store.finalizeReservation(signedRecord()), isFalse);
    expect(await store.reserve(reservedRecord()), isTrue);
    expect(
      await store.finalizeReservation(
        SignatureRecord(
          reqId: reqIdHex,
          walletId: 'OTHER-WALLET',
          date: 1786000001,
          coin: 'slip44:195',
          operation: 'tokenTransfer',
          toAddress: 'TWd4qCEUYAJgLtSpQ2dK7wY9nMxR38uQz',
          amount: '120000000 base units',
          txHash: '0xother',
          status: RequestStatus.signed,
        ),
      ),
      isFalse,
    );
    expect(await store.finalizeReservation(signedRecord()), isTrue);
    expect((await store.get(reqIdHex))!.status, RequestStatus.signed);
    expect(await store.finalizeReservation(signedRecord()), isFalse);
  });

  test('clear empties the ledger (delete-wallet wipe)', () async {
    final db = SignerDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = DriftSignRecordPersistence(db);
    await signRecord(store);
    await store.clear();
    expect(await store.all(), isEmpty);
    expect(await store.get(reqIdHex), isNull);
  });
}
