import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    bool contrast = false,
    bool accessible = false,
  }) => tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          highContrast: contrast,
          accessibleNavigation: accessible,
        ),
        child: Scaffold(
          body: Center(child: SizedBox(width: 260, height: 120, child: child)),
        ),
      ),
    ),
  );

  testWidgets('content cards do not allocate backdrop filters', (tester) async {
    await pump(tester, const KtGlassSurface(child: Text('12.34 ETH')));
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('12.34 ETH'), findsOneWidget);
  });

  testWidgets('floating glass bounds its blur to the clipped surface', (
    tester,
  ) async {
    await pump(
      tester,
      const KtGlassSurface(blur: true, child: Text('Networks')),
    );
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byType(BackdropFilter),
        matching: find.byType(ClipRRect),
      ),
      findsOneWidget,
    );
    expect(tester.getSize(find.byType(BackdropFilter)), const Size(260, 120));
  });

  testWidgets('contrast and accessible navigation remove transparency', (
    tester,
  ) async {
    const surface = KtGlassSurface(blur: true, child: Text('Confirm'));
    for (final contrast in [true, false]) {
      await pump(tester, surface, contrast: contrast, accessible: !contrast);
      expect(find.byType(BackdropFilter), findsNothing);
      final decorations = tester.widgetList<DecoratedBox>(
        find.descendant(
          of: find.byType(KtGlassSurface),
          matching: find.byType(DecoratedBox),
        ),
      );
      final fill = decorations
          .map((w) => w.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.gradient != null);
      expect((fill.gradient! as LinearGradient).colors, [
        Colors.white,
        Colors.white,
      ]);
    }
  });

  testWidgets('press feedback never activates a cancelled touch', (
    tester,
  ) async {
    var calls = 0;
    await pump(
      tester,
      KtPrimaryButton(label: 'Confirm', onPressed: () => calls++),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(FilledButton)),
    );
    await tester.pump(const Duration(milliseconds: 130));
    expect(calls, 0);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.tap(find.byType(FilledButton));
    expect(calls, 1);
  });
}
