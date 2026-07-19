import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/screens/home_screen.dart';

void main() {
  testWidgets('home screen golden at phone size (390x844)', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    // Reads the fallback WalletScope controller (日常钱包, not backed up).
    await tester.pumpWidget(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomeScreen(),
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/home_screen.png'),
    );
  });
}
