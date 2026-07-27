import 'dart:io';

import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:test/test.dart';
import 'package:wallet_data/wallet_data.dart';

void main() {
  test('schemaVersion is 4 and all tables are created', () async {
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

    expect(db.schemaVersion, 4);
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

  test('v1 → v4 migration keeps data and adds replacement metadata', () async {
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
    // v4 backfill: an un-attributed row lands on its chain's mainnet id.
    expect(legacy.networkId, 'eth-mainnet');

    final version = (await db.customSelect('PRAGMA user_version').getSingle())
        .data
        .values
        .first;
    expect(version, 4);
  });

  test('v3 → v4 adds network_id and backfills per chain', () async {
    final dir = await Directory.systemTemp.createTemp('wallet_data_v3');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/v3.sqlite');

    // Exact v3 transactions schema: everything except network_id.
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
          broadcast_at INTEGER,
          nonce TEXT,
          max_priority_fee_raw TEXT,
          max_fee_raw TEXT,
          gas_limit_raw TEXT,
          replaces_id TEXT,
          replaced_by_id TEXT,
          replacement_kind INTEGER
        );
      ''')
      ..execute('''
        CREATE TABLE contacts (
          id TEXT NOT NULL PRIMARY KEY,
          name TEXT NOT NULL,
          address TEXT NOT NULL,
          chain TEXT NOT NULL,
          created_at INTEGER NOT NULL
        );
      ''')
      ..execute('''
        CREATE TABLE custom_tokens (
          id TEXT NOT NULL PRIMARY KEY,
          symbol TEXT NOT NULL,
          name TEXT NOT NULL,
          contract TEXT,
          network TEXT NOT NULL,
          enabled INTEGER NOT NULL DEFAULT 1,
          sort_order INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL
        );
      ''')
      ..execute(
        "INSERT INTO wallets VALUES ('A', 'v3', 0, 1, 0, 1, NULL, NULL, 7)",
      );
    for (final (id, coin, ts) in [
      ('evm', 'eth', 30),
      ('trx', 'tron', 20),
      ('unknown', 'dogecoin', 10),
    ]) {
      raw.execute(
        "INSERT INTO transactions (id, wallet_id, coin, direction, from_addr, "
        "to_addr, amount_raw, status, sign_mode, created_at, nonce) "
        "VALUES ('$id', 'A', '$coin', 1, '0xfrom', '0xto', '100', 8, 0, $ts, '7')",
      );
    }
    raw
      ..execute('PRAGMA user_version = 3')
      ..dispose();

    final db = WalletDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final repo = WalletsRepository(db).scoped('A');

    final rows = {for (final t in await repo.transactions()) t.id: t};
    expect(rows, hasLength(3));
    // Every v3 row survives with its payload intact...
    expect(rows['evm']!.amountRaw, '100');
    expect(rows['evm']!.nonce, '7');
    // ...and gains the chain's mainnet id.
    expect(rows['evm']!.networkId, 'eth-mainnet');
    expect(rows['trx']!.networkId, 'tron-mainnet');
    // An unrecognized coin stays unattributed rather than being guessed.
    expect(rows['unknown']!.networkId, isNull);

    // A filtered read sees only the requested network, and the unattributed
    // row is excluded from every network-scoped list.
    expect(
      (await repo.transactions(networkIds: {'eth-mainnet'})).single.id,
      'evm',
    );

    final version = (await db.customSelect('PRAGMA user_version').getSingle())
        .data
        .values
        .first;
    expect(version, 4);
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
