import 'package:cold_signer/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders placeholder home', (tester) async {
    await tester.pumpWidget(const ColdSignerApp());
    expect(find.text('Cold Signer'), findsOneWidget);
  });
}
