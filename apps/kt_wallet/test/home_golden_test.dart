import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/screens/home_screen.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:ui_kit/ui_kit.dart';

const _addrs = ChainAddresses(
  eth: '0x8f3C2a71c8B29b3d4b79E19bE1',
  polygon: '0x8f3C2a71c8B29b3d4b79E19bE1',
  tron: 'TQm9xPa2Wc8hJdU5eRnT6yGb1sVb7L3kFa',
  solana: '6yKpXwMWd4qmDqVr2W',
);

const _assets = [
  AssetRow(Color(0xFF26A17B), '₮', 'USDT', '500.00 USDT · TRON', r'$500.00', '0.0%', WalletColors.text3),
  AssetRow(Color(0xFF627EEA), 'Ξ', 'Ethereum', '0.0842 ETH', r'$279.80', '+2.4%', WalletColors.green),
  AssetRow(Color(0xFF9945FF), '◎', 'Solana', '0.531 SOL', r'$82.60', '+5.1%', WalletColors.green),
];

void main() {
  testWidgets('home screen golden at phone size (390x844)', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final manager = WalletManager(initial: [
      HotWallet(id: 'daily', name: '日常钱包', avatarColor: 0xFFF59E0B, addresses: _addrs, backedUp: false),
    ]);

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(scaffoldBackgroundColor: WalletColors.bg),
      home: HomeScreen(manager: manager, assets: _assets),
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/home_screen.png'),
    );
  });
}
