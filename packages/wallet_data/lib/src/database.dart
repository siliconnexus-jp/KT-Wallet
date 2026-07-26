import 'package:drift/drift.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Wallets,
    Accounts,
    Tokens,
    Balances,
    Transactions,
    AddressBook,
    SignRequests,
    Settings,
    WalletSettings,
    Contacts,
    CustomTokens,
  ],
)
class WalletDatabase extends _$WalletDatabase {
  WalletDatabase(super.e);

  /// v1: initial schema.
  /// v2: global `contacts` (address book) + `custom_tokens` tables.
  /// v3: EVM nonce/fee metadata and transaction-replacement lineage.
  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(contacts);
        await m.createTable(customTokens);
      }
      if (from < 3) {
        await m.addColumn(transactions, transactions.nonce);
        await m.addColumn(transactions, transactions.maxPriorityFeeRaw);
        await m.addColumn(transactions, transactions.maxFeeRaw);
        await m.addColumn(transactions, transactions.gasLimitRaw);
        await m.addColumn(transactions, transactions.replacesId);
        await m.addColumn(transactions, transactions.replacedById);
        await m.addColumn(transactions, transactions.replacementKind);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
