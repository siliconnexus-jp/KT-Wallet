import 'package:drift/drift.dart';

import 'database.dart';

/// Manages the wallet list itself (the only cross-wallet surface allowed).
/// Everything else goes through a [WalletRepository] bound to one walletId, so
/// there is no API that can read another wallet's data (detailed-design.md
/// §5.1, §8.11).
class WalletsRepository {
  WalletsRepository(this._db);
  final WalletDatabase _db;

  Future<List<Wallet>> listAll() =>
      (_db.select(_db.wallets)..orderBy([(w) => OrderingTerm(expression: w.sortOrder)]))
          .get();

  Future<Wallet?> byId(String id) =>
      (_db.select(_db.wallets)..where((w) => w.id.equals(id))).getSingleOrNull();

  Future<void> insert(WalletsCompanion wallet) =>
      _db.into(_db.wallets).insert(wallet);

  Future<int> count() async {
    final countExp = _db.wallets.id.count();
    final query = _db.selectOnly(_db.wallets)..addColumns([countExp]);
    return (await query.getSingle()).read(countExp) ?? 0;
  }

  /// Deletes a wallet and cascades all of its per-wallet rows in one
  /// transaction.
  Future<void> deleteWallet(String walletId) => _db.transaction(() async {
        await (_db.delete(_db.accounts)..where((t) => t.walletId.equals(walletId))).go();
        await (_db.delete(_db.tokens)..where((t) => t.walletId.equals(walletId))).go();
        await (_db.delete(_db.balances)..where((t) => t.walletId.equals(walletId))).go();
        await (_db.delete(_db.transactions)..where((t) => t.walletId.equals(walletId))).go();
        await (_db.delete(_db.addressBook)..where((t) => t.walletId.equals(walletId))).go();
        await (_db.delete(_db.signRequests)..where((t) => t.walletId.equals(walletId))).go();
        await (_db.delete(_db.walletSettings)..where((t) => t.walletId.equals(walletId))).go();
        await (_db.delete(_db.wallets)..where((t) => t.id.equals(walletId))).go();
      });

  WalletRepository scoped(String walletId) => WalletRepository(_db, walletId);
}

/// All queries in this class are constrained to [walletId] — there is no way to
/// reach another wallet's rows through it.
class WalletRepository {
  WalletRepository(this._db, this.walletId);
  final WalletDatabase _db;
  final String walletId;

  // ---- accounts ----------------------------------------------------------

  Future<List<Account>> accounts() =>
      (_db.select(_db.accounts)..where((a) => a.walletId.equals(walletId))).get();

  Future<void> upsertAccount(AccountsCompanion account) {
    // Force the scope's walletId regardless of what the caller passed, so
    // isolation holds even in release builds (asserts are stripped). INV-11.
    return _db.into(_db.accounts).insertOnConflictUpdate(
          account.copyWith(walletId: Value(walletId)),
        );
  }

  // ---- transactions ------------------------------------------------------

  Future<List<Transaction>> transactions({int? limit}) {
    final q = _db.select(_db.transactions)
      ..where((t) => t.walletId.equals(walletId))
      ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)]);
    if (limit != null) q.limit(limit);
    return q.get();
  }

  Future<void> upsertTransaction(TransactionsCompanion tx) {
    return _db.into(_db.transactions).insertOnConflictUpdate(
          tx.copyWith(walletId: Value(walletId)),
        );
  }

  // ---- address book ------------------------------------------------------

  Future<List<AddressBookData>> contacts() =>
      (_db.select(_db.addressBook)..where((a) => a.walletId.equals(walletId))).get();

  Future<void> addContact(AddressBookCompanion contact) {
    return _db.into(_db.addressBook).insert(
          contact.copyWith(walletId: Value(walletId)),
        );
  }

  // ---- token visibility --------------------------------------------------

  Future<List<Token>> tokens({bool? enabledOnly}) {
    final q = _db.select(_db.tokens)..where((t) => t.walletId.equals(walletId));
    if (enabledOnly == true) {
      q.where((t) => t.enabled.equals(true));
    }
    return q.get();
  }

  Future<void> upsertToken(TokensCompanion token) {
    return _db.into(_db.tokens).insertOnConflictUpdate(
          token.copyWith(walletId: Value(walletId)),
        );
  }

  // ---- balances ----------------------------------------------------------

  Future<void> upsertBalance(BalancesCompanion balance) {
    return _db.into(_db.balances).insertOnConflictUpdate(
          balance.copyWith(walletId: Value(walletId)),
        );
  }

  Future<List<Balance>> balances() =>
      (_db.select(_db.balances)..where((b) => b.walletId.equals(walletId))).get();

  // ---- per-wallet settings ----------------------------------------------

  Future<String?> setting(String key) async {
    final row = await (_db.select(_db.walletSettings)
          ..where((s) => s.walletId.equals(walletId) & s.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> putSetting(String key, String value) => _db
      .into(_db.walletSettings)
      .insertOnConflictUpdate(WalletSettingsCompanion.insert(
        walletId: walletId,
        key: key,
        value: value,
      ));
}
