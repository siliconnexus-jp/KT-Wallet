import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core_crypto/testing.dart';
import 'package:kt_wallet/main.dart';

Future<void> _open(WidgetTester tester, String galleryEntry) async {
  tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  await tester.pumpWidget(KtWalletApp(galleryCrypto: MockCoreCrypto()));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text(galleryEntry), 200);
  await tester.tap(find.text(galleryEntry));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('asset search stays readable without an inner input surface', (
    tester,
  ) async {
    await _open(tester, 'W2 资产列表');
    final finder = find.byKey(const ValueKey('assets-search-input'));
    final field = tester.widget<TextField>(finder);
    expect(field.decoration!.filled, false);
    expect(field.decoration!.hintText, isNotEmpty);
    expect(field.decoration!.enabledBorder, InputBorder.none);
    expect(field.decoration!.focusedBorder, InputBorder.none);
    await tester.enterText(finder, 'USDT');
    await tester.pumpAndSettle();
    expect(find.text('USDT'), findsWidgets);
    expect(find.text('ETH'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('mnemonic import: 导入 enables once all 12 words are typed', (
    tester,
  ) async {
    await _open(tester, 'W26 助记词输入');

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(12));

    // A valid 12-word mnemonic (words the deterministic backend accepts).
    const words = [
      'abandon',
      'ability',
      'able',
      'about',
      'above',
      'absent',
      'absorb',
      'abstract',
      'absurd',
      'abuse',
      'access',
      'accident',
    ];

    // Fill the first 11 — button still disabled.
    for (var i = 0; i < 11; i++) {
      await tester.enterText(fields.at(i), words[i]);
    }
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '导入'))
          .onPressed,
      isNull,
    );

    // Fill the last one — now enabled — and import.
    await tester.enterText(fields.at(11), words[11]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();

    // Landed home on the newly imported wallet.
    expect(find.text('导入钱包 4'), findsOneWidget);
  });

  testWidgets('address book search filters the contact list', (tester) async {
    await _open(tester, 'W16 地址管理');
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob 交易所'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'bob');
    await tester.pumpAndSettle();
    expect(find.text('Bob 交易所'), findsOneWidget);
    expect(find.text('Alice'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的联系人'), findsOneWidget);
  });
}
