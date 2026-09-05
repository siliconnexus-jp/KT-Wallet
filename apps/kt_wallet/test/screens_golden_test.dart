import 'dart:io';
import 'dart:ui' as ui;

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/app_router.dart';
import 'package:kt_wallet/src/screens/home_screen.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/state/wallet_scope.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:ui_kit/ui_kit.dart';

/// Renders every registered screen at phone size and captures a golden, so any
/// overflow / broken layout is caught. Run with --update-goldens to refresh.
void main() {
  final evidence = Platform.environment['KT_GLASS_QA_OUTPUT'];
  final fontPath = Platform.environment['KT_UI_QA_FONT'];
  var fontsLoaded = false;
  final galleryController = WalletController(
    WalletManager(
      initial: [
        HotWallet(
          id: 'WLT-91A4C7',
          name: '日常钱包',
          avatarColor: 0xFFF59E0B,
          addresses: const ChainAddresses(
            eth: '0xa71c8B29b3d4b79E19bE1',
            polygon: '0xa71c8B29b3d4b79E19bE1',
            tron: 'TQm9xPa2Wc8hJdU5eRnT6yGb1sVb7L3kFa',
            solana: 'ayKpXwMWd4qmDqVr2W',
          ),
          backedUp: false,
        ),
      ],
    ),
    allowTestBypass: true,
  );
  const standalonePreviewRoutes = {'/mnemonic-show', '/mnemonic-verify'};
  final previews = {
    ...screenRegistry,
    '活动空状态': (
      '/activity',
      (BuildContext context) => const Scaffold(
        backgroundColor: Colors.transparent,
        body: KtWalletBackdrop(child: RecordsScreen(tabbed: true)),
      ),
    ),
  };
  for (final entry in previews.entries) {
    final slug = entry.value.$1.replaceAll('/', '');
    testWidgets('screen ${entry.key} renders at 390x844', (tester) async {
      if (evidence != null && fontPath != null && !fontsLoaded) {
        await tester.runAsync(() async {
          final font = FontLoader('Inter')
            ..addFont(File(fontPath).readAsBytes().then(ByteData.sublistView));
          await font.load();
          for (final (family, asset) in [
            ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
            (
              'packages/cupertino_icons/CupertinoIcons',
              'packages/cupertino_icons/assets/CupertinoIcons.ttf',
            ),
            ('JetBrains Mono', 'fonts/JetBrainsMono.ttf'),
            ('monospace', 'fonts/JetBrainsMono.ttf'),
          ]) {
            await (FontLoader(family)..addFont(rootBundle.load(asset))).load();
          }
        });
        fontsLoaded = true;
      }
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ktWalletTheme(),
            home: standalonePreviewRoutes.contains(entry.value.$1)
                ? Builder(builder: entry.value.$2)
                : WalletScope(
                    controller: galleryController,
                    child: Builder(builder: entry.value.$2),
                  ),
          ),
        ),
      );
      await tester.pump();

      // Asset images (token icons) decode asynchronously; precache them so
      // goldens capture the rendered logos instead of blank placeholders.
      await tester.runAsync(() async {
        for (final element in find.byType(Image).evaluate()) {
          await precacheImage((element.widget as Image).image, element);
        }
      });
      await tester.pump();

      if (evidence != null) {
        await tester.pump(const Duration(milliseconds: 400));
        await tester.runAsync(() async {
          final raster =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1);
          final data = await raster.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$evidence/$slug.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          raster.dispose();
        });
      } else {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/screens/$slug.png'),
        );
      }
    });
  }
}
