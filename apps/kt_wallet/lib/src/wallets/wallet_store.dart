import 'package:core_crypto/core_crypto.dart';
import 'package:drift/drift.dart';
import 'package:wallet_data/wallet_data.dart' as db;

import 'wallet_manager.dart';
import 'wallet_model.dart';

/// Bridges the persistent wallet_data layer (drift) and the in-memory
/// [WalletManager] domain model: loads domain wallets from the database and
/// persists domain wallets back. A wallet's addresses live in the accounts
/// table (detailed-design.md §5.1), so a domain [Wallet] is assembled from its
/// wallet row + its four account rows.
class WalletStore {
  WalletStore(this._db)
    : _wallets = db.WalletsRepository(_db),
      _contacts = db.ContactsRepository(_db),
      _tokens = db.TokensRepository(_db);
  final db.WalletDatabase _db;
  final db.WalletsRepository _wallets;
  final db.ContactsRepository _contacts;
  final db.TokensRepository _tokens;

  static const _coins = ['eth', 'polygon', 'tron', 'solana'];

  /// Loads all wallets into a fresh [WalletManager].
  Future<WalletManager> load() async {
    final rows = await _wallets.listAll();
    final domain = <Wallet>[];
    for (final row in rows) {
      final accounts = await _wallets.scoped(row.id).accounts();
      domain.add(_toDomain(row, accounts));
    }
    return WalletManager(initial: domain);
  }

  /// Persists a domain wallet: the wallet row + its four account rows, in one
  /// transaction.
  Future<void> save(Wallet wallet) => _db.transaction(() async {
    await _wallets.insert(_walletCompanion(wallet));
    final scoped = _wallets.scoped(wallet.id);
    for (final coin in _coins) {
      await scoped.upsertAccount(_accountCompanion(wallet, coin));
    }
  });

  /// Applies domain-level metadata changes back to the wallet row.
  Future<void> updateMetadata(Wallet wallet) =>
      _db.into(_db.wallets).insertOnConflictUpdate(_walletCompanion(wallet));

  Future<void> delete(String walletId) => _wallets.deleteWallet(walletId);

  // ---- global address book (Settings → 地址管理) --------------------------

  Future<List<db.Contact>> listContacts() => _contacts.list();

  Future<void> addContact(db.Contact contact) =>
      _contacts.insert(contact.toCompanion(false));

  Future<void> deleteContact(String id) => _contacts.delete(id);

  // ---- global custom-token list (Settings → Token 管理) -------------------

  Future<List<db.CustomToken>> listTokens() => _tokens.list();

  Future<void> addToken(db.CustomToken token) =>
      _tokens.insert(token.toCompanion(false));

  Future<void> setTokenEnabled(String id, bool enabled) =>
      _tokens.setEnabled(id, enabled);

  Future<void> deleteToken(String id) => _tokens.delete(id);

  /// Closes the underlying database. Call when the store is retired (e.g.
  /// leaving wallet mode in the combined installer); the store must not be
  /// used afterwards.
  Future<void> close() => _db.close();

  // ---- mapping -----------------------------------------------------------

  Wallet _toDomain(db.Wallet row, List<db.Account> accounts) {
    String addr(String coin) =>
        accounts.firstWhere((a) => a.coin == coin).address;
    final addresses = ChainAddresses(
      eth: addr('eth'),
      polygon: addr('polygon'),
      base: addr('eth'),
      arbitrum: addr('eth'),
      avalanche: addr('eth'),
      tron: addr('tron'),
      solana: addr('solana'),
    );
    return switch (row.type) {
      db.WalletType.hot => HotWallet(
        id: row.id,
        name: row.name,
        avatarColor: row.avatarColor,
        addresses: addresses,
        sortOrder: row.sortOrder,
        backedUp: row.backedUp,
      ),
      db.WalletType.watch => WatchWallet(
        id: row.id,
        name: row.name,
        avatarColor: row.avatarColor,
        addresses: addresses,
        sortOrder: row.sortOrder,
        coldWalletId: row.coldWalletId ?? '',
        protocolVersion: row.protocolVer ?? 1,
      ),
    };
  }

  db.WalletsCompanion _walletCompanion(Wallet w) => switch (w) {
    HotWallet() => db.WalletsCompanion.insert(
      id: w.id,
      name: w.name,
      type: db.WalletType.hot,
      avatarColor: w.avatarColor,
      sortOrder: Value(w.sortOrder),
      backedUp: Value(w.backedUp),
      createdAt: 0,
    ),
    WatchWallet() => db.WalletsCompanion.insert(
      id: w.id,
      name: w.name,
      type: db.WalletType.watch,
      avatarColor: w.avatarColor,
      sortOrder: Value(w.sortOrder),
      coldWalletId: Value(w.coldWalletId),
      protocolVer: Value(w.protocolVersion),
      createdAt: 0,
    ),
  };

  db.AccountsCompanion _accountCompanion(Wallet w, String coin) =>
      db.AccountsCompanion.insert(
        walletId: w.id,
        coin: coin,
        address: w.addresses.forCoin(_coinEnum(coin)),
        derivationPath: _pathFor(coin),
        accountIndex: 0,
      );

  static Coin _coinEnum(String coin) => switch (coin) {
    'eth' => Coin.eth,
    'polygon' => Coin.polygon,
    'tron' => Coin.tron,
    'solana' => Coin.solana,
    _ => throw ArgumentError('unknown coin $coin'),
  };

  static String _pathFor(String coin) => switch (coin) {
    'eth' || 'polygon' => "m/44'/60'/0'/0/0",
    'tron' => "m/44'/195'/0'/0/0",
    'solana' => "m/44'/501'/0'",
    _ => throw ArgumentError('unknown coin $coin'),
  };
}
