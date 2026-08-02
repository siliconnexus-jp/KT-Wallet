import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

Widget _host(Widget child, {double textScale = 1, bool reduceMotion = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: reduceMotion,
      ),
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('navigation exposes a named back action and heading', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _host(KtNavBar(title: 'Confirm transfer', onBack: () {})),
    );

    expect(find.byTooltip('Back'), findsOneWidget);
    final heading = tester.getSemantics(find.text('Confirm transfer'));
    expect(heading.flagsCollection.isHeader, isTrue);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  });

  testWidgets('detail row is one meaningful reading unit', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _host(const KtDetailRow(label: 'Network', value: 'Sepolia')),
    );

    expect(find.bySemanticsLabel('Network, Sepolia'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('detail row stacks instead of clipping at large text', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const KtDetailRow(
          label: 'Recipient address',
          value: '0x1234567890abcdef1234567890abcdef12345678',
          mono: true,
        ),
        textScale: 2,
      ),
    );

    final row = find.byType(KtDetailRow);
    expect(
      find.descendant(of: row, matching: find.byType(Column)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('primary button removes decorative motion when requested', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const KtPrimaryButton(label: 'Sending', loading: true),
        reduceMotion: true,
      ),
    );

    for (final opacity in tester.widgetList<AnimatedOpacity>(
      find.descendant(
        of: find.byType(KtPrimaryButton),
        matching: find.byType(AnimatedOpacity),
      ),
    )) {
      expect(opacity.duration, Duration.zero);
    }
    final scale = tester.widget<AnimatedScale>(
      find.descendant(
        of: find.byType(KtPrimaryButton),
        matching: find.byType(AnimatedScale),
      ),
    );
    expect(scale.duration, Duration.zero);
  });
}
