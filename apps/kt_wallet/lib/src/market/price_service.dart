import 'dart:convert';

import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:http/http.dart' as http;

/// CoinGecko simple/price base URL — keyless public API tier.
const String defaultCoinGeckoBaseUrl = 'https://api.coingecko.com/api/v3';

/// Spot USD prices for the four native coins via CoinGecko `simple/price`
/// (no API key). The http client is injectable for tests; any failure —
/// non-200, timeout, malformed body — returns `null` (callers must treat
/// prices as unavailable, never substitute a made-up number). The last
/// successful quote set is cached in memory as [lastGoodUsd].
class PriceService {
  PriceService({
    http.Client? client,
    this.baseUrl = defaultCoinGeckoBaseUrl,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final Duration timeout;

  /// CoinGecko coin ids for the native coins (POL is the migrated
  /// `polygon-ecosystem-token`, not the retired MATIC id).
  static const coinGeckoIds = {
    Coin.eth: 'ethereum',
    Coin.polygon: 'polygon-ecosystem-token',
    Coin.tron: 'tron',
    Coin.solana: 'solana',
  };

  /// USD-pegged stablecoins quoted at exactly 1.0 without a network call.
  static const peggedUsdBySymbol = {'USDT': 1.0, 'USDC': 1.0, 'BUSD': 1.0};

  Map<Coin, double>? _lastGood;

  /// Last successfully fetched quote set (in-memory only), or null if no
  /// fetch has ever succeeded in this session.
  Map<Coin, double>? get lastGoodUsd => _lastGood;

  /// Fetches spot USD prices. Returns null on any failure; partial responses
  /// keep whichever coins were present.
  Future<Map<Coin, double>?> fetchUsdPrices() async {
    try {
      final ids = coinGeckoIds.values.join(',');
      final uri = Uri.parse('$baseUrl/simple/price?ids=$ids&vs_currencies=usd');
      final resp = await _client.get(uri).timeout(timeout);
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body);
      if (body is! Map) return null;
      final out = <Coin, double>{};
      for (final entry in coinGeckoIds.entries) {
        final row = body[entry.value];
        final usd = row is Map ? row['usd'] : null;
        if (usd is num) out[entry.key] = usd.toDouble();
      }
      if (out.isEmpty) return null;
      _lastGood = Map.unmodifiable(out);
      return _lastGood;
    } catch (_) {
      return null;
    }
  }

  void close() => _client.close();
}
