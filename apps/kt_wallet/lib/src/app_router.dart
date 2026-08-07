import 'package:airgap_protocol/airgap_protocol.dart' show AccountExport;
import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

import 'market/asset_ref.dart';
import 'market/history_service.dart' show ChainTxRecord;
import 'screens/about_screen.dart';
import 'screens/approval_screen.dart';
import 'screens/assets_screens.dart';
import 'screens/backup_screens.dart';
import 'screens/camera_screen.dart';
import 'screens/home_screen.dart';
import 'screens/private_key_screens.dart';
import 'screens/settings_screens.dart';
import 'screens/transfer_screens.dart';
import 'screens/wallet_screens.dart';
import 'state/wallet_controller.dart';
import 'state/developer_mode.dart';
import 'transfer/local_transfer_service.dart';
import 'transfer/transfer_draft.dart';
import 'wallets/wallet_model.dart';

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
  'W36 账户地址': ('/wallet-addresses', (c) => const WalletAddressesScreen()),
  'W37 查看私钥': ('/private-keys', (c) => const PrivateKeyExportScreen()),
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
  'W35 Token 授权管理': ('/approvals', (c) => const TokenApprovalsScreen()),
  'W32 加密备份': ('/backup', (c) => const BackupExportScreen()),
  'W33 从备份恢复': ('/restore', (c) => const BackupRestoreScreen()),
  'W34 关于': ('/about', (c) => const AboutScreen()),
};

/// Sheet-style screens (translucent scrim over the previous screen). Pushed as
/// ordinary routes they would sit on an opaque page — the screen below never
/// renders and the 50%-alpha scrim reads as solid black. A non-opaque page
/// keeps the underlying screen visible and dimmed, matching the design.
const _sheetRoutes = {'/switcher', '/transfer-auth'};

GoRouter buildRouter({
  String initialLocation = '/',
  bool galleryMode = true,
  required WalletController walletController,
  LocalTransferService? transferService,
  TransferSession? transferSession,
}) {
  final effectiveGalleryMode = developerFixturesEnabled && galleryMode;
  return GoRouter(
    initialLocation: initialLocation,
    redirect: (context, state) => productionRouteRedirect(
      galleryMode: effectiveGalleryMode,
      uri: state.uri,
      extra: state.extra,
      walletController: walletController,
      transferSession: transferSession,
    ),
    routes: [
      GoRoute(
        path: '/',
        redirect: effectiveGalleryMode ? null : (c, s) => '/home',
        builder: (c, s) =>
            effectiveGalleryMode ? const _Gallery() : const SizedBox.shrink(),
      ),
      // Flow-only screen: deliberately outside the gallery registry so it is
      // not enumerated by the design gallery / golden tests.
      GoRoute(
        path: '/scan-address',
        builder: (c, s) => const ScanAddressScreen(),
      ),
      GoRoute(
        path: '/invalid-transfer',
        builder: (c, s) => const InvalidTransferState(),
      ),
      GoRoute(path: '/records', builder: (c, s) => const RecordsScreen()),
      for (final entry in screenRegistry.entries)
        if (_sheetRoutes.contains(entry.value.$1))
          GoRoute(
            path: entry.value.$1,
            pageBuilder: (c, s) => CustomTransitionPage(
              key: s.pageKey,
              opaque: false,
              child: entry.value.$1 == '/transfer-auth'
                  ? TransferAuthSheet(transferService: transferService)
                  : entry.value.$2(c),
              transitionsBuilder: (c, animation, _, child) =>
                  FadeTransition(opacity: animation, child: child),
            ),
          )
        else
          GoRoute(
            path: entry.value.$1,
            // Wallet-scoped detail pages accept ?id=<walletId>; import-confirm
            // accepts the decoded AccountExport from the pairing scan via
            // `extra`. Without them (gallery / goldens) they render against
            // the current design-snapshot wallet.
            builder: switch (entry.value.$1) {
              '/wallet-detail' => (c, s) => WalletDetailScreen(
                walletId: s.uri.queryParameters['id'],
              ),
              '/wallet-addresses' => (c, s) => WalletAddressesScreen(
                walletId: s.uri.queryParameters['id'],
              ),
              '/private-keys' => (c, s) => PrivateKeyExportScreen(
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
              // Receive and Send open on the asset the caller was looking at —
              // symbol AND chain. Receive used to take a bare Coin, so it landed
              // on the native coin of the right chain; Send took nothing at all.
              '/receive' => (c, s) => ReceiveScreen(
                asset: s.extra is AssetRef ? s.extra as AssetRef : null,
                initialCoin: s.extra is Coin ? s.extra as Coin : null,
              ),
              '/transfer' => (c, s) => TransferInputScreen(
                asset: s.extra is AssetRef ? s.extra as AssetRef : null,
              ),
              '/confirm-watch' => (c, s) => TransferConfirmScreen(
                isHot: false,
                transferService: transferService,
              ),
              '/confirm-hot' => (c, s) => TransferConfirmScreen(
                isHot: true,
                transferService: transferService,
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
}

/// Rejects production deep links that lack the authenticated in-memory state
/// produced by the preceding screen. The design gallery deliberately keeps
/// fixture fallbacks, but a shipped app must never turn a missing QR payload,
/// draft or signature into a plausible-looking demo wallet/transaction.
String? productionRouteRedirect({
  required bool galleryMode,
  required Uri uri,
  required WalletController walletController,
  Object? extra,
  TransferSession? transferSession,
}) {
  if (galleryMode) return null;
  final path = uri.path;
  final draft = transferSession?.draft;
  final currentWallet = walletController.current;

  // `/splash` is a design-gallery snapshot. Production startup is owned by
  // RootApp/_WalletBootstrap, so a deep link must not expose the fixture.
  if (path == '/splash') return '/home';

  // Creation screens are one authenticated in-memory transaction. Reaching
  // them through a deep link, stale browser history, or a restored route must
  // never show a fixture phrase or let an unrelated wallet be marked backed
  // up. The controller drops this state on process death, which intentionally
  // makes restored creation routes fail closed.
  if ({'/create-warn', '/mnemonic-show', '/mnemonic-verify'}.contains(path) &&
      walletController.pendingMnemonic == null) {
    return '/add-wallet';
  }

  // These destinations only make sense for an existing wallet. Home itself
  // is exempt: HomeScreen intentionally renders AddWalletScreen when the last
  // wallet was deleted.
  if (currentWallet == null &&
      {
        '/switcher',
        '/wallet-manage',
        '/wallet-detail',
        '/wallet-addresses',
        '/private-keys',
        '/assets',
        '/token',
        '/receive',
        '/transfer',
        '/records',
        '/tx-detail',
        '/approvals',
        '/backup',
      }.contains(path)) {
    return '/add-wallet';
  }

  // A requested wallet id is an identity assertion, not a hint. Falling back
  // to the current wallet would show/export/delete the wrong account while
  // the URL still names another one.
  final requestedWalletId = uri.queryParameters['id']?.trim();
  if ({'/wallet-detail', '/wallet-addresses', '/private-keys'}.contains(path) &&
      requestedWalletId != null &&
      requestedWalletId.isNotEmpty &&
      !walletController.wallets.any((w) => w.id == requestedWalletId)) {
    return '/wallet-manage';
  }

  if (path == '/private-keys') {
    if (requestedWalletId == null || requestedWalletId.isEmpty) {
      return '/wallet-manage';
    }
    final requested = walletController.wallets
        .where((wallet) => wallet.id == requestedWalletId)
        .firstOrNull;
    if (requested is! HotWallet) {
      return '/wallet-detail?id=${Uri.encodeQueryComponent(requestedWalletId)}';
    }
  }

  if (path == '/import-confirm' && extra is! AccountExport) {
    return '/connect-cold';
  }
  if (path == '/tx-detail' &&
      (uri.queryParameters['id']?.trim().isEmpty ?? true) &&
      extra is! ChainTxRecord) {
    return '/records';
  }
  if (path == '/token' && extra is! AssetRef) return '/assets';

  // W31 is a design-only fee fixture. Live fee tiers are selected on the
  // transfer page and resolved from chain state on the confirmation page.
  if (path == '/fee') return '/transfer';

  if ({
        '/confirm-watch',
        '/confirm-hot',
        '/sign-qr',
        '/transfer-auth',
      }.contains(path) &&
      draft == null) {
    return '/invalid-transfer';
  }
  if (path == '/scan-result' && transferSession?.request == null) {
    return '/invalid-transfer';
  }
  if (path == '/broadcast-confirm' &&
      (draft == null ||
          transferSession?.request == null ||
          transferSession?.result == null)) {
    return '/invalid-transfer';
  }
  if (path == '/broadcast-result' &&
      (draft == null ||
          transferSession?.localTransactionId == null ||
          transferSession?.broadcastTxHash == null)) {
    return '/invalid-transfer';
  }
  return null;
}

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
