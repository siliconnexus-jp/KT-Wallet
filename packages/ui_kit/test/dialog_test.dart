import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

Widget _harness({
  required ValueChanged<bool?> onResult,
  AppTheme theme = AppTheme.wallet,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: ThemeData(fontFamily: KtFonts.ui),
  home: Builder(
    builder: (context) => Scaffold(
      backgroundColor: theme.bg,
      body: Center(
        child: FilledButton(
          onPressed: () async {
            onResult(
              await showDialog<bool>(
                context: context,
                builder: (_) => KtConfirmDialog(
                  title: '确认替换交易',
                  message: '将使用相同 nonce 和更高网络费重新发送。原收款地址与金额不会改变。',
                  cancelLabel: '取消',
                  confirmLabel: '确认',
                  theme: theme,
                  icon: Icons.bolt_rounded,
                  details: const Text('Nonce 7 · Amount 0.001 ETH'),
                ),
              ),
            );
          },
          child: const Text('Open'),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('confirm dialog returns the selected result', (tester) async {
    bool? result;
    await tester.pumpWidget(_harness(onResult: (value) => result = value));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('kt-dialog')), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);

    await tester.tap(find.byKey(const ValueKey('kt-dialog-confirm')));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('action gives subtle press feedback', (tester) async {
    await tester.pumpWidget(_harness(onResult: (_) {}));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final action = find.byKey(const ValueKey('kt-dialog-confirm'));
    final gesture = await tester.startGesture(tester.getCenter(action));
    await tester.pump();
    final scale = tester.widget<AnimatedScale>(
      find.descendant(of: action, matching: find.byType(AnimatedScale)),
    );
    expect(scale.scale, 0.97);
    expect(scale.duration, const Duration(milliseconds: 120));

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('wallet confirmation dialog golden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_harness(onResult: (_) {}));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/wallet_dialog.png'),
    );
  });

  testWidgets('signer theme uses the shared branded surface', (tester) async {
    await tester.pumpWidget(_harness(onResult: (_) {}, theme: AppTheme.signer));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final materials = tester.widgetList<Material>(
      find.descendant(
        of: find.byKey(const ValueKey('kt-dialog')),
        matching: find.byType(Material),
      ),
    );
    expect(
      materials.any((material) => material.color == SignerColors.surface),
      isTrue,
    );
  });
}
