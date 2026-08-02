import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/app_router.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/state/wallet_scope.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:ui_kit/ui_kit.dart';

/// Renders every registered screen at phone size and captures a golden, so any
/// overflow / broken layout is caught. Run with --update-goldens to refresh.
void main() {
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
  for (final entry in screenRegistry.entries) {
    final slug = entry.value.$1.replaceAll('/', '');
    testWidgets('screen ${entry.key} renders at 390x844', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(scaffoldBackgroundColor: WalletColors.bg),
          home: standalonePreviewRoutes.contains(entry.value.$1)
              ? Builder(builder: entry.value.$2)
              : WalletScope(
                  controller: galleryController,
                  child: Builder(builder: entry.value.$2),
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

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/screens/$slug.png'),
      );
    });
  }
}
