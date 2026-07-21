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
  Future<Map<Coin, BalanceResult>> fetchAll(ChainAddresses addresses) async {
    calls++;
    return results;
  }
}

class _FakePriceService extends PriceService {
  _FakePriceService(this.prices);
  final Map<Coin, double>? prices;
  @override
  Future<Map<Coin, double>?> fetchUsdPrices() async => prices;
}

class _FakeTokenBalanceService extends TokenBalanceService {
  _FakeTokenBalanceService(this.results);
  final Map<String, BalanceResult> results;
  @override
  Future<Map<String, BalanceResult>> fetchAll(ChainAddresses addresses) async =>
      results;
}

WalletController _wallets() => WalletController(WalletManager(initial: [
      HotWallet(
        id: 'w1',
        name: '日常钱包',
        avatarColor: 0xFFF59E0B,
        addresses: const ChainAddresses(
            eth: '0xa', polygon: '0xa', tron: 'Ta', solana: 'a'),
        backedUp: true,
      ),
    ]));

MarketController _liveController() => MarketController(
      wallets: _wallets(),
      balances: _FakeBalanceService({
        Coin.eth: BalanceResult.ok(Amount(
            raw: BigInt.parse('1000000000000000000'),
            decimals: 18,
            symbol: 'ETH')),
        Coin.polygon: BalanceResult.ok(Amount(
            raw: BigInt.parse('2000000000000000000'),
            decimals: 18,
            symbol: 'POL')),
        Coin.tron: BalanceResult.ok(
            Amount(raw: BigInt.from(5000000), decimals: 6, symbol: 'TRX')),
        Coin.solana: BalanceResult.ok(
            Amount(raw: BigInt.from(500000000), decimals: 9, symbol: 'SOL')),
      }),
      prices: _FakePriceService({
        Coin.eth: 2000.0,
        Coin.polygon: 0.5,
        Coin.tron: 0.1,
        Coin.solana: 100.0,
      }),
      tokens: _FakeTokenBalanceService({
        'usdt-eth': BalanceResult.ok(
            Amount(raw: BigInt.from(25000000), decimals: 6, symbol: 'USDT')),
        'usdc-polygon': BalanceResult.ok(
            Amount(raw: BigInt.from(10000000), decimals: 6, symbol: 'USDC')),
        // TronGrid rejected the demo address: honest '--', never a number.
        'usdt-tron': const BalanceResult.error(),
      }),
    );

MarketController _offlineController() => MarketController(
      wallets: _wallets(),
      balances: _FakeBalanceService(
          {for (final c in Coin.values) c: const BalanceResult.error()}),
      prices: _FakePriceService(null),
      tokens: _FakeTokenBalanceService(
          {for (final t in builtinTokens) t.id: const BalanceResult.error()}),
    );

Widget _app(Widget home) => MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

void main() {
  testWidgets('home under a MarketScope shows live balances and fiat total',
      (tester) async {
    final controller = _liveController();
    await tester.pumpWidget(
        _app(MarketScope(controller: controller, child: const HomeScreen())));
    await tester.pumpAndSettle();

    // Live total: 1 ETH*2000 + 2 POL*0.5 + 5 TRX*0.1 + 0.5 SOL*100 = 2051.50,
    // plus the pegged token balances 25 USDT + 10 USDC = 2086.50.
    expect(find.text(r'$2,086.50'), findsOneWidget);
    // Live rows (home tab card; the assets tab inside the IndexedStack builds
    // them too, hence findsWidgets).
    expect(find.text('1 ETH'), findsWidgets);
    expect(find.text('0.5 SOL'), findsWidgets);
    expect(find.text(r'$2,000.00'), findsWidgets);
    // Token rows render under the native rows, fiat via the USD peg; the
    // errored TRON USDT stays an honest '--'.
    expect(find.text('25 USDT · Ethereum'), findsWidgets);
    expect(find.text('10 USDC · Polygon'), findsWidgets);
    expect(find.text(r'$25.00'), findsWidgets);
    expect(find.text(r'$10.00'), findsWidgets);
    expect(find.text('-- USDT · TRON'), findsWidgets);
    // The demo constants must NOT render as if they were live.
    expect(find.text(r'$862.40'), findsNothing);
    expect(find.text('0.0842 ETH'), findsNothing);
    // No offline banner in live mode.
    expect(find.text('离线，显示演示数据'), findsNothing);
    controller.dispose();
  });

  testWidgets(
      'home with every fetch failed shows demo data behind the offline banner',
      (tester) async {
    final controller = _offlineController();
    await tester.pumpWidget(
        _app(MarketScope(controller: controller, child: const HomeScreen())));
    await tester.pumpAndSettle();

    expect(find.text('离线，显示演示数据'), findsWidgets);
    // Demo constants render (explicitly labeled, never as live values).
    expect(find.text(r'$862.40'), findsOneWidget);
    expect(find.text('0.0842 ETH'), findsWidgets);
    controller.dispose();
  });

  testWidgets('home WITHOUT a MarketScope renders the demo constants exactly',
      (tester) async {
    // Same setup as the recorded golden: no scope at all.
    await tester.pumpWidget(_app(const HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text(r'$862.40'), findsOneWidget);
    expect(find.text('0.0842 ETH'), findsWidgets);
    expect(find.text(r'$500.00'), findsWidgets);
    expect(find.text('离线，显示演示数据'), findsNothing);
    expect(find.byType(RefreshIndicator), findsNothing);
  });

  testWidgets('assets list under a MarketScope shows live rows', (tester) async {
    final controller = _liveController();
    await tester.pumpWidget(_app(
        MarketScope(controller: controller, child: const AssetsListScreen())));
    await tester.pumpAndSettle();

    expect(find.text('1 ETH'), findsOneWidget);
    expect(find.text('5 TRX'), findsOneWidget);
    expect(find.text(r'$0.50'), findsOneWidget); // 5 TRX * $0.10
    // Token rows appended under the natives.
    expect(find.text('25 USDT · Ethereum'), findsOneWidget);
    expect(find.text('10 USDC · Polygon'), findsOneWidget);
    expect(find.text('-- USDT · TRON'), findsOneWidget);
    expect(find.text('2.4805 ETH'), findsNothing); // demo row absent
    controller.dispose();
  });

  testWidgets('assets list network filter keeps only that chain\'s token rows',
      (tester) async {
    final controller = _liveController();
    await tester.pumpWidget(_app(
        MarketScope(controller: controller, child: const AssetsListScreen())));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Polygon').first);
    await tester.pumpAndSettle();
    expect(find.text('10 USDC · Polygon'), findsOneWidget);
    expect(find.text('25 USDT · Ethereum'), findsNothing);
    expect(find.text('1 ETH'), findsNothing);
    controller.dispose();
  });

  testWidgets('assets list WITHOUT a scope renders the demo rows', (tester) async {
    await tester.pumpWidget(_app(const AssetsListScreen()));
    await tester.pumpAndSettle();
    expect(find.text('2.4805 ETH'), findsOneWidget);
    expect(find.text(r'$8,241.60'), findsOneWidget);
  });

  testWidgets('changing a persisted RPC override triggers a market refresh',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = AppPrefsController();
    final wallets = _wallets();
    final balances = _FakeBalanceService(
        {for (final c in Coin.values) c: const BalanceResult.error()});
    final controller = MarketController(
      wallets: wallets,
      balances: balances,
      prices: _FakePriceService(null),
      tokens: _FakeTokenBalanceService(
          {for (final t in builtinTokens) t.id: const BalanceResult.error()}),
    );
    await tester.pumpWidget(_app(MarketScopeHost(
      wallets: wallets,
      controller: controller,
      prefs: prefs,
      child: const HomeScreen(),
    )));
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
}
