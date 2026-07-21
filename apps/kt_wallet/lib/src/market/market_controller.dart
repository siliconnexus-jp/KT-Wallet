import 'dart:math' as math;

import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter/foundation.dart';

import '../state/wallet_controller.dart';
import 'balance_service.dart';
import 'price_service.dart';

/// Live market state for the current wallet: per-chain native balances plus
/// spot USD prices, refreshed on home entry, wallet switch (listens to the
/// [WalletController]) and pull-to-refresh — deliberately no polling loop.
///
/// Fiat math uses doubles for DISPLAY ONLY (totals/row values); on-chain
/// amounts stay exact [BalanceResult.amount] integers throughout.
class MarketController extends ChangeNotifier {
  MarketController({
    required WalletController wallets,
    BalanceService? balances,
    PriceService? prices,
  })  :
        // ignore: prefer_initializing_formals
        _wallets = wallets,
        _balances = balances ?? BalanceService(),
        _prices = prices ?? PriceService() {
    _walletId = _wallets.current?.id;
    _wallets.addListener(_onWalletsChanged);
  }

  final WalletController _wallets;
  final BalanceService _balances;
  final PriceService _prices;

  String? _walletId;
  int _generation = 0;
  bool _refreshing = false;
  bool _hasRefreshed = false;

  Map<Coin, BalanceResult> _results = {
    for (final coin in Coin.values) coin: const BalanceResult.loading(),
  };
  Map<Coin, double>? _pricesUsd;

  /// True while a refresh is in flight (rows render '--' placeholders).
  bool get isRefreshing => _refreshing;

  /// True once at least one refresh has completed (success or not).
  bool get hasRefreshed => _hasRefreshed;

  BalanceResult balanceFor(Coin coin) => _results[coin]!;

  /// Spot USD prices, or null when never fetched successfully this session.
  Map<Coin, double>? get pricesUsd => _pricesUsd;

  double? priceUsd(Coin coin) => _pricesUsd?[coin];

  /// True when at least one chain returned a real balance.
  bool get hasLiveBalances =>
      _results.values.any((r) => r.status == BalanceStatus.ok);

  /// Everything errored: no live balance on any chain AND no prices. The UI
  /// falls back to the demo constants behind an explicit "offline — demo
  /// data" banner (never silently presented as live).
  bool get isOffline =>
      _hasRefreshed && !_refreshing && !hasLiveBalances && _pricesUsd == null;

  /// USD value of one chain's balance, or null when either the balance or its
  /// price is unavailable (display-only double math).
  double? fiatValueUsd(Coin coin) {
    final result = _results[coin]!;
    final amount = result.amount;
    if (result.status != BalanceStatus.ok || amount == null) return null;
    final price = _pricesUsd?[coin];
    if (price == null) return null;
    return amount.raw.toDouble() /
        math.pow(10, amount.decimals).toDouble() *
        price;
  }

  /// Sum of the computable per-chain fiat values, or null when none is
  /// computable (a partially failed refresh totals only what's known).
  double? get totalUsd {
    double? total;
    for (final coin in Coin.values) {
      final value = fiatValueUsd(coin);
      if (value != null) total = (total ?? 0) + value;
    }
    return total;
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
    notifyListeners();

    final (balances, prices) = await (
      _balances.fetchAll(wallet.addresses),
      _prices.fetchUsdPrices(),
    ).wait;

    if (generation != _generation) return; // superseded — drop stale results
    _results = balances;
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
