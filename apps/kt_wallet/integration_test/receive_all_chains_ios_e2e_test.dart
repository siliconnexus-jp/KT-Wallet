import 'dart:async';
import 'dart:io';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/main.dart';
import 'package:kt_wallet/src/state/networks.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:ui_kit/ui_kit.dart';

const _walletId = 'receive-all-chains-ios-e2e-v1';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'shows and verifies receive QR flows for every supported testnet',
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
      final addresses = await crypto.deriveAddresses(_walletId);
      final wallets = WalletController(
        WalletManager(
          initial: [
            HotWallet(
              id: _walletId,
              name: 'iOS 全链收款钱包',
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
        () => find.text('iOS 全链收款钱包').evaluate().isNotEmpty,
      );
      await tester.tap(find.text('收款'));
      await tester.pumpAndSettle();
      expect(find.text('收款'), findsWidgets);

      final scenarios = [
        (coin: Coin.tron, picker: 'TRON', pill: 'USDT · TRON', slug: 'tron'),
        (
          coin: Coin.eth,
          picker: 'Ethereum',
          pill: 'ETH · Ethereum',
          slug: 'ethereum',
        ),
        (
          coin: Coin.polygon,
          picker: 'Polygon',
          pill: 'POL · Polygon',
          slug: 'polygon',
        ),
        (coin: Coin.base, picker: 'Base', pill: 'ETH · Base', slug: 'base'),
        (
          coin: Coin.arbitrum,
          picker: 'Arbitrum One',
          pill: 'ETH · Arbitrum',
          slug: 'arbitrum',
        ),
        (
          coin: Coin.avalanche,
          picker: 'Avalanche C-Chain',
          pill: 'AVAX · Avalanche',
          slug: 'avalanche',
        ),
        (
          coin: Coin.bnb,
          picker: 'BNB Smart Chain',
          pill: 'BNB · BNB Smart Chain',
          slug: 'bnb',
        ),
        (
          coin: Coin.solana,
          picker: 'Solana',
          pill: 'SOL · Solana',
          slug: 'solana',
        ),
      ];

      var currentPill = scenarios.first.pill;
      for (final scenario in scenarios) {
        if (scenario.pill != currentPill) {
          await tester.tap(find.text(currentPill));
          await tester.pumpAndSettle();
          await tester.tap(find.text(scenario.picker));
          await tester.pumpAndSettle();
          currentPill = scenario.pill;
        }

        final address = addresses.forCoin(scenario.coin);
        expect(find.text(scenario.pill), findsOneWidget);
        expect(find.text(address), findsOneWidget);
        expect(tester.widget<KtQrCode>(find.byType(KtQrCode)).data, address);
        await _capture(binding, tester, 'receive-${scenario.slug}');

        await tester.tap(find.byKey(const ValueKey('receive-copy')));
        await _waitUntil(
          tester,
          () => find.text('地址已复制').evaluate().isNotEmpty,
        );
      }

      final save = find.byKey(const ValueKey('receive-save-image'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await _waitUntil(
        tester,
        () => find.text('已保存到相册').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 90),
      );
      await _capture(binding, tester, 'receive-card-saved');

      // ignore: avoid_print
      print('RECEIVE_ALL_CHAINS_IOS READY=all');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 20)),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<void> _capture(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
) async {
  final fileName = 'ios-$name';
  final bytes = await binding.takeScreenshot(fileName);
  final path = '${Directory.systemTemp.path}/$fileName.png';
  await File(path).writeAsBytes(bytes, flush: true);
  // Public receive addresses and QR codes only.
  // ignore: avoid_print
  print('RECEIVE_ALL_CHAINS_IOS FILE=$path');
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 900)),
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
