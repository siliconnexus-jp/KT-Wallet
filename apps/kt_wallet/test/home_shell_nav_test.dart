import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/main.dart';

/// Proves the bottom tab bar switches top-level tabs and that the backup
/// verification quiz gates on the correct word before marking the wallet
/// backed up.
Future<void> _openHome(WidgetTester tester) async {
  await tester.pumpWidget(KtWalletApp());
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text('W1/W20 首页'), 200);
  await tester.tap(find.text('W1/W20 首页'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('bottom tab bar switches between home / assets / records / settings',
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
  });

  testWidgets('backup flow: banner → warn → show → verify wrong then right → home',
      (tester) async {
    await _openHome(tester);

    await tester.tap(find.text('立即备份'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示助记词'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我已手写备份，开始校验'));
    await tester.pumpAndSettle();
    expect(find.text('第 4 个单词是？'), findsOneWidget);

    // Wrong answer keeps us on the quiz.
    await tester.tap(find.text('fossil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(find.text('第 4 个单词是？'), findsOneWidget);

    // Let the feedback SnackBar clear so it no longer overlays the button.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // Correct answer (4th word of the demo mnemonic) returns home.
    await tester.tap(find.text('stadium'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    // Banner is gone because the wallet is now backed up.
    expect(find.text('日常钱包'), findsOneWidget);
    expect(find.text('立即备份'), findsNothing);
  });
}
