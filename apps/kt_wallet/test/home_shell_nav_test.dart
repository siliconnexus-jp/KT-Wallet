import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/main.dart';

/// Proves the bottom tab bar switches top-level tabs and that the home backup
/// banner opens the current wallet's authenticated export instead of creating
/// another seed. (The export states themselves are exercised in
/// mnemonic_backup_safety_test.dart.)
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
    'bottom tab bar has home/assets/settings and records opens as a page',
    (tester) async {
      await _openHome(tester);

      // "记录" exists once as a home action, not as a duplicate bottom tab.
      expect(find.text('记录'), findsOneWidget);
      await tester.tap(find.text('记录'));
      await tester.pumpAndSettle();
      expect(find.text('交易记录'), findsOneWidget);
      expect(find.text('-120.00 USDT'), findsNothing);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

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
    'backup banner targets the current wallet instead of new-wallet creation',
    (tester) async {
      await _openHome(tester);

      await tester.tap(find.text('立即备份'));
      await tester.pumpAndSettle();

      expect(find.text('钱包详情'), findsOneWidget);
      expect(find.text('查看助记词'), findsOneWidget);
      expect(find.text('创建钱包'), findsNothing);
      expect(find.text('stadium'), findsNothing);
    },
  );
}
