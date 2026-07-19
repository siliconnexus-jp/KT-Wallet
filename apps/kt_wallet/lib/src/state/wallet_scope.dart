import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/widgets.dart';

import '../wallets/wallet_manager.dart';
import '../wallets/wallet_model.dart';
import 'wallet_controller.dart';

/// Provides the app-wide [WalletController] to the widget tree and rebuilds
/// dependents when it changes.
class WalletScope extends InheritedNotifier<WalletController> {
  const WalletScope({super.key, required WalletController controller, required super.child})
      : super(notifier: controller);

  /// The live controller, or a shared demo controller when a screen is rendered
  /// standalone (the gallery index and golden tests). Real navigation always
  /// runs under a [WalletScope].
  static WalletController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<WalletScope>();
    return scope?.notifier ?? _fallback;
  }

  static final WalletController _fallback = WalletController(WalletManager(initial: [
    HotWallet(
      id: 'daily',
      name: '日常钱包',
      avatarColor: 0xFFF59E0B,
      addresses: const ChainAddresses(
        eth: '0xa71c8B29b3d4b79E19bE1',
        polygon: '0xa71c8B29b3d4b79E19bE1',
        tron: 'TaPa2Wc8hJdU5eRnT6yGb1sVb7L3kFa',
        solana: 'ayKpXwMWd4qmDqVr2W',
      ),
      backedUp: false,
    ),
  ]));
}
