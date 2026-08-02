import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// Expected brand values. Secondary text and status colors intentionally use
/// their WCAG-audited variants instead of the original low-contrast Pencil
/// literals; a regression here can otherwise make every screen unreadable at
/// once while still looking like a small cosmetic change.
const pencilWalletVars = <String, int>{
  'w-bg': 0xFFF5F6F8,
  'w-surface': 0xFFFFFFFF,
  'w-text': 0xFF0C1220,
  'w-text2': 0xFF566274,
  'w-text3': 0xFF5F6B7A,
  'w-accent': 0xFF2557E8,
  'w-green': 0xFF06713F,
  'w-red': 0xFFDF3E42,
  'w-amber': 0xFFB54708,
  'w-border': 0xFFE7E9EE,
};

const pencilSignerVars = <String, int>{
  'c-bg': 0xFF0A0C0F,
  'c-surface': 0xFF14171D,
  'c-surface2': 0xFF1C2027,
  'c-text': 0xFFF4F6F9,
  'c-text2': 0xFF8E97A5,
  'c-ok': 0xFF34D77B,
  'c-warn': 0xFFF5B722,
  'c-danger': 0xFFFF5A5A,
  'c-blue': 0xFF5B8DEF,
  'c-border': 0xFF262B34,
};

void main() {
  group('color tokens match Pencil variables', () {
    test('wallet palette', () {
      final actual = <String, Color>{
        'w-bg': WalletColors.bg,
        'w-surface': WalletColors.surface,
        'w-text': WalletColors.text,
        'w-text2': WalletColors.text2,
        'w-text3': WalletColors.text3,
        'w-accent': WalletColors.accent,
        'w-green': WalletColors.green,
        'w-red': WalletColors.red,
        'w-amber': WalletColors.amber,
        'w-border': WalletColors.border,
      };
      for (final entry in pencilWalletVars.entries) {
        expect(actual[entry.key], Color(entry.value), reason: entry.key);
      }
    });

    test('signer palette', () {
      final actual = <String, Color>{
        'c-bg': SignerColors.bg,
        'c-surface': SignerColors.surface,
        'c-surface2': SignerColors.surface2,
        'c-text': SignerColors.text,
        'c-text2': SignerColors.text2,
        'c-ok': SignerColors.ok,
        'c-warn': SignerColors.warn,
        'c-danger': SignerColors.danger,
        'c-blue': SignerColors.blue,
        'c-border': SignerColors.border,
      };
      for (final entry in pencilSignerVars.entries) {
        expect(actual[entry.key], Color(entry.value), reason: entry.key);
      }
    });
  });

  test('ShardProgressBar clamps fraction into [0,1]', () {
    expect(const ShardProgressBar(received: 12, total: 8).fraction, 1.0);
    expect(const ShardProgressBar(received: 0, total: 8).fraction, 0.0);
    expect(
      const ShardProgressBar(received: 2, total: 8).fraction,
      closeTo(0.25, 1e-9),
    );
  });

  testWidgets('real app chrome suppresses the design-only 9:41 status bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: KtStatusBar())),
    );
    expect(find.text('9:41'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: KtDeviceChrome(
          mockStatusBar: false,
          child: Scaffold(body: KtStatusBar()),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('9:41'),
      findsNothing,
      reason: 'the operating system owns device chrome in production',
    );
  });
}
