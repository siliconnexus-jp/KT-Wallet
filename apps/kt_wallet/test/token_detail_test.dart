import 'package:chains/chains.dart' show Amount, Chain;
import 'package:core_crypto/core_crypto.dart' show ChainAddresses, Coin;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/market/asset_ref.dart';
import 'package:kt_wallet/src/transfer/airgap_codec.dart' show truncateMiddle;
import 'package:kt_wallet/src/market/balance_service.dart';
import 'package:kt_wallet/src/market/explorer_links.dart';
import 'package:kt_wallet/src/market/market_controller.dart';
import 'package:kt_wallet/src/market/market_scope.dart';
import 'package:kt_wallet/src/market/price_service.dart';
import 'package:kt_wallet/src/market/token_balance_service.dart';
import 'package:kt_wallet/src/screens/assets_screens.dart';
import 'package:kt_wallet/src/state/networks.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/state/wallet_scope.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';

/// The detail route used to take no arguments and hardcode "3,120.00 USDT",
/// a $1.00 price and a TRON contract — so every asset row on the home list and
/// the assets tab opened the same page and showed a balance the user did not
/// hold. These pin the real thing down.
class _FakeBalances extends BalanceService {
  _FakeBalances(this.results);
  final Map<Coin, BalanceResult> results;
  @override
  Future<Map<Coin, BalanceResult>> fetchAll(
    ChainAddresses addresses, {
    BalanceResultCallback? onResult,
  }) async {
    results.forEach((k, v) => onResult?.call(k, v));
    return results;
  }
}

class _FakePrices extends PriceService {
  _FakePrices(this.prices, {this.tokenPrices = const {'USDT': 0.95}});
  final Map<Coin, double>? prices;
  final Map<String, double> tokenPrices;
  @override
  Future<Map<Coin, double>?> fetchUsdPrices() async => prices;
  @override
  double? tokenPriceUsd(String symbol) => tokenPrices[symbol];
}

class _FakeTokens extends TokenBalanceService {
  _FakeTokens(this.results);
  final Map<String, BalanceResult> results;
  @override
  Future<Map<String, BalanceResult>> fetchAll(ChainAddresses addresses) async =>
      results;
}

WalletController _wallets() => WalletController(
  WalletManager(
    initial: [
      HotWallet(
        id: 'w1',
        name: 'W',
        avatarColor: 0xFFF59E0B,
        addresses: const ChainAddresses(
          eth: '0xabc',
          polygon: '0xabc',
          tron: 'Tabc',
          solana: 'solabc',
        ),
        backedUp: true,
      ),
    ],
  ),
);

late WalletController _walletController;

MarketController _controller() => MarketController(
  wallets: _walletController = _wallets(),
  balances: _FakeBalances({
    Coin.eth: BalanceResult.ok(
      Amount(
        raw: BigInt.parse('3000000000000000000'),
        decimals: 18,
        symbol: 'ETH',
      ),
    ),
    // Errored on purpose: the detail screen must show '--', not a number.
    Coin.solana: const BalanceResult.error(),
  }),
  prices: _FakePrices({Coin.eth: 2000.0}),
  tokens: _FakeTokens({
    'usdt-eth': BalanceResult.ok(
      Amount(raw: BigInt.from(7500000), decimals: 6, symbol: 'USDT'),
    ),
    // Second USDT deployment: the group must sum both.
    'usdt-tron': BalanceResult.ok(
      Amount(raw: BigInt.from(2500000), decimals: 6, symbol: 'USDT'),
    ),
  }),
);

Widget _app(MarketController market, Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: WalletScope(
    controller: _walletController,
    child: MarketScope(controller: market, child: child),
  ),
);

void main() {
  testWidgets('a native coin shows ITS balance, price and chain', (
    tester,
  ) async {
    final market = _controller();
    addTearDown(market.dispose);
    // The detail screen reads the shared controller; the list the user came
    // from is what triggers the fetch.
    await market.refresh();
    await tester.pumpWidget(
      _app(
        market,
        const TokenDetailScreen(
          asset: AssetRef.native(
            coin: Coin.eth,
            name: 'Ethereum',
            symbol: 'ETH',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('3 ETH'), findsOneWidget);
    expect(find.text(r'≈ $6,000.00'), findsOneWidget);
    expect(find.text(r'$2,000.00'), findsOneWidget); // price row
    expect(find.text('Ethereum'), findsWidgets);

    // None of the old hardcoded token page may survive.
    expect(find.text('3,120.00 USDT'), findsNothing);
    expect(find.text(r'≈ $3,120.00'), findsNothing);
    expect(find.text(r'$1.00'), findsNothing);
    expect(find.text('TR7NHq…gjLj6t'), findsNothing);
    expect(find.text('+0.02%'), findsNothing);
  });

  testWidgets('a token shows its own balance and contract', (tester) async {
    final market = _controller();
    addTearDown(market.dispose);
    await market.refresh();
    final usdt = market.tokens.firstWhere((t) => t.id == 'usdt-eth');
    await tester.pumpWidget(
      _app(market, TokenDetailScreen(asset: AssetRef.token(usdt))),
    );
    await tester.pumpAndSettle();

    expect(find.text('7.5 USDT'), findsOneWidget);
    expect(find.text(r'≈ $7.13'), findsOneWidget);
    expect(find.text(r'$0.95'), findsOneWidget);
    expect(find.text('3,120.00 USDT'), findsNothing);
  });

  testWidgets('an unloaded balance renders -- and never a number', (
    tester,
  ) async {
    final market = _controller();
    addTearDown(market.dispose);
    // The detail screen reads the shared controller; the list the user came
    // from is what triggers the fetch.
    await market.refresh();
    await tester.pumpWidget(
      _app(
        market,
        const TokenDetailScreen(
          asset: AssetRef.native(
            coin: Coin.solana,
            name: 'Solana',
            symbol: 'SOL',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('-- SOL'), findsOneWidget);
    expect(find.text('3,120.00 USDT'), findsNothing);
  });

  testWidgets('a live scope with no asset says so, it does not invent one', (
    tester,
  ) async {
    final market = _controller();
    addTearDown(market.dispose);
    // The detail screen reads the shared controller; the list the user came
    // from is what triggers the fetch.
    await market.refresh();
    await tester.pumpWidget(_app(market, const TokenDetailScreen()));
    await tester.pumpAndSettle();

    expect(find.text('该资产已不可用'), findsOneWidget);
    expect(find.text('3,120.00 USDT'), findsNothing);
  });

  testWidgets('scope-absent keeps the design snapshot for the gallery', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const TokenDetailScreen(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('3,120.00 USDT'), findsOneWidget);
  });

  // The registry lists a TokenInfo per network, so USDC/USDT appeared once
  // per chain in the asset list. One row per symbol now, broken down here.
  testWidgets('a multi-chain group sums its deployments and lists them', (
    tester,
  ) async {
    final market = _controller();
    addTearDown(market.dispose);
    await market.refresh();
    final usdt = market.tokens.where((t) => t.symbol == 'USDT').toList();
    expect(usdt.length, greaterThan(1), reason: 'need a multi-chain fixture');

    await tester.pumpWidget(
      _app(market, TokenDetailScreen(asset: AssetRef.tokenGroup(usdt))),
    );
    await tester.pumpAndSettle();

    // 7.5 on Ethereum + 2.5 on TRON. The total is on the page; the split is
    // one tap away rather than permanently expanded.
    expect(find.text('10 USDT'), findsOneWidget);
    expect(find.text('选择网络'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('chain-chip')));
    await tester.pumpAndSettle();
    expect(find.text('选择网络'), findsOneWidget);
    // Every deployment is listed with its own balance.
    expect(find.text('7.5 USDT'), findsOneWidget);
    expect(find.text('2.5 USDT'), findsOneWidget);
  });

  testWidgets('a chain that failed is excluded from the sum and shows --', (
    tester,
  ) async {
    final wallets = _wallets();
    final market = MarketController(
      wallets: wallets,
      balances: _FakeBalances({}),
      prices: _FakePrices({}),
      tokens: _FakeTokens({
        'usdt-eth': BalanceResult.ok(
          Amount(raw: BigInt.from(7500000), decimals: 6, symbol: 'USDT'),
        ),
        'usdt-tron': const BalanceResult.error(),
      }),
    );
    _walletController = wallets;
    addTearDown(market.dispose);
    await market.refresh();
    final usdt = market.tokens.where((t) => t.symbol == 'USDT').toList();

    await tester.pumpWidget(
      _app(market, TokenDetailScreen(asset: AssetRef.tokenGroup(usdt))),
    );
    await tester.pumpAndSettle();

    // The loaded leg is reported; the failed one is visibly '--' rather than
    // being folded into the total as a zero.
    expect(find.text('7.5 USDT'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chain-chip')));
    await tester.pumpAndSettle();
    expect(find.text('7.5 USDT'), findsWidgets);
    // TRON errored; Avalanche and Solana never loaded in this fixture. All of
    // them read '--' rather than being folded in as zeroes.
    expect(find.text('-- USDT'), findsWidgets);
  });

  testWidgets('picking a chain re-points the actions at it', (tester) async {
    final market = _controller();
    addTearDown(market.dispose);
    await market.refresh();
    final usdt = market.tokens.where((t) => t.symbol == 'USDT').toList();

    await tester.pumpWidget(
      _app(market, TokenDetailScreen(asset: AssetRef.tokenGroup(usdt))),
    );
    await tester.pumpAndSettle();

    // Defaults to the chain holding the most (Ethereum, 7.5), named on a
    // chip; the full list lives behind it, OKX-style, rather than as a
    // permanently expanded radio card.
    expect(find.text('Ethereum'), findsWidgets);
    expect(find.byKey(const ValueKey('chain-chip')), findsOneWidget);

    final second = usdt[1];
    expect(
      find.byKey(ValueKey('chain-option-${second.id}')),
      findsNothing,
      reason: 'options appear only once the chip is tapped',
    );
    await tester.tap(find.byKey(const ValueKey('chain-chip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('chain-option-${second.id}')));
    await tester.pumpAndSettle();

    // The contract row follows the selection.
    expect(find.text(truncateMiddle(second.contract)), findsOneWidget);
  });

  // Stablecoin fiat comes from live quotes now, not a hardcoded $1 peg, so a
  // depeg has to show through instead of being rounded back to par.
  testWidgets('a depegged stablecoin is valued at its quote', (tester) async {
    final wallets = _wallets();
    _walletController = wallets;
    final market = MarketController(
      wallets: wallets,
      balances: _FakeBalances({}),
      // 100 USDT quoted at $0.80.
      prices: _FakePrices({}, tokenPrices: const {'USDT': 0.80}),
      tokens: _FakeTokens({
        'usdt-eth': BalanceResult.ok(
          Amount(raw: BigInt.from(100000000), decimals: 6, symbol: 'USDT'),
        ),
      }),
    );
    addTearDown(market.dispose);
    await market.refresh();
    final usdt = market.tokens.firstWhere((t) => t.id == 'usdt-eth');

    await tester.pumpWidget(
      _app(market, TokenDetailScreen(asset: AssetRef.token(usdt))),
    );
    await tester.pumpAndSettle();

    expect(find.text('100 USDT'), findsOneWidget);
    expect(find.text(r'≈ $80.00'), findsOneWidget);
    expect(find.text(r'$0.80'), findsOneWidget); // price row
    // The old behaviour would have shown par.
    expect(find.text(r'≈ $100.00'), findsNothing);
    expect(find.text(r'$1.00'), findsNothing);
  });

  group('explorer links', () {
    const evm = Network(
      id: 'eth',
      chain: Chain.ethereum,
      name: 'Ethereum',
      rpcUrl: 'https://rpc',
      symbol: 'X',
      explorerUrl: 'https://etherscan.io',
    );
    const tron = Network(
      id: 'tron',
      chain: Chain.tron,
      name: 'TRON',
      rpcUrl: 'https://rpc',
      symbol: 'X',
      explorerUrl: 'https://tronscan.org',
    );
    const devnet = Network(
      id: 'sol-devnet',
      chain: Chain.solana,
      name: 'Devnet',
      rpcUrl: 'https://rpc',
      symbol: 'X',
      explorerUrl: 'https://explorer.solana.com?cluster=devnet',
      isTestnet: true,
    );

    test('addresses and tokens use the per-family path', () {
      expect(
        explorerAddressUrl(evm, '0xabc'),
        'https://etherscan.io/address/0xabc',
      );
      expect(
        explorerTokenUrl(evm, '0xdef'),
        'https://etherscan.io/token/0xdef',
      );
      expect(
        explorerAddressUrl(tron, 'Tabc'),
        'https://tronscan.org/#/address/Tabc',
      );
      expect(
        explorerTokenUrl(tron, 'Tdef'),
        'https://tronscan.org/#/token20/Tdef',
      );
      // SPL mints are plain accounts on explorer.solana.com.
      expect(
        explorerTokenUrl(devnet, 'mint'),
        'https://explorer.solana.com/address/mint?cluster=devnet',
      );
    });

    test('a query suffix on the base stays after the path', () {
      expect(
        explorerAddressUrl(devnet, 'solabc'),
        'https://explorer.solana.com/address/solabc?cluster=devnet',
      );
      expect(
        explorerTxUrl(devnet, 'sig'),
        'https://explorer.solana.com/tx/sig?cluster=devnet',
      );
    });
  });
}
