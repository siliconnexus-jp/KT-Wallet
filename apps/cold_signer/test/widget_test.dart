import 'package:cold_signer/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('boots into the signer screen gallery', (tester) async {
    await tester.pumpWidget(ColdSignerApp());
    await tester.pumpAndSettle();
    expect(find.text('KT Wallet Cold Signer — 屏幕库'), findsOneWidget);
    expect(find.text('C11 启动页'), findsOneWidget);
  });
}
