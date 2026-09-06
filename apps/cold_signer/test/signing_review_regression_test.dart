import 'dart:convert';
import 'dart:typed_data';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:chains/chains.dart';
import 'package:cold_signer/l10n/app_localizations.dart';
import 'package:cold_signer/src/screens/signer_signing_screens.dart';
import 'package:cold_signer/src/signing/demo_airgap.dart';
import 'package:cold_signer/src/widgets/scan_viewfinder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

SignRequest request({
  String walletId = demoWalletId,
  bool token = false,
  int? expiresAt,
}) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return SignRequest(
    reqId: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
    walletId: walletId,
    coin: 42161,
    chainId: 42161,
    createdAt: now,
    expiresAt: expiresAt ?? now + 600,
    rawTx: Eip1559Tx(
      chainId: BigInt.from(42161),
      nonce: BigInt.zero,
      maxPriorityFeePerGas: BigInt.one,
      maxFeePerGas: BigInt.two,
      gasLimit: BigInt.from(100000),
      to: Eip1559Tx.addressBytes('0x0000000000000000000000000000000000000001'),
      value: token ? BigInt.zero : BigInt.parse('1000000000000000'),
      data: token
          ? Erc20.transferCalldata(
              to: '0x0000000000000000000000000000000000000002',
              amount: BigInt.from(12345),
            )
          : Uint8List(0),
    ).encodeUnsigned(),
    // Malicious transport hints must never change native precision/display.
    summary: {'amount': '999', 'decimals': 0, 'token': 'FAKE', 'from': 'FAKE'},
  );
}

Widget app(Widget home) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

void main() {
  testWidgets(
    'Arbitrum native amount uses trusted 18 decimals, ignores summary',
    (tester) async {
      await tester.pumpWidget(app(SignerParseScreen(request: request())));
      await tester.pumpAndSettle();
      expect(find.text('0.001 ETH'), findsOneWidget);
      expect(find.textContaining('（精度 18）'), findsOneWidget);
      expect(find.textContaining('（精度 0）'), findsNothing);
      expect(find.text('FAKE'), findsNothing);
    },
  );

  testWidgets('unknown token precision is explicit, never zero or QR hint', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(SignerParseScreen(request: request(token: true))),
    );
    await tester.pumpAndSettle();
    expect(find.text('12,345 基础单位'), findsOneWidget);
    expect(find.text('Token 精度未经验证，请核对原始数量与合约地址。'), findsOneWidget);
    expect(find.textContaining('（精度 0）'), findsNothing);
  });

  testWidgets('risk displays real reason, request ID, chain and bytes', (
    tester,
  ) async {
    final req = request(walletId: 'another-wallet');
    await tester.pumpWidget(
      app(
        SignerRiskScreen(
          rejection: SignerRejection.fromValidation(
            ValidationCode.badWallet,
            req,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('另一个冷钱包'), findsOneWidget);
    expect(find.textContaining('approve'), findsNothing);
    await tester.tap(find.text('查看原始交易数据'));
    await tester.pumpAndSettle();
    expect(find.text('REQ-010203 · Arbitrum'), findsOneWidget);
    expect(
      find.text(
        req.rawTx.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('TRON'), findsNothing);
  });

  testWidgets('invalid payload does not offer invented raw transaction', (
    tester,
  ) async {
    await tester.pumpWidget(app(const SignerRiskScreen()));
    await tester.pumpAndSettle();
    expect(find.text('查看原始交易数据'), findsNothing);
  });

  testWidgets(
    'returning from rejected or accepted request starts a fresh scan',
    (tester) async {
      var parses = 0;
      final router = GoRouter(
        initialLocation: '/scan',
        routes: [
          GoRoute(
            path: '/scan',
            builder: (_, _) => const SignerScanScreen(
              availability: FakeCameraAvailability(false),
            ),
          ),
          GoRoute(
            path: '/risk',
            builder: (_, state) =>
                SignerRiskScreen(rejection: state.extra as SignerRejection),
          ),
          GoRoute(
            path: '/parse',
            builder: (_, state) {
              parses++;
              return SignerParseScreen(request: state.extra as SignRequest);
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      );
      await tester.pumpAndSettle();
      void feed(SignRequest req, {bool corrupt = false}) {
        final scan = tester.widget<ScanViewfinder>(find.byType(ScanViewfinder));
        for (final frame in Fragmenter(
          chunkSize: 80,
        ).fragment(req.encode(), reqId: req.reqId)) {
          if (corrupt && frame.seq == frame.total - 1) frame.chunk[0] ^= 1;
          scan.onScanned!(base64Url.encode(frame.encode()));
        }
      }

      final firstKey = tester
          .widget<ScanViewfinder>(find.byType(ScanViewfinder))
          .key;
      feed(request(), corrupt: true);
      await tester.pumpAndSettle();
      expect(parses, 0);
      expect(
        tester.widget<ScanViewfinder>(find.byType(ScanViewfinder)).key,
        isNot(firstKey),
      );
      feed(request(walletId: 'wrong-wallet'));
      await tester.pumpAndSettle();
      expect(find.textContaining('另一个冷钱包'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      feed(request());
      await tester.pumpAndSettle();
      expect(parses, 1);
      expect(find.text('0.001 ETH'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      feed(request());
      await tester.pumpAndSettle();
      expect(parses, 2);
    },
  );

  test(
    'all validation failures have a distinct actionable localized reason',
    () {
      final messages = <String>{};
      for (final code in ValidationCode.values.where(
        (code) => code != ValidationCode.ok,
      )) {
        messages.add(
          SignerRejection.fromValidation(
            code,
            request(),
          ).message(lookupAppLocalizations(const Locale('zh'))),
        );
      }
      expect(messages, hasLength(5));
    },
  );
}
