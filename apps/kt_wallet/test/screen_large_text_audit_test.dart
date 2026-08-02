import 'package:core_crypto/core_crypto.dart';
import 'package:core_crypto/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/app_router.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/state/wallet_scope.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:ui_kit/ui_kit.dart';

WalletController _largeTextController() => WalletController(
  WalletManager(
    initial: [
      HotWallet(
        id: 'WLT-LARGE-TEXT',
        name: 'Large Text Wallet',
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
  crypto: MockCoreCrypto(),
  allowTestBypass: true,
);

/// Whole-app 200% Dynamic Type regression gate.
///
/// Every registered production screen is rendered in a compact phone viewport
/// with a 2.0 text scale. Flutter reports RenderFlex overflow and other layout
/// failures through the test binding, while the accessibility guidelines keep
/// enlarged controls labelled and tappable. Physical-device VoiceOver and
/// TalkBack testing remains a separate release check.
void main() {
  const viewports = [
    ('compact', Size(320, 568)),
    ('phone', Size(390, 844)),
    ('landscape', Size(844, 390)),
  ];
  const evidenceRoutes = {
    '/import-confirm',
    '/home',
    '/assets',
    '/receive',
    '/transfer',
    '/address-book',
    '/security',
    '/approvals',
  };

  for (final locale in const [Locale('en'), Locale('zh'), Locale('ja')]) {
    for (final viewport in viewports) {
      for (final entry in screenRegistry.entries) {
        testWidgets(
          '${entry.key} (${locale.languageCode}, ${viewport.$1}) supports 200% text without layout failure',
          (tester) async {
            tester.view.physicalSize = viewport.$2;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            final controller = _largeTextController();
            addTearDown(controller.dispose);
            final semantics = tester.ensureSemantics();

            try {
              await tester.pumpWidget(
                MaterialApp(
                  debugShowCheckedModeBanner: false,
                  locale: locale,
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  theme: ThemeData(scaffoldBackgroundColor: WalletColors.bg),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: const TextScaler.linear(2)),
                    child: child!,
                  ),
                  home: WalletScope(
                    controller: controller,
                    child: Builder(builder: entry.value.$2),
                  ),
                ),
              );
              await tester.pump();

              await expectLater(
                tester,
                meetsGuideline(labeledTapTargetGuideline),
              );
              await expectLater(
                tester,
                meetsGuideline(androidTapTargetGuideline),
              );
              await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));

              if (viewport.$1 == 'phone' &&
                  locale.languageCode == 'en' &&
                  evidenceRoutes.contains(entry.value.$1)) {
                await tester.runAsync(() async {
                  for (final element in find.byType(Image).evaluate()) {
                    await precacheImage(
                      (element.widget as Image).image,
                      element,
                    );
                  }
                });
                await tester.pump();
                final slug = entry.value.$1.substring(1);
                await expectLater(
                  find.byType(MaterialApp),
                  matchesGoldenFile('goldens/large-text/$slug.png'),
                );
              }
            } finally {
              semantics.dispose();
            }
          },
        );
      }
    }
  }
}
