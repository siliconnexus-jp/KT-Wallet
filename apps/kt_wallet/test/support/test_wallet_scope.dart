import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/state/wallet_scope.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';

/// Explicit design/test fixture. Production widgets intentionally have no
/// implicit wallet fallback, so standalone tests must opt into this scope.
WalletController buildTestWalletController({bool backedUp = false}) =>
    WalletController(
      WalletManager(
        initial: [
          HotWallet(
            id: 'WLT-91A4C7',
            name: '日常钱包',
            avatarColor: 0xFFF59E0B,
            addresses: const ChainAddresses(
              eth: '0xa71c8B29b3d4b79E19bE1',
              polygon: '0xa71c8B29b3d4b79E19bE1',
              tron: 'TQm9xPa2Wc8hJdU5eRnT6yGb1sVb7L3kFa',
              solana: 'ayKpXwMWd4qmDqVr2W',
            ),
            backedUp: backedUp,
          ),
        ],
      ),
      allowTestBypass: true,
    );

Widget withTestWalletScope(Widget child, {WalletController? controller}) =>
    WalletScope(
      controller: controller ?? buildTestWalletController(),
      child: child,
    );
