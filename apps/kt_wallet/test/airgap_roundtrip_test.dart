import 'dart:async';

import 'dart:convert';
import 'dart:typed_data';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:chains/chains.dart';
import 'package:core_crypto/core_crypto.dart' show ChainAddresses, Coin;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/main.dart';
import 'package:kt_wallet/src/market/gateway_client.dart';
import 'package:kt_wallet/src/screens/transfer_screens.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/state/wallet_scope.dart';
import 'package:kt_wallet/src/transfer/airgap_codec.dart';
import 'package:kt_wallet/src/transfer/local_transfer_service.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:wallet_data/wallet_data.dart' show TxStatus;

/// End-to-end proof that the watch-wallet signing loop carries REAL
/// AIRGAP-V1 bytes: draft → SignRequest → frames → QR strings → aggregate →
/// decode → verified SignResult, plus the screens that render each stage.

TransferDraft _draft() => TransferDraft(
  symbol: 'USDT',
  networkLabel: 'TRON · TRC-20',
  chain: Chain.tron,
  recipient: 'TWd4qCEUf3aVpXe2HKk9gJt6nMxR38uQz',
  amount: Amount.parse('88.5', 6, symbol: 'USDT'),
  feeTier: 2,
  tokenContract: usdtTronContract,
);

Widget _wrap(Widget child) {
  final controller = WalletController(
    WalletManager(
      initial: [
        HotWallet(
          id: 'airgap-test-wallet',
          name: '日常钱包',
          avatarColor: 0xFFF59E0B,
          addresses: const ChainAddresses(
            eth: '0x0000000000000000000000000000000000000001',
            polygon: '0x0000000000000000000000000000000000000001',
            tron: _testSignerAddress,
            solana: '11111111111111111111111111111111',
          ),
          backedUp: true,
        ),
      ],
    ),
    allowTestBypass: true,
  );
  return MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(scaffoldBackgroundColor: WalletColors.bg),
    home: WalletScope(controller: controller, child: child),
  );
}

class _TronQuoteService extends LocalTransferService {
  @override
  Future<PreparedTronTransfer> prepareTron({
    required TransferDraft draft,
    required String from,
    required String? expectedNetworkIdentity,
  }) async => PreparedTronTransfer(
    from: from,
    recipient: draft.recipient,
    amountRaw: draft.amount.raw,
    tokenContract: draft.tokenContract,
    maximumFeeSun: BigInt.from(1250000),
    referenceBlockHeight: 42,
    expiresAt: DateTime.now()
        .add(const Duration(minutes: 10))
        .millisecondsSinceEpoch,
    rawTx: rawTxFor(draft, from: from),
  );
}

class _ApprovalQuoteService extends LocalTransferService {
  @override
  Future<PreparedEvmTransfer> prepareEvm({
    required TransferDraft draft,
    required String from,
    required int evmChainId,
  }) async {
    final unsigned = rawTxFor(
      draft,
      from: from,
      nonce: BigInt.from(7),
      maxPriorityFeePerGas: BigInt.from(2),
      maxFeePerGas: BigInt.from(30),
      gasLimit: BigInt.from(50000),
      evmChainId: evmChainId,
    );
    return PreparedEvmTransfer(
      chain: draft.chain,
      evmChainId: evmChainId,
      coin: Coin.eth,
      operation: draft.operation,
      from: from,
      recipient: draft.recipient,
      amountRaw: draft.amount.raw,
      tokenContract: draft.tokenContract,
      nonce: BigInt.from(7),
      maxPriorityFeePerGas: BigInt.from(2),
      maxFeePerGas: BigInt.from(30),
      gasLimit: BigInt.from(50000),
      unsignedTx: unsigned,
    );
  }
}

class _SolanaQuoteService extends LocalTransferService {
  @override
  Future<PreparedSolanaTransfer> prepareSolana({
    required TransferDraft draft,
    required String from,
    required String? expectedNetworkIdentity,
  }) async => PreparedSolanaTransfer(
    from: from,
    recipient: draft.recipient,
    amountRaw: draft.amount.raw,
    tokenMint: draft.tokenContract,
    tokenProgram: draft.tokenProgram,
    networkFeeLamports: BigInt.from(5000),
    rentDepositLamports: BigInt.zero,
    lastValidBlockHeight: 12345,
    message: Uint8List.fromList(const [1, 2, 3]),
  );
}

TransferDraft _approvalDraft() => TransferDraft(
  symbol: 'TOK',
  networkLabel: 'Ethereum',
  chain: Chain.ethereum,
  recipient: '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  amount: Amount(raw: BigInt.zero, decimals: 18, symbol: 'TOK'),
  feeTier: 1,
  tokenContract: '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  operation: TxOperation.approvalRevoke,
);

TransferDraft _solanaTokenDraft() => TransferDraft(
  symbol: 'USDC',
  networkLabel: 'Solana',
  chain: Chain.solana,
  recipient: '11111111111111111111111111111111',
  amount: Amount.parse('1', 6, symbol: 'USDC'),
  feeTier: 1,
  tokenContract: 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v',
  tokenProgram: 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA',
);

void main() {
  evmRawTxTests();
  group('protocol round-trip', () {
    test(
      'sign request rejects overlong wallet identity instead of truncating',
      () {
        expect(
          () => buildSignRequest(
            draft: _draft(),
            walletId: 'x' * (AirgapLimits.maxWalletId + 1),
            fromAddress: _testSignerAddress,
          ),
          throwsA(isA<PayloadError>()),
        );
      },
    );

    test(
      'sign-request: draft → fragment → encode → aggregate → decode keeps every field',
      () {
        final draft = _draft();
        final request = buildSignRequest(
          draft: draft,
          walletId: 'cold',
          fromAddress: _testSignerAddress,
        );
        expect(request.reqId.length, AirgapLimits.reqIdLength);
        expect(request.expiresAt - request.createdAt, signRequestTtlSeconds);

        final frames = encodeQrFrames(request, reqId: request.reqId);
        expect(
          frames.length,
          greaterThan(1),
          reason: 'animated QR must span multiple frames',
        );

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
      },
    );

    test(
      'sign-result: signer frames aggregate + decode + verify against the request',
      () {
        final request = buildSignRequest(
          draft: _draft(),
          walletId: 'cold',
          fromAddress: _testSignerAddress,
        );
        final result = buildDemoSignResult(request, signer: _testSignerAddress);
        final frames = encodeQrFrames(result, reqId: request.reqId);

        final decoded = decodeSignResultFrames(frames, expected: request);
        expect(decoded.reqIdHex, request.reqIdHex);
        expect(decoded.walletId, request.walletId);
        expect(decoded.coin, request.coin);
        expect(decoded.signer, _testSignerAddress);
        expect(utf8.decode(decoded.signedTx), startsWith('SIGNED-V1:'));
        expect(decoded.txHash, hexEncode(sha256(decoded.signedTx)));
      },
    );

    test('sign-result answering a different request is rejected', () {
      final a = buildSignRequest(
        draft: _draft(),
        walletId: 'cold',
        fromAddress: _testSignerAddress,
      );
      final b = buildSignRequest(
        draft: _draft(),
        walletId: 'cold',
        fromAddress: _testSignerAddress,
      );
      expect(a.reqIdHex, isNot(b.reqIdHex)); // Random.secure reqIds
      final frames = encodeQrFrames(
        buildDemoSignResult(a, signer: _testSignerAddress),
        reqId: a.reqId,
      );
      expect(
        () => decodeSignResultFrames(frames, expected: b),
        throwsStateError,
      );
    });

    test('approval revoke request carries exact approve(spender, 0) bytes', () {
      final draft = _approvalDraft();
      final request = buildSignRequest(
        draft: draft,
        walletId: 'cold',
        fromAddress: '0x0000000000000000000000000000000000000001',
        nonce: BigInt.from(7),
        maxPriorityFeePerGas: BigInt.from(2),
        maxFeePerGas: BigInt.from(30),
        gasLimit: BigInt.from(50000),
        evmChainId: 1,
      );
      final parsed = parseUnsignedTransfer(Chain.ethereum, request.rawTx);

      expect(parsed.operation, TxOperation.approvalRevoke);
      expect(parsed.tokenContract, draft.tokenContract);
      expect(parsed.to, draft.recipient);
      expect(parsed.amountRaw, BigInt.zero);
      expect(request.summary?[SummaryKeys.amount], 'approve(spender, 0)');
    });

    test('cryptographic gate rejects request chain-domain drift', () async {
      final tx = Eip1559Tx(
        chainId: BigInt.from(11155111),
        nonce: BigInt.zero,
        maxPriorityFeePerGas: BigInt.one,
        maxFeePerGas: BigInt.two,
        gasLimit: BigInt.from(21000),
        to: Eip1559Tx.addressBytes(
          '0x000000000000000000000000000000000000dEaD',
        ),
        value: BigInt.one,
        data: Uint8List(0),
      );
      final request = SignRequest(
        reqId: Uint8List.fromList(const [1, 2, 3, 4, 5, 6, 7, 8]),
        walletId: 'cold',
        coin: 60,
        chainId: 1,
        rawTx: tx.encodeUnsigned(),
        createdAt: 1000,
        expiresAt: 1600,
      );
      final result = SignResult(
        reqId: Uint8List.fromList(request.reqId),
        walletId: request.walletId,
        coin: request.coin,
        signedTx: Uint8List.fromList(const [0]),
        signer: '0x0000000000000000000000000000000000000001',
        txHash: '0x00',
      );

      expect(
        () => verifySignResultCryptographically(
          result.encode(),
          expected: request,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'sign-result transaction chainId mismatch',
          ),
        ),
      );
    });
  });

  group('W6 sign-qr screen', () {
    testWidgets('does not publish QR or session request before durable save', (
      tester,
    ) async {
      final save = Completer<void>();
      final session = TransferSession()..draft = _draft();
      await tester.pumpWidget(
        _wrap(
          TransferSessionScope(
            session: session,
            child: SignRequestQrScreen(
              requestPersistence: (_, _, status, _) {
                expect(status, TxStatus.awaitingSig);
                return save.future;
              },
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(KtQrCode), findsNothing);
      expect(session.request, isNull);

      save.complete();
      await tester.pump();

      expect(find.byType(KtQrCode), findsOneWidget);
      expect(session.request, isNotNull);
    });

    testWidgets('save failure fails closed without publishing signable bytes', (
      tester,
    ) async {
      final session = TransferSession()..draft = _draft();
      await tester.pumpWidget(
        _wrap(
          TransferSessionScope(
            session: session,
            child: SignRequestQrScreen(
              requestPersistence: (_, _, _, _) async {
                throw StateError('transaction database unavailable');
              },
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(KtQrCode), findsNothing);
      expect(session.request, isNull);
      expect(session.localTransactionId, isNull);
      expect(find.text('无法安全保存待签名交易，签名二维码未生成。请返回后重试。'), findsOneWidget);
    });

    testWidgets(
      'renders a real QR, cycles frames on the timer, shows the real shard count',
      (tester) async {
        final session = TransferSession()..draft = _draft();
        await tester.pumpWidget(
          _wrap(
            TransferSessionScope(
              session: session,
              child: const SignRequestQrScreen(),
            ),
          ),
        );
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
        expect(
          find.text('REQ-${request.reqIdHex.substring(0, 6).toUpperCase()}'),
          findsOneWidget,
        );
      },
    );

    testWidgets('without a draft the demo request renders deterministically', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const SignRequestQrScreen()));
      await tester.pump();
      // Fixed demo reqId keeps the design literal REQ-7F3A2C.
      expect(find.text('REQ-7F3A2C'), findsOneWidget);
      expect(find.text('120.00 USDT'), findsOneWidget);
      expect(find.byType(KtQrCode), findsOneWidget);
    });
  });

  group('confirm screens', () {
    testWidgets(
      'watch confirm shows draft-derived fields when a draft is in scope',
      (tester) async {
        final session = TransferSession()..draft = _draft();
        await tester.pumpWidget(
          _wrap(
            TransferSessionScope(
              session: session,
              child: TransferConfirmScreen(
                isHot: false,
                transferService: _TronQuoteService(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('-88.5 USDT'), findsOneWidget);
        expect(
          find.text('TWd4qCEU…nMxR38uQz'),
          findsOneWidget,
        ); // draft recipient, truncated
        // A LIVE draft never shows the demo schedule. The injected chain quote
        // is the same exact object later consumed by QR/signing.
        expect(find.text('≈ 27.4 TRX'), findsNothing);
        expect(find.textContaining('1.25 TRX'), findsOneWidget);
        // Fiat likewise: no price source in this bare harness → '--', never a
        // 1:1 "≈ \$88.5" peg.
        expect(find.text('≈ \$88.5'), findsNothing);
        expect(
          find.text('88.5 USDT'),
          findsOneWidget,
        ); // token transfer: total = token amount
        expect(find.text('TRON · TRC-20'), findsOneWidget);
        // From = fallback demo wallet name + its TRON address, truncated.
        expect(find.text('日常钱包 TQm9…3kFa'), findsOneWidget);
      },
    );

    testWidgets(
      'hot confirm falls back to the design demo values without a draft',
      (tester) async {
        await tester.pumpWidget(
          _wrap(const TransferConfirmScreen(isHot: true)),
        );
        await tester.pump();

        expect(find.text('-120.00 USDT'), findsOneWidget);
        expect(find.text('≈ 13.7 TRX（\$1.90）'), findsOneWidget);
        expect(find.text('主钱包 TQm9…3kFa'), findsOneWidget);
        expect(find.text('120.00 USDT'), findsOneWidget);
      },
    );

    testWidgets(
      'watch revoke review shows allowance change and does not block on token risk',
      (tester) async {
        final session = TransferSession()..draft = _approvalDraft();
        var riskLookups = 0;
        await tester.pumpWidget(
          _wrap(
            TransferSessionScope(
              session: session,
              child: TransferConfirmScreen(
                isHot: false,
                transferService: _ApprovalQuoteService(),
                tokenRiskLookup: (_, _) async {
                  riskLookups++;
                  throw StateError('revocation must not query token risk');
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(riskLookups, 0);
        expect(find.text('撤销授权'), findsWidgets);
        expect(find.text('被授权合约'), findsOneWidget);
        expect(find.text('approve(spender, 0)'), findsOneWidget);
        expect(find.text('-0 TOK'), findsNothing);
        expect(find.text('生成待签名二维码'), findsOneWidget);
        expect(
          tester
              .widget<KtPrimaryButton>(find.byType(KtPrimaryButton))
              .onPressed,
          isNotNull,
        );
      },
    );

    testWidgets('Solana token threat uses its exact mint and blocks signing', (
      tester,
    ) async {
      final draft = _solanaTokenDraft();
      final session = TransferSession()..draft = draft;
      var lookups = 0;
      await tester.pumpWidget(
        _wrap(
          TransferSessionScope(
            session: session,
            child: TransferConfirmScreen(
              isHot: true,
              transferService: _SolanaQuoteService(),
              tokenRiskLookup: (chain, contract) async {
                lookups++;
                expect(chain, Coin.solana);
                expect(contract, draft.tokenContract);
                return const GatewayTokenRisk(
                  status: GatewayTokenRiskStatus.unsafe,
                  category: 'malicious',
                  source: 'goplus',
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(lookups, 1);
      expect(find.text('检测到高风险 Token 合约'), findsOneWidget);
      expect(find.textContaining('本次签名已阻止'), findsOneWidget);
      expect(
        tester.widget<KtPrimaryButton>(find.byType(KtPrimaryButton)).onPressed,
        isNull,
      );
    });
  });

  group('W7 → W8 decoded result', () {
    testWidgets(
      'the simulated scan feeds real frames through the aggregator and W8 shows the decoded hash',
      (tester) async {
        tester.platformDispatcher.localesTestValue = <Locale>[
          const Locale('zh'),
        ];
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
        final expectedRequest = buildSignRequest(
          walletId: 'daily',
          fromAddress: dailyTron,
        );
        final expectedResult = buildDemoSignResult(
          expectedRequest,
          signer: dailyTron,
        );

        // Navigate to W7 and trigger the simulated scan.
        final router = GoRouter.of(
          tester.element(find.byType(SignRequestQrScreen)),
        );
        unawaited(router.push('/scan-result'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('扫描签名结果'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.qr_code_2));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // W8 renders fields decoded from the protocol payload, not constants.
        expect(find.text('广播交易'), findsWidgets);
        expect(
          find.text(truncateMiddle(expectedResult.txHash, head: 6, tail: 6)),
          findsOneWidget,
        );
        expect(find.text(truncateMiddle(dailyTron)), findsOneWidget); // signer
        expect(
          find.text('-120 USDT'),
          findsOneWidget,
        ); // demo draft amount via summary
      },
    );
  });
}

/// #13 EVM leg wired: the sign-request rawTx for EVM chains is a REAL
/// EIP-1559 unsigned transaction, not the JSON placeholder.
void evmRawTxTests() {
  test(
    'EVM draft rawTx is a typed 0x02 EIP-1559 encoding matching Eip1559Tx',
    () {
      final draft = TransferDraft(
        symbol: 'ETH',
        networkLabel: 'Ethereum',
        chain: Chain.ethereum,
        recipient: '0x925fEA1c0dbf3B011391bbed682E32861BE73213',
        amount: Amount.parse('0.5', 18, symbol: 'ETH'),
        feeTier: 1,
      );
      final raw = rawTxFor(
        draft,
        from: '0x0000000000000000000000000000000000000001',
      );
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
    },
  );

  test(
    'rawTxFor overrides encode the live nonce/fees byte-for-byte (#nonce/gas)',
    () {
      final draft = TransferDraft(
        symbol: 'ETH',
        networkLabel: 'Ethereum',
        chain: Chain.ethereum,
        recipient: '0x925fEA1c0dbf3B011391bbed682E32861BE73213',
        amount: Amount.parse('0.5', 18, symbol: 'ETH'),
        feeTier: 1,
      );
      const from = '0x0000000000000000000000000000000000000001';
      final tip = BigInt.from(1500000000); // 1.5 gwei
      final maxFee = BigInt.from(52000000000); // 52 gwei
      final raw = rawTxFor(
        draft,
        from: from,
        nonce: BigInt.from(42),
        maxPriorityFeePerGas: tip,
        maxFeePerGas: maxFee,
      );

      final expected = Eip1559Tx.forTransfer(
        TransferIntent(
          chain: Chain.ethereum,
          operation: TxOperation.nativeTransfer,
          from: from,
          to: draft.recipient,
          amount: draft.amount,
        ),
        chainId: BigInt.one,
        nonce: BigInt.from(42),
        maxPriorityFeePerGas: tip,
        maxFeePerGas: maxFee,
        gasLimit: BigInt.from(21000),
      ).encodeUnsigned();
      expect(raw, expected);
      // And it genuinely differs from the demo-constant encoding.
      expect(raw, isNot(equals(rawTxFor(draft, from: from))));
    },
  );

  test('TRON draft rawTx keeps the documented JSON placeholder shape', () {
    final raw = rawTxFor(demoDraft, from: usdtTronContract);
    final decoded = json.decode(utf8.decode(raw)) as Map<String, dynamic>;
    expect(decoded['chain'], 'tron');
    expect(decoded['v'], 1);
  });
}

const _testSignerAddress = 'TQm9xPa2Wc8hJdU5eRnT6yGb1sVb7L3kFa';
