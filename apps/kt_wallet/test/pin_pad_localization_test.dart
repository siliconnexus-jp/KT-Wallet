import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/widgets/pin_pad.dart';

void main() {
  for (final entry in const <(Locale, String)>[
    (Locale('en'), 'Delete last digit'),
    (Locale('zh'), '删除最后一位'),
    (Locale('ja'), '最後の桁を削除'),
  ]) {
    testWidgets('PIN delete key follows ${entry.$1.languageCode}', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          locale: entry.$1,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: PinPad(onKey: (_) {})),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel(entry.$2), findsOneWidget);
      semantics.dispose();
    });
  }
}
