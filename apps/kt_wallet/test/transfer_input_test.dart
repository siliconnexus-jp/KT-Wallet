import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/main.dart';

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
}
