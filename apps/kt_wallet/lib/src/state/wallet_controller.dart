import 'package:flutter/foundation.dart';

import '../wallets/wallet_manager.dart';
import '../wallets/wallet_model.dart';

/// App-wide wallet state. Wraps the tested [WalletManager] as a [ChangeNotifier]
/// so screens rebuild when the current wallet changes (switch/add/rename/etc.).
/// This is the seam that turns the static screens into a live app.
class WalletController extends ChangeNotifier {
  WalletController(this._manager);
  final WalletManager _manager;

  List<Wallet> get wallets => _manager.wallets;
  Wallet? get current => _manager.current;
  int get count => _manager.count;
  bool get canAddMore => _manager.canAddMore;

  void select(String id) {
    if (_manager.currentId == id) return;
    _manager.select(id);
    notifyListeners();
  }

  void add(Wallet wallet) {
    _manager.add(wallet);
    notifyListeners();
  }

  void rename(String id, String name) {
    _manager.rename(id, name);
    notifyListeners();
  }

  void markBackedUp(String id) {
    _manager.markBackedUp(id);
    notifyListeners();
  }

  void remove(String id) {
    _manager.remove(id);
    notifyListeners();
  }
}
