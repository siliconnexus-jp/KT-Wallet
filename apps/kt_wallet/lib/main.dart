import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import 'src/screens/home_screen.dart';
import 'src/wallets/wallet_manager.dart';
import 'src/wallets/wallet_model.dart';

void main() {
  runApp(const KtWalletApp());
}

/// Sample data so the flagship home screen (Pencil W20) can be run and compared
/// against the design. Real data comes from WalletStore + RPC balances.
WalletManager _seedManager() {
  const addrs = ChainAddresses(
    eth: '0x8f3C2a71c8B29b3d4b79E19bE1',
    polygon: '0x8f3C2a71c8B29b3d4b79E19bE1',
    tron: 'TQm9xPa2Wc8hJdU5eRnT6yGb1sVb7L3kFa',
    solana: '6yKpXwMWd4qmDqVr2W',
  );
  return WalletManager(initial: [
    HotWallet(id: 'daily', name: '日常钱包', avatarColor: 0xFFF59E0B, addresses: addrs, backedUp: false),
  ]);
}

const _assets = [
  AssetRow(Color(0xFF26A17B), '₮', 'USDT', '500.00 USDT · TRON', r'$500.00', '0.0%', WalletColors.text3),
  AssetRow(Color(0xFF627EEA), 'Ξ', 'Ethereum', '0.0842 ETH', r'$279.80', '+2.4%', WalletColors.green),
  AssetRow(Color(0xFF9945FF), '◎', 'Solana', '0.531 SOL', r'$82.60', '+5.1%', WalletColors.green),
];

class KtWalletApp extends StatelessWidget {
  const KtWalletApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KT Wallet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Inter',
        colorScheme: ColorScheme.fromSeed(seedColor: WalletColors.accent),
        scaffoldBackgroundColor: WalletColors.bg,
      ),
      home: HomeScreen(manager: _seedManager(), assets: _assets),
    );
  }
}
