import 'package:core_crypto/core_crypto.dart';
import 'package:core_crypto/testing.dart';
import 'package:flutter/foundation.dart';

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
    0xFF0EA5E9, 0xFF10B981, 0xFFEF4444, 0xFFF59E0B, 0xFF8B5CF6, 0xFFEC4899,
  ];

  List<Wallet> get wallets => _manager.wallets;
  Wallet? get current => _manager.current;
  int get count => _manager.count;
  bool get canAddMore => _manager.canAddMore;

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

  void remove(String id) {
    _manager.remove(id);
    _store?.delete(id);
    notifyListeners();
  }

  void _persistMetadata(String id) {
    final store = _store;
    if (store == null) return;
    final wallet = _manager.wallets.where((w) => w.id == id).firstOrNull;
    if (wallet != null) store.updateMetadata(wallet);
  }
}
