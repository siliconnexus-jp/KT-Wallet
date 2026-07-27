import 'dart:math' as math;

// ignore_for_file: prefer_initializing_formals

import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter/foundation.dart';

import '../state/wallet_controller.dart';
import 'balance_service.dart';
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
  }) : _wallets = wallets,
       _balances = balances ?? BalanceService(),
       _prices = prices ?? PriceService(),
       _isTestnet = isTestnet ?? _neverTestnet,
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

  /// Whether [coin]'s ACTIVE network instance is a testnet, re-evaluated on
  /// every read (network switches apply live). Testnet amounts are real but
  /// have no market price — fiat is suppressed, never invented. Default:
  /// nothing is a testnet (today's behavior for all existing wiring).
  final bool Function(Coin coin) _isTestnet;

  static bool _neverTestnet(Coin _) => false;

  String? _walletId;
  int _generation = 0;
  bool _refreshing = false;
  bool _hasRefreshed = false;

  Map<Coin, BalanceResult> _results = {
    for (final coin in Coin.values) coin: const BalanceResult.loading(),
  };
  Map<String, BalanceResult> _tokenResults = const {};
  Map<Coin, double>? _pricesUsd;

  /// True while a refresh is in flight (rows render '--' placeholders).
  bool get isRefreshing => _refreshing;

  /// True once at least one refresh has completed (success or not).
  bool get hasRefreshed => _hasRefreshed;

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

  double? priceUsd(Coin coin) => _pricesUsd?[coin];

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
    return amount.raw.toDouble() /
        math.pow(10, amount.decimals).toDouble() *
        price;
  }

  double? tokenPriceUsd(String symbol) => _prices.tokenPriceUsd(symbol);

  double? tokenChange24hPercent(String symbol) =>
      _prices.tokenChange24hPercent(symbol);

  /// USD value of one token's balance, or null when unavailable. Stablecoins
  /// use live market quotes, so a depeg is reflected instead of being forced
  /// to $1. Tokens without a price feed stay null ('--'), never invented.
  double? tokenFiatValueUsd(TokenInfo token) {
    if (_isTestnet(token.chain)) return null;
    final result = tokenBalanceFor(token.id);
    final amount = result.amount;
    if (result.status != BalanceStatus.ok || amount == null) return null;
    final price = tokenPriceUsd(token.symbol);
    if (price == null) return null;
    return amount.raw.toDouble() /
        math.pow(10, amount.decimals).toDouble() *
        price;
  }

  /// Sum of the computable per-chain and per-token fiat values, or null when
  /// none is computable (a partially failed refresh totals only what's known).
  double? get totalUsd {
    double? total;
    for (final coin in Coin.values) {
      final value = fiatValueUsd(coin);
      if (value != null) total = (total ?? 0) + value;
    }
    for (final token in tokens) {
      final value = tokenFiatValueUsd(token);
      if (value != null) total = (total ?? 0) + value;
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
      current += value;
      previous += value / ratio;
      covered++;
    }

    for (final coin in Coin.values) {
      include(fiatValueUsd(coin), change24hPercent(coin));
    }
    for (final token in tokens) {
      include(
        tokenFiatValueUsd(token),
        _isTestnet(token.chain) ? null : tokenChange24hPercent(token.symbol),
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
    if (_hasRefreshed || _refreshing) return;
    refresh();
  }

  /// Fetches balances (current wallet's addresses) and prices concurrently.
  /// A refresh superseded by a newer one (e.g. wallet switched mid-flight)
  /// discards its results.
  Future<void> refresh() async {
    final wallet = _wallets.current;
    if (wallet == null) return;
    final generation = ++_generation;
    _refreshing = true;
    _results = {
      for (final coin in Coin.values) coin: const BalanceResult.loading(),
    };
    _tokenResults = {
      for (final token in tokens) token.id: const BalanceResult.loading(),
    };
    notifyListeners();

    final tokenService = _tokens;
    // With every active chain on a testnet there is nothing to price — skip
    // the fetch entirely (an unpriceable quote must not even be requested).
    // Mixed environments still fetch once; testnet chains ignore the result
    // via the fiat guards above.
    final skipPrices = Coin.values.every(_isTestnet);
    final (balances, prices, tokenBalances) = await (
      _balances.fetchAll(
        wallet.addresses,
        onResult: (coin, result) {
          // Reveal each fast chain immediately. A slow or unavailable RPC on
          // another chain must not keep an already-known ETH/SOL/etc. balance
          // behind the same '--' placeholder.
          if (generation != _generation) return;
          _results = {..._results, coin: result};
          notifyListeners();
        },
      ),
      skipPrices
          ? Future<Map<Coin, double>?>.value(null)
          : _prices.fetchUsdPrices(),
      tokenService == null
          ? Future.value(const <String, BalanceResult>{})
          : tokenService.fetchAll(wallet.addresses),
    ).wait;

    if (generation != _generation) return; // superseded — drop stale results
    _results = balances;
    _tokenResults = tokenBalances;
    // A failed price fetch falls back to the session's last good quotes
    // (prices drift slowly; balances are never substituted this way).
    _pricesUsd = prices ?? _prices.lastGoodUsd;
    _refreshing = false;
    _hasRefreshed = true;
    notifyListeners();
  }

  void _onWalletsChanged() {
    final id = _wallets.current?.id;
    if (id == _walletId) return;
    _walletId = id;
    if (id != null) refresh();
  }

  @override
  void dispose() {
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

String formatChange24h(double? value) {
  if (value == null) return '';
  final normalized = value.abs() < 0.005 ? 0.0 : value;
  return '${normalized >= 0 ? '+' : ''}${normalized.toStringAsFixed(2)}%';
}

String formatSignedUsd(double value) {
  final normalized = value.abs() < 0.005 ? 0.0 : value;
  return '${normalized >= 0 ? '+' : '-'}${formatUsd(normalized.abs())}';
}
