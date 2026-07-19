import 'package:core_crypto_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('example app renders bridge buttons', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.text('generateMnemonic (12 words)'), findsOneWidget);
  });
}
