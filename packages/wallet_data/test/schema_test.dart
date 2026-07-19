import 'package:drift/native.dart';
import 'package:test/test.dart';
import 'package:wallet_data/wallet_data.dart';

void main() {
  test('schemaVersion is 1 and all tables are created', () async {
    final db = WalletDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // Forces onCreate; then query sqlite master for the table set.
    await db.customSelect('SELECT 1').get();
    final tables = (await db
            .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
            .get())
        .map((r) => r.data['name'] as String)
        .toSet();

    expect(db.schemaVersion, 1);
    for (final expected in [
      'wallets',
      'accounts',
      'tokens',
      'balances',
      'transactions',
      'address_book',
      'sign_requests',
      'settings',
      'wallet_settings',
    ]) {
      expect(tables, contains(expected), reason: 'missing table $expected');
    }
  });

  test('concurrent transactions on separate wallets do not corrupt', () async {
    final db = WalletDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = WalletsRepository(db);
    await repo.insert(WalletsCompanion.insert(
      id: 'A', name: 'A', type: WalletType.hot, avatarColor: 1, createdAt: 0,
    ));
    await repo.insert(WalletsCompanion.insert(
      id: 'B', name: 'B', type: WalletType.hot, avatarColor: 1, createdAt: 0,
    ));

    TransactionsCompanion tx(String id, String w) =>
        TransactionsCompanion.insert(
          id: id,
          walletId: w,
          coin: 'eth',
          direction: TxDirection.outgoing,
          fromAddr: 'f',
          toAddr: 't',
          amountRaw: '1',
          status: TxStatus.confirmed,
          signMode: SignMode.local,
          createdAt: 0,
        );

    // Fire many inserts across both wallets concurrently.
    await Future.wait([
      for (var i = 0; i < 50; i++) repo.scoped('A').upsertTransaction(tx('a$i', 'A')),
      for (var i = 0; i < 50; i++) repo.scoped('B').upsertTransaction(tx('b$i', 'B')),
    ]);

    expect(await repo.scoped('A').transactions(), hasLength(50));
    expect(await repo.scoped('B').transactions(), hasLength(50));
  });

  test('deleteWallet is the authoritative cascade (drift emits no FK here)',
      () async {
    // drift does not emit REFERENCES clauses for these tables in this config,
    // so DB-level FK cascade does NOT fire — WalletsRepository.deleteWallet's
    // manual, transactional child deletion is load-bearing. This test pins that
    // contract so a regression in deleteWallet can't silently orphan rows.
    final db = WalletDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = WalletsRepository(db);
    await repo.insert(WalletsCompanion.insert(
      id: 'A', name: 'A', type: WalletType.hot, avatarColor: 1, createdAt: 0,
    ));
    await repo.scoped('A').upsertTransaction(TransactionsCompanion.insert(
          id: 't1',
          walletId: 'A',
          coin: 'eth',
          direction: TxDirection.outgoing,
          fromAddr: 'f',
          toAddr: 't',
          amountRaw: '1',
          status: TxStatus.confirmed,
          signMode: SignMode.local,
          createdAt: 0,
        ));
    await repo.deleteWallet('A');
    expect(await repo.scoped('A').transactions(), isEmpty);
  });

  test('transactions come back newest-first', () async {
    final db = WalletDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = WalletsRepository(db);
    await repo.insert(WalletsCompanion.insert(
      id: 'A', name: 'A', type: WalletType.hot, avatarColor: 1, createdAt: 0,
    ));
    final a = repo.scoped('A');
    for (final (id, ts) in [('old', 100), ('new', 300), ('mid', 200)]) {
      await a.upsertTransaction(TransactionsCompanion.insert(
        id: id,
        walletId: 'A',
        coin: 'eth',
        direction: TxDirection.outgoing,
        fromAddr: 'f',
        toAddr: 't',
        amountRaw: '1',
        status: TxStatus.confirmed,
        signMode: SignMode.local,
        createdAt: ts,
      ));
    }
    final ordered = (await a.transactions()).map((t) => t.id).toList();
    expect(ordered, ['new', 'mid', 'old']);
  });
}
