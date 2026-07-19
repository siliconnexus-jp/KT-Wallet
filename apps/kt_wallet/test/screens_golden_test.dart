import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/app_router.dart';
import 'package:ui_kit/ui_kit.dart';

/// Renders every registered screen at phone size and captures a golden, so any
/// overflow / broken layout is caught. Run with --update-goldens to refresh.
void main() {
  for (final entry in screenRegistry.entries) {
    final slug = entry.value.$1.replaceAll('/', '');
    testWidgets('screen ${entry.key} renders at 390x844', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(scaffoldBackgroundColor: WalletColors.bg),
        home: Builder(builder: entry.value.$2),
      ));
      await tester.pump();

      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/screens/$slug.png'));
    });
  }
}
