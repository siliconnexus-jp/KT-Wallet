import 'package:cold_signer/l10n/app_localizations.dart';
import 'package:cold_signer/src/signer_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// Renders every Cold Signer screen at phone size to catch overflow / broken
/// layout. Run with --update-goldens to refresh.
void main() {
  for (final entry in signerRegistry.entries) {
    final slug = entry.value.$1.replaceAll('/', '');
    testWidgets('signer ${entry.key} renders at 390x844', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: SignerColors.bg),
        home: Builder(builder: entry.value.$2),
      ));
      await tester.pump();

      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/screens/$slug.png'));
    });
  }
}
