import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

import 'screens/assets_screens.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screens.dart';
import 'screens/transfer_screens.dart';
import 'screens/wallet_screens.dart';
import 'wallets/wallet_manager.dart';
import 'wallets/wallet_model.dart';

const _demoAddrs = ChainAddresses(
  eth: '0x8f3C2a71c8B29b3d4b79E19bE1',
  polygon: '0x8f3C2a71c8B29b3d4b79E19bE1',
  tron: 'TQm9xPa2Wc8hJdU5eRnT6yGb1sVb7L3kFa',
  solana: '6yKpXwMWd4qmDqVr2W',
);

WalletManager demoManager() => WalletManager(initial: [
      HotWallet(id: 'daily', name: '日常钱包', avatarColor: 0xFFF59E0B, addresses: _demoAddrs, backedUp: false),
    ]);

const demoAssets = [
  AssetRow(Color(0xFF26A17B), '₮', 'USDT', '500.00 USDT · TRON', r'$500.00', '0.0%', WalletColors.text3),
  AssetRow(Color(0xFF627EEA), 'Ξ', 'Ethereum', '0.0842 ETH', r'$279.80', '+2.4%', WalletColors.green),
  AssetRow(Color(0xFF9945FF), '◎', 'Solana', '0.531 SOL', r'$82.60', '+5.1%', WalletColors.green),
];

/// Registry of every implemented screen, powering both the router and a gallery
/// index (so each screen can be opened and compared against its Pencil design).
final screenRegistry = <String, (String, WidgetBuilder)>{
  'W10 启动页': ('/splash', (c) => const SplashScreen()),
  'W22 添加钱包': ('/add-wallet', (c) => const AddWalletScreen()),
  'W23 创建钱包安全提示': ('/create-warn', (c) => const CreateWarnScreen()),
  'W24 助记词展示': ('/mnemonic-show', (c) => const MnemonicShowScreen()),
  'W25 助记词校验': ('/mnemonic-verify', (c) => const MnemonicVerifyScreen()),
  'W26 助记词输入': ('/mnemonic-import', (c) => const MnemonicImportScreen()),
  'W11 连接离线钱包': ('/connect-cold', (c) => const ConnectColdScreen()),
  'W12 扫描账户二维码': ('/scan-account', (c) => const ScanAccountScreen()),
  'W13 导入确认': ('/import-confirm', (c) => const ImportConfirmScreen()),
  'W1/W20 首页': ('/home', (c) => HomeScreen(manager: demoManager(), assets: demoAssets)),
  'W21 钱包切换器': ('/switcher', (c) => const WalletSwitcherSheet()),
  'W27 钱包管理': ('/wallet-manage', (c) => const WalletManageScreen()),
  'W28 钱包详情编辑': ('/wallet-detail', (c) => const WalletDetailScreen()),
  'W2 资产列表': ('/assets', (c) => const AssetsListScreen()),
  'W3 Token 详情': ('/token', (c) => const TokenDetailScreen()),
  'W14 收款': ('/receive', (c) => const ReceiveScreen()),
  'W4 转账输入': ('/transfer', (c) => const TransferInputScreen()),
  'W31 手续费选择': ('/fee', (c) => const FeeSelectScreen()),
  'W5 交易确认(观察)': ('/confirm-watch', (c) => const TransferConfirmScreen(isHot: false)),
  'W29 交易确认(普通)': ('/confirm-hot', (c) => const TransferConfirmScreen(isHot: true)),
  'W30 转账身份验证': ('/transfer-auth', (c) => const TransferAuthSheet()),
  'W6 待签名二维码': ('/sign-qr', (c) => const SignRequestQrScreen()),
  'W7 扫描签名结果': ('/scan-result', (c) => const ScanResultScreen()),
  'W8 广播确认': ('/broadcast-confirm', (c) => const BroadcastConfirmScreen()),
  'W9 广播结果': ('/broadcast-result', (c) => const BroadcastResultScreen()),
  'W15 交易详情': ('/tx-detail', (c) => const TxDetailScreen()),
  'W16 地址管理': ('/address-book', (c) => const AddressBookScreen()),
  'W17 Token 管理': ('/token-manage', (c) => const TokenManageScreen()),
  'W18 网络设置': ('/network', (c) => const NetworkSettingsScreen()),
  'W19 安全设置': ('/security', (c) => const SecuritySettingsScreen()),
};

GoRouter buildRouter() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (c, s) => const _Gallery()),
        for (final entry in screenRegistry.entries)
          GoRoute(path: entry.value.$1, builder: (c, s) => entry.value.$2(c)),
      ],
    );

class _Gallery extends StatelessWidget {
  const _Gallery();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WalletColors.bg,
      appBar: AppBar(title: const Text('KT Wallet — 屏幕库'), backgroundColor: WalletColors.surface),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final entry in screenRegistry.entries)
            Card(
              color: WalletColors.surface,
              child: ListTile(
                title: Text(entry.key),
                subtitle: Text(entry.value.$1, style: const TextStyle(fontFamily: KtFonts.mono, fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go(entry.value.$1),
              ),
            ),
        ],
      ),
    );
  }
}
