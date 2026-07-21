import 'dart:convert';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:chains/chains.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/main.dart';
import 'package:kt_wallet/src/screens/transfer_screens.dart';
import 'package:kt_wallet/src/transfer/airgap_codec.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';
import 'package:ui_kit/ui_kit.dart';

/// End-to-end proof that the watch-wallet signing loop carries REAL
/// AIRGAP-V1 bytes: draft → SignRequest → frames → QR strings → aggregate →
/// decode → verified SignResult, plus the screens that render each stage.

TransferDraft _draft() => TransferDraft(
      symbol: 'USDT',
      networkLabel: 'TRON · TRC-20',
      chain: Chain.tron,
      decimals: 6,
      recipient: 'TWd4qCEUf3aVpXe2HKk9gJt6nMxR38uQz',
      amount: Amount.parse('88.5', 6, symbol: 'USDT'),
      feeTier: 2,
      tokenContract: usdtTronContract,
    );

Widget _wrap(Widget child) => MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(scaffoldBackgroundColor: WalletColors.bg),
      home: child,
    );

void main() {
  evmRawTxTests();
  group('protocol round-trip', () {
    test('sign-request: draft → fragment → encode → aggregate → decode keeps every field', () {
      final draft = _draft();
      final request = buildSignRequest(draft: draft, walletId: 'cold', fromAddress: demoFromAddress);
      expect(request.reqId.length, AirgapLimits.reqIdLength);
      expect(request.expiresAt - request.createdAt, signRequestTtlSeconds);

      final frames = encodeQrFrames(request, reqId: request.reqId);
      expect(frames.length, greaterThan(1), reason: 'animated QR must span multiple frames');

      // Feed the frames as a scanner would (including a duplicate re-scan).
      final aggregator = FrameAggregator();
      for (final qr in [...frames, frames.first]) {
        aggregator.addFrame(AirgapFrame.decode(base64Url.decode(qr)));
      }
      expect(aggregator.state, AggregatorState.done);
      expect(aggregator.progress.total, frames.length);

      final decoded = AirgapPayload.decode(aggregator.payload!);
      expect(decoded, isA<SignRequest>());
      final req = decoded as SignRequest;
      expect(req.reqIdHex, request.reqIdHex);
      expect(req.walletId, 'cold');
      expect(req.coin, 195); // SLIP-44 TRON
      expect(req.chainId, isNull);
      expect(req.rawTx, request.rawTx);
      expect(req.createdAt, request.createdAt);
      expect(req.expiresAt, request.expiresAt);
      expect(req.summary?[SummaryKeys.network], 'TRON · TRC-20');
      expect(req.summary?[SummaryKeys.amount], '88.5 USDT');
      expect(req.summary?[SummaryKeys.recipient], draft.recipient);

      // The raw bytes really are the canonical intent from the draft.
      final tx = json.decode(utf8.decode(req.rawTx)) as Map<String, dynamic>;
      expect(tx['to'], draft.recipient);
      expect(tx['amountRaw'], '88500000');
      expect(tx['contract'], usdtTronContract);
    });

    test('sign-result: signer frames aggregate + decode + verify against the request', () {
      final request = buildSignRequest(draft: _draft(), walletId: 'cold', fromAddress: demoFromAddress);
      final result = buildDemoSignResult(request, signer: demoFromAddress);
      final frames = encodeQrFrames(result, reqId: request.reqId);

      final decoded = decodeSignResultFrames(frames, expected: request);
      expect(decoded.reqIdHex, request.reqIdHex);
      expect(decoded.walletId, request.walletId);
      expect(decoded.coin, request.coin);
      expect(decoded.signer, demoFromAddress);
      expect(utf8.decode(decoded.signedTx), startsWith('SIGNED-V1:'));
      expect(decoded.txHash, hexEncode(sha256(decoded.signedTx)));
    });

    test('sign-result answering a different request is rejected', () {
      final a = buildSignRequest(draft: _draft(), walletId: 'cold', fromAddress: demoFromAddress);
      final b = buildSignRequest(draft: _draft(), walletId: 'cold', fromAddress: demoFromAddress);
      expect(a.reqIdHex, isNot(b.reqIdHex)); // Random.secure reqIds
      final frames = encodeQrFrames(buildDemoSignResult(a, signer: demoFromAddress), reqId: a.reqId);
      expect(() => decodeSignResultFrames(frames, expected: b), throwsStateError);
    });
  });

  group('W6 sign-qr screen', () {
    testWidgets('renders a real QR, cycles frames on the timer, shows the real shard count', (tester) async {
      final session = TransferSession()..draft = _draft();
      await tester.pumpWidget(_wrap(TransferSessionScope(session: session, child: const SignRequestQrScreen())));
      await tester.pump();

      // The screen registered its outstanding request in the session.
      final request = session.request!;
      final frames = encodeQrFrames(request, reqId: request.reqId);
      expect(frames.length, greaterThan(1));

      String qrData() => tester.widget<KtQrCode>(find.byType(KtQrCode)).data;
      expect(qrData(), frames[0]);
      expect(find.text('动态分片 1 / ${frames.length}'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 600));
      expect(qrData(), frames[1]);
      expect(find.text('动态分片 2 / ${frames.length}'), findsOneWidget);

      // A full extra loop wraps back to frame 0.
      for (var i = 0; i < frames.length - 1; i++) {
        await tester.pump(const Duration(milliseconds: 600));
      }
      expect(qrData(), frames[0]);

      // Draft-derived rows + the real request id.
      expect(find.text('88.5 USDT'), findsOneWidget);
      expect(find.text('REQ-${request.reqIdHex.substring(0, 6).toUpperCase()}'), findsOneWidget);
    });

    testWidgets('without a draft the demo request renders deterministically', (tester) async {
      await tester.pumpWidget(_wrap(const SignRequestQrScreen()));
      await tester.pump();
      // Fixed demo reqId keeps the design literal REQ-7F3A2C.
      expect(find.text('REQ-7F3A2C'), findsOneWidget);
      expect(find.text('120.00 USDT'), findsOneWidget);
      expect(find.byType(KtQrCode), findsOneWidget);
    });
  });

  group('confirm screens', () {
    testWidgets('watch confirm shows draft-derived fields when a draft is in scope', (tester) async {
      final session = TransferSession()..draft = _draft();
      await tester.pumpWidget(_wrap(TransferSessionScope(session: session, child: const TransferConfirmScreen(isHot: false))));
      await tester.pump();

      expect(find.text('-88.5 USDT'), findsOneWidget);
      expect(find.text('TWd4qCEU…nMxR38uQz'), findsOneWidget); // draft recipient, truncated
      expect(find.text('≈ 27.4 TRX'), findsOneWidget); // fast tier on TRON
      expect(find.text('88.5 USDT'), findsOneWidget); // token transfer: total = token amount
      expect(find.text('TRON · TRC-20'), findsOneWidget);
      // From = fallback demo wallet name + its TRON address, truncated.
      expect(find.text('日常钱包 TQm9…3kFa'), findsOneWidget);
    });

    testWidgets('hot confirm falls back to the design demo values without a draft', (tester) async {
      await tester.pumpWidget(_wrap(const TransferConfirmScreen(isHot: true)));
      await tester.pump();

      expect(find.text('-120.00 USDT'), findsOneWidget);
      expect(find.text('≈ 13.7 TRX（\$1.90）'), findsOneWidget);
      expect(find.text('主钱包 TQm9…3kFa'), findsOneWidget);
      expect(find.text('120.00 USDT'), findsOneWidget);
    });
  });

  group('W7 → W8 decoded result', () {
    testWidgets('the simulated scan feeds real frames through the aggregator and W8 shows the decoded hash', (tester) async {
      tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      // Full app (session scope + router) opened straight on W6 so the
      // outstanding demo request exists.
      await tester.pumpWidget(KtWalletApp(initialLocation: '/sign-qr'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('待签名交易'), findsOneWidget);

      // Recompute the deterministic demo request W6 just built: gallery seed
      // wallet 'daily' with the seeded TRON address.
      const dailyTron = 'TaPa2Wc8hJdU5eRnT6yGb1sVb7L3kFa';
      final expectedRequest = buildSignRequest(walletId: 'daily', fromAddress: dailyTron);
      final expectedResult = buildDemoSignResult(expectedRequest, signer: dailyTron);

      // Navigate to W7 and trigger the simulated scan.
      final router = GoRouter.of(tester.element(find.byType(SignRequestQrScreen)));
      router.push('/scan-result');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('扫描签名结果'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.qr_code_2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // W8 renders fields decoded from the protocol payload, not constants.
      expect(find.text('广播交易'), findsWidgets);
      expect(find.text(truncateMiddle(expectedResult.txHash, head: 6, tail: 6)), findsOneWidget);
      expect(find.text(truncateMiddle(dailyTron)), findsOneWidget); // signer
      expect(find.text('-120 USDT'), findsOneWidget); // demo draft amount via summary
    });
  });
}

/// #13 EVM leg wired: the sign-request rawTx for EVM chains is a REAL
/// EIP-1559 unsigned transaction, not the JSON placeholder.
void evmRawTxTests() {
  test('EVM draft rawTx is a typed 0x02 EIP-1559 encoding matching Eip1559Tx', () {
    final draft = TransferDraft(
      symbol: 'ETH',
      networkLabel: 'Ethereum',
      chain: Chain.ethereum,
      decimals: 18,
      recipient: '0x925fEA1c0dbf3B011391bbed682E32861BE73213',
      amount: Amount.parse('0.5', 18, symbol: 'ETH'),
      feeTier: 1,
    );
    final raw = rawTxFor(draft, from: '0x0000000000000000000000000000000000000001');
    expect(raw.first, 0x02, reason: 'typed EIP-1559 envelope');

    // Re-encode with the same demo chain-state parameters — byte equality
    // proves rawTx really is the chains-package serialization.
    final gwei = BigInt.from(1000000000);
    final expected = Eip1559Tx.forTransfer(
      TransferIntent(
        chain: Chain.ethereum,
        operation: TxOperation.nativeTransfer,
        from: '0x0000000000000000000000000000000000000001',
        to: draft.recipient,
        amount: draft.amount,
      ),
      chainId: BigInt.one,
      nonce: BigInt.zero,
      maxPriorityFeePerGas: BigInt.two * gwei,
      maxFeePerGas: BigInt.from(40) * gwei,
      gasLimit: BigInt.from(21000),
    ).encodeUnsigned();
    expect(raw, expected);
  });

  test('TRON draft rawTx keeps the documented JSON placeholder shape', () {
    final raw = rawTxFor(demoDraft, from: usdtTronContract);
    final decoded = json.decode(utf8.decode(raw)) as Map<String, dynamic>;
    expect(decoded['chain'], 'tron');
    expect(decoded['v'], 1);
  });
}
