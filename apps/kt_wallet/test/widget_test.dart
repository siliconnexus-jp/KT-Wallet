import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/main.dart';

void main() {
  testWidgets('boots into the screen gallery', (tester) async {
    tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(KtWalletApp());
    await tester.pumpAndSettle();
    expect(find.text('KT Wallet — 屏幕库'), findsOneWidget);
    // First gallery entry is on-screen (list is lazy).
    expect(find.text('W10 启动页'), findsOneWidget);
  });
}
