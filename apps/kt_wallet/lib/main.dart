import 'package:core_crypto/core_crypto.dart';
import 'package:core_crypto/testing.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

import 'src/app_router.dart';
import 'src/data/database_provider.dart';
import 'src/state/wallet_controller.dart';
import 'src/state/wallet_scope.dart';
import 'src/wallets/wallet_manager.dart';
import 'src/wallets/wallet_model.dart';
import 'src/wallets/wallet_store.dart';

/// Production entrypoint: opens the on-device drift database, wires a
/// persistent [WalletStore] (deterministic [MockCoreCrypto] backend where
/// wallet-core is unavailable), loads saved wallets (seeding a starter set on
/// first run), and launches straight into the wallet home.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = openWalletDatabase();
  final crypto = MockCoreCrypto();
  final store = WalletStore(db);

  var manager = await store.load();
  if (manager.count == 0) {
    await _seedFirstRun(crypto, store);
    manager = await store.load();
  }

  final controller =
      WalletController(manager, crypto: crypto, store: store);
  runApp(KtWalletApp(controller: controller, initialLocation: '/home'));
}

ChainAddresses _addr(String seed) => ChainAddresses(
      eth: '0x${seed}71c8B29b3d4b79E19bE1',
      polygon: '0x${seed}71c8B29b3d4b79E19bE1',
      tron: 'T${seed}Pa2Wc8hJdU5eRnT6yGb1sVb7L3kFa',
      solana: '${seed}yKpXwMWd4qmDqVr2W',
    );

/// First launch: one real hot wallet (mnemonic generated + addresses derived)
/// plus one watch wallet, persisted, so the app opens to a populated home.
Future<void> _seedFirstRun(CoreCrypto crypto, WalletStore store) async {
  final id = 'daily';
  final mnemonic = await crypto.generateMnemonic();
  await crypto.storeWallet(walletId: id, mnemonic: mnemonic);
  final addresses = await crypto.deriveAddresses(id);
  await store.save(HotWallet(
    id: id,
    name: '日常钱包',
    avatarColor: 0xFFF59E0B,
    addresses: addresses,
    sortOrder: 0,
    backedUp: true,
  ));
  await store.save(WatchWallet(
    id: 'cold',
    name: '主钱包',
    avatarColor: 0xFF0C1220,
    addresses: _addr('c'),
    sortOrder: 1,
    coldWalletId: 'WLT-3E8A91',
    protocolVersion: 1,
  ));
}

/// In-memory demo controller for the design gallery and widget tests (no
/// persistence). The 日常钱包 stays un-backed-up so the backup banner/flow is
/// exercisable.
WalletController _seedController() => WalletController(WalletManager(initial: [
      HotWallet(id: 'daily', name: '日常钱包', avatarColor: 0xFFF59E0B, addresses: _addr('a'), backedUp: false),
      HotWallet(id: 'savings', name: '储蓄钱包', avatarColor: 0xFF8B5CF6, addresses: _addr('b'), sortOrder: 1, backedUp: true),
      WatchWallet(id: 'cold', name: '主钱包', avatarColor: 0xFF0C1220, addresses: _addr('c'), sortOrder: 2, coldWalletId: 'WLT-3E8A91', protocolVersion: 1),
    ]));

class KtWalletApp extends StatelessWidget {
  KtWalletApp({super.key, WalletController? controller, String initialLocation = '/'})
      : _controller = controller ?? _seedController(),
        _router = buildRouter(initialLocation: initialLocation);

  final GoRouter _router;
  final WalletController _controller;

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
