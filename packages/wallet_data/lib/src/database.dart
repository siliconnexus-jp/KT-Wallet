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
  ],
)
class WalletDatabase extends _$WalletDatabase {
  WalletDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
