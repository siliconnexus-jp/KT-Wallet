import 'dart:async';
import 'dart:io';

import 'package:chains/chains.dart' show Amount;
import 'package:core_crypto/core_crypto.dart' show ChainAddresses, Coin;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/market/balance_service.dart';
import 'package:kt_wallet/src/market/history_controller.dart';
import 'package:kt_wallet/src/market/history_service.dart';
import 'package:kt_wallet/src/market/history_snapshot.dart';
import 'package:kt_wallet/src/market/market_controller.dart';
import 'package:kt_wallet/src/market/market_scope.dart';
import 'package:kt_wallet/src/market/market_snapshot.dart';
import 'package:kt_wallet/src/market/price_service.dart';
import 'package:kt_wallet/src/market/token_balance_service.dart';
import 'package:kt_wallet/src/screens/assets_screens.dart';
import 'package:kt_wallet/src/screens/home_screen.dart';
import 'package:kt_wallet/src/state/app_prefs.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/state/wallet_scope.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';

class _Balances extends BalanceService {
  _Balances(this.results, {this.gate});

  final Map<Coin, BalanceResult> results;
  final Completer<void>? gate;

  @override
  Future<Map<Coin, BalanceResult>> fetchAll(
    ChainAddresses addresses, {
    BalanceResultCallback? onResult,
  }) async {
    if (gate != null) await gate!.future;
    for (final entry in results.entries) {
      onResult?.call(entry.key, entry.value);
    }
    return results;
  }
}

class _Prices extends PriceService {
  _Prices(this.values);
  final Map<Coin, double>? values;

  @override
  Future<Map<Coin, double>?> fetchUsdPrices() async => values;

  @override
  double? tokenPriceUsd(String symbol) =>
      symbol == 'USDC' || symbol == 'USDT' ? 1 : null;
}

class _Tokens extends TokenBalanceService {
  _Tokens(this.results);
  final Map<String, BalanceResult> results;

  @override
  Future<Map<String, BalanceResult>> fetchAll(ChainAddresses addresses) async =>
      results;
}

class _MarketSnapshots implements MarketSnapshotStore {
  _MarketSnapshots(this.snapshot);
  final MarketSnapshot? snapshot;

  @override
  Future<MarketSnapshot?> load(String walletId, String scope) async =>
      snapshot?.scope == scope ? snapshot : null;

  @override
  Future<void> save(String walletId, MarketSnapshot snapshot) async {}
}

class _PagedHistory extends HistoryService {
  @override
  Future<HistoryResult> fetch(
    Coin coin,
    String address, {
    int limit = HistoryService.pageSize,
    String? networkId,
  }) async {
    if (coin != Coin.eth) return const HistoryResult.unsupported();
    return HistoryResult.ok([
      for (var i = 0; i < limit; i++)
        ChainTxRecord(
          coin: Coin.eth,
          id: '0x${i.toRadixString(16)}:native',
          hash: '0x${i.toRadixString(16).padLeft(64, '0')}',
          outgoing: i.isEven,
          fromAddress: i.isEven
              ? _addresses.eth
              : '0x2222222222222222222222222222222222222222',
          toAddress: i.isEven
              ? '0x2222222222222222222222222222222222222222'
              : _addresses.eth,
          amountText: '${(i + 1) / 1000} ETH',
          timestamp: DateTime(2026, 7, 30, 15).subtract(Duration(minutes: i)),
          confirmed: true,
        ),
    ]);
  }
}

class _FailingHistory extends HistoryService {
  @override
  Future<HistoryResult> fetch(
    Coin coin,
    String address, {
    int limit = HistoryService.pageSize,
    String? networkId,
  }) async => const HistoryResult.error();
}

class _HistorySnapshots implements HistorySnapshotStore {
  _HistorySnapshots(this.snapshot);
  final HistorySnapshot snapshot;

  @override
  Future<HistorySnapshot?> load(String walletId, String scope) async =>
      snapshot.scope == scope ? snapshot : null;

  @override
  Future<void> save(String walletId, HistorySnapshot snapshot) async {}
}

const _addresses = ChainAddresses(
  eth: '0x1111111111111111111111111111111111111111',
  polygon: '0x1111111111111111111111111111111111111111',
  base: '0x1111111111111111111111111111111111111111',
  arbitrum: '0x1111111111111111111111111111111111111111',
  avalanche: '0x1111111111111111111111111111111111111111',
  bnb: '0x1111111111111111111111111111111111111111',
  tron: 'TJRabPrwbZy45sbavfcjinPJC18kjpRTv8',
  solana: '11111111111111111111111111111111',
);

WalletController _wallets() => WalletController(
  WalletManager(
    initial: [
      HotWallet(
        id: 'experience-wallet',
        name: '体验验收钱包',
        avatarColor: 0xFF5570D8,
        addresses: _addresses,
        backedUp: true,
      ),
    ],
  ),
);

Map<Coin, BalanceResult> _liveNative() => {
  Coin.eth: BalanceResult.ok(
    Amount(
      raw: BigInt.parse('1250000000000000000'),
      decimals: 18,
      symbol: 'ETH',
    ),
  ),
  for (final coin in Coin.values.where((coin) => coin != Coin.eth))
    coin: BalanceResult.ok(
      Amount(
        raw: BigInt.zero,
        decimals: coin == Coin.tron
            ? 6
            : coin == Coin.solana
            ? 9
            : 18,
        symbol: switch (coin) {
          Coin.polygon => 'POL',
          Coin.avalanche => 'AVAX',
          Coin.bnb => 'BNB',
          Coin.tron => 'TRX',
          Coin.solana => 'SOL',
          _ => 'ETH',
        },
      ),
    ),
};

Map<String, BalanceResult> _liveTokens() => {
  for (final token in builtinTokens)
    token.id: BalanceResult.ok(
      Amount(
        raw: token.symbol == 'USDC' && token.chain == Coin.eth
            ? BigInt.from(42500000)
            : BigInt.zero,
        decimals: token.decimals,
        symbol: token.symbol,
      ),
    ),
};

Widget _scoped({
  required WalletController wallets,
  required AppPrefsController prefs,
  MarketController? market,
  HistoryController? history,
  required Widget child,
}) {
  Widget current = child;
  if (history != null) {
    current = HistoryScope(controller: history, child: current);
  }
  if (market != null) {
    current = MarketScope(controller: market, child: current);
  }
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(
      fontFamily: 'Inter',
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3155DD)),
    ),
    home: WalletScope(
      controller: wallets,
      child: AppPrefsScope(controller: prefs, child: current),
    ),
  );
}

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
  print('EXPERIENCE_CAPTURE FILE=$path');
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 350)),
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'wallet experience upgrade visual acceptance',
    (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('zh')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();

      final wallets = _wallets();
      final prefs = AppPrefsController();
      final cachedAt = DateTime.now().subtract(const Duration(minutes: 3));
      final gate = Completer<void>();
      final cachedMarket = MarketController(
        wallets: wallets,
        balances: _Balances({
          for (final coin in Coin.values) coin: const BalanceResult.error(),
        }, gate: gate),
        prices: _Prices(null),
        tokens: _Tokens({
          for (final token in builtinTokens)
            token.id: const BalanceResult.error(),
        }),
        snapshots: _MarketSnapshots(
          MarketSnapshot(
            scope: 'capture',
            savedAt: cachedAt,
            native: _liveNative(),
            tokens: _liveTokens(),
            nativePrices: const {Coin.eth: 3100},
            tokenPrices: const {'USDC': 1},
            nativeChanges: const {Coin.eth: 1.8},
            tokenChanges: const {'USDC': 0.01},
          ),
        ),
        snapshotScope: () => 'capture',
      );
      final cachedRefresh = cachedMarket.refresh();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpWidget(
        _scoped(
          wallets: wallets,
          prefs: prefs,
          market: cachedMarket,
          child: const HomeScreen(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(const ValueKey('market-freshness')), findsOneWidget);
      expect(find.textContaining('3 分钟前验证'), findsOneWidget);
      await _capture(binding, tester, '01-cached-home');

      gate.complete();
      await cachedRefresh;
      cachedMarket.dispose();

      await prefs.toggleFavoriteAsset('USDC');
      await prefs.setHideZeroBalances(true);
      final liveMarket = MarketController(
        wallets: wallets,
        balances: _Balances(_liveNative()),
        prices: _Prices(const {Coin.eth: 3100}),
        tokens: _Tokens(_liveTokens()),
      );
      await liveMarket.refresh();
      await tester.pumpWidget(
        _scoped(
          wallets: wallets,
          prefs: prefs,
          market: liveMarket,
          child: const AssetsListScreen(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('assets-hide-zero-filter')),
        findsOneWidget,
      );
      expect(find.text('USDC'), findsOneWidget);
      expect(find.text('POL'), findsNothing);
      await _capture(binding, tester, '02-assets-preferences');
      liveMarket.dispose();

      final offlineMarket = MarketController(
        wallets: wallets,
        balances: _Balances({
          for (final coin in Coin.values) coin: const BalanceResult.error(),
        }),
        prices: _Prices(null),
        tokens: _Tokens({
          for (final token in builtinTokens)
            token.id: const BalanceResult.error(),
        }),
      );
      await prefs.setHideZeroBalances(false);
      await offlineMarket.refresh();
      await tester.pumpWidget(
        _scoped(
          wallets: wallets,
          prefs: prefs,
          market: offlineMarket,
          child: const AssetsListScreen(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('网络不可用，实时数据加载失败'), findsOneWidget);
      expect(find.text('3,120.00 USDT · TRON'), findsNothing);
      await _capture(binding, tester, '03-offline-honest-assets');
      offlineMarket.dispose();

      final historyCachedAt = DateTime.now().subtract(
        const Duration(minutes: 4),
      );
      final cachedHistory = HistoryController(
        wallets: wallets,
        service: _FailingHistory(),
        snapshots: _HistorySnapshots(
          HistorySnapshot(
            scope: 'capture',
            savedAt: historyCachedAt,
            results: {
              Coin.eth: HistoryResult.ok([
                ChainTxRecord(
                  coin: Coin.eth,
                  hash: '0xcached',
                  outgoing: false,
                  amountText: '0.025 ETH',
                  timestamp: historyCachedAt,
                  confirmed: true,
                ),
              ]),
            },
          ),
        ),
        snapshotScope: () => 'capture',
      );
      await cachedHistory.refresh();
      await tester.pumpWidget(
        _scoped(
          wallets: wallets,
          prefs: prefs,
          history: cachedHistory,
          child: const RecordsScreen(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('history-cached-label')),
        findsOneWidget,
      );
      expect(find.text('+0.025 ETH'), findsOneWidget);
      await _capture(binding, tester, '04-cached-history');
      cachedHistory.dispose();

      final pagedHistory = HistoryController(
        wallets: wallets,
        service: _PagedHistory(),
      );
      await pagedHistory.refresh();
      await tester.pumpWidget(
        _scoped(
          wallets: wallets,
          prefs: prefs,
          history: pagedHistory,
          child: const RecordsScreen(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('history-load-more')),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('加载更多'), findsOneWidget);
      await _capture(binding, tester, '05-history-load-more');

      await tester.tap(find.byKey(const ValueKey('history-load-more')));
      await tester.pumpAndSettle();
      expect(pagedHistory.records, hasLength(40));
      await _capture(binding, tester, '06-history-expanded');
      pagedHistory.dispose();

      // ignore: avoid_print
      print('EXPERIENCE_CAPTURE READY=all');
      // Leave the app container alive long enough for host-side tooling to
      // copy the exact PNGs from Simulator / Android app cache.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 45)),
      );
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
