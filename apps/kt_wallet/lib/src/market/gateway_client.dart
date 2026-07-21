import 'dart:convert';

import 'package:chains/rpc.dart' show GasFeeEstimate, GasFeeEstimateTier;
import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:http/http.dart' as http;

/// Thin JSON-RPC 2.0 client for the OPTIONAL KT gateway (`POST {url}/rpc`).
///
/// The gateway is never required: services hold a [GatewayResolver] that
/// returns null in direct mode, and every gateway failure falls back to the
/// existing direct chain path (or an honest error where none exists).
///
/// Protocol contract (mirrored by the Go service):
/// - `kt_health` () → `{"ok": true, "version": "..."}`
/// - `kt_getBalances` `{chain, address, tokens?}` → native + per-token rows
///   (a failing token carries a per-token `error` instead of failing the call)
/// - `kt_getPrices` `{symbols}` → `{prices: {SYM: {usd: F}}, cachedAtMs}`
/// - `kt_getChainParams` `{chain, address}` → decimal nonce + 3-tier fees
/// - `kt_getHistory` `{chain, address, limit?}` → `{status, records}`
/// - `kt_broadcast` `{chain, payload}` → `{txHash}`
/// Errors: -32700/-32600/-32601/-32602 protocol, -32000 upstream_error
/// (data.upstream / data.message carry the node's reason), -32001
/// rate_limited, -32002 unsupported.
class GatewayClient {
  GatewayClient({
    required String baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  })  : baseUrl = _stripTrailingSlash(baseUrl),
        _client = client ?? http.Client();

  /// Gateway base URL without a trailing slash; requests go to `$baseUrl/rpc`.
  final String baseUrl;
  final Duration timeout;
  final http.Client _client;

  int _nextId = 0;

  static String _stripTrailingSlash(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  /// Wire name for [coin] — the contract's `chain` enum happens to match
  /// [Coin.name] exactly ("eth" | "polygon" | "tron" | "solana").
  static String chainName(Coin coin) => coin.name;

  /// One JSON-RPC 2.0 call (no batches). JSON-RPC errors throw
  /// [GatewayException]; transport failures (non-200, timeout, malformed
  /// body) throw their native exception types.
  Future<Object?> _call(String method, [Map<String, Object?>? params]) async {
    final id = ++_nextId;
    final resp = await _client
        .post(
          Uri.parse('$baseUrl/rpc'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({
            'jsonrpc': '2.0',
            'id': id,
            'method': method,
            'params': ?params,
          }),
        )
        .timeout(timeout);
    if (resp.statusCode != 200) {
      throw http.ClientException(
          'HTTP ${resp.statusCode}', Uri.parse('$baseUrl/rpc'));
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) {
      throw const FormatException('gateway response is not a JSON object');
    }
    final error = decoded['error'];
    if (error is Map) {
      final data = error['data'];
      throw GatewayException(
        code: error['code'] is int ? error['code'] as int : 0,
        message:
            error['message'] is String ? error['message'] as String : 'error',
        upstream: data is Map && data['upstream'] is String
            ? data['upstream'] as String
            : null,
        upstreamMessage: data is Map && data['message'] is String
            ? data['message'] as String
            : null,
      );
    }
    return decoded['result'];
  }

  /// `kt_health` — true iff the gateway answered `{ok: true}`. Never throws
  /// (any failure is "not healthy"): this backs the settings screen's
  /// test-connection action.
  Future<bool> health() async {
    try {
      final result = await _call('kt_health');
      return result is Map && result['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  /// `kt_getBalances` — native balance plus one row per requested token
  /// (order preserved; a failing token carries [GatewayTokenBalance.error]).
  Future<GatewayBalances> getBalances({
    required Coin chain,
    required String address,
    List<GatewayTokenQuery> tokens = const [],
  }) async {
    final result = await _call('kt_getBalances', {
      'chain': chainName(chain),
      'address': address,
      if (tokens.isNotEmpty)
        'tokens': [
          for (final t in tokens)
            {'contract': t.contract, 'decimals': t.decimals, 'symbol': t.symbol}
        ],
    });
    if (result is! Map) throw const FormatException('bad balances result');
    final native = result['native'];
    if (native is! Map) throw const FormatException('missing native balance');
    final rows = result['tokens'];
    return GatewayBalances(
      native: GatewayNativeBalance(
        raw: _decBigInt(native['raw']),
        decimals: _int(native['decimals']),
        symbol: _string(native['symbol']),
      ),
      tokens: [
        if (rows is List)
          for (final row in rows)
            if (row is Map)
              GatewayTokenBalance(
                contract: _string(row['contract']),
                error: row['error'] is String ? row['error'] as String : null,
                // raw/decimals/symbol are only trustworthy on non-error rows;
                // a malformed success row degrades to a per-token error.
                raw: row['error'] == null && row['raw'] is String
                    ? BigInt.tryParse(row['raw'] as String)
                    : null,
                decimals: row['decimals'] is int ? row['decimals'] as int : 0,
                symbol: row['symbol'] is String ? row['symbol'] as String : '',
              ),
      ],
    );
  }

  /// `kt_getPrices` — USD spot quotes keyed by symbol (unknown symbols are
  /// omitted by the gateway; an empty map is a valid, useless answer).
  Future<GatewayPrices> getPrices(List<String> symbols) async {
    final result = await _call('kt_getPrices', {'symbols': symbols});
    if (result is! Map) throw const FormatException('bad prices result');
    final prices = result['prices'];
    if (prices is! Map) throw const FormatException('missing prices map');
    final out = <String, double>{};
    for (final entry in prices.entries) {
      final usd = entry.value is Map ? (entry.value as Map)['usd'] : null;
      if (entry.key is String && usd is num) {
        out[entry.key as String] = usd.toDouble();
      }
    }
    return GatewayPrices(
      usdBySymbol: Map.unmodifiable(out),
      cachedAtMs: result['cachedAtMs'] is int ? result['cachedAtMs'] as int : 0,
    );
  }

  /// `kt_getChainParams` — pending nonce + EIP-1559 fee tiers (EVM only;
  /// the gateway answers -32602 for other chains).
  Future<GatewayChainParams> getChainParams({
    required Coin chain,
    required String address,
  }) async {
    final result = await _call('kt_getChainParams', {
      'chain': chainName(chain),
      'address': address,
    });
    if (result is! Map) throw const FormatException('bad chain params result');
    final fees = result['fees'];
    if (fees is! Map) throw const FormatException('missing fees');
    GasFeeEstimateTier tier(String name) {
      final t = fees[name];
      if (t is! Map) throw FormatException('missing $name fee tier');
      return GasFeeEstimateTier(
        maxPriorityFeePerGas: _decBigInt(t['maxPriorityFeePerGas']),
        maxFeePerGas: _decBigInt(t['maxFeePerGas']),
      );
    }

    final nonce = int.tryParse(_string(result['nonce']));
    if (nonce == null) throw const FormatException('non-decimal nonce');
    return GatewayChainParams(
      nonce: nonce,
      fees: GasFeeEstimate(
        slow: tier('slow'),
        standard: tier('standard'),
        fast: tier('fast'),
      ),
    );
  }

  /// `kt_getHistory` — recent transactions, or `unsupported` when the gateway
  /// has no indexer for [chain]. Malformed records are skipped, not fatal.
  Future<GatewayHistory> getHistory({
    required Coin chain,
    required String address,
    int? limit,
  }) async {
    final result = await _call('kt_getHistory', {
      'chain': chainName(chain),
      'address': address,
      'limit': ?limit,
    });
    if (result is! Map) throw const FormatException('bad history result');
    final status = result['status'];
    if (status == 'unsupported') return const GatewayHistory.unsupported();
    if (status != 'ok') throw const FormatException('unknown history status');
    final rows = result['records'];
    if (rows is! List) throw const FormatException('missing records list');
    final records = <GatewayHistoryRecord>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final hash = row['hash'];
      final direction = row['direction'];
      final ts = row['timestampMs'];
      if (hash is! String || ts is! int) continue;
      if (direction != 'in' && direction != 'out') continue;
      records.add(GatewayHistoryRecord(
        hash: hash,
        outgoing: direction == 'out',
        amountRaw:
            row['amountRaw'] is String ? BigInt.tryParse(row['amountRaw'] as String) : null,
        decimals: row['decimals'] is int ? row['decimals'] as int : null,
        symbol: row['symbol'] is String ? row['symbol'] as String : null,
        timestampMs: ts,
        failed: row['status'] == 'failed',
      ));
    }
    return GatewayHistory.ok(List.unmodifiable(records));
  }

  /// `kt_broadcast` — pushes an encoded signed payload (hex for EVM, base64
  /// for Solana, the TronGrid JSON string for TRON) and returns the node's
  /// transaction hash. A node rejection arrives as [GatewayException] -32000
  /// with the node's message in [GatewayException.upstreamMessage].
  Future<String> broadcast({
    required Coin chain,
    required String payload,
  }) async {
    final result = await _call('kt_broadcast', {
      'chain': chainName(chain),
      'payload': payload,
    });
    if (result is! Map || result['txHash'] is! String) {
      throw const FormatException('bad broadcast result');
    }
    return result['txHash'] as String;
  }

  void close() => _client.close();

  static BigInt _decBigInt(Object? value) {
    final parsed = value is String ? BigInt.tryParse(value) : null;
    if (parsed == null) throw const FormatException('non-decimal integer');
    return parsed;
  }

  static int _int(Object? value) {
    if (value is! int) throw const FormatException('missing integer');
    return value;
  }

  static String _string(Object? value) {
    if (value is! String) throw const FormatException('missing string');
    return value;
  }
}

/// A JSON-RPC error answered by the gateway. [code] follows the contract
/// (-32000 upstream_error, -32001 rate_limited, -32002 unsupported, plus the
/// standard protocol codes); for upstream errors [upstreamMessage] carries the
/// node's own reason.
class GatewayException implements Exception {
  const GatewayException({
    required this.code,
    required this.message,
    this.upstream,
    this.upstreamMessage,
  });

  final int code;
  final String message;

  /// Which upstream the gateway was talking to (error data.upstream), if any.
  final String? upstream;

  /// The upstream node's own message (error data.message), if any.
  final String? upstreamMessage;

  /// The contract's "no indexer / not implemented for this chain" code.
  bool get isUnsupported => code == -32002;

  /// The contract's "a node accepted the request and rejected it" code.
  bool get isUpstreamError => code == -32000;

  @override
  String toString() => 'GatewayException($code, $message'
      '${upstreamMessage == null ? '' : ', upstream: $upstreamMessage'})';
}

/// Resolves the gateway to use for the next call, or null in direct mode.
/// Resolved on every fetch (like [RpcEndpointResolver]) so saving or clearing
/// the gateway URL in settings applies from the very next refresh.
typedef GatewayResolver = GatewayClient? Function();

/// A token to query through `kt_getBalances`.
class GatewayTokenQuery {
  const GatewayTokenQuery({
    required this.contract,
    required this.decimals,
    required this.symbol,
  });

  final String contract;
  final int decimals;
  final String symbol;
}

class GatewayNativeBalance {
  const GatewayNativeBalance({
    required this.raw,
    required this.decimals,
    required this.symbol,
  });

  final BigInt raw;
  final int decimals;
  final String symbol;
}

/// One per-token row of a `kt_getBalances` answer. [raw] is non-null exactly
/// when the row succeeded ([error] == null and the value parsed).
class GatewayTokenBalance {
  const GatewayTokenBalance({
    required this.contract,
    required this.raw,
    required this.decimals,
    required this.symbol,
    this.error,
  });

  final String contract;
  final BigInt? raw;
  final int decimals;
  final String symbol;
  final String? error;
}

class GatewayBalances {
  const GatewayBalances({required this.native, required this.tokens});

  final GatewayNativeBalance native;
  final List<GatewayTokenBalance> tokens;
}

class GatewayPrices {
  const GatewayPrices({required this.usdBySymbol, required this.cachedAtMs});

  final Map<String, double> usdBySymbol;
  final int cachedAtMs;
}

class GatewayChainParams {
  const GatewayChainParams({required this.nonce, required this.fees});

  final int nonce;
  final GasFeeEstimate fees;
}

class GatewayHistoryRecord {
  const GatewayHistoryRecord({
    required this.hash,
    required this.outgoing,
    required this.amountRaw,
    required this.decimals,
    required this.symbol,
    required this.timestampMs,
    required this.failed,
  });

  final String hash;
  final bool outgoing;
  final BigInt? amountRaw;
  final int? decimals;
  final String? symbol;
  final int timestampMs;
  final bool failed;
}

class GatewayHistory {
  const GatewayHistory.ok(this.records) : unsupported = false;
  const GatewayHistory.unsupported()
      : unsupported = true,
        records = const [];

  /// True when the gateway itself reports no history source for the chain.
  final bool unsupported;
  final List<GatewayHistoryRecord> records;
}
