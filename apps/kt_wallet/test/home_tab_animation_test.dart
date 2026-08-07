import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/screens/home_screen.dart';

import 'support/test_wallet_scope.dart';

Widget _app({bool reduceMotion = false}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: withTestWalletScope(
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: const HomeScreen(),
    ),
  ),
);

AnimatedOpacity _tabOpacity(WidgetTester tester, int index) => tester
    .widget<AnimatedOpacity>(find.byKey(ValueKey('home-tab-opacity-$index')));

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('tab change animates the page without an extra top indicator', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-tab-indicator')), findsNothing);
    expect(_tabOpacity(tester, 0).opacity, 1);
    expect(_tabOpacity(tester, 1).opacity, 0);

    await tester.tap(find.byKey(const ValueKey('home-tab-1')));
    await tester.pump();

    expect(_tabOpacity(tester, 0).opacity, 0);
    expect(_tabOpacity(tester, 1).opacity, 1);
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pumpAndSettle();
    expect(find.text('资产'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid tab changes retarget without waiting for completion', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('home-tab-1')));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.byKey(const ValueKey('home-tab-0')));
    await tester.pumpAndSettle();

    expect(_tabOpacity(tester, 0).opacity, 1);
    expect(_tabOpacity(tester, 1).opacity, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('page change crossfades without directional travel', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('home-tab-2')));
    await tester.pump();

    expect(find.byKey(const ValueKey('home-tab-slide-0')), findsNothing);
    expect(find.byKey(const ValueKey('home-tab-slide-2')), findsNothing);
    expect(_tabOpacity(tester, 2).duration, const Duration(milliseconds: 140));

    await tester.pumpAndSettle();
    expect(find.text('设置'), findsWidgets);
  });

  testWidgets('reduced motion keeps only a short fade', (tester) async {
    await tester.pumpWidget(_app(reduceMotion: true));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('home-tab-2')));
    await tester.pump();

    expect(_tabOpacity(tester, 2).duration, const Duration(milliseconds: 100));

    await tester.pumpAndSettle();
    expect(find.text('设置'), findsWidgets);
  });
}
