import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/main.dart';

void main() {
  testWidgets('renders placeholder home', (tester) async {
    await tester.pumpWidget(const KtWalletApp());
    expect(find.text('KT Wallet'), findsOneWidget);
  });
}
