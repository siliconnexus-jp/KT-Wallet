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
/// - `kt_health` () → `{"ok": true, "version": "...", "networks": [...]}`
/// - `kt_getBalances` `{chain, network?, address, tokens?}` → native +
///   per-token rows (a failing token carries a per-token `error` instead of
///   failing the call)
/// - `kt_getPrices` `{symbols}` → `{prices: {SYM: {usd: F}}, cachedAtMs}`
/// - `kt_getChainParams` `{chain, network?, address}` → decimal nonce +
///   3-tier fees
/// - `kt_getHistory` `{chain, network?, address, limit?}` → `{status, records}`
/// - `kt_broadcast` `{chain, network?, payload}` → `{txHash}`
/// Errors: -32700/-32600/-32601/-32602 protocol, -32000 upstream_error
/// (data.upstream / data.message carry the node's reason), -32001
/// rate_limited, -32002 unsupported.
///
/// NETWORK SCOPING (release-critical): every chain-scoped method carries the
/// ACTIVE network id from [networks]. An omitted `network` makes the gateway
/// answer for the chain's MAINNET, so a client on Sepolia that leaves it out
/// reads mainnet balances, builds transactions with a mainnet nonce, and
/// broadcasts testnet-signed bytes to a mainnet node. When no [networks]
/// resolver is wired (tests, gallery) the param stays absent and the
/// pre-network behavior applies unchanged.
class GatewayClient {
  GatewayClient({
    required String baseUrl,
    http.Client? client,
    NetworkIdResolver? networks,
    Set<String>? advertisedNetworks,
    this.timeout = const Duration(seconds: 10),
  }) : baseUrl = _stripTrailingSlash(baseUrl),
       _client = client ?? http.Client(),
       _networks = networks ?? _noNetwork,
       _advertised = advertisedNetworks == null
           ? null
           : Set.unmodifiable(advertisedNetworks);

  /// Gateway base URL without a trailing slash; requests go to `$baseUrl/rpc`.
  final String baseUrl;
  final Duration timeout;
  final http.Client _client;

  /// Active-network source for the chain-scoped methods.
  final NetworkIdResolver _networks;

  static String? _noNetwork(Coin coin) => null;

  /// The network ids this gateway advertises, learned once from `kt_health`
  /// (or seeded at construction in tests). Null until the first probe.
  Set<String>? _advertised;

  /// In-flight probe, shared by concurrent calls (one refresh fans out to
  /// every chain at once — that must cost a single `kt_health`).
  Future<Set<String>>? _probing;

  /// What a gateway deployed before the `networks` field can serve: one
  /// mainnet per chain family it knew about. Sending the matching id to such
  /// a gateway is harmless (it ignores the unknown param and answers for the
  /// mainnet anyway), while every testnet correctly bypasses it.
  static const Set<String> legacyNetworks = {
    'eth-mainnet',
    'polygon-mainnet',
    'tron-mainnet',
    'sol-mainnet',
  };

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
        'HTTP ${resp.statusCode}',
        Uri.parse('$baseUrl/rpc'),
      );
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
        message: error['message'] is String
            ? error['message'] as String
            : 'error',
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
  /// test-connection action. Always hits the wire (it is a liveness check),
  /// and refreshes the advertised-network set on the way.
  Future<bool> health() async {
    try {
      final result = await _call('kt_health');
      if (result is! Map || result['ok'] != true) return false;
      _advertised = _networksFrom(result);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The active network id this client scopes [chain] calls to, or null when
  /// no network source is wired.
  String? activeNetworkId(Coin chain) => _networks(chain);

  /// The `network` param for [chain]: the active id, or null when no network
  /// source is wired (pre-network behavior — the gateway answers for the
  /// chain's mainnet).
  ///
  /// CUSTOM-NETWORK POLICY: throws [GatewayNetworkUnsupported] when the active
  /// network is not one the gateway advertises — a user-added `custom-*`
  /// network the gateway cannot possibly know, or a chain family this app
  /// supports and the deployed gateway does not. Callers treat that like any
  /// other gateway failure and take their direct path, which is the only
  /// honest outcome: the alternative is the gateway silently answering for
  /// MAINNET. The advertised set is learned once per client from `kt_health`;
  /// if that probe fails the gateway is not answering anyway, so the call is
  /// bypassed and the set is re-probed next time.
  Future<String?> _networkParam(Coin chain) async {
    final id = _networks(chain);
    if (id == null) return null;
    final Set<String> advertised;
    try {
      advertised = await _advertisedNetworks();
    } catch (_) {
      throw GatewayNetworkUnsupported(id);
    }
    if (!advertised.contains(id)) throw GatewayNetworkUnsupported(id);
    return id;
  }

  Future<Set<String>> _advertisedNetworks() {
    final known = _advertised;
    if (known != null) return Future.value(known);
    return _probing ??= _probeNetworks().whenComplete(() => _probing = null);
  }

  Future<Set<String>> _probeNetworks() async {
    final result = await _call('kt_health');
    if (result is! Map || result['ok'] != true) {
      throw const FormatException('gateway is not healthy');
    }
    return _advertised = _networksFrom(result);
  }

  /// The `networks` array of a `kt_health` result; a gateway that predates the
  /// field is assumed to serve [legacyNetworks] only.
  static Set<String> _networksFrom(Map<Object?, Object?> health) {
    final rows = health['networks'];
    if (rows is! List) return legacyNetworks;
    return Set.unmodifiable({
      for (final row in rows)
        if (row is String) row,
    });
  }

  /// `kt_getBalances` — native balance plus one row per requested token
  /// (order preserved; a failing token carries [GatewayTokenBalance.error]),
  /// scoped to the active network of [chain].
  Future<GatewayBalances> getBalances({
    required Coin chain,
    required String address,
    List<GatewayTokenQuery> tokens = const [],
  }) async {
    final network = await _networkParam(chain);
    final result = await _call('kt_getBalances', {
      'chain': chainName(chain),
      'network': ?network,
      'address': address,
      if (tokens.isNotEmpty)
        'tokens': [
          for (final t in tokens)
            {
              'contract': t.contract,
              'decimals': t.decimals,
              'symbol': t.symbol,
            },
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

  /// `kt_getChainParams` — pending nonce + EIP-1559 fee tiers of the active
  /// network of [chain] (EVM only; the gateway answers -32602 for other
  /// chains). The network scoping is what keeps a testnet transaction from
  /// being built with a mainnet nonce.
  Future<GatewayChainParams> getChainParams({
    required Coin chain,
    required String address,
  }) async {
    final network = await _networkParam(chain);
    final result = await _call('kt_getChainParams', {
      'chain': chainName(chain),
      'network': ?network,
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

  /// `kt_getHistory` — recent transactions of the active network of [chain],
  /// or `unsupported` when the gateway has no indexer for it. Malformed
  /// records are skipped, not fatal.
  Future<GatewayHistory> getHistory({
    required Coin chain,
    required String address,
    int? limit,
  }) async {
    final network = await _networkParam(chain);
    final result = await _call('kt_getHistory', {
      'chain': chainName(chain),
      'network': ?network,
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
      records.add(
        GatewayHistoryRecord(
          hash: hash,
          outgoing: direction == 'out',
          amountRaw: row['amountRaw'] is String
              ? BigInt.tryParse(row['amountRaw'] as String)
              : null,
          decimals: row['decimals'] is int ? row['decimals'] as int : null,
          symbol: row['symbol'] is String ? row['symbol'] as String : null,
          timestampMs: ts,
          failed: row['status'] == 'failed',
        ),
      );
    }
    return GatewayHistory.ok(List.unmodifiable(records));
  }

  /// `kt_broadcast` — pushes an encoded signed payload (hex for EVM, base64
  /// for Solana, the TronGrid JSON string for TRON) to the active network of
  /// [chain] and returns the node's transaction hash. A node rejection
  /// arrives as [GatewayException] -32000 with the node's message in
  /// [GatewayException.upstreamMessage].
  ///
  /// The network param is resolved BEFORE the post: a bypass
  /// ([GatewayNetworkUnsupported]) can therefore never leave a transaction
  /// half-submitted, and a testnet-signed payload can never reach a mainnet
  /// node (which would answer -32000 and, per INV-15, block the direct retry
  /// of a perfectly valid transaction).
  Future<String> broadcast({
    required Coin chain,
    required String payload,
  }) async {
    final network = await _networkParam(chain);
    final result = await _call('kt_broadcast', {
      'chain': chainName(chain),
      'network': ?network,
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
  String toString() =>
      'GatewayException($code, $message'
      '${upstreamMessage == null ? '' : ', upstream: $upstreamMessage'})';
}

/// Raised INSTEAD of contacting the gateway when the active network is one it
/// does not advertise: a user-added `custom-*` network, or a chain family this
/// app knows and the deployed gateway does not.
///
/// Deliberately NOT a [GatewayException]: no request left the app and no node
/// saw anything, so every caller — including [broadcast]'s INV-15 "one post"
/// rule — is free to take its direct path. Bypassing is the only honest
/// option; the gateway would otherwise answer for the chain's MAINNET.
class GatewayNetworkUnsupported implements Exception {
  const GatewayNetworkUnsupported(this.networkId);

  /// The active network id the gateway cannot serve.
  final String networkId;

  @override
  String toString() =>
      'GatewayNetworkUnsupported($networkId): the gateway does not serve this '
      'network; using the direct path';
}

/// Resolves the gateway to use for the next call, or null in direct mode.
/// Resolved on every fetch (like [RpcEndpointResolver]) so saving or clearing
/// the gateway URL in settings applies from the very next refresh.
typedef GatewayResolver = GatewayClient? Function();

/// Resolves the ACTIVE network id of a chain family ('eth-sepolia',
/// 'custom-1753...'), i.e. `NetworkController.activeFor(chain).id`. Returning
/// null means "no network source wired" (tests, gallery): chain-scoped calls
/// then omit the `network` param and the gateway answers for the chain's
/// mainnet, exactly as before network support existed.
typedef NetworkIdResolver = String? Function(Coin coin);

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
  const GatewayHistory.unsupported() : unsupported = true, records = const [];

  /// True when the gateway itself reports no history source for the chain.
  final bool unsupported;
  final List<GatewayHistoryRecord> records;
}
