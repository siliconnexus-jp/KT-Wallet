import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/main.dart';
import 'package:kt_wallet/src/market/token_balance_service.dart'
    show usdtEthToken;

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

  // A typo in a name or an address used to mean delete and re-enter: the
  // "⋮" menu only offered copy and delete.
  testWidgets('address book: a contact can be edited in place', (tester) async {
    await _open(tester, 'W16 地址管理');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(_sheetField(0), 'Crol'); // typo on purpose
    await tester.enterText(
      _sheetField(1),
      'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('Crol'), findsOneWidget);

    // The gallery seeds demo contacts; the new row is appended last.
    await tester.tap(find.byIcon(Icons.more_vert).last);
    await tester.pumpAndSettle();
    expect(find.text('编辑'), findsOneWidget);
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    // The sheet opens pre-filled with the contact being edited.
    expect(find.text('编辑联系人'), findsOneWidget);
    expect(tester.widget<TextField>(_sheetField(0)).controller!.text, 'Crol');

    await tester.enterText(_sheetField(0), 'Carol');
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('编辑联系人'), findsNothing);
    expect(find.text('Carol'), findsOneWidget);
    // Edited in place — not appended as a second row.
    expect(find.text('Crol'), findsNothing);
  });

  testWidgets('address book: editing the address re-detects the chain', (
    tester,
  ) async {
    await _open(tester, 'W16 地址管理');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(_sheetField(0), 'Dave');
    await tester.enterText(
      _sheetField(1),
      'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('TRON'), findsWidgets);

    await tester.tap(find.byIcon(Icons.more_vert).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    await tester.enterText(
      _sheetField(1),
      '0x71C7656EC7ab88b098defB751B7401B5f6d8976F',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('Ethereum'), findsWidgets);
  });

  testWidgets('token manage: "+" appends an enabled token row', (tester) async {
    await _open(tester, 'W17 Token 管理');
    expect(find.text('搜索币种名称、符号或合约地址'), findsOneWidget);
    expect(find.byIcon(Icons.verified_rounded), findsWidgets);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('添加代币'), findsOneWidget);

    await tester.enterText(_sheetField(0), 'KTT');
    await tester.enterText(_sheetField(1), 'KT Test Token');
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('添加代币'), findsNothing); // sheet closed
    expect(find.text('KTT'), findsOneWidget);
    expect(find.text('KT Test Token'), findsOneWidget);
  });

  testWidgets('token manage search filters by symbol, name, and contract', (
    tester,
  ) async {
    await _open(tester, 'W17 Token 管理');
    final search = find.widgetWithText(TextField, '搜索币种名称、符号或合约地址');

    await tester.enterText(search, 'UNI');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('UNI'), findsWidgets);
    expect(find.text('USDT'), findsNothing);

    await tester.enterText(search, usdtEthToken.contract);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('USDT'), findsWidgets);
    expect(find.byIcon(Icons.verified_rounded), findsWidgets);
  });

  testWidgets('token manage warns when a custom contract claims USDT', (
    tester,
  ) async {
    await _open(tester, 'W17 Token 管理');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.enterText(_sheetField(0), 'USDT');
    await tester.enterText(_sheetField(1), 'Cheap Tether');
    await tester.enterText(
      _sheetField(2),
      '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('此合约不在 KT Wallet 验证的官方 USDT 地址列表中'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('此合约不在 KT Wallet 验证的官方 USDT 地址列表中'),
      findsOneWidget,
    );
  });
}
