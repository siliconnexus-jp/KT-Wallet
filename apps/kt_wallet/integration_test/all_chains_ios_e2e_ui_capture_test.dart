import 'support/e2e_credential_batch.dart';
import 'support/e2e_wallet_cleanup.dart';

import 'dart:async';
import 'dart:io';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/main.dart';
import 'package:kt_wallet/src/market/asset_ref.dart';
import 'package:kt_wallet/src/market/market_scope.dart';
import 'package:kt_wallet/src/market/token_balance_service.dart';
import 'package:kt_wallet/src/state/networks.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';

const _walletId = 'all-chains-ios-e2e-ui-v1';

final _nativeAssets = <(String, AssetRef)>[
  (
    'ethereum',
    AssetRef.native(
      coin: Coin.eth,
      name: 'Ethereum',
      symbol: 'ETH',
      network: 'Sepolia',
    ),
  ),
  (
    'polygon',
    AssetRef.native(
      coin: Coin.polygon,
      name: 'Polygon',
      symbol: 'POL',
      network: 'Amoy',
    ),
  ),
  (
    'base',
    AssetRef.native(
      coin: Coin.base,
      name: 'Base',
      symbol: 'ETH',
      network: 'Base Sepolia',
    ),
  ),
  (
    'arbitrum',
    AssetRef.native(
      coin: Coin.arbitrum,
      name: 'Arbitrum',
      symbol: 'ETH',
      network: 'Arbitrum Sepolia',
    ),
  ),
  (
    'avalanche',
    AssetRef.native(
      coin: Coin.avalanche,
      name: 'Avalanche',
      symbol: 'AVAX',
      network: 'Avalanche Fuji',
    ),
  ),
  (
    'bnb',
    AssetRef.native(
      coin: Coin.bnb,
      name: 'BNB Smart Chain',
      symbol: 'BNB',
      network: 'BNB Smart Chain Testnet',
    ),
  ),
  (
    'tron',
    AssetRef.native(
      coin: Coin.tron,
      name: 'TRON',
      symbol: 'TRX',
      network: 'Nile',
    ),
  ),
  (
    'solana',
    AssetRef.native(
      coin: Coin.solana,
      name: 'Solana',
      symbol: 'SOL',
      network: 'Devnet',
    ),
  ),
];

final _stableAssets = <(String, AssetRef)>[
  ('ethereum-usdt', AssetRef.token(usdtSepoliaToken)),
  ('polygon-usdc', AssetRef.token(usdcPolygonAmoyToken)),
  ('base-usdc', AssetRef.token(usdcBaseSepoliaToken)),
  ('arbitrum-usdc', AssetRef.token(usdcArbitrumSepoliaToken)),
  ('avalanche-usdc', AssetRef.token(usdcAvalancheFujiToken)),
  ('bnb-busd', AssetRef.token(busdBnbTestnetToken)),
  ('tron-usdt', AssetRef.token(usdtTronNileToken)),
  ('solana-usdc', AssetRef.token(usdcSolanaDevnetToken)),
];

void main() {
  requireFreshE2eCredentialBatchIfConfigured();
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'capture live iOS testnet UI for every supported chain and history',
    (tester) async {
      expect(Platform.isIOS, isTrue);
      const mnemonic = String.fromEnvironment('SEPOLIA_E2E_MNEMONIC');
      expect(mnemonic, isNotEmpty);
      tester.platformDispatcher.localesTestValue = const [Locale('zh')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      final crypto = MethodChannelCoreCrypto();
      await crypto.storeWallet(
        walletId: _walletId,
        mnemonic: mnemonic,
        requireAuth: false,
      );
      registerE2eWalletCleanup(crypto, _walletId);
      final addresses = await crypto.deriveAddresses(_walletId);
      final wallets = WalletController(
        WalletManager(
          initial: [
            HotWallet(
              id: _walletId,
              name: 'iOS 全链 E2E 钱包',
              avatarColor: 0xFF5570D8,
              addresses: addresses,
              backedUp: true,
            ),
          ],
        ),
        crypto: crypto,
      );
      final networks = NetworkController(
        initialEnvironment: NetworkEnvironment.testnet,
      );

      await tester.pumpWidget(
        KtWalletApp(
          controller: wallets,
          networkController: networks,
          initialLocation: '/home',
        ),
      );
      await _waitUntil(
        tester,
        () => find.text('iOS 全链 E2E 钱包').evaluate().isNotEmpty,
      );
      await networks.setEnvironment(NetworkEnvironment.testnet);
      await tester.pumpAndSettle();

      final market = MarketScope.read(
        tester.element(find.byType(Scaffold).first),
      )!;
      await tester.runAsync(market.refresh);
      await tester.pumpAndSettle();
      await _capture(binding, tester, '01-live-testnet-home');

      const captureOnly = String.fromEnvironment('E2E_UI_ASSET');
      if (captureOnly.isNotEmpty) {
        final requested = [
          for (final (slug, asset) in _nativeAssets) ('native-$slug', asset),
          for (final (slug, asset) in _stableAssets) ('stable-$slug', asset),
        ].where((entry) => entry.$1 == captureOnly).toList();
        expect(requested, hasLength(1), reason: 'unknown E2E_UI_ASSET');
        await _captureTransfer(
          binding,
          tester,
          requested.single.$2,
          requested.single.$1,
        );
        // ignore: avoid_print
        print('ALL_CHAINS_IOS_UI READY=$captureOnly');
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 60)),
        );
        return;
      }

      for (final (slug, asset) in _nativeAssets) {
        await _captureTransfer(binding, tester, asset, 'native-$slug');
      }
      for (final (slug, asset) in _stableAssets) {
        await _captureTransfer(binding, tester, asset, 'stable-$slug');
      }

      expect(find.text('记录'), findsOneWidget);
      await tester.tap(find.text('记录'));
      await _waitUntil(tester, () => find.text('交易记录').evaluate().isNotEmpty);
      await _waitUntil(
        tester,
        () => find
            .byKey(const ValueKey('history-loading-skeleton'))
            .evaluate()
            .isEmpty,
        timeout: const Duration(seconds: 90),
      );
      await _capture(binding, tester, '18-live-wallet-history');

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      await _openAsset(tester, AssetRef.token(usdcBaseSepoliaToken));
      await _waitUntil(
        tester,
        () => find.byKey(const ValueKey('asset-history')).evaluate().isNotEmpty,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('asset-history')));
      await _waitUntil(
        tester,
        () => find
            .byKey(const ValueKey('history-loading-skeleton'))
            .evaluate()
            .isEmpty,
        timeout: const Duration(seconds: 90),
      );
      await _capture(binding, tester, '19-base-usdc-live-history');

      // Give the host runner time to copy the final PNG before uninstalling.
      // ignore: avoid_print
      print('ALL_CHAINS_IOS_UI READY=all');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 20)),
      );
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

Future<void> _captureTransfer(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  AssetRef asset,
  String slug,
) async {
  final context = tester.element(find.byType(Navigator).first);
  unawaited(GoRouter.of(context).push('/transfer', extra: asset));
  await _waitUntil(
    tester,
    () =>
        find.text(asset.symbol).evaluate().isNotEmpty &&
        find.text('收款地址').evaluate().isNotEmpty,
  );
  await _capture(binding, tester, slug);
  GoRouter.of(tester.element(find.byType(Scaffold).first)).pop();
  await tester.pumpAndSettle();
}

Future<void> _openAsset(WidgetTester tester, AssetRef asset) async {
  final context = tester.element(find.byType(Navigator).first);
  unawaited(GoRouter.of(context).push('/token', extra: asset));
  await tester.pumpAndSettle();
}

Future<void> _capture(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
) async {
  final fileName = 'ios-$name';
  final png = await binding.takeScreenshot(fileName);
  final path = '${Directory.systemTemp.path}/$fileName.png';
  await File(path).writeAsBytes(png, flush: true);
  // Public addresses, balances and transaction rows only.
  // ignore: avoid_print
  print('ALL_CHAINS_IOS_UI FILE=$path');
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 750)),
  );
}

Future<void> _waitUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 45),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('UI condition was not reached');
    }
    await tester.pump(const Duration(milliseconds: 250));
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
}
