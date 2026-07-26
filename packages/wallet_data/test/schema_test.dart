import 'dart:io';

import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:test/test.dart';
import 'package:wallet_data/wallet_data.dart';

void main() {
  test('schemaVersion is 3 and all tables are created', () async {
    final db = WalletDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // Forces onCreate; then query sqlite master for the table set.
    await db.customSelect('SELECT 1').get();
    final tables =
        (await db
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type='table'",
                )
                .get())
            .map((r) => r.data['name'] as String)
            .toSet();

    expect(db.schemaVersion, 3);
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
      'contacts',
      'custom_tokens',
    ]) {
      expect(tables, contains(expected), reason: 'missing table $expected');
    }
  });

  test('v1 → v3 migration keeps data and adds replacement metadata', () async {
    // Build the two v1 tables touched by later migrations. The old
    // transactions schema deliberately has none of the EVM replacement
    // columns introduced in v3.
    final dir = await Directory.systemTemp.createTemp('wallet_data_migration');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/v1.sqlite');

    final raw = sqlite3.sqlite3.open(file.path);
    raw
      ..execute('''
        CREATE TABLE wallets (
          id TEXT NOT NULL PRIMARY KEY,
          name TEXT NOT NULL,
          type INTEGER NOT NULL,
          avatar_color INTEGER NOT NULL,
          sort_order INTEGER NOT NULL DEFAULT 0,
          backed_up INTEGER NOT NULL DEFAULT 0,
          cold_wallet_id TEXT,
          protocol_ver INTEGER,
          created_at INTEGER NOT NULL
        );
      ''')
      ..execute('''
        CREATE TABLE transactions (
          id TEXT NOT NULL PRIMARY KEY,
          wallet_id TEXT NOT NULL,
          req_id TEXT,
          coin TEXT NOT NULL,
          contract TEXT,
          direction INTEGER NOT NULL,
          from_addr TEXT NOT NULL,
          to_addr TEXT NOT NULL,
          amount_raw TEXT NOT NULL,
          fee_raw TEXT,
          hash TEXT,
          status INTEGER NOT NULL,
          sign_mode INTEGER NOT NULL,
          memo TEXT,
          created_at INTEGER NOT NULL,
          broadcast_at INTEGER
        );
      ''')
      ..execute(
        "INSERT INTO wallets VALUES ('A', 'legacy', 0, 1, 0, 1, NULL, NULL, 7)",
      )
      ..execute('''
        INSERT INTO transactions VALUES (
          'legacy-tx', 'A', NULL, 'eth', NULL, 1,
          '0xfrom', '0xto', '100', '2', '0xhash',
          4, 0, NULL, 8, 9
        )
      ''')
      ..execute('PRAGMA user_version = 1')
      ..dispose();

    final db = WalletDatabase(NativeDatabase(file));
    addTearDown(db.close);

    // v1 row survives the upgrade.
    final wallet = await WalletsRepository(db).byId('A');
    expect(wallet, isNotNull);
    expect(wallet!.name, 'legacy');

    // The v2 tables exist and are usable.
    final contactsRepo = ContactsRepository(db);
    await contactsRepo.insert(
      ContactsCompanion.insert(
        id: 'c1',
        name: 'Alice',
        address: '0xalice',
        chain: 'ethereum',
        createdAt: 1,
      ),
    );
    expect((await contactsRepo.list()).single.name, 'Alice');

    final tokensRepo = TokensRepository(db);
    await tokensRepo.insert(
      CustomTokensCompanion.insert(
        id: 't1',
        symbol: 'USDT',
        name: 'Tether USD',
        network: 'TRON · TRC-20',
        createdAt: 1,
      ),
    );
    expect((await tokensRepo.list()).single.symbol, 'USDT');

    // The v1 transaction survives and all v3 fields are safely null.
    final legacy = (await WalletsRepository(
      db,
    ).scoped('A').transactions()).single;
    expect(legacy.id, 'legacy-tx');
    expect(legacy.nonce, isNull);
    expect(legacy.maxPriorityFeeRaw, isNull);
    expect(legacy.maxFeeRaw, isNull);
    expect(legacy.gasLimitRaw, isNull);
    expect(legacy.replacesId, isNull);
    expect(legacy.replacedById, isNull);
    expect(legacy.replacementKind, isNull);

    final version = (await db.customSelect('PRAGMA user_version').getSingle())
        .data
        .values
        .first;
    expect(version, 3);
  });

  test('concurrent transactions on separate wallets do not corrupt', () async {
    final db = WalletDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = WalletsRepository(db);
    await repo.insert(
      WalletsCompanion.insert(
        id: 'A',
        name: 'A',
        type: WalletType.hot,
        avatarColor: 1,
        createdAt: 0,
      ),
    );
    await repo.insert(
      WalletsCompanion.insert(
        id: 'B',
        name: 'B',
        type: WalletType.hot,
        avatarColor: 1,
        createdAt: 0,
      ),
    );

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
      for (var i = 0; i < 50; i++)
        repo.scoped('A').upsertTransaction(tx('a$i', 'A')),
      for (var i = 0; i < 50; i++)
        repo.scoped('B').upsertTransaction(tx('b$i', 'B')),
    ]);

    expect(await repo.scoped('A').transactions(), hasLength(50));
    expect(await repo.scoped('B').transactions(), hasLength(50));
  });

  test(
    'deleteWallet is the authoritative cascade (drift emits no FK here)',
    () async {
      // drift does not emit REFERENCES clauses for these tables in this config,
      // so DB-level FK cascade does NOT fire — WalletsRepository.deleteWallet's
      // manual, transactional child deletion is load-bearing. This test pins that
      // contract so a regression in deleteWallet can't silently orphan rows.
      final db = WalletDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = WalletsRepository(db);
      await repo.insert(
        WalletsCompanion.insert(
          id: 'A',
          name: 'A',
          type: WalletType.hot,
          avatarColor: 1,
          createdAt: 0,
        ),
      );
      await repo
          .scoped('A')
          .upsertTransaction(
            TransactionsCompanion.insert(
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
            ),
          );
      await repo.deleteWallet('A');
      expect(await repo.scoped('A').transactions(), isEmpty);
    },
  );

  test('transactions come back newest-first', () async {
    final db = WalletDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = WalletsRepository(db);
    await repo.insert(
      WalletsCompanion.insert(
        id: 'A',
        name: 'A',
        type: WalletType.hot,
        avatarColor: 1,
        createdAt: 0,
      ),
    );
    final a = repo.scoped('A');
    for (final (id, ts) in [('old', 100), ('new', 300), ('mid', 200)]) {
      await a.upsertTransaction(
        TransactionsCompanion.insert(
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
        ),
      );
    }
    final ordered = (await a.transactions()).map((t) => t.id).toList();
    expect(ordered, ['new', 'mid', 'old']);
  });
}
