import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/main.dart';

void main() {
  testWidgets('boots into the screen gallery', (tester) async {
    await tester.pumpWidget(KtWalletApp());
    await tester.pumpAndSettle();
    expect(find.text('KT Wallet — 屏幕库'), findsOneWidget);
    // First gallery entry is on-screen (list is lazy).
    expect(find.text('W10 启动页'), findsOneWidget);
  });
}
