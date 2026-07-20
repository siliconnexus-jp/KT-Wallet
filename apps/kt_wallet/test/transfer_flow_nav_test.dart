import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/main.dart';

/// Walks the full transfer navigation, proving the screens are wired into one
/// flow driven by the current wallet type.
Future<void> _open(WidgetTester tester, String galleryEntry) async {
  tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  await tester.pumpWidget(KtWalletApp());
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text(galleryEntry), 200);
  await tester.tap(find.text(galleryEntry));
  await tester.pumpAndSettle();
}

Future<void> _openHome(WidgetTester tester) => _open(tester, 'W1/W20 首页');

void main() {
  testWidgets('hot wallet: home → transfer → confirm → auth → result → home',
      (tester) async {
    await _openHome(tester);
    // Default wallet 日常钱包 is hot.
    await tester.tap(find.text('转账'));
    await tester.pumpAndSettle();
    expect(find.text('USDT'), findsWidgets); // transfer input

    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    // Hot confirm shows 确认转账.
    expect(find.text('确认转账'), findsOneWidget);

    await tester.tap(find.text('确认转账'));
    await tester.pumpAndSettle();
    expect(find.text('验证以确认转账'), findsOneWidget); // auth sheet

    await tester.tap(find.text('使用 Face ID 验证'));
    await tester.pumpAndSettle();
    expect(find.text('交易已提交'), findsOneWidget); // result

    await tester.tap(find.text('返回首页'));
    await tester.pumpAndSettle();
    expect(find.text('日常钱包'), findsOneWidget); // back on home
  });

  testWidgets('watch wallet: transfer confirm generates a sign-request QR',
      (tester) async {
    await _openHome(tester);
    // Switch to the watch wallet (主钱包).
    await tester.tap(find.text('日常钱包'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('主钱包').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('转账'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    // Watch confirm shows the air-gap button, not local sign.
    expect(find.text('生成待签名二维码'), findsOneWidget);

    await tester.tap(find.text('生成待签名二维码'));
    await tester.pumpAndSettle();
    expect(find.text('待签名交易'), findsOneWidget); // W6 QR screen
  });

  testWidgets('token detail: send opens the transfer input screen',
      (tester) async {
    await _open(tester, 'W3 Token 详情');
    await tester.tap(find.text('转账'));
    await tester.pumpAndSettle();
    expect(find.text('收款地址'), findsOneWidget); // W4 transfer input
  });

  testWidgets('token detail: receive opens the receive screen',
      (tester) async {
    await _open(tester, 'W3 Token 详情');
    await tester.tap(find.text('收款'));
    await tester.pumpAndSettle();
    expect(find.text('TQm9xPa2Wc8hJdU5eRnT6yGb1sVb7L3kFa'), findsOneWidget); // W14 receive
  });
}
