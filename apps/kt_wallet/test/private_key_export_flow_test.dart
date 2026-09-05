import 'package:core_crypto/core_crypto.dart';
import 'package:core_crypto/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/main.dart';
import 'package:kt_wallet/src/market/market_controller.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';

const _mnemonic =
    'abandon ability able about above absent absorb abstract absurd abuse access accident';

Future<WalletController> _controller() async {
  final crypto = MockCoreCrypto();
  await crypto.storeWallet(walletId: 'w1', mnemonic: _mnemonic);
  final derived = await crypto.deriveAddresses('w1');
  final controller = WalletController(WalletManager(), crypto: crypto);
  await controller.add(
    HotWallet(
      id: 'w1',
      name: '账户 01',
      avatarColor: 0xFF2557E8,
      addresses: ChainAddresses(
        eth: derived.eth,
        polygon: derived.polygon,
        base: derived.base,
        arbitrum: derived.arbitrum,
        avalanche: derived.avalanche,
        bnb: derived.bnb,
        tron: derived.tron,
        solana: derived.solana,
      ),
      backedUp: true,
    ),
  );
  return controller;
}

Future<void> _pump(WidgetTester tester, WalletController controller) async {
  tester.platformDispatcher.localesTestValue = const [Locale('zh')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  // This suite exercises export, not market refresh. Keep the TRON status
  // deterministic instead of racing a failed HTTP request in the goldens.
  final market = MarketController(wallets: controller, canRefresh: () => false);
  addTearDown(market.dispose);
  await tester.pumpWidget(
    KtWalletApp(
      controller: controller,
      marketController: market,
      initialLocation: '/private-keys?id=w1',
    ),
  );
  await tester.pump();
}

Future<void> _openDirectory(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('private-key-warning-primary')));
  await tester.pumpAndSettle();
}

Future<void> _precacheDirectoryIcons(WidgetTester tester) async {
  final context = tester.element(
    find.byKey(const ValueKey('private-key-directory-screen')),
  );
  await tester.runAsync(() async {
    for (final asset in const [
      'eth',
      'matic',
      'base',
      'arb',
      'avax',
      'bnb',
      'sol',
      'trx',
    ]) {
      await precacheImage(AssetImage('assets/tokens/$asset.png'), context);
    }
  });
  await tester.pump();
}

void main() {
  testWidgets(
    'one concise risk notice gates authentication without a countdown',
    (tester) async {
      final controller = await _controller();
      await _pump(tester, controller);

      expect(find.text('查看前请注意'), findsOneWidget);
      expect(find.text('我已了解，继续'), findsOneWidget);
      expect(find.textContaining('请注意 1/3'), findsNothing);
      expect(
        tester
            .widget<KtPrimaryButton>(
              find.byKey(const ValueKey('private-key-warning-primary')),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        find.byKey(const ValueKey('private-key-directory-screen')),
        findsNothing,
      );
      await _openDirectory(tester);

      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('private-key-directory-screen')),
        findsOneWidget,
      );
      expect(find.text('账户 01'), findsOneWidget);
      expect(find.text('EVM 网络'), findsOneWidget);
      expect(find.text('Solana'), findsOneWidget);
      expect(find.text('TRON'), findsOneWidget);
      for (final id in [
        'eth-mainnet',
        'polygon-mainnet',
        'base-mainnet',
        'arbitrum-mainnet',
        'avalanche-mainnet',
        'bnb-mainnet',
      ]) {
        expect(find.byKey(ValueKey('private-key-network-$id')), findsOneWidget);
      }
      expect(find.text('ETH'), findsNothing);
      expect(find.text('POL'), findsNothing);
    },
  );

  testWidgets('secure and full copy follow the OKX confirmation flow', (
    tester,
  ) async {
    final controller = await _controller();
    await _pump(tester, controller);

    await _openDirectory(tester);

    await tester.tap(find.byKey(const ValueKey('private-key-expand-evm')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('private-key-concealed-evm')),
      findsOneWidget,
    );
    expect(find.text('请确保周围没有其他人及摄像头'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('private-key-safe-copy-evm')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('private-key-safe-copy-sheet')),
      findsOneWidget,
    );
    for (var index = 0; index < 6; index++) {
      expect(find.byKey(ValueKey('private-key-suffix-$index')), findsOneWidget);
    }
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(find.text('已安全复制'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('private-key-full-copy-evm')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('private-key-full-copy-sheet')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('private-key-full-copy-confirm')),
    );
    await tester.pump();
    expect(find.textContaining('完整私钥已复制'), findsOneWidget);
  });

  testWidgets('concealed panel toggles the native private-key view', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final controller = await _controller();
      await _pump(tester, controller);
      await _openDirectory(tester);

      await tester.tap(find.byKey(const ValueKey('private-key-expand-evm')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('private-key-concealed-evm')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('private-key-reveal-evm')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('private-key-revealed-evm')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('private-key-native-eth')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('private-key-reveal-evm')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('private-key-concealed-evm')),
        findsOneWidget,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'OKX-aligned directory and copy sheets match controlled goldens',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = await _controller();
      await _pump(tester, controller);
      await _openDirectory(tester);
      await _precacheDirectoryIcons(tester);

      await tester.tap(find.byKey(const ValueKey('private-key-expand-evm')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/private-key/private-key-directory-expanded.png',
        ),
      );

      await tester.tap(find.byKey(const ValueKey('private-key-safe-copy-evm')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/private-key/private-key-safe-copy.png'),
      );
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('private-key-full-copy-evm')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/private-key/private-key-full-copy.png'),
      );
    },
  );
}
