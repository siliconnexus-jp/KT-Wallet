import 'dart:convert';

import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:http/http.dart' as http;

import '../rpc/bounded_http_client.dart';
import 'balance_service.dart' show BalanceService;
import 'fiat_math.dart';
import 'gateway_client.dart';

/// CoinGecko simple/price base URL — keyless public API tier.
const String defaultCoinGeckoBaseUrl = 'https://api.coingecko.com/api/v3';

/// Spot USD prices and 24h percentage changes for supported native coins via
/// CoinGecko `simple/price` (no API key). The http client is injectable for
/// tests; any failure — non-200, timeout, malformed body — returns `null`
/// (callers must treat prices as unavailable, never substitute a made-up
/// number). The last successful quote set is cached in memory as [lastGoodUsd].
class PriceService {
  PriceService({
    http.Client? client,
    this.baseUrl = defaultCoinGeckoBaseUrl,
    this.timeout = const Duration(seconds: 10),
    GatewayResolver? gateway,
  }) : _client = BoundedHttpClient(client ?? http.Client()),
       _gateway = gateway ?? _noGateway;

  static GatewayClient? _noGateway() => null;

  final http.Client _client;
  final String baseUrl;
  final Duration timeout;

  /// Optional gateway (null in direct mode), resolved on every fetch.
  final GatewayResolver _gateway;

  /// CoinGecko coin ids for the native coins (POL is the migrated
  /// `polygon-ecosystem-token`, not the retired MATIC id).
  static const coinGeckoIds = {
    Coin.eth: 'ethereum',
    Coin.polygon: 'polygon-ecosystem-token',
    Coin.base: 'ethereum',
    Coin.arbitrum: 'ethereum',
    Coin.avalanche: 'avalanche-2',
    Coin.bnb: 'binancecoin',
    Coin.tron: 'tron',
    Coin.solana: 'solana',
  };

  /// CoinGecko ids for the token symbols shown by the built-in registry.
  static const coinGeckoTokenIds = {
    'USDT': 'tether',
    'USDC': 'usd-coin',
    'BUSD': 'binance-usd',
    'DAI': 'dai',
    'WETH': 'weth',
    'WBTC': 'wrapped-bitcoin',
    'LINK': 'chainlink',
    'UNI': 'uniswap',
    'SHIB': 'shiba-inu',
    'PEPE': 'pepe',
    'JUP': 'jupiter-exchange-solana',
    'BONK': 'bonk',
    'PYUSD': 'paypal-usd',
  };

  Map<Coin, double>? _lastGood;
  Map<String, double>? _lastGoodTokenUsd;
  Map<Coin, double> _lastGoodChange24h = const {};
  Map<String, double> _lastGoodTokenChange24h = const {};
  Map<String, double> _lastGoodFiatPerUsd = const {'USD': 1};

  /// Last successfully fetched quote set (in-memory only), or null if no
  /// fetch has ever succeeded in this session.
  Map<Coin, double>? get lastGoodUsd => _lastGood;

  /// Last successful token quote set. Stablecoins are market-priced too so a
  /// depeg is reflected instead of being silently forced to $1.
  Map<String, double>? get lastGoodTokenUsd => _lastGoodTokenUsd;
  Map<Coin, double> get lastGoodChange24h => _lastGoodChange24h;
  Map<String, double> get lastGoodTokenChange24h => _lastGoodTokenChange24h;
  Map<String, double> get lastGoodFiatPerUsd => _lastGoodFiatPerUsd;

  double? fiatPerUsd(String currency) =>
      _lastGoodFiatPerUsd[currency.toUpperCase()];

  double? tokenPriceUsd(String symbol) => _lastGoodTokenUsd?[symbol];
  double? change24hPercent(Coin coin) => _lastGoodChange24h[coin];
  double? tokenChange24hPercent(String symbol) =>
      _lastGoodTokenChange24h[symbol];

  /// Hydrates the display-only last-good cache before a background refresh.
  /// Transaction construction never reads these values.
  void restoreLastGood({
    required Map<Coin, double> nativeUsd,
    required Map<String, double> tokenUsd,
    required Map<Coin, double> nativeChange24h,
    required Map<String, double> tokenChange24h,
    Map<String, double> fiatPerUsd = const {'USD': 1},
  }) {
    final safeNativeUsd = {
      for (final entry in nativeUsd.entries)
        entry.key: ?positiveFiniteMarketNumber(entry.value),
    };
    final safeTokenUsd = {
      for (final entry in tokenUsd.entries)
        entry.key: ?positiveFiniteMarketNumber(entry.value),
    };
    if (safeNativeUsd.isNotEmpty) _lastGood = Map.unmodifiable(safeNativeUsd);
    if (safeTokenUsd.isNotEmpty) {
      _lastGoodTokenUsd = Map.unmodifiable(safeTokenUsd);
    }
    _lastGoodChange24h = Map.unmodifiable({
      for (final entry in nativeChange24h.entries)
        entry.key: ?finiteMarketNumber(entry.value),
    });
    _lastGoodTokenChange24h = Map.unmodifiable({
      for (final entry in tokenChange24h.entries)
        entry.key: ?finiteMarketNumber(entry.value),
    });
    _lastGoodFiatPerUsd = Map.unmodifiable({
      'USD': 1,
      for (final entry in fiatPerUsd.entries)
        entry.key.toUpperCase(): ?positiveFiniteMarketNumber(entry.value),
    });
  }

  /// Fetches spot USD prices. Returns null on any failure; partial responses
  /// keep whichever coins were present.
  ///
  /// GATEWAY SEMANTICS: with a gateway configured, `kt_getPrices` is asked
  /// first (symbols per [BalanceService.symbolFor]); a failing or empty
  /// gateway answer falls back to the direct CoinGecko fetch, so prices
  /// survive a broken gateway. Direct mode never contacts the gateway.
  Future<Map<Coin, double>?> fetchUsdPrices() async {
    final gateway = _gateway();
    if (gateway != null) {
      try {
        final quoted = await gateway.getPrices(
          {
            for (final coin in Coin.values) BalanceService.symbolFor[coin]!,
            ...coinGeckoTokenIds.keys,
          }.toList(),
        );
        final out = <Coin, double>{
          for (final coin in Coin.values)
            if (quoted.usdBySymbol[BalanceService.symbolFor[coin]!] != null)
              coin: quoted.usdBySymbol[BalanceService.symbolFor[coin]!]!,
        };
        final tokenOut = <String, double>{
          for (final symbol in coinGeckoTokenIds.keys)
            if (quoted.usdBySymbol[symbol] != null)
              symbol: quoted.usdBySymbol[symbol]!,
        };
        final changeOut = <Coin, double>{
          for (final coin in Coin.values)
            if (quoted.change24hBySymbol[BalanceService.symbolFor[coin]!] !=
                null)
              coin: quoted.change24hBySymbol[BalanceService.symbolFor[coin]!]!,
        };
        final tokenChangeOut = <String, double>{
          for (final symbol in coinGeckoTokenIds.keys)
            if (quoted.change24hBySymbol[symbol] != null)
              symbol: quoted.change24hBySymbol[symbol]!,
        };
        if (out.isNotEmpty || tokenOut.isNotEmpty) {
          if (tokenOut.isNotEmpty) {
            _lastGoodTokenUsd = Map.unmodifiable(tokenOut);
          }
          _lastGoodChange24h = Map.unmodifiable(changeOut);
          _lastGoodTokenChange24h = Map.unmodifiable(tokenChangeOut);
          _lastGoodFiatPerUsd = quoted.fiatPerUsd;
          _lastGood = Map.unmodifiable(out);
          return _lastGood;
        }
        // All symbols unknown to the gateway: try CoinGecko instead.
      } catch (_) {
        // GatewayException / transport failure: direct CoinGecko fallback.
      }
    }
    try {
      final ids = {
        ...coinGeckoIds.values,
        ...coinGeckoTokenIds.values,
      }.join(',');
      final uri = Uri.parse(
        '$baseUrl/simple/price?ids=$ids&vs_currencies=usd,cny,jpy'
        '&include_24hr_change=true',
      );
      final resp = await _client.get(uri).timeout(timeout);
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body);
      if (body is! Map) return null;
      final out = <Coin, double>{};
      final changeOut = <Coin, double>{};
      for (final entry in coinGeckoIds.entries) {
        final row = body[entry.value];
        final usd = row is Map ? positiveFiniteMarketNumber(row['usd']) : null;
        if (usd != null) out[entry.key] = usd;
        final change = row is Map ? row['usd_24h_change'] : null;
        final parsedChange = finiteMarketNumber(change);
        if (usd != null && parsedChange != null) {
          changeOut[entry.key] = parsedChange;
        }
      }
      final tokenOut = <String, double>{};
      final tokenChangeOut = <String, double>{};
      for (final entry in coinGeckoTokenIds.entries) {
        final row = body[entry.value];
        final usd = row is Map ? positiveFiniteMarketNumber(row['usd']) : null;
        if (usd != null) tokenOut[entry.key] = usd;
        final change = row is Map ? row['usd_24h_change'] : null;
        final parsedChange = finiteMarketNumber(change);
        if (usd != null && parsedChange != null) {
          tokenChangeOut[entry.key] = parsedChange;
        }
      }
      if (out.isEmpty && tokenOut.isEmpty) return null;
      final rates = <String, double>{'USD': 1};
      for (final row in body.values) {
        if (row is! Map) continue;
        final usd = row['usd'];
        final cny = row['cny'];
        final jpy = row['jpy'];
        final safeUsd = positiveFiniteMarketNumber(usd);
        if (safeUsd == null) continue;
        final safeCny = positiveFiniteMarketNumber(cny);
        final safeJpy = positiveFiniteMarketNumber(jpy);
        if (safeCny != null) {
          final rate = safeCny / safeUsd;
          if (rate.isFinite && rate > 0) rates['CNY'] = rate;
        }
        if (safeJpy != null) {
          final rate = safeJpy / safeUsd;
          if (rate.isFinite && rate > 0) rates['JPY'] = rate;
        }
        if (rates.length == 3) break;
      }
      if (tokenOut.isNotEmpty) {
        _lastGoodTokenUsd = Map.unmodifiable(tokenOut);
      }
      _lastGoodChange24h = Map.unmodifiable(changeOut);
      _lastGoodTokenChange24h = Map.unmodifiable(tokenChangeOut);
      _lastGoodFiatPerUsd = Map.unmodifiable(rates);
      _lastGood = Map.unmodifiable(out);
      return _lastGood;
    } catch (_) {
      return null;
    }
  }

  void close() => _client.close();
}
