import 'dart:convert';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:cold_signer/l10n/app_localizations.dart';
import 'package:cold_signer/src/screens/signer_signing_screens.dart';
import 'package:cold_signer/src/signing/demo_airgap.dart';
import 'package:cold_signer/src/signing/frame_scan.dart';
import 'package:cold_signer/src/widgets/scan_viewfinder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// C6 camera plumbing without the plugin: the fallback viewfinder renders
/// when no camera is available, and scanned strings (one base64url frame
/// each) advance the same aggregator the simulated taps feed.
void main() {
  test('scanned strings advance the aggregator; garbage counts silently', () {
    final frames = [
      for (final f in demoSignRequestFrames()) base64Url.encode(f.encode()),
    ];
    expect(frames.length, greaterThan(1));

    final session = QrFrameScanSession();
    session.add('not a frame'); // stray QR in view
    for (final (i, frame) in frames.indexed) {
      expect(session.add(frame).received, i + 1);
    }
    expect(session.isDone, isTrue);
    expect(session.anomalies, 1);
    expect(AirgapPayload.decode(session.payload!), isA<SignRequest>());
  });

  test('oversized camera text is rejected before base64 allocation', () {
    final session = QrFrameScanSession();
    session.add('A' * (AirgapFrame.maxQrTextLength + 1));
    expect(session.anomalies, 1);
    expect(session.progress.received, 0);
  });

  testWidgets(
    'C6 renders the simulated viewfinder when no camera is available',
    (tester) async {
      tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SignerScanScreen(
            availability: FakeCameraAvailability(false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.qr_code_2), findsOneWidget);
      expect(find.byType(MobileScanner), findsNothing);

      // The simulated tap loop still captures demo frames.
      final total = demoSignRequestFrames().length;
      expect(find.text('接收分片 0 / $total'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.qr_code_2));
      await tester.pump();
      expect(find.text('接收分片 1 / $total'), findsOneWidget);
    },
  );
}
