import 'dart:convert';
import 'dart:typed_data';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:cold_signer/l10n/app_localizations.dart';
import 'package:cold_signer/main.dart';
import 'package:cold_signer/src/screens/signer_signing_screens.dart';
import 'package:cold_signer/src/signing/demo_airgap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// The signer half of the air-gap loop, end to end: demo request → real
/// Fragmenter frames → real FrameAggregator → decode → parse screen fields,
/// and the answering SignResult → frames → animated result QR.

/// Fixed clock so createdAt/expiresAt are deterministic in the pure tests.
final _fixedNow = DateTime.utc(2026, 7, 21, 12);

void main() {
  test('demo sign-request round-trips: fragment → aggregate → decode', () {
    final request = demoSignRequest(now: _fixedNow);
    final frames = demoSignRequestFrames(now: _fixedNow);
    // The demo chunk size must actually yield a multi-frame session.
    expect(frames.length, greaterThan(1));

    final aggregator = FrameAggregator();
    for (var i = 0; i < frames.length; i++) {
      // Round-trip each frame through its wire bytes, as a camera read would.
      final progress =
          aggregator.addFrame(AirgapFrame.decode(frames[i].encode()));
      expect(progress.received, i + 1);
      expect(progress.total, frames.length);
      expect(progress.duplicates, 0);
      expect(progress.anomalies, 0);
    }
    expect(aggregator.state, AggregatorState.done);

    final decoded = AirgapPayload.decode(aggregator.payload!);
    expect(decoded, isA<SignRequest>());
    final req = decoded as SignRequest;
    expect(req.reqIdHex, request.reqIdHex);
    expect(req.reqIdHex, '7f3a2c915ed408b6');
    expect(req.walletId, demoWalletId);
    expect(req.coin, demoCoinTron);
    expect(req.rawTx, request.rawTx);
    expect(req.createdAt, request.createdAt);
    expect(req.expiresAt, request.createdAt + demoExpirySeconds);
    expect(req.summary?['amount'], '120.00');
    expect(req.summary?['token'], 'USDT');
    expect(req.summary?['from'], demoSignerAddress);
    expect(req.summary?['to'], demoToAddress);

    // And the decoded request passes the validator's acceptance check.
    final verdict = SignRequestValidator(
      localWalletId: demoWalletId,
      records: InMemorySignRecordStore(),
      transactionAllowed: (r) => r.coin == demoCoinTron,
      clock: () => _fixedNow,
    ).validate(req);
    expect(verdict.isOk, isTrue);
  });

  test('demo sign-result answers the request and round-trips', () {
    final request = demoSignRequest(now: _fixedNow);
    final result = demoSignResult(request);
    final frames = demoSignResultFrames(result);

    final aggregator = FrameAggregator();
    for (final frame in frames) {
      // The result QR carries base64url text; decode it back to wire bytes
      // exactly as kt_wallet's scanner would.
      final wire = base64Url.decode(base64Url.encode(frame.encode()));
      aggregator.addFrame(AirgapFrame.decode(Uint8List.fromList(wire)));
    }
    expect(aggregator.state, AggregatorState.done);

    final decoded = AirgapPayload.decode(aggregator.payload!);
    expect(decoded, isA<SignResult>());
    final res = decoded as SignResult;
    expect(res.reqIdHex, request.reqIdHex); // answers the same request
    expect(res.walletId, request.walletId);
    expect(res.coin, request.coin);
    expect(res.signer, demoSignerAddress);
    expect(res.txHash, demoTxHash);
    // signedTx = rawTx + the 65-byte demo signature stand-in.
    expect(res.signedTx.length, request.rawTx.length + 65);
    expect(res.signedTx.sublist(0, request.rawTx.length), request.rawTx);
  });

  testWidgets('scan: each tap feeds one frame; the last decodes into parse',
      (tester) async {
    tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(ColdSignerApp(initialLocation: '/scan'));
    await tester.pumpAndSettle();

    final total = demoSignRequestFrames().length;
    expect(find.text('接收分片 0 / $total'), findsOneWidget);

    // Every capture short of the last advances the shard progress.
    for (var k = 1; k < total; k++) {
      await tester.tap(find.byIcon(Icons.qr_code_2).first);
      await tester.pump();
      expect(find.text('接收分片 $k / $total'), findsOneWidget);
    }

    // The final frame completes aggregation, decodes and navigates to C7
    // showing the DECODED payload's fields.
    await tester.tap(find.byIcon(Icons.qr_code_2).first);
    await tester.pumpAndSettle();
    expect(find.text('确认交易内容'), findsOneWidget);
    expect(find.text('120.00 USDT'), findsOneWidget);
    expect(find.text(demoSignerAddress), findsOneWidget);
    expect(find.text(demoToAddress), findsOneWidget);
    expect(find.text(demoWalletId), findsOneWidget);
    expect(find.text('7F3A2C915ED408B6'), findsOneWidget); // full reqId hex
    expect(find.text('REQ-7F3A2C'), findsOneWidget); // short label
  });

  testWidgets('result QR: renders real frames, cycles them, counter matches',
      (tester) async {
    final expected =
        demoSignResultFrames(demoSignResult(demoSignRequest())).length;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const SignerResultQrScreen(),
    ));
    await tester.pump();

    expect(expected, greaterThan(1));
    expect(find.text('动态分片 1 / $expected'), findsOneWidget);
    final firstFrame = tester.widget<KtQrCode>(find.byType(KtQrCode)).data;
    // Frame payloads are the base64url wire bytes of real AirgapFrames.
    final parsed =
        AirgapFrame.decode(Uint8List.fromList(base64Url.decode(firstFrame)));
    expect(parsed.total, expected);
    expect(parsed.reqId, demoReqId);

    // The ~600ms timer advances to the next frame.
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('动态分片 2 / $expected'), findsOneWidget);
    final secondFrame = tester.widget<KtQrCode>(find.byType(KtQrCode)).data;
    expect(secondFrame, isNot(firstFrame));

    // And wraps around after a full cycle.
    await tester.pump(Duration(milliseconds: 600 * (expected - 1)));
    expect(find.text('动态分片 1 / $expected'), findsOneWidget);
  });
}
