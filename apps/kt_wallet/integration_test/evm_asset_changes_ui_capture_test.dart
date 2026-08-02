import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chains/chains.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:core_crypto/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/market/gateway_client.dart';
import 'package:kt_wallet/src/screens/transfer_screens.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/state/wallet_scope.dart';
import 'package:kt_wallet/src/transfer/airgap_codec.dart' show rawTxFor;
import 'package:kt_wallet/src/transfer/local_transfer_service.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:ui_kit/ui_kit.dart';

const _from = '0x70997970C51812dc3A010C7d01b50e0d17dc79C8';
const _to = '0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC';
const _usdt = '0xdAC17F958D2ee523a2206206994597C13D831ec7';
const _emitScreenshotBase64 = bool.fromEnvironment('KT_EMIT_SCREENSHOT_BASE64');

class _EvmQuoteService extends LocalTransferService {
  @override
  Future<PreparedEvmTransfer> prepareEvm({
    required TransferDraft draft,
    required String from,
    required int evmChainId,
  }) async {
    final nonce = BigInt.from(18);
    final priorityFee = BigInt.from(2000000000);
    final maxFee = BigInt.from(32000000000);
    final gasLimit = BigInt.from(draft.tokenContract == null ? 21000 : 65000);
    return PreparedEvmTransfer(
      chain: draft.chain,
      evmChainId: evmChainId,
      coin: Coin.eth,
      operation: draft.operation,
      from: from,
      recipient: draft.recipient,
      amountRaw: draft.amount.raw,
      tokenContract: draft.tokenContract,
      nonce: nonce,
      maxPriorityFeePerGas: priorityFee,
      maxFeePerGas: maxFee,
      gasLimit: gasLimit,
      unsignedTx: rawTxFor(
        draft,
        from: from,
        nonce: nonce,
        maxPriorityFeePerGas: priorityFee,
        maxFeePerGas: maxFee,
        gasLimit: gasLimit,
        evmChainId: evmChainId,
      ),
    );
  }
}

WalletController _wallets() => WalletController(
  WalletManager(
    initial: [
      HotWallet(
        id: 'evm-asset-change-evidence',
        name: '测试钱包',
        avatarColor: 0xFF3155DD,
        addresses: const ChainAddresses(
          eth: _from,
          polygon: _from,
          base: _from,
          arbitrum: _from,
          avalanche: _from,
          bnb: _from,
          tron: 'TNXoiAJ3dct8Fjg4M9fkLFh9S2v9TXc32G',
          solana: '2KW2XRd9kwqet15Aha2oK3tYvd3nWbTFH1MBiRAv1BE1',
        ),
        backedUp: true,
      ),
    ],
  ),
  crypto: MockCoreCrypto(),
  allowTestBypass: true,
);

TransferDraft _nativeDraft() => TransferDraft(
  symbol: 'ETH',
  networkLabel: 'Ethereum',
  chain: Chain.ethereum,
  recipient: _to,
  amount: Amount.parse('0.5', 18, symbol: 'ETH'),
  feeTier: 1,
);

TransferDraft _tokenDraft() => TransferDraft(
  symbol: 'USDT',
  networkLabel: 'Ethereum · ERC-20',
  chain: Chain.ethereum,
  recipient: _to,
  amount: Amount.parse('2.5', 6, symbol: 'USDT'),
  feeTier: 1,
  tokenContract: _usdt,
);

Widget _frame({
  required WalletController wallets,
  required TransferSession session,
  Future<GatewayTokenRisk> Function(Coin chain, String contract)?
  tokenRiskLookup,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData(
    fontFamily: 'Inter',
    colorScheme: ColorScheme.fromSeed(seedColor: WalletColors.accent),
    scaffoldBackgroundColor: WalletColors.bg,
  ),
  home: KtDeviceChrome(
    mockStatusBar: false,
    child: WalletScope(
      controller: wallets,
      child: TransferSessionScope(
        session: session,
        child: TransferConfirmScreen(
          key: ValueKey('evm-confirm-${session.draft?.symbol}'),
          isHot: true,
          transferService: _EvmQuoteService(),
          tokenRiskLookup:
              tokenRiskLookup ??
              (_, _) async => const GatewayTokenRisk(
                status: GatewayTokenRiskStatus.safe,
                source: 'official_catalog',
              ),
        ),
      ),
    ),
  ),
);

Future<void> _capture(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
) async {
  final platform = Platform.isIOS ? 'ios' : 'android';
  final fileName = '$platform-$name';
  final bytes = await binding.takeScreenshot(fileName);
  final path = '${Directory.systemTemp.path}/$fileName.png';
  await File(path).writeAsBytes(bytes, flush: true);
  // ignore: avoid_print
  print('EVM_ASSET_CHANGE_CAPTURE READY=$name FILE=$path');
  if (_emitScreenshotBase64) {
    // Explicit local evidence mode only. Keeping the base64 out of normal CI
    // prevents oversized logs while allowing the host to save the exact frame
    // returned by IntegrationTestWidgetsFlutterBinding.
    // ignore: avoid_print
    print('EVM_ASSET_CHANGE_PNG NAME=$fileName DATA=${base64Encode(bytes)}');
  }
  await tester.runAsync(
    () =>
        Future<void>.delayed(Duration(seconds: _emitScreenshotBase64 ? 1 : 60)),
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native confirmation shows decoded asset changes',
    (tester) async {
      if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
      final wallets = _wallets();
      addTearDown(wallets.dispose);

      final nativeSession = TransferSession()..draft = _nativeDraft();
      await tester.pumpWidget(_frame(wallets: wallets, session: nativeSession));
      await tester.pumpAndSettle();
      expect(find.text('预计资产变化'), findsOneWidget);
      expect(find.text('转出 ETH'), findsOneWidget);
      expect(find.text('最多 -0.000672 ETH'), findsOneWidget);
      expect(find.textContaining('尚未备份助记词'), findsNothing);
      expect(tester.takeException(), isNull);
      await _capture(binding, tester, '19-evm-native-asset-changes');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'ERC-20 confirmation separates token outflow and native max fee',
    (tester) async {
      if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
      final wallets = _wallets();
      addTearDown(wallets.dispose);
      final tokenSession = TransferSession()..draft = _tokenDraft();
      await tester.pumpWidget(_frame(wallets: wallets, session: tokenSession));
      await tester.pumpAndSettle();
      expect(find.text('预计资产变化'), findsOneWidget);
      expect(find.text('转出 USDT'), findsOneWidget);
      expect(find.text('最多 -0.00208 ETH'), findsOneWidget);
      expect(find.textContaining('尚未备份助记词'), findsNothing);
      expect(tester.takeException(), isNull);
      await _capture(binding, tester, '20-evm-token-asset-changes');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'unsafe token risk blocks signing with explicit reason',
    (tester) async {
      if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
      final wallets = _wallets();
      addTearDown(wallets.dispose);
      final session = TransferSession()..draft = _tokenDraft();
      await tester.pumpWidget(
        _frame(
          wallets: wallets,
          session: session,
          tokenRiskLookup: (_, _) async => const GatewayTokenRisk(
            status: GatewayTokenRiskStatus.unsafe,
            category: 'phishing',
            source: 'operator_registry',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('检测到高风险 Token 合约'), findsOneWidget);
      expect(find.textContaining('本次签名已阻止'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('token-risk-notice')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _capture(binding, tester, '21-token-risk-unsafe');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'risk service outage stays unknown instead of green',
    (tester) async {
      if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
      final wallets = _wallets();
      addTearDown(wallets.dispose);
      final session = TransferSession()..draft = _tokenDraft();
      await tester.pumpWidget(
        _frame(
          wallets: wallets,
          session: session,
          tokenRiskLookup: (_, _) async => throw TimeoutException('offline'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('暂时无法检查 Token 风险'), findsOneWidget);
      expect(find.text('官方 Token 身份已核对'), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('token-risk-notice')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _capture(binding, tester, '22-token-risk-unavailable');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
