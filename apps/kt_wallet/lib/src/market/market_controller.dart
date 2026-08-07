// ignore_for_file: prefer_initializing_formals

import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter/foundation.dart';

import '../state/wallet_controller.dart';
import '../observability/experience_metrics.dart';
import 'asset_ref.dart' show AssetDeployment;
import 'balance_service.dart';
import 'fiat_math.dart';
import 'market_snapshot.dart';
import 'price_service.dart';
import 'token_balance_service.dart';

/// Live market state for the current wallet: per-chain native balances, the
/// built-in registry's token balances (when a [TokenBalanceService] is wired)
/// plus spot USD prices, refreshed on home entry, wallet switch (listens to the
/// [WalletController]) and pull-to-refresh — deliberately no polling loop.
///
/// Fiat math uses doubles for DISPLAY ONLY (totals/row values); on-chain
/// amounts stay exact [BalanceResult.amount] integers throughout.
class MarketController extends ChangeNotifier {
  MarketController({
    required WalletController wallets,
    BalanceService? balances,
    PriceService? prices,
    TokenBalanceService? tokens,
    bool Function(Coin coin)? isTestnet,
    MarketSnapshotStore? snapshots,
    String Function()? snapshotScope,
    bool Function()? canRefresh,
  }) : _wallets = wallets,
       _balances = balances ?? BalanceService(),
       _prices = prices ?? PriceService(),
       _isTestnet = isTestnet ?? _neverTestnet,
       _snapshots = snapshots,
       _snapshotScope = snapshotScope ?? _defaultSnapshotScope,
       _canRefresh = canRefresh ?? _alwaysRefresh,
       // Deliberately nullable (no network-hitting default): contexts that
       // never wire a token service (older tests, gallery) simply have no
       // token rows.
       _tokens = tokens {
    _walletId = _wallets.current?.id;
    _wallets.addListener(_onWalletsChanged);
    _tokenResults = {
      for (final token in this.tokens) token.id: const BalanceResult.loading(),
    };
  }

  final WalletController _wallets;
  final BalanceService _balances;
  final PriceService _prices;
  final TokenBalanceService? _tokens;
  final MarketSnapshotStore? _snapshots;
  final String Function() _snapshotScope;
  final bool Function() _canRefresh;

  /// Whether [coin]'s ACTIVE network instance is a testnet, re-evaluated on
  /// every read (network switches apply live). Testnet amounts are real but
  /// have no market price — fiat is suppressed, never invented. Default:
  /// nothing is a testnet (today's behavior for all existing wiring).
  final bool Function(Coin coin) _isTestnet;

  static bool _neverTestnet(Coin _) => false;
  static bool _alwaysRefresh() => true;
  static String _defaultSnapshotScope() => 'default';

  String? _walletId;
  String? _activeSnapshotScope;
  int _generation = 0;
  bool _refreshing = false;
  bool _hasRefreshed = false;
  bool _showingCachedData = false;
  bool _disposed = false;
  DateTime? _lastUpdatedAt;

  Map<Coin, BalanceResult> _results = {
    for (final coin in Coin.values) coin: const BalanceResult.loading(),
  };
  Map<String, BalanceResult> _tokenResults = const {};
  Map<Coin, double>? _pricesUsd;

  /// True while a refresh is in flight (rows render '--' placeholders).
  bool get isRefreshing => _refreshing;

  /// True once at least one refresh has completed (success or not).
  bool get hasRefreshed => _hasRefreshed;
  bool get showingCachedData => _showingCachedData;
  DateTime? get lastUpdatedAt => _lastUpdatedAt;

  BalanceResult balanceFor(Coin coin) =>
      _results[coin] ?? const BalanceResult.unsupported();

  /// The token registry rendered under the native rows (empty when no token
  /// service was wired up).
  List<TokenInfo> get tokens => _tokens?.tokens ?? const [];

  /// Per-token fetch result, keyed by [TokenInfo.id].
  BalanceResult tokenBalanceFor(String id) =>
      _tokenResults[id] ?? const BalanceResult.loading();

  /// Spot USD prices, or null when never fetched successfully this session.
  Map<Coin, double>? get pricesUsd => _pricesUsd;

  /// Spot price for the active deployment of [coin].
  ///
  /// A quote is keyed by the mainnet asset symbol, so exposing it for a
  /// testnet deployment would make worthless faucet funds look valuable.
  /// Keep this guard at the controller boundary so future screens cannot
  /// accidentally bypass the portfolio-level fiat checks.
  double? priceUsd(Coin coin) => _isTestnet(coin) ? null : _pricesUsd?[coin];

  /// CoinGecko market movement for the currently selected asset. Testnet
  /// holdings deliberately suppress market data just like their USD value.
  double? change24hPercent(Coin coin) =>
      _isTestnet(coin) ? null : _prices.change24hPercent(coin);

  /// True when at least one chain or token returned a real balance.
  bool get hasLiveBalances =>
      _results.values.any((r) => r.status == BalanceStatus.ok) ||
      _tokenResults.values.any((r) => r.status == BalanceStatus.ok);

  /// Everything errored: no live balance on any chain AND no prices. The UI
  /// falls back to the demo constants behind an explicit "offline — demo
  /// data" banner (never silently presented as live).
  bool get isOffline =>
      _hasRefreshed && !_refreshing && !hasLiveBalances && _pricesUsd == null;

  /// USD value of one chain's balance, or null when either the balance or its
  /// price is unavailable (display-only double math).
  double? fiatValueUsd(Coin coin) {
    // Testnet coins have no market price by definition — fiat is unavailable
    // even when a (mainnet) quote for the same symbol is in the cache.
    if (_isTestnet(coin)) return null;
    final result = balanceFor(coin);
    final amount = result.amount;
    if (result.status != BalanceStatus.ok || amount == null) return null;
    final price = _pricesUsd?[coin];
    if (price == null) return null;
    return fiatValueForDisplay(amount, price);
  }

  /// Token quote scoped to the token's active chain deployment.
  double? tokenPriceUsdFor(Coin coin, String symbol) =>
      _isTestnet(coin) ? null : _prices.tokenPriceUsd(symbol);

  /// Token market movement scoped to the token's active chain deployment.
  double? tokenChange24hPercentFor(Coin coin, String symbol) =>
      _isTestnet(coin) ? null : _prices.tokenChange24hPercent(symbol);

  double? fiatPerUsd(String currency) => _prices.fiatPerUsd(currency);

  /// Converts a USD display value into the selected fiat only when the live or
  /// last-good FX rate is known. Missing FX data stays unavailable (`null`).
  double? convertUsd(double? usd, String currency) {
    if (usd == null) return null;
    final rate = fiatPerUsd(currency);
    return multiplyFiatForDisplay(usd, rate);
  }

  /// USD value of one token's balance, or null when unavailable. Stablecoins
  /// use live market quotes, so a depeg is reflected instead of being forced
  /// to $1. Tokens without a price feed stay null ('--'), never invented.
  double? tokenFiatValueUsd(TokenInfo token) {
    if (_isTestnet(token.chain)) return null;
    final result = tokenBalanceFor(token.id);
    final amount = result.amount;
    if (result.status != BalanceStatus.ok || amount == null) return null;
    final price = tokenPriceUsdFor(token.chain, token.symbol);
    if (price == null) return null;
    return fiatValueForDisplay(amount, price);
  }

  /// Balance of one [AssetDeployment], whichever kind it is. Native coins and
  /// registry tokens read through separate maps; a caller that renders a
  /// mixed group (ETH spans Ethereum and its L2s) should not have to branch.
  BalanceResult resultFor(AssetDeployment at) =>
      at.tokenId == null ? balanceFor(at.coin) : tokenBalanceFor(at.tokenId!);

  /// True only when every deployment returned a real balance and the total is
  /// exactly zero. Unknown/error rows are never hidden as if they were empty.
  bool isDefinitelyZero(Iterable<AssetDeployment> deployments) {
    var sawAny = false;
    for (final deployment in deployments) {
      final result = resultFor(deployment);
      final amount = result.amount;
      if (result.status != BalanceStatus.ok || amount == null) return false;
      sawAny = true;
      if (amount.raw != BigInt.zero) return false;
    }
    return sawAny;
  }

  /// True only when every native and registry-token balance that belongs to
  /// the current wallet is known and exactly zero.
  ///
  /// This is intentionally stricter than [totalUsd] == 0: a partial outage
  /// can also produce a zero total from the known subset. The home screen uses
  /// this distinction to render a real `0.00` daily movement only when zero is
  /// proven; otherwise it keeps the row visible with unavailable markers.
  bool get portfolioBalanceIsDefinitelyZero {
    final wallet = _wallets.current;
    if (wallet == null) return false;
    var sawAny = false;

    bool include(BalanceResult result) {
      final amount = result.amount;
      if (result.status != BalanceStatus.ok || amount == null) return false;
      sawAny = true;
      return amount.raw == BigInt.zero;
    }

    for (final coin in wallet.addresses.enabledCoins) {
      if (!include(balanceFor(coin))) return false;
    }
    for (final token in tokens) {
      if (!include(tokenBalanceFor(token.id))) return false;
    }
    return sawAny;
  }

  double? fiatTotalFor(Iterable<AssetDeployment> deployments, String symbol) {
    var total = 0.0;
    var sawAny = false;
    for (final deployment in deployments) {
      final value = fiatFor(deployment, symbol);
      if (value == null) continue;
      total += value;
      if (!total.isFinite) return null;
      sawAny = true;
    }
    return sawAny ? total : null;
  }

  /// USD value of one deployment, or null when unavailable.
  double? fiatFor(AssetDeployment at, String symbol) {
    if (at.tokenId == null) return fiatValueUsd(at.coin);
    if (_isTestnet(at.coin)) return null;
    final result = tokenBalanceFor(at.tokenId!);
    final amount = result.amount;
    if (result.status != BalanceStatus.ok || amount == null) return null;
    final price = tokenPriceUsdFor(at.coin, symbol);
    if (price == null) return null;
    return fiatValueForDisplay(amount, price);
  }

  /// 24h change for a deployment's asset. Native coins are quoted per chain
  /// (an L2's ETH is the same quote as Ethereum's), tokens per symbol.
  double? changeFor(AssetDeployment at, String symbol) => at.tokenId == null
      ? change24hPercent(at.coin)
      : tokenChange24hPercentFor(at.coin, symbol);

  /// Sum of the computable per-chain and per-token fiat values, or null when
  /// none is computable (a partially failed refresh totals only what's known).
  double? get totalUsd {
    double? total;
    for (final coin in Coin.values) {
      final value = fiatValueUsd(coin);
      if (value != null) {
        final next = (total ?? 0) + value;
        if (!next.isFinite) return null;
        total = next;
      }
    }
    for (final token in tokens) {
      final value = tokenFiatValueUsd(token);
      if (value != null) {
        final next = (total ?? 0) + value;
        if (!next.isFinite) return null;
        total = next;
      }
    }
    return total;
  }

  /// Estimated 24h movement of the current portfolio caused by market prices.
  ///
  /// CoinGecko gives a percentage per asset, not the wallet's historical
  /// balance. We reconstruct each covered asset's previous value from its
  /// current holding and quote. Assets without a fresh 24h quote are excluded
  /// from both sides instead of being treated as flat.
  PortfolioChange24h? get portfolioChange24h {
    var current = 0.0;
    var previous = 0.0;
    var covered = 0;

    void include(double? value, double? change) {
      if (value == null || change == null || !value.isFinite) return;
      final ratio = 1 + change / 100;
      if (!ratio.isFinite || ratio <= 0) return;
      final nextCurrent = current + value;
      final nextPrevious = previous + value / ratio;
      if (!nextCurrent.isFinite || !nextPrevious.isFinite) return;
      current = nextCurrent;
      previous = nextPrevious;
      covered++;
    }

    for (final coin in Coin.values) {
      include(fiatValueUsd(coin), change24hPercent(coin));
    }
    for (final token in tokens) {
      include(
        tokenFiatValueUsd(token),
        tokenChange24hPercentFor(token.chain, token.symbol),
      );
    }
    if (covered == 0 || previous == 0) return null;
    final delta = current - previous;
    return PortfolioChange24h(
      deltaUsd: delta,
      percent: delta / previous * 100,
      coveredAssetCount: covered,
    );
  }

  /// First-entry refresh: no-op if one already ran or is running (wallet
  /// switches and pull-to-refresh call [refresh] directly).
  void refreshIfNeeded() {
    if (_disposed || !_canRefresh() || _hasRefreshed || _refreshing) return;
    refresh();
  }

  /// Fetches balances (current wallet's addresses) and prices concurrently.
  /// A refresh superseded by a newer one (e.g. wallet switched mid-flight)
  /// discards its results.
  Future<void> refresh() async {
    if (_disposed || !_canRefresh()) return;
    final wallet = _wallets.current;
    if (wallet == null) return;
    final metricStopwatch = Stopwatch()..start();
    final generation = ++_generation;
    final scope = _snapshotScope();
    final contextChanged =
        wallet.id != _walletId || scope != _activeSnapshotScope;
    _walletId = wallet.id;
    _activeSnapshotScope = scope;
    _refreshing = true;
    if (contextChanged) {
      _results = {
        for (final coin in Coin.values) coin: const BalanceResult.loading(),
      };
      _tokenResults = {
        for (final token in tokens) token.id: const BalanceResult.loading(),
      };
      _pricesUsd = null;
      _showingCachedData = false;
      _lastUpdatedAt = null;
      _hasRefreshed = false;
    }
    notifyListeners();

    try {
      if (contextChanged && _snapshots != null) {
        MarketSnapshot? snapshot;
        try {
          snapshot = await _snapshots.load(wallet.id, scope);
        } catch (_) {
          // This is a display-only acceleration cache. A corrupt value or
          // transient cache-store failure must never block the authoritative
          // live balance refresh.
          snapshot = null;
        }
        if (generation != _generation) return;
        if (snapshot != null) {
          final tokenIds = {for (final token in tokens) token.id};
          _results = {
            for (final coin in Coin.values)
              coin:
                  snapshot.native[coin] ??
                  _results[coin] ??
                  const BalanceResult.loading(),
          };
          _tokenResults = {
            for (final token in tokens)
              token.id:
                  (tokenIds.contains(token.id)
                      ? snapshot.tokens[token.id]
                      : null) ??
                  const BalanceResult.loading(),
          };
          _prices.restoreLastGood(
            nativeUsd: snapshot.nativePrices,
            tokenUsd: snapshot.tokenPrices,
            nativeChange24h: snapshot.nativeChanges,
            tokenChange24h: snapshot.tokenChanges,
            fiatPerUsd: snapshot.fiatPerUsd,
          );
          _pricesUsd = snapshot.nativePrices.isEmpty
              ? null
              : snapshot.nativePrices;
          _showingCachedData = true;
          _lastUpdatedAt = snapshot.savedAt;
          notifyListeners();
        }
      }

      final tokenService = _tokens;
      // With every active chain on a testnet there is nothing to price — skip
      // the fetch entirely (an unpriceable quote must not even be requested).
      // Mixed environments still fetch once; testnet chains ignore the result
      // via the fiat guards above.
      final skipPrices = wallet.addresses.enabledCoins.every(_isTestnet);
      void revealNative(Coin coin, BalanceResult result) {
        if (generation != _generation) return;
        _results = {..._results, coin: result};
        notifyListeners();
      }

      late final Future<TokenBalanceBatch> tokenFuture;
      late final Future<Map<Coin, BalanceResult>> balanceFuture;
      if (tokenService != null && tokenService.gatewayEnabled) {
        tokenFuture = tokenService.fetchAllWithNative(
          wallet.addresses,
          onNativeResult: revealNative,
        );
        balanceFuture = tokenFuture.then((batch) async {
          final missing = wallet.addresses.enabledCoins
              .where((coin) => !batch.native.containsKey(coin))
              .toList();
          if (missing.isEmpty) return batch.native;
          final fallback = await _balances.fetchCoins(
            wallet.addresses,
            missing,
            onResult: revealNative,
            skipGateway: batch.gatewayFailedChains,
          );
          return {...batch.native, ...fallback};
        });
      } else {
        balanceFuture = _balances.fetchAll(
          wallet.addresses,
          onResult: revealNative,
        );
        tokenFuture = tokenService == null
            ? Future.value(const TokenBalanceBatch(tokens: {}))
            : tokenService
                  .fetchAll(wallet.addresses)
                  .then((results) => TokenBalanceBatch(tokens: results));
      }

      final (balances, prices, tokenBatch) = await (
        balanceFuture,
        skipPrices
            ? Future<Map<Coin, double>?>.value(null)
            : _prices.fetchUsdPrices(),
        tokenFuture,
      ).wait;

      if (generation != _generation) return; // superseded — drop stale results
      final requestedResults = <BalanceResult?>[
        for (final coin in wallet.addresses.enabledCoins) balances[coin],
        if (tokenService != null)
          for (final token in tokens) tokenBatch.tokens[token.id],
      ];
      final priceableCoins = wallet.addresses.enabledCoins.where(
        (coin) => !_isTestnet(coin),
      );
      final pricesComplete =
          skipPrices ||
          priceableCoins.every((coin) {
            final price = prices?[coin];
            return price != null && price.isFinite && price > 0;
          });
      // The UI deliberately keeps every chain independent, but the aggregate
      // refresh metric must not call a partial outage successful. Explicitly
      // unsupported rows are neutral; missing/loading/error rows, or missing
      // or invalid native quotes in a priceable environment, make it fail.
      final liveFetchSucceeded =
          requestedResults.any(
            (result) => result?.status == BalanceStatus.ok,
          ) &&
          requestedResults.every(
            (result) =>
                result?.status == BalanceStatus.ok ||
                result?.status == BalanceStatus.unsupported,
          ) &&
          pricesComplete;
      var retainedStale = false;
      BalanceResult retainLastGood(
        BalanceResult? previous,
        BalanceResult fresh,
      ) {
        if (fresh.status == BalanceStatus.error &&
            previous?.status == BalanceStatus.ok) {
          retainedStale = true;
          return previous!;
        }
        return fresh;
      }

      _results = {
        for (final coin in Coin.values)
          coin: retainLastGood(
            _results[coin],
            balances[coin] ?? const BalanceResult.unsupported(),
          ),
      };
      _tokenResults = {
        for (final token in tokens)
          token.id: retainLastGood(
            _tokenResults[token.id],
            tokenBatch.tokens[token.id] ?? const BalanceResult.unsupported(),
          ),
      };
      // A failed price fetch falls back to the session's last good quotes.
      // Mark that state stale too; otherwise fiat values could silently look
      // current while only the native/token balance calls succeeded.
      if (!skipPrices &&
          prices == null &&
          (_pricesUsd != null || _prices.lastGoodUsd != null)) {
        retainedStale = true;
      }
      // In an all-testnet environment a missing quote is intentional, not a
      // failed refresh. Do not publish the session's mainnet last-good prices
      // into this generation or persist them under the testnet snapshot scope.
      _pricesUsd = skipPrices
          ? null
          : prices ?? _pricesUsd ?? _prices.lastGoodUsd;
      _refreshing = false;
      _hasRefreshed = true;
      _showingCachedData = retainedStale;
      final now = DateTime.now();
      _lastUpdatedAt = retainedStale ? (_lastUpdatedAt ?? now) : now;
      notifyListeners();

      if (_snapshots != null && hasLiveBalances) {
        final snapshot = MarketSnapshot(
          scope: scope,
          savedAt: _lastUpdatedAt!,
          native: _results,
          tokens: _tokenResults,
          nativePrices: _pricesUsd ?? const {},
          tokenPrices: skipPrices
              ? const {}
              : _prices.lastGoodTokenUsd ?? const {},
          nativeChanges: skipPrices ? const {} : _prices.lastGoodChange24h,
          tokenChanges: skipPrices ? const {} : _prices.lastGoodTokenChange24h,
          fiatPerUsd: _prices.lastGoodFiatPerUsd,
        );
        _snapshots.save(wallet.id, snapshot).ignore();
      }
      ExperienceMetrics.instance.record(
        ExperienceMetricNames.marketRefresh,
        metricStopwatch.elapsed,
        success: liveFetchSucceeded,
      );
    } catch (_) {
      if (_disposed || generation != _generation) return;
      // Provider contracts normally return explicit error results. Keep this
      // boundary for unexpected transport/plugin failures so the portfolio
      // cannot remain on an infinite skeleton and a later refresh may retry.
      _results = {
        for (final entry in _results.entries)
          entry.key: entry.value.status == BalanceStatus.loading
              ? const BalanceResult.error()
              : entry.value,
      };
      _tokenResults = {
        for (final entry in _tokenResults.entries)
          entry.key: entry.value.status == BalanceStatus.loading
              ? const BalanceResult.error()
              : entry.value,
      };
      _refreshing = false;
      _hasRefreshed = true;
      _showingCachedData = _lastUpdatedAt != null && hasLiveBalances;
      notifyListeners();
      ExperienceMetrics.instance.record(
        ExperienceMetricNames.marketRefresh,
        metricStopwatch.elapsed,
        success: false,
      );
    }
  }

  void _onWalletsChanged() {
    if (_disposed) return;
    final id = _wallets.current?.id;
    if (id == _walletId) return;
    if (id == null) {
      _clearWalletState();
      return;
    }
    refresh();
  }

  /// Invalidates every request owned by the deleted wallet before removing
  /// its balances from memory. A late provider response must not repopulate a
  /// screen after the final wallet (and its public account identity) is gone.
  void _clearWalletState() {
    _generation++;
    _walletId = null;
    _activeSnapshotScope = null;
    _refreshing = false;
    _hasRefreshed = false;
    _showingCachedData = false;
    _lastUpdatedAt = null;
    _results = {
      for (final coin in Coin.values) coin: const BalanceResult.loading(),
    };
    _tokenResults = {
      for (final token in tokens) token.id: const BalanceResult.loading(),
    };
    _pricesUsd = null;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // Balance/price futures cannot be cancelled. Supersede their callbacks so
    // no late provider result can notify a controller after route teardown.
    _generation++;
    _wallets.removeListener(_onWalletsChanged);
    super.dispose();
  }
}

class PortfolioChange24h {
  const PortfolioChange24h({
    required this.deltaUsd,
    required this.percent,
    required this.coveredAssetCount,
  });

  final double deltaUsd;
  final double percent;
  final int coveredAssetCount;
}

/// Formats a non-negative USD value as `$1,234.56` (grouped thousands, two
/// fraction digits) to match the design's fiat strings.
String formatUsd(double value) {
  if (!value.isFinite || value < 0) return '--';
  final fixed = value.toStringAsFixed(2);
  final dot = fixed.indexOf('.');
  final intPart = fixed.substring(0, dot);
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    buf.write(intPart[i]);
    final remaining = intPart.length - 1 - i;
    if (remaining > 0 && remaining % 3 == 0) buf.write(',');
  }
  return '\$$buf${fixed.substring(dot)}';
}

String formatFiat(double value, String currency) {
  if (!value.isFinite || value < 0) return '--';
  final normalized = currency.toUpperCase();
  final decimals = normalized == 'JPY' ? 0 : 2;
  final fixed = value.toStringAsFixed(decimals);
  final dot = fixed.indexOf('.');
  final intPart = dot < 0 ? fixed : fixed.substring(0, dot);
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    buf.write(intPart[i]);
    final remaining = intPart.length - 1 - i;
    if (remaining > 0 && remaining % 3 == 0) buf.write(',');
  }
  final suffix = dot < 0 ? '' : fixed.substring(dot);
  final symbol = switch (normalized) {
    'USD' => r'$',
    'CNY' => 'CN¥',
    'JPY' => 'JP¥',
    _ => '$normalized ',
  };
  return '$symbol$buf$suffix';
}

String formatChange24h(double? value) {
  if (value == null || !value.isFinite) return '';
  final normalized = value.abs() < 0.005 ? 0.0 : value;
  return '${normalized >= 0 ? '+' : ''}${normalized.toStringAsFixed(2)}%';
}

String formatSignedUsd(double value) {
  if (!value.isFinite) return '--';
  final normalized = value.abs() < 0.005 ? 0.0 : value;
  return '${normalized >= 0 ? '+' : '-'}${formatUsd(normalized.abs())}';
}
