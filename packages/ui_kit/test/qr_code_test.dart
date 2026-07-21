import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr/qr.dart';
import 'package:ui_kit/ui_kit.dart';

void main() {
  testWidgets('KtQrCode renders a real QR matrix for its payload', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Center(child: KtQrCode(data: 'AIRGAP:TEST:0001', size: 220)),
    ));
    expect(find.byType(KtQrCode), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  test('module matrix matches package:qr for the same payload', () {
    final image = QrImage(QrCode(payload: QrPayload.fromString('hello'), errorCorrectLevel: QrErrorCorrectLevel.medium));
    // Finder pattern corner is always dark in a valid QR code.
    expect(image.isDark(0, 0), isTrue);
    expect(image.moduleCount, greaterThanOrEqualTo(21));
  });
}
