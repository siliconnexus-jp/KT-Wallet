import 'wallet_model.dart';

/// In-memory multi-wallet registry with the current-wallet selection
/// (detailed-design.md §6.1–6.2, ui-m.md §6). Persistence is layered on via
/// wallet_data; this holds the switching + cap logic that the UI and providers
/// consume.
class WalletManager {
  WalletManager({List<Wallet>? initial}) : _wallets = [...?initial] {
    if (_wallets.isNotEmpty) _currentId = _sorted().first.id;
  }

  static const maxWallets = 20;

  final List<Wallet> _wallets;
  String? _currentId;

  List<Wallet> get wallets => _sorted();
  int get count => _wallets.length;
  bool get canAddMore => _wallets.length < maxWallets;

  String? get currentId => _currentId;
  Wallet? get current => _currentId == null ? null : _byId(_currentId!);

  List<Wallet> _sorted() =>
      [..._wallets]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  Wallet? _byId(String id) {
    for (final w in _wallets) {
      if (w.id == id) return w;
    }
    return null;
  }

  /// Adds a wallet. Throws if the id already exists or the cap is reached.
  void add(Wallet wallet) {
    if (_byId(wallet.id) != null) {
      throw WalletError('duplicate wallet id: ${wallet.id}');
    }
    if (!canAddMore) {
      throw WalletError('wallet limit reached ($maxWallets)');
    }
    _wallets.add(wallet);
    _currentId ??= wallet.id;
  }

  /// Switches the active wallet. Switching is global: every wallet-scoped
  /// provider re-derives from [current].
  void select(String id) {
    if (_byId(id) == null) throw WalletError('unknown wallet id: $id');
    _currentId = id;
  }

  void rename(String id, String name) {
    _replace(
      id,
      (w) => switch (w) {
        HotWallet() => w.copyWith(name: name),
        WatchWallet() => w.copyWith(name: name),
      },
    );
  }

  void setColor(String id, int color) {
    _replace(
      id,
      (w) => switch (w) {
        HotWallet() => w.copyWith(avatarColor: color),
        WatchWallet() => w.copyWith(avatarColor: color),
      },
    );
  }

  void markBackedUp(String id) {
    _replace(
      id,
      (w) => switch (w) {
        HotWallet() => w.copyWith(backedUp: true),
        WatchWallet() => throw WalletError(
          'watch wallets have no backup state',
        ),
      },
    );
  }

  /// Removes a wallet; if it was current, selection falls back to the first
  /// remaining wallet (or null).
  void remove(String id) {
    final w = _byId(id);
    if (w == null) throw WalletError('unknown wallet id: $id');
    _wallets.remove(w);
    if (_currentId == id) {
      _currentId = _wallets.isEmpty ? null : _sorted().first.id;
    }
  }

  /// Reorders wallets to the given id order (drag-to-sort persistence).
  /// [orderedIds] must be an exact permutation of the current wallet ids;
  /// validated up front so a bad argument never leaves partially-applied state.
  void reorder(List<String> orderedIds) {
    if (orderedIds.toSet().length != orderedIds.length) {
      throw WalletError('duplicate ids in reorder');
    }
    final existing = _wallets.map((w) => w.id).toSet();
    if (orderedIds.toSet().length != existing.length ||
        !orderedIds.toSet().containsAll(existing)) {
      throw WalletError('reorder must be a full permutation of wallet ids');
    }
    for (var i = 0; i < orderedIds.length; i++) {
      _replace(
        orderedIds[i],
        (w) => switch (w) {
          HotWallet() => w.copyWith(sortOrder: i),
          WatchWallet() => w.copyWith(sortOrder: i),
        },
      );
    }
  }

  void _replace(String id, Wallet Function(Wallet) update) {
    final idx = _wallets.indexWhere((w) => w.id == id);
    if (idx < 0) throw WalletError('unknown wallet id: $id');
    _wallets[idx] = update(_wallets[idx]);
  }
}

class WalletError implements Exception {
  WalletError(this.message);
  final String message;
  @override
  String toString() => 'WalletError: $message';
}
