import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/main.dart';

/// Proves the home "更多" quick action opens the shortcuts sheet and its
/// entries navigate to the right screens.
Future<void> _openHome(WidgetTester tester) async {
  tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  await tester.pumpWidget(KtWalletApp(initialLocation: '/home'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'more sheet lists the three shortcuts and opens the address book',
    (tester) async {
      await _openHome(tester);

      await tester.tap(find.text('更多'));
      await tester.pumpAndSettle();

      // The sheet lists 连接离线钱包 / 地址簿 / 钱包管理. (钱包管理 and 地址簿 also
      // exist offstage in the settings tab, hence `findsWidgets` + `.last`.)
      expect(find.text('连接离线钱包'), findsOneWidget);
      expect(find.text('地址簿'), findsWidgets);
      expect(find.text('钱包管理'), findsWidgets);

      await tester.tap(find.text('地址簿').last);
      await tester.pumpAndSettle();
      expect(find.text('地址管理'), findsOneWidget); // W16 address book
    },
  );

  testWidgets('more sheet opens the connect-cold flow', (tester) async {
    await _openHome(tester);

    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('连接离线钱包'));
    await tester.pumpAndSettle();
    expect(find.text('扫描账户二维码'), findsOneWidget); // W11 connect cold
  });
}
