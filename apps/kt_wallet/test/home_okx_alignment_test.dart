import 'package:flutter/material.dart';
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
