import 'package:drift/drift.dart';

import 'database.dart';
import 'tables.dart' show TxCheckOutcome, TxStatus;

/// Raised when a second locally-created EVM transaction tries to reserve a
/// nonce that is already owned by a submitted or pending transaction.
class EvmNonceConflict implements Exception {
  const EvmNonceConflict(this.existing);

  final Transaction existing;

  @override
  String toString() =>
      'EVM nonce ${existing.nonce} is already reserved by ${existing.id}';
}

/// Manages the wallet list itself (the only cross-wallet surface allowed).
/// Everything else goes through a [WalletRepository] bound to one walletId, so
/// there is no API that can read another wallet's data (detailed-design.md
/// §5.1, §8.11).
class WalletsRepository {
  WalletsRepository(this._db);
  final WalletDatabase _db;

  Future<List<Wallet>> listAll() => (_db.select(
    _db.wallets,
  )..orderBy([(w) => OrderingTerm(expression: w.sortOrder)])).get();

  Future<Wallet?> byId(String id) => (_db.select(
    _db.wallets,
  )..where((w) => w.id.equals(id))).getSingleOrNull();

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
    await (_db.delete(
      _db.accounts,
    )..where((t) => t.walletId.equals(walletId))).go();
    await (_db.delete(
      _db.tokens,
    )..where((t) => t.walletId.equals(walletId))).go();
    await (_db.delete(
      _db.balances,
    )..where((t) => t.walletId.equals(walletId))).go();
    await (_db.delete(
      _db.transactions,
    )..where((t) => t.walletId.equals(walletId))).go();
    await (_db.delete(
      _db.addressBook,
    )..where((t) => t.walletId.equals(walletId))).go();
    await (_db.delete(
      _db.signRequests,
    )..where((t) => t.walletId.equals(walletId))).go();
    await (_db.delete(
      _db.walletSettings,
    )..where((t) => t.walletId.equals(walletId))).go();
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

  Future<List<Account>> accounts() => (_db.select(
    _db.accounts,
  )..where((a) => a.walletId.equals(walletId))).get();

  Future<void> upsertAccount(AccountsCompanion account) {
    // Force the scope's walletId regardless of what the caller passed, so
    // isolation holds even in release builds (asserts are stripped). INV-11.
    return _db
        .into(_db.accounts)
        .insertOnConflictUpdate(account.copyWith(walletId: Value(walletId)));
  }

  // ---- transactions ------------------------------------------------------

  /// Wallet-scoped transaction list, newest first. [networkIds] restricts the
  /// result to rows recorded on those network instances (the caller passes the
  /// currently ACTIVE ids) — pending/history surfaces must never mix a
  /// testnet row into a mainnet list. Passing null keeps every network.
  Future<List<Transaction>> transactions({
    int? limit,
    Set<String>? networkIds,
  }) {
    final q = _db.select(_db.transactions)
      ..where((t) => t.walletId.equals(walletId))
      ..orderBy([
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ]);
    if (networkIds != null) {
      q.where((t) => t.networkId.isIn(networkIds.toList()));
    }
    if (limit != null) q.limit(limit);
    return q.get();
  }

  Future<Transaction?> transactionById(String id) =>
      (_db.select(_db.transactions)
            ..where((t) => t.walletId.equals(walletId) & t.id.equals(id)))
          .getSingleOrNull();

  Future<void> upsertTransaction(TransactionsCompanion tx) {
    return _db
        .into(_db.transactions)
        .insertOnConflictUpdate(tx.copyWith(walletId: Value(walletId)));
  }

  /// Atomically reserves an EVM nonce and inserts [tx]. A replacement is
  /// allowed to reuse [replacesId]'s nonce, but a second live replacement (or
  /// a racing new transfer) is rejected. This closes the gap between fetching
  /// `pending` nonce and broadcasting where two UI actions could otherwise
  /// sign different transactions with the same nonce.
  ///
  /// The conflict key is scoped PER NETWORK ([networkId]): nonces are a
  /// per-(account, chain-instance) sequence, so a pending Sepolia row must not
  /// block a legitimate Ethereum-mainnet transfer that happens to reuse the
  /// same number, and vice versa.
  Future<void> reserveEvmTransaction(
    TransactionsCompanion tx, {
    required String coin,
    required String networkId,
    required String from,
    required String nonce,
    String? replacesId,
  }) => _db.transaction(() async {
    final query = _db.select(_db.transactions)
      ..where(
        (t) =>
            t.walletId.equals(walletId) &
            t.coin.equals(coin) &
            t.networkId.equals(networkId) &
            t.fromAddr.equals(from) &
            t.nonce.equals(nonce) &
            t.status.isIn([
              TxStatus.submitted.index,
              TxStatus.broadcast.index,
              TxStatus.pending.index,
            ]),
      );
    final active = await query.get();
    final conflicts = active.where((row) => row.id != replacesId).toList();
    if (conflicts.isNotEmpty) {
      throw EvmNonceConflict(conflicts.first);
    }
    await _db
        .into(_db.transactions)
        .insert(tx.copyWith(walletId: Value(walletId)));
  });

  Future<void> updateTransactionStatus(
    String id,
    TxStatus status, {
    String? hash,
    int? broadcastAt,
    int? lastCheckedAt,
    TxCheckOutcome? lastCheckOutcome,
    bool clearLastCheckOutcome = false,
  }) async {
    await (_db.update(
      _db.transactions,
    )..where((t) => t.walletId.equals(walletId) & t.id.equals(id))).write(
      TransactionsCompanion(
        status: Value(status),
        hash: hash == null ? const Value.absent() : Value(hash),
        broadcastAt: broadcastAt == null
            ? const Value.absent()
            : Value(broadcastAt),
        lastCheckedAt: lastCheckedAt == null
            ? const Value.absent()
            : Value(lastCheckedAt),
        lastCheckOutcome: clearLastCheckOutcome
            ? const Value(null)
            : lastCheckOutcome == null
            ? const Value.absent()
            : Value(lastCheckOutcome),
      ),
    );
  }

  /// Backfills an observed EVM nonce without ever overwriting existing
  /// evidence. Returns true only when this call changed the row.
  Future<bool> setTransactionNonceIfAbsent(String id, String nonce) async {
    final parsed = BigInt.tryParse(nonce);
    if (parsed == null || parsed.isNegative) {
      throw ArgumentError.value(nonce, 'nonce');
    }
    final changed =
        await (_db.update(_db.transactions)..where(
              (t) =>
                  t.walletId.equals(walletId) &
                  t.id.equals(id) &
                  t.nonce.isNull(),
            ))
            .write(TransactionsCompanion(nonce: Value(parsed.toString())));
    return changed == 1;
  }

  /// Records that an EVM node accepted a replacement for propagation.
  ///
  /// Node acceptance is not finality: the original transaction can still win
  /// the nonce race. Both rows therefore remain live until a receipt proves
  /// which hash consumed the nonce. [replacedById] is only a candidate link at
  /// this stage; [settleEvmTransaction] applies the terminal lineage.
  Future<bool> recordEvmReplacementBroadcast({
    required String originalId,
    required String replacementId,
    required String hash,
    required int broadcastAt,
  }) => _db.transaction(() async {
    final original = await transactionById(originalId);
    final canReplace =
        original != null &&
        (original.status == TxStatus.submitted ||
            original.status == TxStatus.pending);
    if (canReplace) {
      await (_db.update(_db.transactions)..where(
            (t) => t.walletId.equals(walletId) & t.id.equals(originalId),
          ))
          .write(TransactionsCompanion(replacedById: Value(replacementId)));
    }
    await (_db.update(_db.transactions)..where(
          (t) => t.walletId.equals(walletId) & t.id.equals(replacementId),
        ))
        .write(
          TransactionsCompanion(
            status: const Value(TxStatus.pending),
            hash: Value(hash),
            broadcastAt: Value(broadcastAt),
          ),
        );
    return canReplace;
  });

  /// Applies a receipt-backed terminal EVM result and resolves every locally
  /// known transaction competing for the same nonce.
  ///
  /// A confirmed or reverted transaction consumes its nonce. If [id] is a
  /// replacement, the original becomes `replaced`; if [id] is the original,
  /// every still-live replacement becomes `replaced`. Local signing/broadcast
  /// failures must continue to use [updateTransactionStatus] because they do
  /// not prove that any nonce was consumed on-chain.
  Future<void> settleEvmTransaction({
    required String id,
    required TxStatus status,
    String? hash,
    int? lastCheckedAt,
  }) {
    if (status != TxStatus.confirmed && status != TxStatus.failed) {
      throw ArgumentError.value(status, 'status', 'must consume the nonce');
    }
    return _db.transaction(() async {
      final row = await transactionById(id);
      if (row == null) return;
      await (_db.update(
        _db.transactions,
      )..where((t) => t.walletId.equals(walletId) & t.id.equals(id))).write(
        TransactionsCompanion(
          status: Value(status),
          hash: hash == null ? const Value.absent() : Value(hash),
          lastCheckedAt: lastCheckedAt == null
              ? const Value.absent()
              : Value(lastCheckedAt),
          lastCheckOutcome: const Value(null),
        ),
      );

      const live = [TxStatus.submitted, TxStatus.broadcast, TxStatus.pending];
      final liveIndexes = live.map((value) => value.index).toList();
      final originalId = row.replacesId;
      if (originalId != null) {
        await (_db.update(_db.transactions)..where(
              (t) =>
                  t.walletId.equals(walletId) &
                  t.id.equals(originalId) &
                  t.status.isIn(liveIndexes),
            ))
            .write(
              TransactionsCompanion(
                status: const Value(TxStatus.replaced),
                replacedById: Value(id),
                lastCheckOutcome: const Value(null),
              ),
            );
      }

      await (_db.update(_db.transactions)..where(
            (t) =>
                t.walletId.equals(walletId) &
                t.replacesId.equals(id) &
                t.status.isIn(liveIndexes),
          ))
          .write(
            TransactionsCompanion(
              status: const Value(TxStatus.replaced),
              replacedById: Value(id),
              lastCheckOutcome: const Value(null),
            ),
          );
    });
  }

  // ---- address book ------------------------------------------------------

  Future<List<AddressBookData>> contacts() => (_db.select(
    _db.addressBook,
  )..where((a) => a.walletId.equals(walletId))).get();

  Future<void> addContact(AddressBookCompanion contact) {
    return _db
        .into(_db.addressBook)
        .insert(contact.copyWith(walletId: Value(walletId)));
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
    return _db
        .into(_db.tokens)
        .insertOnConflictUpdate(token.copyWith(walletId: Value(walletId)));
  }

  // ---- balances ----------------------------------------------------------

  Future<void> upsertBalance(BalancesCompanion balance) {
    return _db
        .into(_db.balances)
        .insertOnConflictUpdate(balance.copyWith(walletId: Value(walletId)));
  }

  Future<List<Balance>> balances() => (_db.select(
    _db.balances,
  )..where((b) => b.walletId.equals(walletId))).get();

  // ---- per-wallet settings ----------------------------------------------

  Future<String?> setting(String key) async {
    final row =
        await (_db.select(_db.walletSettings)
              ..where((s) => s.walletId.equals(walletId) & s.key.equals(key)))
            .getSingleOrNull();
    return row?.value;
  }

  Future<void> putSetting(String key, String value) => _db
      .into(_db.walletSettings)
      .insertOnConflictUpdate(
        WalletSettingsCompanion.insert(
          walletId: walletId,
          key: key,
          value: value,
        ),
      );
}

/// Global (cross-wallet) address-book contacts — the Settings → 地址管理 list.
/// Not wallet-scoped by design: contacts are an app-level surface (unlike the
/// per-wallet [AddressBook] table used by transfer flows).
class ContactsRepository {
  ContactsRepository(this._db);
  final WalletDatabase _db;

  Future<List<Contact>> list() =>
      (_db.select(_db.contacts)..orderBy([
            (c) => OrderingTerm(expression: c.createdAt),
            (c) => OrderingTerm(expression: c.id),
          ]))
          .get();

  Future<void> insert(Insertable<Contact> contact) =>
      _db.into(_db.contacts).insert(contact);

  /// Edits a contact in place. `createdAt` is deliberately untouched so the
  /// row keeps its position in the list after a rename.
  Future<void> update(
    String id, {
    required String name,
    required String address,
    required String chain,
  }) => (_db.update(_db.contacts)..where((c) => c.id.equals(id))).write(
    ContactsCompanion(
      name: Value(name),
      address: Value(address),
      chain: Value(chain),
    ),
  );

  Future<void> delete(String id) =>
      (_db.delete(_db.contacts)..where((c) => c.id.equals(id))).go();
}

/// Global custom-token registry — the Settings → Token 管理 list.
class TokensRepository {
  TokensRepository(this._db);
  final WalletDatabase _db;

  Future<List<CustomToken>> list() =>
      (_db.select(_db.customTokens)..orderBy([
            (t) => OrderingTerm(expression: t.sortOrder),
            (t) => OrderingTerm(expression: t.createdAt),
            (t) => OrderingTerm(expression: t.id),
          ]))
          .get();

  Future<void> insert(Insertable<CustomToken> token) =>
      _db.into(_db.customTokens).insert(token);

  Future<void> setEnabled(String id, bool enabled) =>
      (_db.update(_db.customTokens)..where((t) => t.id.equals(id))).write(
        CustomTokensCompanion(enabled: Value(enabled)),
      );

  Future<void> delete(String id) =>
      (_db.delete(_db.customTokens)..where((t) => t.id.equals(id))).go();
}
