import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/screens/home_screen.dart';
import 'package:kt_wallet/src/widgets/liquid_glass.dart';

import 'support/test_wallet_scope.dart';

void main() {
  for (final locale in ['zh', 'en', 'ja']) {
    testWidgets('$locale glass tabs fit compact large text and safe area', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: withTestWalletScope(
              MediaQuery(
                data: const MediaQueryData(
                  textScaler: TextScaler.linear(2),
                  padding: EdgeInsets.only(bottom: 34),
                ),
                child: const HomeScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final index in [1, 2, 0]) {
          final tab = find.byKey(ValueKey('home-tab-$index'));
          expect(tester.getSize(tab).height, greaterThanOrEqualTo(48));
          await tester.tap(tab);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (index == 2) {
            await tester.drag(
              find.byType(ListView).hitTestable().first,
              const Offset(0, -1800),
            );
            await tester.pumpAndSettle();
            final lastSetting = find.text(
              AppLocalizations.of(tester.element(tab)).settingsAbout,
            );
            expect(
              tester.getBottomLeft(lastSetting).dy,
              lessThan(
                tester
                    .getTopLeft(
                      find.byKey(const ValueKey('home-tab-background')),
                    )
                    .dy,
              ),
            );
          }
        }
        final rect = tester.getRect(
          find.byKey(const ValueKey('home-tab-background')),
        );
        expect(rect.left, 20);
        expect(rect.bottom, closeTo(568 - 34 - 12, .01));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('opaque contrast fallback, reduced motion and RTL selection', (
    tester,
  ) async {
    var selected = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return MediaQuery(
              data: const MediaQueryData(
                highContrast: true,
                disableAnimations: true,
              ),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(
                  bottomNavigationBar: LiquidWalletTabs(
                    items: const [
                      ('Home', Icons.home_outlined),
                      ('Assets', Icons.toll_outlined),
                      ('Settings', Icons.settings_outlined),
                    ],
                    selected: selected,
                    onSelected: (index) => update(() => selected = index),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsNothing);
    final indicator = find.byKey(const ValueKey('home-tab-indicator'));
    expect(
      tester.getCenter(indicator).dx,
      closeTo(
        tester.getCenter(find.byKey(const ValueKey('home-tab-0'))).dx,
        .01,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('home-tab-2')));
    await tester.pump();
    expect(selected, 2);
    expect(
      tester.widget<AnimatedAlign>(find.byType(AnimatedAlign)).duration,
      Duration.zero,
    );
    expect(
      tester.getCenter(indicator).dx,
      closeTo(
        tester.getCenter(find.byKey(const ValueKey('home-tab-2'))).dx,
        .01,
      ),
    );
  });

  testWidgets('glass tabs expose keyboard navigation', (tester) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: LiquidWalletTabs(
            items: const [
              ('Home', Icons.home),
              ('Assets', Icons.toll),
              ('Settings', Icons.settings),
            ],
            selected: selected,
            onSelected: (index) => selected = index,
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(selected, 1);
  });

  // Optional local visual evidence uses only the explicit design fixture,
  // never a real wallet or production storage. No host font is required in CI.
  testWidgets('home and retained destinations render visual evidence', (
    tester,
  ) async {
    final output = Platform.environment['KT_UI_QA_OUTPUT'];
    final fontPath = Platform.environment['KT_UI_QA_FONT'];
    if (output != null && fontPath != null) {
      await tester.runAsync(() async {
        final loader = FontLoader('QA');
        loader.addFont(
          File(
            fontPath,
          ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
        await loader.load();
        for (final (family, asset) in [
          ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
          (
            'packages/cupertino_icons/CupertinoIcons',
            'packages/cupertino_icons/assets/CupertinoIcons.ttf',
          ),
          ('JetBrains Mono', 'fonts/JetBrainsMono.ttf'),
          ('monospace', 'fonts/JetBrainsMono.ttf'),
          ('Inter', 'fonts/Inter.ttf'),
        ]) {
          final assetFont = FontLoader(family)..addFont(rootBundle.load(asset));
          await assetFont.load();
        }
      });
    }
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(fontFamily: fontPath == null ? null : 'QA'),
        home: RepaintBoundary(
          key: boundary,
          child: withTestWalletScope(const HomeScreen()),
        ),
      ),
    );
    for (final index in [0, 1, 2]) {
      await tester.tap(find.byKey(ValueKey('home-tab-$index')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        for (final element in find.byType(Image).evaluate()) {
          await precacheImage((element.widget as Image).image, element);
        }
      });
      await tester.pump();
      expect(tester.takeException(), isNull);
      if (output != null) {
        await tester.runAsync(() async {
          final raster =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final data = await raster.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$output/tab-$index.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          raster.dispose();
        });
      }
    }
  });
}
