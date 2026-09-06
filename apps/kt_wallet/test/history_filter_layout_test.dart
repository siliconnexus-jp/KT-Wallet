import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/screens/home_screen.dart';
import 'package:ui_kit/ui_kit.dart';

import 'support/test_wallet_scope.dart';

void main() {
  final type = find.byKey(const ValueKey('history-type-filter-button'));
  final network = find.byKey(const ValueKey('history-network-filter-button'));
  for (final locale in ['zh', 'en', 'ja']) {
    for (final width in [320.0, 390.0, 600.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('$locale history filters at width $width scale $scale', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              theme: ktWalletTheme(),
              locale: Locale(locale),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: withTestWalletScope(
                  const Scaffold(body: RecordsScreen(tabbed: true)),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final typeRect = tester.getRect(type);
          final networkRect = tester.getRect(network);
          expect(typeRect.height, greaterThanOrEqualTo(48));
          expect(networkRect.height, greaterThanOrEqualTo(48));
          final stacked = find
              .byKey(const ValueKey('history-filter-stacked'))
              .evaluate()
              .isNotEmpty;
          if (stacked) {
            expect(typeRect.left, networkRect.left);
            expect(typeRect.width, networkRect.width);
            expect(networkRect.top, greaterThan(typeRect.bottom));
          } else {
            expect(typeRect.height, closeTo(networkRect.height, .01));
            expect(typeRect.top, networkRect.top);
            expect(typeRect.bottom, networkRect.bottom);
          }
          if (locale == 'ja' && width == 390 && scale == 1) {
            expect(stacked, false);
            expect(find.text('全タイプ'), findsOneWidget);
            expect(find.text('全ネットワーク'), findsOneWidget);
          }
          for (final control in [type, network]) {
            for (final paragraph
                in find
                    .descendant(of: control, matching: find.byType(RichText))
                    .evaluate()) {
              expect(
                (paragraph.renderObject! as RenderParagraph).didExceedMaxLines,
                false,
              );
            }
          }
          expect(tester.takeException(), isNull);
          await tester.tap(type);
          await tester.pumpAndSettle();
          final l10n = AppLocalizations.of(tester.element(type));
          expect(find.text(l10n.historyTypeFilterTitle), findsOneWidget);
          Navigator.of(
            tester.element(find.text(l10n.historyTypeFilterTitle)),
          ).pop();
          await tester.pumpAndSettle();
          await tester.tap(network);
          await tester.pumpAndSettle();
          expect(find.text(l10n.historyNetworkFilterTitle), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
