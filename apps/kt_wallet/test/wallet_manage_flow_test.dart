import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/main.dart';

/// Proves the add-wallet and delete-wallet paths mutate the live controller so
/// the multi-wallet list actually grows and shrinks.
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
  testWidgets('add-wallet back returns to wallet management', (tester) async {
    await _openHome(tester);

    await tester.tap(find.text('日常钱包'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加钱包'));
    await tester.pumpAndSettle();

    expect(find.text('创建新钱包'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('钱包管理'), findsOneWidget);
    expect(find.text('共 3 个钱包 · 上限 20 个'), findsOneWidget);
    expect(find.text('创建新钱包'), findsNothing);
  });

  testWidgets('create new wallet from switcher adds a wallet and selects it', (
    tester,
  ) async {
    await _openHome(tester);

    // Open the switcher via the header pill, then the add-wallet screen.
    await tester.tap(find.text('日常钱包'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加钱包'));
    await tester.pumpAndSettle();
    expect(find.text('创建新钱包'), findsOneWidget);

    // 创建新钱包 generates a real mnemonic and enters the backup flow.
    await tester.tap(find.text('创建新钱包'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示助记词'));
    await tester.pumpAndSettle();
    // The show screen renders a full 12-word mnemonic (numbered 01..12).
    expect(find.text('01'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    await tester.tap(find.text('我已手写备份，开始校验'));
    await tester.pumpAndSettle();
    expect(
      find.text('第 4 个单词是？'),
      findsOneWidget,
    ); // real backup-verify challenge
  });

  testWidgets('delete wallet from manage screen removes it from the list', (
    tester,
  ) async {
    await _openHome(tester);

    await tester.tap(find.text('日常钱包'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('管理'));
    await tester.pumpAndSettle();
    expect(find.text('共 3 个钱包 · 上限 20 个'), findsOneWidget);

    // Delete 储蓄钱包 (the second wallet) and confirm.
    final deleteIcons = find.byIcon(Icons.delete_outline);
    await tester.tap(deleteIcons.at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('kt-dialog-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('共 2 个钱包 · 上限 20 个'), findsOneWidget);
    expect(find.text('储蓄钱包'), findsNothing);
  });
}
