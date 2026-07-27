import 'package:airgap_protocol/airgap_protocol.dart' show AccountExport;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

import 'market/asset_ref.dart';
import 'market/history_service.dart' show ChainTxRecord;
import 'screens/assets_screens.dart';
import 'screens/camera_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screens.dart';
import 'screens/transfer_screens.dart';
import 'screens/wallet_screens.dart';

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
  'W1/W20 首页': ('/home', (c) => const HomeScreen()),
  'W21 钱包切换器': ('/switcher', (c) => const WalletSwitcherSheet()),
  'W27 钱包管理': ('/wallet-manage', (c) => const WalletManageScreen()),
  'W28 钱包详情编辑': ('/wallet-detail', (c) => const WalletDetailScreen()),
  'W2 资产列表': ('/assets', (c) => const AssetsListScreen()),
  'W3 Token 详情': ('/token', (c) => const TokenDetailScreen()),
  'W14 收款': ('/receive', (c) => const ReceiveScreen()),
  'W4 转账输入': ('/transfer', (c) => const TransferInputScreen()),
  'W31 手续费选择': ('/fee', (c) => const FeeSelectScreen()),
  'W5 交易确认(观察)': (
    '/confirm-watch',
    (c) => const TransferConfirmScreen(isHot: false),
  ),
  'W29 交易确认(普通)': (
    '/confirm-hot',
    (c) => const TransferConfirmScreen(isHot: true),
  ),
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

/// Sheet-style screens (translucent scrim over the previous screen). Pushed as
/// ordinary routes they would sit on an opaque page — the screen below never
/// renders and the 50%-alpha scrim reads as solid black. A non-opaque page
/// keeps the underlying screen visible and dimmed, matching the design.
const _sheetRoutes = {'/switcher', '/transfer-auth'};

GoRouter buildRouter({String initialLocation = '/'}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(path: '/', builder: (c, s) => const _Gallery()),
    // Flow-only screen: deliberately outside the gallery registry so it is
    // not enumerated by the design gallery / golden tests.
    GoRoute(
      path: '/scan-address',
      builder: (c, s) => const ScanAddressScreen(),
    ),
    for (final entry in screenRegistry.entries)
      if (_sheetRoutes.contains(entry.value.$1))
        GoRoute(
          path: entry.value.$1,
          pageBuilder: (c, s) => CustomTransitionPage(
            key: s.pageKey,
            opaque: false,
            child: entry.value.$2(c),
            transitionsBuilder: (c, animation, _, child) =>
                FadeTransition(opacity: animation, child: child),
          ),
        )
      else
        GoRoute(
          path: entry.value.$1,
          // Wallet detail accepts ?id=<walletId> when pushed from the manage
          // list; import-confirm accepts the decoded AccountExport from the
          // pairing scan via `extra`. Without them (gallery / goldens) both
          // render their demo snapshots.
          builder: switch (entry.value.$1) {
            '/wallet-detail' => (c, s) => WalletDetailScreen(
              walletId: s.uri.queryParameters['id'],
            ),
            '/import-confirm' => (c, s) => ImportConfirmScreen(
              export: s.extra is AccountExport
                  ? s.extra as AccountExport
                  : null,
            ),
            '/tx-detail' => (c, s) => TxDetailScreen(
              transactionId: s.uri.queryParameters['id'],
              // On-chain rows with no local counterpart travel as `extra`.
              chainRecord: s.extra is ChainTxRecord
                  ? s.extra as ChainTxRecord
                  : null,
            ),
            // The tapped asset rides in `extra`. Without it the screen used to
            // render one hardcoded token for every row; now a live scope with
            // no asset says so instead.
            '/token' => (c, s) => TokenDetailScreen(
              asset: s.extra is AssetRef ? s.extra as AssetRef : null,
            ),
            // Live W12: the registry (gallery + goldens) keeps the
            // design-snapshot ScanAccountScreen; actual navigation gets
            // the camera-enabled variant, which renders identically when
            // no camera is available.
            '/scan-account' => (c, s) => const ScanAccountCameraScreen(),
            _ => (c, s) => entry.value.$2(c),
          },
        ),
  ],
);

class _Gallery extends StatelessWidget {
  const _Gallery();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WalletColors.bg,
      appBar: AppBar(
        title: const Text('KT Wallet — 屏幕库'),
        backgroundColor: WalletColors.surface,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final entry in screenRegistry.entries)
            Card(
              color: WalletColors.surface,
              child: ListTile(
                title: Text(entry.key),
                subtitle: Text(
                  entry.value.$1,
                  style: const TextStyle(
                    fontFamily: KtFonts.mono,
                    fontSize: 12,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go(entry.value.$1),
              ),
            ),
        ],
      ),
    );
  }
}
