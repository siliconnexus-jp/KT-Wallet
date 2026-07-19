import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/main.dart';

void main() {
  testWidgets('renders the home screen for the seeded wallet', (tester) async {
    await tester.pumpWidget(const KtWalletApp());
    expect(find.text('日常钱包'), findsOneWidget);
    expect(find.text('总资产估值 (USD)'), findsOneWidget);
    // Hot wallet, not backed up → backup banner shows.
    expect(find.text('尚未备份助记词，存在丢失风险'), findsOneWidget);
    // Assets rendered.
    expect(find.text('USDT'), findsOneWidget);
  });
}
