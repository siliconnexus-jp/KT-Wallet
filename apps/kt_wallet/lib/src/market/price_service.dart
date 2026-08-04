import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:http/http.dart' as http;

import '../rpc/bounded_http_client.dart';
import '../rpc/json_rpc_envelope.dart';
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

  static const _coinGeckoQuoteKeys = <String>{
    'usd',
    'usd_24h_change',
    'cny',
    'cny_24h_change',
    'jpy',
    'jpy_24h_change',
    'last_updated_at',
  };
  static const _maximumQuoteAge = Duration(minutes: 15);
  static const _maximumFutureClockSkew = Duration(minutes: 5);
  static const _maximumChange = 1000000000.0;
  static const _maximumFxDeviation = 0.005;

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

  /// Fetches spot USD prices. Returns null on any failure. Both Gateway and
  /// direct CoinGecko responses are all-or-nothing trust boundaries: a bad,
  /// partial, additive, stale or internally inconsistent quote set never
  /// replaces the last known-good display cache.
  ///
  /// GATEWAY SEMANTICS: with a gateway configured, `kt_getPrices` is asked
  /// first (symbols per [BalanceService.symbolFor]); a failing or empty
  /// gateway answer falls back to the direct CoinGecko fetch, so prices
  /// survive a broken gateway. Direct mode never contacts the gateway.
  Future<Map<Coin, double>?> fetchUsdPrices() async {
    final gateway = _gateway();
    if (gateway != null) {
      try {
        final requestedSymbols = {
          for (final coin in Coin.values) BalanceService.symbolFor[coin]!,
          ...coinGeckoTokenIds.keys,
        };
        final quoted = await gateway.getPrices(requestedSymbols.toList());
        if (quoted.usdBySymbol.length != requestedSymbols.length ||
            !requestedSymbols.every(quoted.usdBySymbol.containsKey)) {
          throw const FormatException('partial known-symbol price result');
        }
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
        // Defensive fallback; the exact-set check above normally owns this.
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
        '&include_24hr_change=true&include_last_updated_at=true'
        '&precision=full',
      );
      final resp = await _client.get(uri).timeout(timeout);
      if (resp.statusCode != 200) return null;
      final body = decodeJsonWithoutDuplicateKeys(resp.body);
      final expectedIds = {...coinGeckoIds.values, ...coinGeckoTokenIds.values};
      if (body is! Map || !_hasExactStringKeys(body, expectedIds)) return null;

      final now = DateTime.now();
      final quotes = <String, _DirectMarketQuote>{};
      final cnyRates = <double>[];
      final jpyRates = <double>[];
      for (final entry in body.entries) {
        final id = entry.key;
        final row = entry.value;
        if (id is! String ||
            !expectedIds.contains(id) ||
            row is! Map ||
            !_hasExactStringKeys(row, _coinGeckoQuoteKeys)) {
          return null;
        }
        final usd = positiveFiniteMarketNumber(row['usd']);
        final cny = positiveFiniteMarketNumber(row['cny']);
        final jpy = positiveFiniteMarketNumber(row['jpy']);
        final usdChange = _nullableMarketChange(row['usd_24h_change']);
        final cnyChange = _nullableMarketChange(row['cny_24h_change']);
        final jpyChange = _nullableMarketChange(row['jpy_24h_change']);
        final updatedAt = row['last_updated_at'];
        if (usd == null ||
            cny == null ||
            jpy == null ||
            (row['usd_24h_change'] != null && usdChange == null) ||
            (row['cny_24h_change'] != null && cnyChange == null) ||
            (row['jpy_24h_change'] != null && jpyChange == null) ||
            updatedAt is! int) {
          return null;
        }
        final sourceTime = DateTime.fromMillisecondsSinceEpoch(
          updatedAt * 1000,
          isUtc: true,
        );
        if (sourceTime.isBefore(now.subtract(_maximumQuoteAge)) ||
            sourceTime.isAfter(now.add(_maximumFutureClockSkew))) {
          return null;
        }
        final cnyRate = cny / usd;
        final jpyRate = jpy / usd;
        if (!_rateInRange(cnyRate, 0.1, 100) ||
            !_rateInRange(jpyRate, 1, 10000)) {
          return null;
        }
        cnyRates.add(cnyRate);
        jpyRates.add(jpyRate);
        quotes[id] = _DirectMarketQuote(usd: usd, change24h: usdChange);
      }
      if (!_ratesAgree(cnyRates) || !_ratesAgree(jpyRates)) return null;

      final out = <Coin, double>{
        for (final entry in coinGeckoIds.entries)
          entry.key: quotes[entry.value]!.usd,
      };
      final changeOut = <Coin, double>{
        for (final entry in coinGeckoIds.entries)
          if (quotes[entry.value]!.change24h != null)
            entry.key: quotes[entry.value]!.change24h!,
      };
      final tokenOut = <String, double>{
        for (final entry in coinGeckoTokenIds.entries)
          entry.key: quotes[entry.value]!.usd,
      };
      final tokenChangeOut = <String, double>{
        for (final entry in coinGeckoTokenIds.entries)
          if (quotes[entry.value]!.change24h != null)
            entry.key: quotes[entry.value]!.change24h!,
      };
      final rates = <String, double>{
        'USD': 1,
        'CNY': _median(cnyRates),
        'JPY': _median(jpyRates),
      };
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

  static bool _hasExactStringKeys(
    Map<Object?, Object?> value,
    Set<String> expected,
  ) =>
      value.length == expected.length &&
      value.keys.every((key) => key is String && expected.contains(key));

  static double? _nullableMarketChange(Object? value) {
    if (value == null) return null;
    final parsed = finiteMarketNumber(value);
    return parsed != null && parsed >= -100 && parsed <= _maximumChange
        ? parsed
        : null;
  }

  static bool _rateInRange(double value, double minimum, double maximum) =>
      value.isFinite && value >= minimum && value <= maximum;

  static bool _ratesAgree(List<double> rates) {
    if (rates.isEmpty) return false;
    final median = _median(rates);
    return rates.every(
      (rate) => (rate / median - 1).abs() <= _maximumFxDeviation,
    );
  }

  static double _median(List<double> values) {
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
  }
}

class _DirectMarketQuote {
  const _DirectMarketQuote({required this.usd, required this.change24h});

  final double usd;
  final double? change24h;
}
