import 'dart:convert';
import 'dart:io';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:chains/chains.dart';
import 'package:cold_signer/l10n/app_localizations.dart';
import 'package:cold_signer/src/screens/signer_signing_screens.dart';
import 'package:cold_signer/src/signing/demo_airgap.dart';
import 'package:cold_signer/src/widgets/scan_viewfinder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _cjkFont = String.fromEnvironment('KT_QA_CJK_FONT');
const _previewDirectory = String.fromEnvironment('KT_REVIEW_PREVIEW_DIR');

SignRequest request({
  String walletId = demoWalletId,
  bool token = false,
  String contract = '0x0000000000000000000000000000000000000001',
  int networkId = 42161,
  int tokenAmount = 12345,
  int? createdAt,
  int? expiresAt,
}) {
  final now = createdAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return SignRequest(
    reqId: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
    walletId: walletId,
    coin: 42161,
    chainId: networkId,
    createdAt: now,
    expiresAt: expiresAt ?? now + 600,
    rawTx: Eip1559Tx(
      chainId: BigInt.from(networkId),
      nonce: BigInt.zero,
      maxPriorityFeePerGas: BigInt.one,
      maxFeePerGas: BigInt.two,
      gasLimit: BigInt.from(100000),
      to: Eip1559Tx.addressBytes(contract),
      value: token ? BigInt.zero : BigInt.parse('1000000000000000'),
      data: token
          ? Erc20.transferCalldata(
              to: '0x0000000000000000000000000000000000000002',
              amount: BigInt.from(tokenAmount),
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
  setUpAll(() async {
    for (final (family, path) in [
      ('Inter', 'fonts/Inter.ttf'),
      ('JetBrains Mono', 'fonts/JetBrainsMono.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(path))).load();
    }
    if (_cjkFont.isNotEmpty) {
      final data = ByteData.sublistView(await File(_cjkFont).readAsBytes());
      await (FontLoader('CjkPreview')..addFont(Future.value(data))).load();
    }
  });
  const usdc = '0xaf88d065e77c8cc2239327c5edb3a432268e5831';
  testWidgets('authentication uses the same local token and native amounts', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        SignerAuthScreen(
          request: request(token: true, contract: usdc, tokenAmount: 2000000),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 USDC'), findsOneWidget);
    expect(find.textContaining('FAKE'), findsNothing);
    await tester.pumpWidget(app(SignerAuthScreen(request: request())));
    await tester.pumpAndSettle();
    expect(find.text('0.001 ETH'), findsOneWidget);
    await tester.pumpWidget(
      app(SignerAuthScreen(request: request(token: true))),
    );
    await tester.pumpAndSettle();
    expect(find.text('12,345 基础单位'), findsOneWidget);
  });
  testWidgets('Arbitrum USDC uses local scale and ignores hostile QR hints', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        SignerParseScreen(
          request: request(token: true, contract: usdc, tokenAmount: 2000000),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 USDC'), findsOneWidget);
    expect(find.textContaining('2,000,000'), findsOneWidget);
    expect(find.textContaining('（精度 6）'), findsOneWidget);
    expect(find.text('名称与精度来自内置目录，请核对完整合约地址。'), findsOneWidget);
    expect(find.text(usdc), findsOneWidget);
    expect(find.textContaining('FAKE'), findsNothing);
    expect(find.text('Token 精度未经验证，请核对原始数量与合约地址。'), findsNothing);
  });

  testWidgets('same address on a testnet does not inherit mainnet decimals', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        SignerParseScreen(
          request: request(
            token: true,
            contract: usdc,
            networkId: 421614,
            tokenAmount: 2000000,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 USDC'), findsNothing);
    expect(find.text('2,000,000 基础单位'), findsOneWidget);
  });

  for (final width in [320.0, 390.0, 430.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final language in ['zh', 'en', 'ja']) {
        testWidgets(
          'live review aligns details at $width / $scale / $language',
          (tester) async {
            tester.view.physicalSize = Size(width, 1100);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final req = request(
              token: true,
              contract: usdc,
              tokenAmount: 2000000,
              walletId: 'w_WXp-Ha112g0VPWI0lA3hp69j',
              createdAt:
                  DateTime(2026, 9, 7, 9, 29, 45).millisecondsSinceEpoch ~/
                  1000,
            );
            await tester.pumpWidget(
              MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ThemeData(
                  brightness: Brightness.dark,
                  fontFamily: 'Inter',
                  fontFamilyFallback: _cjkFont.isEmpty ? null : ['CjkPreview'],
                ),
                locale: Locale(language),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: SignerParseScreen(request: req),
              ),
            );
            await tester.pumpAndSettle();
            final l10n = lookupAppLocalizations(Locale(language));
            final values = [
              l10n.requestId,
              l10n.walletIdLabel,
              l10n.createdAtLabel,
              l10n.expiresAtLabel,
              l10n.chainIdLabel,
              l10n.tokenContractLabel,
              l10n.maximumFeeBaseUnits,
            ];
            final rects = [
              for (final label in values)
                tester.getRect(
                  find.byKey(ValueKey('signer-detail-value-$label')),
                ),
            ];
            for (final rect in rects) {
              expect(rect.right, closeTo(rects.first.right, 0.01));
              expect(rect.left, closeTo(rects.first.left, 0.01));
            }
            expect(find.text(usdc), findsOneWidget);
            expect(find.text(req.walletId), findsOneWidget);
            expect(tester.takeException(), isNull);
            if (width == 390 &&
                scale == 1 &&
                (language == 'en' || _previewDirectory.isNotEmpty)) {
              await expectLater(
                find.byType(MaterialApp),
                matchesGoldenFile(
                  _previewDirectory.isEmpty
                      ? 'goldens/screens/live-token-review-en.png'
                      : '$_previewDirectory/live-token-review-$language.png',
                ),
              );
            }
          },
        );
      }
    }
  }

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
