import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/main.dart';
import 'package:ui_kit/ui_kit.dart';

Future<void> _open(WidgetTester tester, String galleryEntry) async {
  tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  await tester.pumpWidget(KtWalletApp());
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text(galleryEntry), 200);
  await tester.tap(find.text(galleryEntry));
  await tester.pumpAndSettle();
}

bool _nextEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, '下一步')).onPressed != null;

void main() {
  testWidgets('transfer input validates address and amount before 下一步',
      (tester) async {
    await _open(tester, 'W4 转账输入');

    // Fields: [address, amount]. Defaults are valid → enabled.
    final fields = find.byType(TextField);
    expect(_nextEnabled(tester), isTrue);

    // Wrong-network (EVM) address is rejected as a mispaste.
    await tester.enterText(fields.at(0), '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed');
    await tester.pumpAndSettle();
    expect(_nextEnabled(tester), isFalse);

    // Restore a valid TRON address.
    await tester.enterText(fields.at(0), 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t');
    await tester.pumpAndSettle();
    expect(_nextEnabled(tester), isTrue);

    // Amount over the available balance shows 余额不足 and disables 下一步.
    await tester.enterText(fields.at(1), '9999');
    await tester.pumpAndSettle();
    expect(find.text('余额不足'), findsOneWidget);
    expect(_nextEnabled(tester), isFalse);

    // A within-balance amount re-enables it.
    await tester.enterText(fields.at(1), '10.5');
    await tester.pumpAndSettle();
    expect(_nextEnabled(tester), isTrue);
  });

  testWidgets('navbar scan opens the mock camera and fills a valid address',
      (tester) async {
    await _open(tester, 'W4 转账输入');

    // Clear the prefilled address so the scan result is unambiguous.
    await tester.enterText(find.byType(TextField).at(0), '');
    await tester.pumpAndSettle();
    expect(_nextEnabled(tester), isFalse);

    // Navbar scanner icon opens the address scanner screen.
    await tester.tap(find.byIcon(Icons.qr_code_scanner).first);
    await tester.pumpAndSettle();
    expect(find.text('扫描地址二维码'), findsOneWidget);

    // Tapping the viewfinder simulates a successful scan and pops the address.
    await tester.tap(find.byIcon(Icons.qr_code_2));
    await tester.pumpAndSettle();
    expect(find.text('TQm9xPa2Wc8hJdU5eRnT6yGb1sVbAgQs8D'), findsOneWidget);
    expect(find.text('地址格式正确 · TRON 网络'), findsOneWidget);
    expect(_nextEnabled(tester), isTrue);
  });

  testWidgets('token selector switches chain, symbol and available balance',
      (tester) async {
    await _open(tester, 'W4 转账输入');
    expect(find.text('地址格式正确 · TRON 网络'), findsOneWidget);

    // Open the asset sheet from the token card and pick ETH.
    await tester.tap(find.text('TRON · TRC-20'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ETH'));
    await tester.pumpAndSettle();

    // The TRON address is now a wrong-network paste for Ethereum.
    expect(find.text('地址格式正确 · TRON 网络'), findsNothing);
    expect(_nextEnabled(tester), isFalse);
    // Symbol and balance follow the selected asset.
    expect(find.text('可用 0.0842 ETH'), findsOneWidget);
    expect(find.text('ETH'), findsWidgets);

    // A valid Ethereum address is accepted again on the new chain.
    await tester.enterText(find.byType(TextField).at(0), '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed');
    await tester.pumpAndSettle();
    expect(find.text('地址格式正确 · Ethereum 网络'), findsOneWidget);
  });

  testWidgets('custom fee screen result maps back onto the segmented tier',
      (tester) async {
    await _open(tester, 'W4 转账输入');
    expect(tester.widget<KtSegmented>(find.byType(KtSegmented)).selected, 1);

    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();
    expect(find.text('确认手续费'), findsOneWidget);

    // Pick the fast tier and confirm; the transfer screen mirrors it.
    await tester.tap(find.text('快'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认手续费'));
    await tester.pumpAndSettle();
    expect(tester.widget<KtSegmented>(find.byType(KtSegmented)).selected, 2);
  });
}
