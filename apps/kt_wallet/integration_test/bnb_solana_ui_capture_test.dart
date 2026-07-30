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

const _walletId = 'bnb-solana-ui-capture-v1';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'capture BNB Testnet, PYUSD Devnet ATA and JUP production UI',
    (tester) async {
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
      final addresses = await crypto.deriveAddresses(_walletId);
      final wallets = WalletController(
        WalletManager(
          initial: [
            HotWallet(
              id: _walletId,
              name: 'BNB / Solana 实测钱包',
              avatarColor: 0xFFF3BA2F,
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

      if (Platform.isAndroid) {
        await binding.convertFlutterSurfaceToImage();
      }
      await tester.pumpWidget(
        KtWalletApp(
          controller: wallets,
          networkController: networks,
          initialLocation: '/home',
        ),
      );
      await _waitUntil(
        tester,
        () => find.text('BNB / Solana 实测钱包').evaluate().isNotEmpty,
      );
      final market = MarketScope.read(
        tester.element(find.byType(Scaffold).first),
      )!;
      await tester.runAsync(market.refresh);
      await tester.pumpAndSettle();
      await _capture(binding, tester, '01-testnet-home');

      await _openTransfer(
        tester,
        AssetRef.native(
          coin: Coin.bnb,
          name: 'BNB',
          symbol: 'BNB',
          network: 'BNB Smart Chain',
        ),
      );
      await _waitUntil(
        tester,
        () => find.text('BNB Smart Chain Testnet').evaluate().isNotEmpty,
      );
      await _capture(binding, tester, '02-bnb-testnet-transfer');
      GoRouter.of(tester.element(find.byType(Scaffold).first)).pop();
      await tester.pumpAndSettle();

      await _openTransfer(tester, AssetRef.token(pyusdSolanaDevnetToken));
      await _waitUntil(tester, () => find.text('Devnet').evaluate().isNotEmpty);
      await _capture(binding, tester, '03-pyusd-devnet-transfer');
      GoRouter.of(tester.element(find.byType(Scaffold).first)).pop();
      await tester.pumpAndSettle();

      await networks.setEnvironment(NetworkEnvironment.mainnet);
      await tester.pumpAndSettle();
      await _openTransfer(tester, AssetRef.token(jupSolanaToken));
      await _waitUntil(
        tester,
        () =>
            find.text('JUP').evaluate().isNotEmpty &&
            find.text('Solana').evaluate().isNotEmpty,
      );
      await _capture(binding, tester, '04-jup-mainnet-transfer');
      // Keep the app container alive long enough for the host test runner to
      // collect the final screenshot before `flutter test` uninstalls the app.
      // ignore: avoid_print
      print('UI_EVIDENCE READY=all');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 20)),
      );
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

Future<void> _openTransfer(WidgetTester tester, AssetRef asset) async {
  final context = tester.element(find.byType(Navigator).first);
  unawaited(GoRouter.of(context).push('/transfer', extra: asset));
  await tester.pumpAndSettle();
}

Future<void> _capture(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
) async {
  final prefix = Platform.isIOS ? 'ios' : 'android';
  final fileName = '$prefix-$name';
  final png = await binding.takeScreenshot(fileName);
  final path = '${Directory.systemTemp.path}/$fileName.png';
  await File(path).writeAsBytes(png, flush: true);
  // ignore: avoid_print
  print('UI_EVIDENCE FILE=$path');
  await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 8)));
}

Future<void> _waitUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 35),
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
