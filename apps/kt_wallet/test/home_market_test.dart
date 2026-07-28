import 'package:chains/chains.dart' show Amount;
import 'package:core_crypto/core_crypto.dart' show ChainAddresses, Coin;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/market/balance_service.dart';
import 'package:kt_wallet/src/market/market_controller.dart';
import 'package:kt_wallet/src/market/market_scope.dart';
import 'package:kt_wallet/src/market/price_service.dart';
import 'package:kt_wallet/src/market/token_balance_service.dart';
import 'package:kt_wallet/src/screens/assets_screens.dart';
import 'package:kt_wallet/src/screens/home_screen.dart';
import 'package:kt_wallet/src/state/app_prefs.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeBalanceService extends BalanceService {
  _FakeBalanceService(this.results);
  final Map<Coin, BalanceResult> results;
  int calls = 0;
  @override
  Future<Map<Coin, BalanceResult>> fetchAll(
    ChainAddresses addresses, {
    BalanceResultCallback? onResult,
  }) async {
    calls++;
    for (final entry in results.entries) {
      onResult?.call(entry.key, entry.value);
    }
    return results;
  }
}

class _FakePriceService extends PriceService {
  _FakePriceService(
    this.prices, {
    this.tokenPrices = const {'USDT': 0.99, 'USDC': 1.01},
    this.changes = const {},
    this.tokenChanges = const {},
  });
  final Map<Coin, double>? prices;
  final Map<String, double> tokenPrices;
  final Map<Coin, double> changes;
  final Map<String, double> tokenChanges;
  @override
  Future<Map<Coin, double>?> fetchUsdPrices() async => prices;
  @override
  double? tokenPriceUsd(String symbol) => tokenPrices[symbol];
  @override
  double? change24hPercent(Coin coin) => changes[coin];
  @override
  double? tokenChange24hPercent(String symbol) => tokenChanges[symbol];
}

class _FakeTokenBalanceService extends TokenBalanceService {
  _FakeTokenBalanceService(this.results);
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
        name: '日常钱包',
        avatarColor: 0xFFF59E0B,
        addresses: const ChainAddresses(
          eth: '0xa',
          polygon: '0xa',
          tron: 'Ta',
          solana: 'a',
        ),
        backedUp: true,
      ),
    ],
  ),
);

MarketController _liveController() => MarketController(
  wallets: _wallets(),
  balances: _FakeBalanceService({
    Coin.eth: BalanceResult.ok(
      Amount(
        raw: BigInt.parse('1000000000000000000'),
        decimals: 18,
        symbol: 'ETH',
      ),
    ),
    Coin.polygon: BalanceResult.ok(
      Amount(
        raw: BigInt.parse('2000000000000000000'),
        decimals: 18,
        symbol: 'POL',
      ),
    ),
    Coin.tron: BalanceResult.ok(
      Amount(raw: BigInt.from(5000000), decimals: 6, symbol: 'TRX'),
    ),
    Coin.solana: BalanceResult.ok(
      Amount(raw: BigInt.from(500000000), decimals: 9, symbol: 'SOL'),
    ),
  }),
  prices: _FakePriceService(
    {Coin.eth: 2000.0, Coin.polygon: 0.5, Coin.tron: 0.1, Coin.solana: 100.0},
    changes: const {
      Coin.eth: 10,
      Coin.polygon: 10,
      Coin.tron: 10,
      Coin.solana: 10,
    },
    tokenChanges: const {'USDT': 10, 'USDC': 10},
  ),
  tokens: _FakeTokenBalanceService({
    'usdt-eth': BalanceResult.ok(
      Amount(raw: BigInt.from(25000000), decimals: 6, symbol: 'USDT'),
    ),
    'usdc-polygon': BalanceResult.ok(
      Amount(raw: BigInt.from(10000000), decimals: 6, symbol: 'USDC'),
    ),
    // TronGrid rejected the demo address: honest '--', never a number.
    'usdt-tron': const BalanceResult.error(),
  }),
);

MarketController _offlineController() => MarketController(
  wallets: _wallets(),
  balances: _FakeBalanceService({
    for (final c in Coin.values) c: const BalanceResult.error(),
  }),
  // No token quotes either: an offline session must not fall back to a $1
  // peg for stablecoins.
  prices: _FakePriceService(null, tokenPrices: const {}),
  tokens: _FakeTokenBalanceService({
    for (final t in builtinTokens) t.id: const BalanceResult.error(),
  }),
);

Widget _app(Widget home) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

void main() {
  testWidgets('home under a MarketScope shows live balances and fiat total', (
    tester,
  ) async {
    final controller = _liveController();
    await tester.pumpWidget(
      _app(MarketScope(controller: controller, child: const HomeScreen())),
    );
    await tester.pumpAndSettle();

    // Token fiat uses live quotes (USDT 0.99, USDC 1.01), not a $1 peg.
    // Live total: 1 ETH*2000 + 2 POL*0.5 + 5 TRX*0.1 + 0.5 SOL*100 = 2051.50,
    // plus live-priced tokens: 25*0.99 + 10*1.01 = 2086.35.
    expect(find.text(r'$2,086.35'), findsOneWidget);
    expect(find.text(r'+$189.67 (+10.00%) 过去24小时'), findsOneWidget);
    expect(find.text('+10.00%'), findsWidgets);
    // Live rows (home tab card; the assets tab inside the IndexedStack builds
    // them too, hence findsWidgets).
    // ETH is native on Ethereum, Base and Arbitrum, so it is ONE row across
    // three chains — not three rows that each say "0 ETH".
    expect(find.text('1 ETH · 3 条链'), findsWidgets);
    expect(find.text('0.5 SOL · Solana'), findsWidgets);
    expect(find.text(r'$2,000.00'), findsWidgets);
    // Token rows render under the native rows using live market quotes; the
    // errored TRON USDT stays an honest '--'.
    // USDT is deployed on Ethereum and TRON, so it is ONE row now, not two.
    // TronGrid rejected the demo address, so that leg is excluded from the
    // sum and shows '--' in the detail breakdown — the row still reports the
    // 25 that did load.
    expect(find.text('25 USDT · 7 条链'), findsWidgets);
    expect(find.text('10 USDC · 6 条链'), findsWidgets);
    expect(find.text(r'$24.75'), findsWidgets);
    expect(find.text(r'$10.10'), findsWidgets);
    expect(find.text('-- USDT · TRON'), findsNothing);
    // The demo constants must NOT render as if they were live.
    expect(find.text(r'$862.40'), findsNothing);
    expect(find.text('0.0842 ETH'), findsNothing);
    // No offline banner in live mode.
    expect(find.text('离线，显示演示数据'), findsNothing);
    controller.dispose();
  });

  testWidgets(
    'home with every fetch failed never substitutes production demo data',
    (tester) async {
      final controller = _offlineController();
      await tester.pumpWidget(
        _app(MarketScope(controller: controller, child: const HomeScreen())),
      );
      await tester.pumpAndSettle();

      expect(find.text('网络不可用，实时数据加载失败'), findsWidgets);
      expect(find.text(r'$862.40'), findsNothing);
      expect(find.text('0.0842 ETH'), findsNothing);
      controller.dispose();
    },
  );

  testWidgets('home WITHOUT a MarketScope renders the demo constants exactly', (
    tester,
  ) async {
    // Same setup as the recorded golden: no scope at all.
    await tester.pumpWidget(_app(const HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text(r'$862.40'), findsOneWidget);
    expect(find.text('0.0842 ETH'), findsWidgets);
    expect(find.text(r'$500.00'), findsWidgets);
    expect(find.text('离线，显示演示数据'), findsNothing);
    expect(find.byType(RefreshIndicator), findsNothing);
  });

  testWidgets('assets list under a MarketScope shows live rows', (
    tester,
  ) async {
    final controller = _liveController();
    await tester.pumpWidget(
      _app(
        MarketScope(controller: controller, child: const AssetsListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 ETH · 3 条链'), findsOneWidget);
    expect(find.text('5 TRX · TRON'), findsOneWidget);
    expect(find.text(r'$0.50'), findsOneWidget); // 5 TRX * $0.10
    // Token rows appended under the natives.
    expect(find.text('25 USDT · 7 条链'), findsOneWidget);
    expect(find.text('10 USDC · 6 条链'), findsOneWidget);
    expect(find.text('-- USDT · TRON'), findsNothing);
    expect(find.text('2.4805 ETH'), findsNothing); // demo row absent
    controller.dispose();
  });

  testWidgets(
    'assets list network filter keeps only that chain\'s token rows',
    (tester) async {
      final controller = _liveController();
      await tester.pumpWidget(
        _app(
          MarketScope(controller: controller, child: const AssetsListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Polygon').first);
      await tester.pumpAndSettle();
      // Both stablecoins ARE deployed on Polygon, so both survive the filter.
      // The multi-chain rows used to carry a '*' sentinel that matched no
      // specific chip, so picking a network hid the very tokens held on it.
      expect(find.text('10 USDC · 6 条链'), findsOneWidget);
      expect(find.text('25 USDT · 7 条链'), findsOneWidget);
      // Native rows still filter to their own chain.
      expect(find.text('1 ETH · 3 条链'), findsNothing);
      controller.dispose();
    },
  );

  testWidgets('assets list WITHOUT a scope renders the demo rows', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const AssetsListScreen()));
    await tester.pumpAndSettle();
    expect(find.text('2.4805 ETH'), findsOneWidget);
    expect(find.text(r'$8,241.60'), findsOneWidget);
  });

  testWidgets('changing a persisted RPC override triggers a market refresh', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = AppPrefsController();
    final wallets = _wallets();
    final balances = _FakeBalanceService({
      for (final c in Coin.values) c: const BalanceResult.error(),
    });
    final controller = MarketController(
      wallets: wallets,
      balances: balances,
      prices: _FakePriceService(null),
      tokens: _FakeTokenBalanceService({
        for (final t in builtinTokens) t.id: const BalanceResult.error(),
      }),
    );
    await tester.pumpWidget(
      _app(
        MarketScopeHost(
          wallets: wallets,
          controller: controller,
          prefs: prefs,
          child: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(balances.calls, 1); // home-entry refresh

    await prefs.setRpcOverride(Coin.eth, 'https://my-eth.example');
    await tester.pumpAndSettle();
    expect(balances.calls, 2); // endpoint change → refetch

    // Unrelated preference edits do not refetch.
    await prefs.setFiat('CNY');
    await tester.pumpAndSettle();
    expect(balances.calls, 2);

    // Clearing the override back to the default refetches once more.
    await prefs.setRpcOverride(Coin.eth, null);
    await tester.pumpAndSettle();
    expect(balances.calls, 3);
    controller.dispose();
  });

  testWidgets('changing the persisted gateway URL triggers a market refresh', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = AppPrefsController();
    final wallets = _wallets();
    final balances = _FakeBalanceService({
      for (final c in Coin.values) c: const BalanceResult.error(),
    });
    final controller = MarketController(
      wallets: wallets,
      balances: balances,
      prices: _FakePriceService(null),
      tokens: _FakeTokenBalanceService({
        for (final t in builtinTokens) t.id: const BalanceResult.error(),
      }),
    );
    await tester.pumpWidget(
      _app(
        MarketScopeHost(
          wallets: wallets,
          controller: controller,
          prefs: prefs,
          child: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(balances.calls, 1); // home-entry refresh

    // Configuring a gateway changes where every balance comes from → refetch.
    await prefs.setGatewayUrl('https://gw.example');
    await tester.pumpAndSettle();
    expect(balances.calls, 2);

    // Unrelated preference edits still do not refetch.
    await prefs.setFiat('CNY');
    await tester.pumpAndSettle();
    expect(balances.calls, 2);

    // Clearing back to direct mode refetches once more.
    await prefs.setGatewayUrl(null);
    await tester.pumpAndSettle();
    expect(balances.calls, 3);
    controller.dispose();
  });
}
