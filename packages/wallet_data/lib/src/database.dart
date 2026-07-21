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
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(contacts);
            await m.createTable(customTokens);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
