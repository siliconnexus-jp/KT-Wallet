import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/main.dart';

Future<void> _open(WidgetTester tester, String galleryEntry) async {
  tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  await tester.pumpWidget(KtWalletApp());
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text(galleryEntry), 200);
  await tester.ensureVisible(find.text(galleryEntry));
  await tester.pumpAndSettle();
  await tester.tap(find.text(galleryEntry));
  await tester.pumpAndSettle();
}

Finder _sheetField(int index) => find
    .descendant(of: find.byType(BottomSheet), matching: find.byType(TextField))
    .at(index);

void main() {
  testWidgets('address book: "+" validates the address and appends a contact', (
    tester,
  ) async {
    await _open(tester, 'W16 地址管理');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('添加联系人'), findsOneWidget);

    // A non-chain address is rejected with an inline error.
    await tester.enterText(_sheetField(0), 'Carol');
    await tester.enterText(_sheetField(1), 'not-an-address');
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('不是有效的链地址'), findsOneWidget);
    expect(find.text('添加联系人'), findsOneWidget); // sheet stays open

    // A valid TRON address saves and the row inherits the TRON tag.
    await tester.enterText(
      _sheetField(1),
      'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('添加联系人'), findsNothing); // sheet closed
    expect(find.text('Carol'), findsOneWidget);
    expect(find.text('TRON'), findsWidgets);
  });

  testWidgets('token manage: "+" appends an enabled token row', (tester) async {
    await _open(tester, 'W17 Token 管理');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('添加代币'), findsOneWidget);

    await tester.enterText(_sheetField(0), 'LINK');
    await tester.enterText(_sheetField(1), 'Chainlink');
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('添加代币'), findsNothing); // sheet closed
    expect(find.text('LINK'), findsOneWidget);
    expect(find.text('Chainlink'), findsOneWidget);
  });
}
