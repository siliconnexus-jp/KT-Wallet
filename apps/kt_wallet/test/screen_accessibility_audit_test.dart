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

WalletController _galleryController() => WalletController(
  WalletManager(
    initial: [
      HotWallet(
        id: 'WLT-A11Y',
        name: 'Accessibility Wallet',
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

/// Broad automated accessibility gate for every registered KT Wallet screen.
///
/// This complements, but does not replace, physical-device VoiceOver and
/// TalkBack testing. Flutter's guidelines catch unlabeled controls, undersized
/// touch targets and insufficient text contrast before a screen can regress
/// unnoticed.
void main() {
  const viewports = [
    ('compact', Size(320, 568)),
    ('phone', Size(390, 844)),
    ('landscape', Size(844, 390)),
  ];
  for (final locale in const [Locale('en'), Locale('zh'), Locale('ja')]) {
    for (final viewport in viewports) {
      for (final entry in screenRegistry.entries) {
        testWidgets(
          '${entry.key} (${locale.languageCode}, ${viewport.$1}) meets automated accessibility guidelines',
          (tester) async {
            tester.view.physicalSize = viewport.$2;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            final controller = _galleryController();
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
              await expectLater(tester, meetsGuideline(textContrastGuideline));
            } finally {
              semantics.dispose();
            }
          },
        );
      }
    }
  }
}
