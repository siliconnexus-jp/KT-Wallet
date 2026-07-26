import 'package:core_crypto/core_crypto.dart';
import 'package:core_crypto/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:wallet_data/wallet_data.dart'
    show
        Contact,
        CustomToken,
        SignMode,
        Transaction,
        TxReplacementKind,
        TxStatus;

import '../wallets/wallet_manager.dart';
import '../wallets/wallet_model.dart';
import '../wallets/wallet_store.dart';

/// App-wide wallet state. Wraps the tested [WalletManager] as a [ChangeNotifier]
/// so screens rebuild when the current wallet changes (switch/add/rename/etc.).
///
/// Key operations go through [CoreCrypto] (real on iOS; deterministic
/// [MockCoreCrypto] where wallet-core is unavailable, so every flow is
/// exercisable). Production wires a [WalletStore] for drift persistence; tests
/// can omit it (in-memory only).
class WalletController extends ChangeNotifier {
  WalletController(this._manager, {CoreCrypto? crypto, WalletStore? store})
    : _crypto = crypto ?? MockCoreCrypto(),
      // ignore: prefer_initializing_formals
      _store = store;

  final WalletManager _manager;
  final CoreCrypto _crypto;
  final WalletStore? _store;

  /// Releases the backing store's database connection (no-op for in-memory
  /// controllers). Call when the controller is retired, e.g. when leaving
  /// wallet mode in the combined installer; the controller must not be used
  /// afterwards.
  Future<void> close() async => _store?.close();

  /// Mnemonic generated during create-onboarding, held only between the
  /// "create new wallet" tap and the backup-verify confirmation, then dropped.
  String? _pendingMnemonic;
  String? get pendingMnemonic => _pendingMnemonic;

  static const _palette = [
    0xFF0EA5E9,
    0xFF10B981,
    0xFFEF4444,
    0xFFF59E0B,
    0xFF8B5CF6,
    0xFFEC4899,
  ];

  List<Wallet> get wallets => _manager.wallets;
  Wallet? get current => _manager.current;
  CoreCrypto get crypto => _crypto;
  bool get usesDemoCrypto => _crypto is MockCoreCrypto;
  int get count => _manager.count;
  bool get canAddMore => _manager.canAddMore;

  Future<List<Transaction>> localTransactions() async {
    final walletId = current?.id;
    if (walletId == null || _store == null) return const [];
    return _store.transactions(walletId);
  }

  Future<Transaction?> localTransactionById(String id) async {
    final walletId = current?.id;
    if (walletId == null || _store == null) return null;
    return _store.transactionById(walletId, id);
  }

  Future<void> saveOutgoingTransaction({
    required String id,
    String? reqId,
    required Coin coin,
    String? contract,
    required String from,
    required String to,
    required String amountRaw,
    String? feeRaw,
    String? hash,
    required TxStatus status,
    required SignMode signMode,
    required int createdAt,
    int? broadcastAt,
    String? nonce,
    String? maxPriorityFeeRaw,
    String? maxFeeRaw,
    String? gasLimitRaw,
    String? replacesId,
    String? replacedById,
    TxReplacementKind? replacementKind,
  }) async {
    final walletId = current?.id;
    if (walletId == null || _store == null) return;
    await _store.upsertTransaction(
      id: id,
      walletId: walletId,
      reqId: reqId,
      coin: coin,
      contract: contract,
      from: from,
      to: to,
      amountRaw: amountRaw,
      feeRaw: feeRaw,
      hash: hash,
      status: status,
      signMode: signMode,
      createdAt: createdAt,
      broadcastAt: broadcastAt,
      nonce: nonce,
      maxPriorityFeeRaw: maxPriorityFeeRaw,
      maxFeeRaw: maxFeeRaw,
      gasLimitRaw: gasLimitRaw,
      replacesId: replacesId,
      replacedById: replacedById,
      replacementKind: replacementKind,
    );
    notifyListeners();
  }

  Future<void> reserveOutgoingEvmTransaction({
    required String id,
    required Coin coin,
    String? contract,
    required String from,
    required String to,
    required String amountRaw,
    required String feeRaw,
    required SignMode signMode,
    required int createdAt,
    required String nonce,
    required String maxPriorityFeeRaw,
    required String maxFeeRaw,
    required String gasLimitRaw,
    String? replacesId,
    TxReplacementKind? replacementKind,
  }) async {
    final walletId = current?.id;
    if (walletId == null || _store == null) {
      throw StateError('No persistent wallet selected');
    }
    await _store.reserveEvmTransaction(
      id: id,
      walletId: walletId,
      coin: coin,
      contract: contract,
      from: from,
      to: to,
      amountRaw: amountRaw,
      feeRaw: feeRaw,
      signMode: signMode,
      createdAt: createdAt,
      nonce: nonce,
      maxPriorityFeeRaw: maxPriorityFeeRaw,
      maxFeeRaw: maxFeeRaw,
      gasLimitRaw: gasLimitRaw,
      replacesId: replacesId,
      replacementKind: replacementKind,
    );
    notifyListeners();
  }

  Future<void> updateTransactionStatus(
    String id,
    TxStatus status, {
    String? hash,
    int? broadcastAt,
  }) async {
    final walletId = current?.id;
    if (walletId == null || _store == null) return;
    await _store.updateTransactionStatus(
      walletId,
      id,
      status,
      hash: hash,
      broadcastAt: broadcastAt,
    );
    notifyListeners();
  }

  Future<bool> acceptEvmReplacement({
    required String originalId,
    required String replacementId,
    required String hash,
    required int broadcastAt,
  }) async {
    final walletId = current?.id;
    if (walletId == null || _store == null) return false;
    final accepted = await _store.acceptEvmReplacement(
      walletId: walletId,
      originalId: originalId,
      replacementId: replacementId,
      hash: hash,
      broadcastAt: broadcastAt,
    );
    notifyListeners();
    return accepted;
  }

  int _nextColor() => _palette[_manager.count % _palette.length];
  String _newId() => 'w${DateTime.now().microsecondsSinceEpoch}';

  void select(String id) {
    if (_manager.currentId == id) return;
    _manager.select(id);
    notifyListeners();
  }

  /// Adds an already-built wallet (watch-wallet pairing / seeding) and persists.
  void add(Wallet wallet) {
    _manager.add(wallet);
    _store?.save(wallet);
    notifyListeners();
  }

  // ---- onboarding: create ------------------------------------------------

  /// Generates a fresh mnemonic and holds it for the backup show/verify flow.
  Future<void> beginCreate() async {
    _pendingMnemonic = await _crypto.generateMnemonic();
    notifyListeners();
  }

  /// Commits the pending mnemonic as a new, backed-up hot wallet. [name] is the
  /// localized default name built by the caller (which has an l10n context).
  Future<HotWallet> finalizeCreate({required String name}) async {
    final mnemonic = _pendingMnemonic;
    if (mnemonic == null) throw StateError('no pending mnemonic to finalize');
    final wallet = await _materialize(name, mnemonic);
    _pendingMnemonic = null;
    return wallet;
  }

  // ---- onboarding: import ------------------------------------------------

  /// Imports an existing mnemonic as a hot wallet (already backed up elsewhere).
  /// [name] is the localized default name built by the caller.
  Future<HotWallet> importWallet(String mnemonic, {required String name}) =>
      _materialize(name, mnemonic.trim());

  /// Stores the key in CoreCrypto, derives public addresses, builds the domain
  /// wallet, adds it to the manager, persists it, and selects it.
  Future<HotWallet> _materialize(String name, String mnemonic) async {
    final id = _newId();
    await _crypto.storeWallet(walletId: id, mnemonic: mnemonic);
    final addresses = await _crypto.deriveAddresses(id);
    final wallet = HotWallet(
      id: id,
      name: name,
      avatarColor: _nextColor(),
      addresses: addresses,
      sortOrder: _manager.count,
      backedUp: true,
    );
    _manager.add(wallet);
    _manager.select(id);
    await _store?.save(wallet);
    notifyListeners();
    return wallet;
  }

  // ---- mutations ---------------------------------------------------------

  void rename(String id, String name) {
    _manager.rename(id, name);
    _persistMetadata(id);
    notifyListeners();
  }

  void setColor(String id, int color) {
    _manager.setColor(id, color);
    _persistMetadata(id);
    notifyListeners();
  }

  /// Exposes the stored mnemonic for backup/inspection flows. Requires the
  /// wallet's key material to exist in [CoreCrypto] (throws
  /// [CoreCryptoException] otherwise, e.g. for demo-seeded wallets).
  Future<String> exportMnemonic(String id) => _crypto.exportMnemonic(id);

  void markBackedUp(String id) {
    _manager.markBackedUp(id);
    _persistMetadata(id);
    notifyListeners();
  }

  Future<void> remove(String id) async {
    final wallet = _manager.byId(id);
    if (_store != null && wallet is HotWallet) {
      await _crypto.deleteWallet(id);
    }
    _manager.remove(id);
    await _store?.delete(id);
    notifyListeners();
  }

  /// Moves the wallet at [oldIndex] (position in the sorted [wallets] list) to
  /// [newIndex], then persists every wallet's new sortOrder — a drag rewrites
  /// the whole permutation, so all rows are "affected".
  void reorder(int oldIndex, int newIndex) {
    final ids = _manager.wallets.map((w) => w.id).toList();
    final id = ids.removeAt(oldIndex);
    ids.insert(newIndex, id);
    _manager.reorder(ids);
    for (final walletId in ids) {
      _persistMetadata(walletId);
    }
    notifyListeners();
  }

  void _persistMetadata(String id) {
    final store = _store;
    if (store == null) return;
    final wallet = _manager.wallets.where((w) => w.id == id).firstOrNull;
    if (wallet != null) store.updateMetadata(wallet);
  }

  // ---- global address book & custom-token list ---------------------------
  //
  // Persisted through the store when present; a plain in-memory list when
  // `_store == null` (gallery/goldens/widget tests), so the screens have a
  // single code path either way.

  final List<Contact> _contacts = [];
  final List<CustomToken> _tokens = [];
  int _rowSeq = 0;

  /// Whether contacts/tokens survive a restart (drift store wired).
  bool get hasStore => _store != null;

  List<Contact> get contacts => List.unmodifiable(_contacts);
  List<CustomToken> get tokens => List.unmodifiable(_tokens);

  String _rowId(String prefix) =>
      '$prefix${DateTime.now().microsecondsSinceEpoch}-${_rowSeq++}';

  /// Refreshes [contacts] from the store (no-op refresh without one).
  Future<List<Contact>> loadContacts() async {
    final store = _store;
    if (store != null) {
      _contacts
        ..clear()
        ..addAll(await store.listContacts());
    }
    return contacts;
  }

  Future<Contact> addContact({
    required String name,
    required String address,
    required String chain,
  }) async {
    final contact = Contact(
      id: _rowId('c'),
      name: name,
      address: address,
      chain: chain,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _store?.addContact(contact);
    _contacts.add(contact);
    notifyListeners();
    return contact;
  }

  Future<void> removeContact(String id) async {
    await _store?.deleteContact(id);
    _contacts.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  /// Refreshes [tokens] from the store (no-op refresh without one).
  Future<List<CustomToken>> loadTokens() async {
    final store = _store;
    if (store != null) {
      _tokens
        ..clear()
        ..addAll(await store.listTokens());
    }
    return tokens;
  }

  Future<CustomToken> addToken({
    required String symbol,
    required String name,
    String? contract,
    required String network,
    bool enabled = true,
  }) async {
    final token = CustomToken(
      id: _rowId('t'),
      symbol: symbol,
      name: name,
      contract: contract,
      network: network,
      enabled: enabled,
      sortOrder: _tokens.length,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _store?.addToken(token);
    _tokens.add(token);
    notifyListeners();
    return token;
  }

  Future<void> setTokenEnabled(String id, bool enabled) async {
    await _store?.setTokenEnabled(id, enabled);
    final i = _tokens.indexWhere((t) => t.id == id);
    if (i >= 0) _tokens[i] = _tokens[i].copyWith(enabled: enabled);
    notifyListeners();
  }
}
