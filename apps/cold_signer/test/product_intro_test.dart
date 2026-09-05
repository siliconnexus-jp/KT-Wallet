import 'package:cold_signer/src/onboarding/product_intro_app.dart';
import 'package:cold_signer/src/state/locale_controller.dart';
import 'package:cold_signer/src/widgets/signer_brand_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart';

void main() {
  for (final language in ['zh', 'en', 'ja']) {
    testWidgets('introduction supports $language and persists independently', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'wallet.productIntro.v1': true});
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      Widget intro() => SignerIntroApp(
        localeController: LocaleController(initial: Locale(language)),
        child: const MaterialApp(home: Text('signer setup')),
      );
      await tester.pumpWidget(intro());
      await tester.pumpAndSettle();
      expect(find.byType(KtProductIntro), findsOneWidget);
      expect(find.byType(SignerBrandMark), findsOneWidget);
      for (var page = 0; page < 3; page++) {
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('intro-next')));
        await tester.pumpAndSettle();
      }
      expect(find.text('signer setup'), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          signerIntroCompletedKey,
        ),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(intro());
      await tester.pumpAndSettle();
      expect(find.text('signer setup'), findsOneWidget);
    });
  }
}
