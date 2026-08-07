import 'dart:async';

import 'package:chains/chains.dart' show Amount;
import 'package:core_crypto/core_crypto.dart' show ChainAddresses, Coin;
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/market/balance_service.dart';
import 'package:kt_wallet/src/market/market_controller.dart';
import 'package:kt_wallet/src/market/market_snapshot.dart';
import 'package:kt_wallet/src/market/price_service.dart';
import 'package:kt_wallet/src/market/token_balance_service.dart';
import 'package:kt_wallet/src/observability/experience_metrics.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';

class FakeBalanceService extends BalanceService {
  FakeBalanceService(this.results);
  Map<Coin, BalanceResult> results;
  int calls = 0;
  ChainAddresses? lastAddresses;
  int subsetCalls = 0;

  /// When set, the next fetch waits on it before returning (for in-flight
  /// state assertions); consumed once.
  Completer<void>? gate;

  @override
  Future<Map<Coin, BalanceResult>> fetchAll(
    ChainAddresses addresses, {
    BalanceResultCallback? onResult,
  }) async {
    calls++;
    lastAddresses = addresses;
    final g = gate;
    gate = null;
    if (g != null) await g.future;
    for (final entry in results.entries) {
      onResult?.call(entry.key, entry.value);
    }
    return results;
  }

  @override
  Future<Map<Coin, BalanceResult>> fetchCoins(
    ChainAddresses addresses,
    Iterable<Coin> coins, {
    BalanceResultCallback? onResult,
    Set<Coin> skipGateway = const {},
  }) async {
    subsetCalls++;
    final subset = {for (final coin in coins) coin: ?results[coin]};
    for (final entry in subset.entries) {
      onResult?.call(entry.key, entry.value);
    }
    return subset;
  }
}

class FakeTokenBalanceService extends TokenBalanceService {
  FakeTokenBalanceService(this.results);
  final Map<String, BalanceResult> results;
  @override
  Future<Map<String, BalanceResult>> fetchAll(ChainAddresses addresses) async =>
      results;
}

class FakeCombinedTokenBalanceService extends TokenBalanceService {
  FakeCombinedTokenBalanceService(this.batch);
  final TokenBalanceBatch batch;

  @override
  bool get gatewayEnabled => true;

  @override
  Future<TokenBalanceBatch> fetchAllWithNative(
    ChainAddresses addresses, {
    NativeBalanceResultCallback? onNativeResult,
  }) async {
    for (final entry in batch.native.entries) {
      onNativeResult?.call(entry.key, entry.value);
    }
    return batch;
  }
}

class FakeSnapshotStore implements MarketSnapshotStore {
  FakeSnapshotStore({this.snapshot});
  MarketSnapshot? snapshot;
  MarketSnapshot? saved;

  @override
  Future<MarketSnapshot?> load(String walletId, String scope) async =>
      snapshot?.scope == scope ? snapshot : null;

  @override
  Future<void> save(String walletId, MarketSnapshot snapshot) async {
    saved = snapshot;
  }
}

class ThrowingMarketSnapshotStore implements MarketSnapshotStore {
  int loadCalls = 0;

  @override
  Future<MarketSnapshot?> load(String walletId, String scope) async {
    loadCalls++;
    throw StateError('corrupt display cache');
  }

  @override
  Future<void> save(String walletId, MarketSnapshot snapshot) async {}
}

class ThrowOnceBalanceService extends BalanceService {
  ThrowOnceBalanceService(this.results);

  final Map<Coin, BalanceResult> results;
  bool failed = false;

  @override
  Future<Map<Coin, BalanceResult>> fetchAll(
    ChainAddresses addresses, {
    BalanceResultCallback? onResult,
  }) async {
    if (!failed) {
      failed = true;
      throw StateError('temporary upstream failure');
    }
    for (final entry in results.entries) {
      onResult?.call(entry.key, entry.value);
    }
    return results;
  }
}

class ProgressiveBalanceService extends BalanceService {
  final ethReady = Completer<void>();
  final finish = Completer<void>();

  @override
  Future<Map<Coin, BalanceResult>> fetchAll(
    ChainAddresses addresses, {
    BalanceResultCallback? onResult,
  }) async {
    final eth = BalanceResult.ok(
      Amount(
        raw: BigInt.parse('1000000000000000000'),
        decimals: 18,
        symbol: 'ETH',
      ),
    );
    onResult?.call(Coin.eth, eth);
    ethReady.complete();
    await finish.future;
    return {Coin.eth: eth, Coin.solana: const BalanceResult.error()};
  }
}

class FakePriceService extends PriceService {
  FakePriceService(
    this.prices, {
    this.cached,
    this.tokenPrices = const {'USDT': 0.99, 'USDC': 1.01, 'BUSD': 0.98},
    this.changes = const {},
    this.tokenChanges = const {},
  });
  Map<Coin, double>? prices;
  Map<Coin, double>? cached;
  final Map<String, double> tokenPrices;
  final Map<Coin, double> changes;
  final Map<String, double> tokenChanges;
  int calls = 0;
  @override
  Future<Map<Coin, double>?> fetchUsdPrices() async {
    calls++;
    return prices;
  }

  @override
  Map<Coin, double>? get lastGoodUsd => cached;
  @override
  double? tokenPriceUsd(String symbol) => tokenPrices[symbol];
  @override
  double? change24hPercent(Coin coin) => changes[coin];
  @override
  double? tokenChange24hPercent(String symbol) => tokenChanges[symbol];
}

ChainAddresses _addr(String seed) => ChainAddresses(
  eth: '0x$seed',
  polygon: '0x$seed',
  tron: 'T$seed',
  solana: seed,
);

WalletController _wallets() => WalletController(
  WalletManager(
    initial: [
      HotWallet(
        id: 'a',
        name: 'A',
        avatarColor: 0xFF000000,
        addresses: _addr('aaa'),
        backedUp: true,
      ),
      HotWallet(
        id: 'b',
        name: 'B',
        avatarColor: 0xFF000000,
        addresses: _addr('bbb'),
        sortOrder: 1,
        backedUp: true,
      ),
    ],
  ),
);

WalletController _singleWatchWallet() => WalletController(
  WalletManager(
    initial: [
      WatchWallet(
        id: 'watch-only',
        name: 'Watch only',
        avatarColor: 0xFF000000,
        addresses: _addr('watch'),
        coldWalletId: 'cold-watch-only',
        protocolVersion: 1,
      ),
    ],
  ),
);

Map<Coin, BalanceResult> _okResults() => {
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
};

Map<Coin, BalanceResult> _allErrors() => {
  for (final c in Coin.values) c: const BalanceResult.error(),
};

const _prices = {
  Coin.eth: 2000.0,
  Coin.polygon: 0.5,
  Coin.tron: 0.1,
  Coin.solana: 100.0,
};

void main() {
  setUp(ExperienceMetrics.instance.clear);

  test(
    'a broken display snapshot is ignored and live balances still load',
    () async {
      final snapshots = ThrowingMarketSnapshotStore();
      final controller = MarketController(
        wallets: _wallets(),
        balances: FakeBalanceService(_okResults()),
        prices: FakePriceService(_prices),
        snapshots: snapshots,
        snapshotScope: () => 'mainnet',
      );
      addTearDown(controller.dispose);

      await controller.refresh();

      expect(snapshots.loadCalls, 1);
      expect(controller.isRefreshing, isFalse);
      expect(controller.hasRefreshed, isTrue);
      expect(controller.balanceFor(Coin.eth).status, BalanceStatus.ok);
      expect(controller.showingCachedData, isFalse);
    },
  );

  test('an unexpected balance failure closes honestly and can retry', () async {
    final balances = ThrowOnceBalanceService(_okResults());
    final controller = MarketController(
      wallets: _wallets(),
      balances: balances,
      prices: FakePriceService(_prices),
    );
    addTearDown(controller.dispose);

    await controller.refresh();

    expect(controller.isRefreshing, isFalse);
    expect(controller.hasRefreshed, isTrue);
    expect(controller.balanceFor(Coin.eth).status, BalanceStatus.error);
    expect(controller.totalUsd, isNull);

    await controller.refresh();

    expect(controller.isRefreshing, isFalse);
    expect(controller.balanceFor(Coin.eth).status, BalanceStatus.ok);
    expect(controller.totalUsd, closeTo(2051.5, 1e-9));
  });

  test(
    'disposing during a balance refresh drops every late callback',
    () async {
      final gate = Completer<void>();
      final balances = FakeBalanceService(_okResults())..gate = gate;
      final controller = MarketController(
        wallets: _wallets(),
        balances: balances,
        prices: FakePriceService(_prices),
      );

      final refresh = controller.refresh();
      while (balances.calls == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      controller.dispose();
      gate.complete();

      await expectLater(refresh, completes);
    },
  );

  test(
    'removing the last wallet clears market state and drops late responses',
    () async {
      final gate = Completer<void>();
      final balances = FakeBalanceService(_okResults())..gate = gate;
      final wallets = _singleWatchWallet();
      final controller = MarketController(
        wallets: wallets,
        balances: balances,
        prices: FakePriceService(_prices),
      );
      addTearDown(controller.dispose);

      final refresh = controller.refresh();
      while (balances.calls == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      await wallets.remove('watch-only');
      gate.complete();
      await refresh;

      expect(wallets.current, isNull);
      expect(controller.hasRefreshed, isFalse);
      expect(controller.totalUsd, isNull);
      for (final coin in Coin.values) {
        expect(controller.balanceFor(coin).status, BalanceStatus.loading);
      }
    },
  );

  test('initial state: loading rows, no total, not offline', () {
    final controller = MarketController(
      wallets: _wallets(),
      balances: FakeBalanceService(_okResults()),
      prices: FakePriceService(_prices),
    );
    for (final coin in Coin.values) {
      expect(controller.balanceFor(coin).status, BalanceStatus.loading);
    }
    expect(controller.hasRefreshed, isFalse);
    expect(controller.totalUsd, isNull);
    expect(controller.isOffline, isFalse);
  });

  test(
    'refresh: loading → ok with fiat total, notifying on both edges',
    () async {
      final gate = Completer<void>();
      final balances = FakeBalanceService(_okResults())..gate = gate;
      final controller = MarketController(
        wallets: _wallets(),
        balances: balances,
        prices: FakePriceService(_prices),
      );
      var notifications = 0;
      controller.addListener(() => notifications++);

      final done = controller.refresh();
      // In flight: loading placeholders, one notification so far.
      expect(controller.isRefreshing, isTrue);
      expect(controller.hasRefreshed, isFalse);
      expect(controller.balanceFor(Coin.eth).status, BalanceStatus.loading);
      expect(notifications, 1);

      gate.complete();
      await done;

      expect(controller.isRefreshing, isFalse);
      expect(controller.hasRefreshed, isTrue);
      // Start + one notification per completed chain + final batch completion.
      expect(notifications, 6);
      expect(controller.balanceFor(Coin.eth).status, BalanceStatus.ok);
      // 1 ETH*2000 + 2 POL*0.5 + 5 TRX*0.1 + 0.5 SOL*100 = 2051.50
      expect(controller.totalUsd, closeTo(2051.5, 1e-9));
      expect(controller.fiatValueUsd(Coin.tron), closeTo(0.5, 1e-9));
      expect(controller.isOffline, isFalse);
      final metric = ExperienceMetrics.instance.recent.singleWhere(
        (event) => event.name == ExperienceMetricNames.marketRefresh,
      );
      expect(metric.success, isTrue);
    },
  );

  test(
    'non-positive prices and overflowing display values stay unavailable',
    () async {
      final negative = MarketController(
        wallets: _wallets(),
        balances: FakeBalanceService(_okResults()),
        prices: FakePriceService({Coin.eth: -2000}),
      );
      await negative.refresh();
      expect(negative.fiatValueUsd(Coin.eth), isNull);
      expect(
        ExperienceMetrics.instance.recent
            .lastWhere(
              (event) => event.name == ExperienceMetricNames.marketRefresh,
            )
            .success,
        isFalse,
      );

      final extremeBalances = <Coin, BalanceResult>{
        for (final coin in Coin.values) coin: const BalanceResult.error(),
        Coin.eth: BalanceResult.ok(
          Amount(raw: BigInt.one << 4096, decimals: 18, symbol: 'ETH'),
        ),
      };
      final extreme = MarketController(
        wallets: _wallets(),
        balances: FakeBalanceService(extremeBalances),
        prices: FakePriceService(const {Coin.eth: 2000}),
      );
      await extreme.refresh();
      expect(extreme.fiatValueUsd(Coin.eth), isNull);
      expect(extreme.totalUsd, isNull);
    },
  );

  test(
    'refresh reveals a fast chain before the slowest RPC completes',
    () async {
      final balances = ProgressiveBalanceService();
      final controller = MarketController(
        wallets: _wallets(),
        balances: balances,
        prices: FakePriceService(_prices),
      );

      final done = controller.refresh();
      await balances.ethReady.future;

      expect(controller.isRefreshing, isTrue);
      expect(controller.balanceFor(Coin.eth).status, BalanceStatus.ok);
      expect(controller.balanceFor(Coin.eth).amount!.format(), '1');
      expect(controller.balanceFor(Coin.solana).status, BalanceStatus.loading);

      balances.finish.complete();
      await done;
      expect(controller.isRefreshing, isFalse);
      expect(controller.balanceFor(Coin.solana).status, BalanceStatus.error);
    },
  );

  test(
    'persistent snapshot is shown while live balances refresh in background',
    () async {
      final gate = Completer<void>();
      final balances = FakeBalanceService(_okResults())..gate = gate;
      final savedAt = DateTime(2026, 7, 30, 8);
      final snapshots = FakeSnapshotStore(
        snapshot: MarketSnapshot(
          scope: 'mainnet',
          savedAt: savedAt,
          native: {
            Coin.eth: BalanceResult.ok(
              Amount(
                raw: BigInt.parse('500000000000000000'),
                decimals: 18,
                symbol: 'ETH',
              ),
            ),
          },
          tokens: const {},
          nativePrices: const {Coin.eth: 2000},
          tokenPrices: const {},
          nativeChanges: const {},
          tokenChanges: const {},
        ),
      );
      final controller = MarketController(
        wallets: _wallets(),
        balances: balances,
        prices: FakePriceService(_prices),
        snapshots: snapshots,
        snapshotScope: () => 'mainnet',
      );

      final done = controller.refresh();
      await pumpEventQueue();

      expect(controller.isRefreshing, isTrue);
      expect(controller.showingCachedData, isTrue);
      expect(controller.lastUpdatedAt, savedAt);
      expect(controller.balanceFor(Coin.eth).amount!.format(), '0.5');
      expect(controller.totalUsd, 1000);

      gate.complete();
      await done;
      expect(controller.isRefreshing, isFalse);
      expect(controller.showingCachedData, isFalse);
      expect(controller.balanceFor(Coin.eth).amount!.format(), '1');
      await pumpEventQueue();
      expect(snapshots.saved, isNotNull);
    },
  );

  test(
    'same-scope refresh keeps last-good rows instead of resetting to --',
    () async {
      final balances = FakeBalanceService(_okResults());
      final controller = MarketController(
        wallets: _wallets(),
        balances: balances,
        prices: FakePriceService(_prices),
        snapshotScope: () => 'mainnet',
      );
      await controller.refresh();

      final gate = Completer<void>();
      balances.gate = gate;
      final done = controller.refresh();
      expect(controller.isRefreshing, isTrue);
      expect(controller.balanceFor(Coin.eth).status, BalanceStatus.ok);
      expect(controller.balanceFor(Coin.eth).amount!.format(), '1');

      gate.complete();
      await done;
    },
  );

  test(
    'gateway token batch supplies native balances without duplicate calls',
    () async {
      final native = {
        for (final coin in Coin.values)
          coin: BalanceResult.ok(
            Amount(
              raw: BigInt.zero,
              decimals: BalanceService.decimalsFor[coin]!,
              symbol: BalanceService.symbolFor[coin]!,
            ),
          ),
      };
      final balances = FakeBalanceService(_okResults());
      final controller = MarketController(
        wallets: _wallets(),
        balances: balances,
        prices: FakePriceService(_prices),
        tokens: FakeCombinedTokenBalanceService(
          TokenBalanceBatch(tokens: const {}, native: native),
        ),
      );

      await controller.refresh();
      expect(balances.calls, 0);
      expect(balances.subsetCalls, 0);
      expect(controller.balanceFor(Coin.eth).status, BalanceStatus.ok);
    },
  );

  test('all balances error + no prices → offline, total null', () async {
    final controller = MarketController(
      wallets: _wallets(),
      balances: FakeBalanceService(_allErrors()),
      prices: FakePriceService(null),
    );
    await controller.refresh();
    expect(controller.hasLiveBalances, isFalse);
    expect(controller.totalUsd, isNull);
    expect(controller.isOffline, isTrue);
    for (final coin in Coin.values) {
      expect(controller.balanceFor(coin).status, BalanceStatus.error);
    }
  });

  test('an all-testnet legacy wallet never requests market prices', () async {
    final prices = FakePriceService(null);
    final enabled = _wallets().current!.addresses.enabledCoins.toSet();
    final controller = MarketController(
      wallets: _wallets(),
      balances: FakeBalanceService(_okResults()),
      prices: prices,
      isTestnet: enabled.contains,
    );
    addTearDown(controller.dispose);

    await controller.refresh();

    expect(prices.calls, 0);
    expect(
      ExperienceMetrics.instance.recent
          .singleWhere(
            (event) => event.name == ExperienceMetricNames.marketRefresh,
          )
          .success,
      isTrue,
    );
  });

  test('price failure falls back to the session last-good cache', () async {
    final controller = MarketController(
      wallets: _wallets(),
      balances: FakeBalanceService(_okResults()),
      prices: FakePriceService(null, cached: _prices),
    );
    await controller.refresh();
    expect(controller.priceUsd(Coin.eth), 2000.0);
    expect(controller.totalUsd, closeTo(2051.5, 1e-9));
    expect(controller.isOffline, isFalse);
    final metric = ExperienceMetrics.instance.recent.singleWhere(
      (event) => event.name == ExperienceMetricNames.marketRefresh,
    );
    expect(metric.success, isFalse);
  });

  test('partial failure: total sums only computable chains', () async {
    final results = _okResults();
    results[Coin.eth] = const BalanceResult.error();
    final controller = MarketController(
      wallets: _wallets(),
      balances: FakeBalanceService(results),
      prices: FakePriceService(_prices),
    );
    await controller.refresh();
    expect(controller.fiatValueUsd(Coin.eth), isNull);
    // 2 POL*0.5 + 5 TRX*0.1 + 0.5 SOL*100 = 51.50
    expect(controller.totalUsd, closeTo(51.5, 1e-9));
    expect(controller.isOffline, isFalse);
    final metric = ExperienceMetrics.instance.recent.singleWhere(
      (event) => event.name == ExperienceMetricNames.marketRefresh,
    );
    expect(metric.success, isFalse);
  });

  test(
    '24h portfolio movement is reconstructed from covered holdings',
    () async {
      final controller = MarketController(
        wallets: _wallets(),
        balances: FakeBalanceService(_okResults()),
        prices: FakePriceService(
          _prices,
          changes: {for (final coin in _prices.keys) coin: 10},
        ),
      );
      await controller.refresh();

      expect(controller.change24hPercent(Coin.eth), 10);
      final change = controller.portfolioChange24h;
      expect(change, isNotNull);
      // Current $2,051.50 is 110% of the reconstructed $1,865.00.
      expect(change!.deltaUsd, closeTo(186.5, 1e-9));
      expect(change.percent, closeTo(10, 1e-9));
      expect(change.coveredAssetCount, 4);
    },
  );

  test('portfolio zero requires every active balance to be known', () async {
    final zeroResults = {
      for (final entry in _okResults().entries)
        entry.key: BalanceResult.ok(
          Amount(
            raw: BigInt.zero,
            decimals: entry.value.amount!.decimals,
            symbol: entry.value.amount!.symbol,
          ),
        ),
    };
    final balances = FakeBalanceService(zeroResults);
    final controller = MarketController(
      wallets: _wallets(),
      balances: balances,
      prices: FakePriceService(_prices),
    );
    addTearDown(controller.dispose);

    await controller.refresh();
    expect(controller.totalUsd, 0);
    expect(controller.portfolioChange24h, isNull);
    expect(controller.portfolioBalanceIsDefinitelyZero, isTrue);

    balances.results = {
      ...zeroResults,
      Coin.solana: const BalanceResult.error(),
    };
    await controller.refresh();
    expect(controller.portfolioBalanceIsDefinitelyZero, isFalse);
  });

  test('wallet switch auto-refreshes with the new wallet addresses', () async {
    final wallets = _wallets();
    final balances = FakeBalanceService(_okResults());
    final controller = MarketController(
      wallets: wallets,
      balances: balances,
      prices: FakePriceService(_prices),
    );
    await controller.refresh();
    expect(balances.calls, 1);
    expect(balances.lastAddresses!.eth, '0xaaa');

    wallets.select('b');
    await pumpEventQueue();
    expect(balances.calls, 2);
    expect(balances.lastAddresses!.eth, '0xbbb');
    controller.dispose();
  });

  test(
    'token balances: per-token results, pegged fiat, total inclusion',
    () async {
      final controller = MarketController(
        wallets: _wallets(),
        balances: FakeBalanceService(_okResults()),
        prices: FakePriceService(_prices),
        tokens: FakeTokenBalanceService({
          'usdt-eth': BalanceResult.ok(
            Amount(raw: BigInt.from(25000000), decimals: 6, symbol: 'USDT'),
          ),
          'usdc-polygon': BalanceResult.ok(
            Amount(raw: BigInt.from(10000000), decimals: 6, symbol: 'USDC'),
          ),
          'usdt-tron': const BalanceResult.error(),
        }),
      );
      // Registry exposed; everything starts as loading.
      expect(controller.tokens.map((t) => t.id), [
        'usdt-eth',
        'usdc-eth',
        'dai-eth',
        'weth-eth',
        'wbtc-eth',
        'link-eth',
        'uni-eth',
        'shib-eth',
        'pepe-eth',
        'busd-eth',
        'pyusd-eth',
        'usdt-polygon',
        'usdc-polygon',
        'usdt-base',
        'usdc-base',
        'usdt-arbitrum',
        'usdc-arbitrum',
        'usdt-avalanche',
        'usdc-avalanche',
        'busd-bnb',
        'usdt-tron',
        'usdt-solana',
        'usdc-solana',
        'jup-solana',
        'bonk-solana',
        'pyusd-solana',
      ]);
      expect(
        controller.tokenBalanceFor('usdt-eth').status,
        BalanceStatus.loading,
      );

      await controller.refresh();
      expect(controller.tokenBalanceFor('usdt-eth').status, BalanceStatus.ok);
      expect(
        controller.tokenBalanceFor('usdt-tron').status,
        BalanceStatus.error,
      );

      final byId = {for (final t in controller.tokens) t.id: t};
      // Stablecoin fiat uses the live market quote, including depegs.
      expect(
        controller.tokenFiatValueUsd(byId['usdt-eth']!),
        closeTo(24.75, 1e-9),
      );
      expect(
        controller.tokenFiatValueUsd(byId['usdc-polygon']!),
        closeTo(10.1, 1e-9),
      );
      // Errored token: no fiat value, never an invented number.
      expect(controller.tokenFiatValueUsd(byId['usdt-tron']!), isNull);
      // Natives 2051.50 + live-priced tokens 34.85.
      expect(controller.totalUsd, closeTo(2086.35, 1e-9));
      expect(
        ExperienceMetrics.instance.recent
            .singleWhere(
              (event) => event.name == ExperienceMetricNames.marketRefresh,
            )
            .success,
        isFalse,
      );
      controller.dispose();
    },
  );

  test('a controller without a token service has no token rows', () async {
    final controller = MarketController(
      wallets: _wallets(),
      balances: FakeBalanceService(_okResults()),
      prices: FakePriceService(_prices),
    );
    await controller.refresh();
    expect(controller.tokens, isEmpty);
    expect(
      controller.tokenBalanceFor('usdt-eth').status,
      BalanceStatus.loading,
    );
    expect(controller.totalUsd, closeTo(2051.5, 1e-9));
    controller.dispose();
  });

  test('formatUsd groups thousands with two fraction digits', () {
    expect(formatUsd(0), r'$0.00');
    expect(formatUsd(862.4), r'$862.40');
    expect(formatUsd(1234.5), r'$1,234.50');
    expect(formatUsd(1234567.891), r'$1,234,567.89');
  });

  test('formatFiat uses explicit currency symbols and JPY precision', () {
    expect(formatFiat(1234.5, 'USD'), r'$1,234.50');
    expect(formatFiat(1234.5, 'CNY'), 'CN¥1,234.50');
    expect(formatFiat(1234.5, 'JPY'), 'JP¥1,235');
    expect(formatFiat(double.infinity, 'USD'), '--');
    expect(formatFiat(-1, 'USD'), '--');
  });

  test('market change formatters preserve sign and precision', () {
    expect(formatChange24h(1.234), '+1.23%');
    expect(formatChange24h(-1.234), '-1.23%');
    expect(formatChange24h(null), '');
    expect(formatChange24h(double.nan), '');
    expect(formatSignedUsd(12.345), r'+$12.35');
    expect(formatSignedUsd(-12.345), r'-$12.35');
    expect(formatSignedUsd(double.infinity), '--');
  });

  test(
    'a refresh superseded by a wallet switch drops its stale results',
    () async {
      final wallets = _wallets();
      final gate = Completer<void>();
      final balances = FakeBalanceService(_allErrors())..gate = gate;
      final controller = MarketController(
        wallets: wallets,
        balances: balances,
        prices: FakePriceService(_prices),
      );

      final stale = controller.refresh(); // slow, gated, all-error results
      balances.results = _okResults(); // the switch-triggered fetch succeeds
      wallets.select('b');
      await pumpEventQueue();
      gate.complete(); // stale fetch finally returns its errors
      await stale;
      await pumpEventQueue();

      // The newer (wallet-b) results win; the stale errors were discarded.
      expect(controller.balanceFor(Coin.eth).status, BalanceStatus.ok);
      expect(balances.lastAddresses!.eth, '0xbbb');
      controller.dispose();
    },
  );
}
