import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/screens/camera_screen.dart';
import 'package:kt_wallet/src/widgets/scan_viewfinder.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Camera fallback: when no camera is available (fake probe, as in every
/// widget test) the viewfinder renders the simulated design and the tap loop
/// still drives it — no plugin is ever touched.
void main() {
  testWidgets(
    'unavailable camera renders the simulated viewfinder; tap simulates',
    (tester) async {
      var taps = 0;
      final scans = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScanViewfinder(
              height: 400,
              frameColor: Colors.blue,
              availability: const FakeCameraAvailability(false),
              onSimulatedTap: () => taps++,
              onScanned: scans.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Simulated viewfinder: the placeholder QR glyph, no live preview.
      expect(find.byIcon(Icons.qr_code_2), findsOneWidget);
      expect(find.byType(MobileScanner), findsNothing);

      await tester.tap(find.byIcon(Icons.qr_code_2));
      expect(taps, 1);
      expect(scans, isEmpty);
    },
  );

  testWidgets(
    'KtCameraScreen falls back identically with a scan callback wired',
    (tester) async {
      var simulated = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: KtCameraScreen(
            title: 'T',
            hint: 'H',
            onClose: () {},
            onSimulatedScan: () => simulated++,
            onScanned: (_) {},
            availability: const FakeCameraAvailability(false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.qr_code_2), findsOneWidget);
      expect(find.byType(MobileScanner), findsNothing);
      await tester.tap(find.byIcon(Icons.qr_code_2));
      expect(simulated, 1);
    },
  );

  group('scannedAddressCandidate', () {
    test('accepts an address valid on any supported chain', () {
      expect(scannedAddressCandidate(ScanAddressScreen.demoAddress), isNotNull);
      expect(
        scannedAddressCandidate(' ${ScanAddressScreen.demoAddress} '),
        isNotNull,
        reason: 'whitespace from the QR content is trimmed',
      );
    });

    test('rejects non-address QR content', () {
      expect(scannedAddressCandidate(''), isNull);
      expect(scannedAddressCandidate('https://example.com/pay'), isNull);
      expect(scannedAddressCandidate('not an address'), isNull);
    });
  });
}
