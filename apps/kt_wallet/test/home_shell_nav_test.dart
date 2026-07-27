import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/main.dart';

/// Proves the bottom tab bar switches top-level tabs and that the home backup
/// banner cannot walk an existing wallet through a fake backup. (The quiz
/// itself is exercised on the create-onboarding path, the only flow that has a
/// real phrase in hand — see mnemonic_backup_safety_test.dart.)
Future<void> _openHome(WidgetTester tester) async {
  tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  await tester.pumpWidget(KtWalletApp());
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text('W1/W20 首页'), 200);
  await tester.tap(find.text('W1/W20 首页'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'bottom tab bar switches between home / assets / records / settings',
    (tester) async {
      await _openHome(tester);

      // Records tab (tab-bar label is the last '记录' match; the home action row
      // also has one).
      await tester.tap(find.text('记录').last);
      await tester.pumpAndSettle();
      expect(find.text('交易记录'), findsOneWidget);

      // Settings tab.
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      expect(find.text('安全设置'), findsOneWidget);

      // Back to home tab.
      await tester.tap(find.text('首页'));
      await tester.pumpAndSettle();
      expect(find.text('立即备份'), findsOneWidget); // home backup banner
    },
  );

  testWidgets(
    'backup flow: banner → warn → show refuses for an existing wallet',
    (tester) async {
      // This path has no pending mnemonic (the wallet already exists), so there
      // is no phrase to display. It used to render the design-gallery constant
      // and walk the user through "verifying" it, then mark the wallet backed
      // up — recording a phrase that unlocks nothing.
      await _openHome(tester);

      await tester.tap(find.text('立即备份'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('显示助记词'));
      await tester.pumpAndSettle();

      expect(find.text('无法显示助记词'), findsOneWidget);
      expect(find.text('stadium'), findsNothing); // demo phrase not rendered
      // No route onward to the quiz, so markBackedUp cannot be reached.
      expect(find.text('我已手写备份，开始校验'), findsNothing);
    },
  );
}
