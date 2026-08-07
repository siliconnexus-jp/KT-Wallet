import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/screens/home_screen.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:ui_kit/ui_kit.dart';

import 'support/test_wallet_scope.dart';

Widget _app({WalletController? controller, Widget home = const HomeScreen()}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: withTestWalletScope(home, controller: controller),
    );

BoxDecoration _pillDecoration(WidgetTester tester, String key) {
  final animated = find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(AnimatedContainer),
  );
  return tester.widget<AnimatedContainer>(animated).decoration!
      as BoxDecoration;
}

void main() {
  testWidgets('W1A uses the three real bottom destinations and pill states', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-search-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-scan-button')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-wallet-addresses-button')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('home-tab-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-tab-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-tab-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-tab-3')), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('home-tab-background'))).height,
      67,
    );
    final firstTab = find.byKey(const ValueKey('home-tab-0'));
    final firstTabIcon = find.descendant(
      of: firstTab,
      matching: find.byType(Icon),
    );
    final firstTabLabel = find.descendant(
      of: firstTab,
      matching: find.text('首页'),
    );
    final selectedIcon = tester.widget<Icon>(firstTabIcon);
    expect(selectedIcon.icon, Icons.account_balance_wallet_outlined);
    expect(selectedIcon.size, 28);
    expect(selectedIcon.color, Colors.black);
    expect(tester.widget<Text>(firstTabLabel).style!.fontSize, 13);
    expect(tester.widget<Text>(firstTabLabel).style!.color, Colors.black);

    final secondTab = find.byKey(const ValueKey('home-tab-1'));
    final secondTabIcon = find.descendant(
      of: secondTab,
      matching: find.byType(Icon),
    );
    final secondTabLabel = find.descendant(
      of: secondTab,
      matching: find.text('资产'),
    );
    expect(tester.widget<Icon>(secondTabIcon).color, const Color(0xFF8A8F98));
    expect(
      tester.widget<Text>(secondTabLabel).style!.color,
      const Color(0xFF8A8F98),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('home-search-surface'))).height,
      40,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('home-scan-button'))),
      const Size(48, 48),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('home-scan-surface'))),
      const Size(36, 36),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('home-category-coins'))).height,
      32,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('home-category-header'))).height,
      48,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('home-category-manage'))),
      const Size(48, 48),
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('home-category-manage-surface')),
      ),
      const Size(32, 32),
    );
    expect(find.byKey(const ValueKey('home-tab-indicator')), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('home-search-field')))
          .textAlignVertical,
      TextAlignVertical.center,
    );

    final headerBottom = tester
        .getBottomLeft(find.byKey(const ValueKey('home-wallet-header')))
        .dy;
    final balanceRow = find.byKey(const ValueKey('home-balance-amount-row'));
    final balanceAmount = find.byKey(const ValueKey('home-balance-amount'));
    final privacyButton = find.byKey(
      const ValueKey('home-balance-privacy-button'),
    );
    expect(find.text('总资产估值 (USD)'), findsNothing);
    expect(tester.getTopLeft(balanceRow).dy - headerBottom, 2);
    expect(
      tester.getTopLeft(privacyButton).dx -
          tester.getTopRight(balanceAmount).dx,
      8,
    );
    expect(
      tester.getCenter(privacyButton).dy,
      tester.getCenter(balanceAmount).dy,
    );
    expect(tester.getSize(privacyButton), const Size.square(44));
    await tester.tap(balanceAmount);
    await tester.pumpAndSettle();
    expect(find.text('••••••'), findsOneWidget);

    expect(
      _pillDecoration(tester, 'home-category-coins').color,
      WalletColors.text,
    );
    expect(
      _pillDecoration(tester, 'home-category-networks').color,
      WalletColors.bg,
    );

    await tester.tap(find.byKey(const ValueKey('home-category-networks')));
    await tester.pumpAndSettle();
    expect(
      _pillDecoration(tester, 'home-category-networks').color,
      WalletColors.text,
    );
    expect(find.text('Ethereum'), findsOneWidget);
    expect(find.text('BNB Smart Chain'), findsOneWidget);
  });

  testWidgets('wallet address sheet lists only this wallet enabled networks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('home-wallet-addresses-button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('wallet-addresses-sheet')),
      findsOneWidget,
    );
    expect(find.text('账户地址'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('wallet-address-search-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('wallet-address-alphabet-index')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('wallet-address-index-A')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('wallet-address-index-Z')),
      findsOneWidget,
    );
    for (final id in const [
      'eth-mainnet',
      'polygon-mainnet',
      'tron-mainnet',
      'sol-mainnet',
    ]) {
      expect(find.byKey(ValueKey('wallet-address-row-$id')), findsOneWidget);
    }
    for (final id in const [
      'base-mainnet',
      'arbitrum-mainnet',
      'avalanche-mainnet',
      'bnb-mainnet',
    ]) {
      expect(find.byKey(ValueKey('wallet-address-row-$id')), findsNothing);
    }

    await tester.enterText(
      find.byKey(const ValueKey('wallet-address-search-field')),
      'sol',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('wallet-address-row-sol-mainnet')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('wallet-address-row-eth-mainnet')),
      findsNothing,
    );
    await tester.enterText(
      find.byKey(const ValueKey('wallet-address-search-field')),
      '',
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('wallet-address-index-T')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ListView>(find.byKey(const ValueKey('wallet-address-list')))
          .controller!
          .offset,
      greaterThan(0),
    );
    tester
        .widget<ListView>(find.byKey(const ValueKey('wallet-address-list')))
        .controller!
        .jumpTo(0);
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('wallet-address-copy-eth-mainnet')),
    );
    await tester.pump();
    expect(clipboardText, '0xa71c8B29b3d4b79E19bE1');
    expect(find.text('地址已复制'), findsOneWidget);
  });

  testWidgets('W1B and W1C pin only the category row', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _app(
        home: HomeScreen(
          assets: [for (var i = 0; i < 12; i++) demoAssets[i % 3]],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('home-scroll-view')),
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('home-category-header')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-search-field')).hitTestable(),
      findsNothing,
    );
    expect(find.text('日常钱包').hitTestable(), findsNothing);
    expect(
      find.byKey(const ValueKey('home-tab-0')).hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('search filters the visible coin rows without fabricated data', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('home-search-field')),
      'sol',
    );
    await tester.pumpAndSettle();

    expect(find.text('Solana'), findsOneWidget);
    expect(find.text('Ethereum'), findsNothing);
    expect(find.text('USDT'), findsNothing);
  });

  testWidgets('custom category reads WalletController tokens', (tester) async {
    final controller = buildTestWalletController();
    await controller.addToken(
      symbol: 'TST',
      name: 'Test Token',
      contract: '0x1111111111111111111111111111111111111111',
      network: 'Sepolia',
    );

    await tester.pumpWidget(_app(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-category-custom')));
    await tester.pumpAndSettle();

    expect(find.text('TST'), findsOneWidget);
    expect(find.text('Test Token · Sepolia'), findsOneWidget);
  });
}
