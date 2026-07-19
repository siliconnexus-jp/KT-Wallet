import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import 'src/app_router.dart';
import 'src/state/wallet_controller.dart';
import 'src/state/wallet_scope.dart';
import 'src/wallets/wallet_manager.dart';
import 'src/wallets/wallet_model.dart';

void main() {
  runApp(KtWalletApp());
}

ChainAddresses _addr(String seed) => ChainAddresses(
      eth: '0x${seed}71c8B29b3d4b79E19bE1',
      polygon: '0x${seed}71c8B29b3d4b79E19bE1',
      tron: 'T${seed}Pa2Wc8hJdU5eRnT6yGb1sVb7L3kFa',
      solana: '${seed}yKpXwMWd4qmDqVr2W',
    );

/// Seed several wallets so the switcher, backup banner and hot/watch variants
/// are all exercisable in the live app.
WalletController _seedController() => WalletController(WalletManager(initial: [
      HotWallet(id: 'daily', name: '日常钱包', avatarColor: 0xFFF59E0B, addresses: _addr('a'), backedUp: false),
      HotWallet(id: 'savings', name: '储蓄钱包', avatarColor: 0xFF8B5CF6, addresses: _addr('b'), sortOrder: 1, backedUp: true),
      WatchWallet(id: 'cold', name: '主钱包', avatarColor: 0xFF0C1220, addresses: _addr('c'), sortOrder: 2, coldWalletId: 'WLT-3E8A91', protocolVersion: 1),
    ]));

class KtWalletApp extends StatelessWidget {
  KtWalletApp({super.key});

  final _router = buildRouter();
  final _controller = _seedController();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'KT Wallet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Inter',
        colorScheme: ColorScheme.fromSeed(seedColor: WalletColors.accent),
        scaffoldBackgroundColor: WalletColors.bg,
      ),
      routerConfig: _router,
      builder: (context, child) => WalletScope(controller: _controller, child: child!),
    );
  }
}
