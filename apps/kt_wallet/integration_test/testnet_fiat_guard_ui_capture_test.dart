import 'package:chains/chains.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:core_crypto/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/market/asset_ref.dart';
import 'package:kt_wallet/src/market/balance_service.dart';
import 'package:kt_wallet/src/market/market_controller.dart';
import 'package:kt_wallet/src/market/market_scope.dart';
import 'package:kt_wallet/src/market/price_service.dart';
import 'package:kt_wallet/src/market/token_balance_service.dart';
import 'package:kt_wallet/src/screens/assets_screens.dart';
import 'package:kt_wallet/src/screens/home_screen.dart';
import 'package:kt_wallet/src/screens/transfer_screens.dart';
import 'package:kt_wallet/src/state/networks.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/transfer/airgap_codec.dart' show rawTxFor;
import 'package:kt_wallet/src/state/wallet_scope.dart';
import 'package:kt_wallet/src/transfer/local_transfer_service.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:ui_kit/ui_kit.dart';

const _evmFrom = '0x70997970C51812dc3A010C7d01b50e0d17dc79C8';
const _evmTo = '0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC';

class _TestnetBalances extends BalanceService {
  @override
  Future<Map<Coin, BalanceResult>> fetchAll(
    ChainAddresses addresses, {
    BalanceResultCallback? onResult,
  }) async {
    final results = {
      for (final coin in Coin.values)
        coin: BalanceResult.ok(
          Amount(
            raw:
                BigInt.from(1000000) *
                BigInt.from(10).pow(BalanceService.decimalsFor[coin]! - 6),
            decimals: BalanceService.decimalsFor[coin]!,
            symbol: BalanceService.symbolFor[coin]!,
          ),
        ),
    };
    for (final entry in results.entries) {
      onResult?.call(entry.key, entry.value);
    }
    return results;
  }
}

class _TestnetTokens extends TokenBalanceService {
  @override
  List<TokenInfo> get tokens => const [busdBnbTestnetToken];

  @override
  Future<Map<String, BalanceResult>> fetchAll(ChainAddresses addresses) async =>
      {
        busdBnbTestnetToken.id: BalanceResult.ok(
          Amount(
            raw: BigInt.parse('10000000000000000000'),
            decimals: 18,
            symbol: 'BUSD',
          ),
        ),
      };
}

class _SepoliaQuoteService extends LocalTransferService {
  @override
  Future<PreparedEvmTransfer> prepareEvm({
    required TransferDraft draft,
    required String from,
    required int evmChainId,
  }) async {
    final nonce = BigInt.from(7);
    final priorityFee = BigInt.from(2000000000);
    final maxFee = BigInt.from(32000000000);
    final gasLimit = BigInt.from(21000);
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
        id: 'testnet-fiat-evidence',
        name: '测试钱包',
        avatarColor: 0xFF3155DD,
        addresses: const ChainAddresses(
          eth: _evmFrom,
          polygon: _evmFrom,
          base: _evmFrom,
          arbitrum: _evmFrom,
          avalanche: _evmFrom,
          bnb: _evmFrom,
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

Future<MarketController> _market(WalletController wallets) async {
  final prices = PriceService()
    ..restoreLastGood(
      nativeUsd: {for (final coin in Coin.values) coin: 2000},
      tokenUsd: const {'BUSD': 0.80},
      nativeChange24h: {for (final coin in Coin.values) coin: 5.2},
      tokenChange24h: const {'BUSD': 4.2},
    );
  final controller = MarketController(
    wallets: wallets,
    balances: _TestnetBalances(),
    tokens: _TestnetTokens(),
    prices: prices,
    isTestnet: (_) => true,
  );
  await controller.refresh();
  return controller;
}

Widget _frame({
  required WalletController wallets,
  required MarketController market,
  required NetworkController networks,
  required Widget child,
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
    child: NetworkScope(
      controller: networks,
      child: WalletScope(
        controller: wallets,
        child: MarketScope(controller: market, child: child),
      ),
    ),
  ),
);

Future<void> _evidencePause(WidgetTester tester, String marker) async {
  // ignore: avoid_print
  print('TESTNET_FIAT_CAPTURE READY=$marker');
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(seconds: 20)),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'testnet never displays cached mainnet fiat on home, token or confirm',
    (tester) async {
      final wallets = _wallets();
      final market = await _market(wallets);
      final networks = NetworkController(
        initialEnvironment: NetworkEnvironment.testnet,
      );
      addTearDown(wallets.dispose);
      addTearDown(market.dispose);

      await tester.pumpWidget(
        _frame(
          wallets: wallets,
          market: market,
          networks: networks,
          child: const HomeScreen(key: ValueKey('testnet-home')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('测试网资产无市场价格'), findsOneWidget);
      expect(find.textContaining(r'$'), findsNothing);
      await _evidencePause(tester, 'home');

      await tester.pumpWidget(
        _frame(
          wallets: wallets,
          market: market,
          networks: networks,
          child: TokenDetailScreen(
            key: const ValueKey('testnet-token'),
            asset: AssetRef.token(busdBnbTestnetToken),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('10 BUSD'), findsOneWidget);
      expect(find.text(r'$0.80'), findsNothing);
      expect(find.text('+4.20%'), findsNothing);
      await _evidencePause(tester, 'token');

      final session = TransferSession()
        ..draft = TransferDraft(
          symbol: 'ETH',
          networkLabel: 'Sepolia',
          chain: Chain.ethereum,
          recipient: _evmTo,
          amount: Amount.parse('0.5', 18, symbol: 'ETH'),
          feeTier: 1,
        );
      await tester.pumpWidget(
        _frame(
          wallets: wallets,
          market: market,
          networks: networks,
          child: TransferSessionScope(
            session: session,
            child: TransferConfirmScreen(
              key: const ValueKey('testnet-confirm'),
              isHot: true,
              transferService: _SepoliaQuoteService(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('测试网资产无市场价格'), findsOneWidget);
      expect(find.text('≈ 0.000672 ETH'), findsOneWidget);
      expect(find.textContaining('（--）'), findsNothing);
      expect(find.textContaining(r'$'), findsNothing);
      expect(session.preparedNetworkId, 'eth-sepolia');
      await _evidencePause(tester, 'confirm');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
