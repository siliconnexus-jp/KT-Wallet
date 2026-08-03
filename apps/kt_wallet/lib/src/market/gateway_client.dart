import 'dart:convert';

import 'package:chains/chains.dart' show Amount;
import 'package:chains/rpc.dart' show GasFeeEstimate, GasFeeEstimateTier;
import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:http/http.dart' as http;

import '../rpc/bounded_http_client.dart';
import '../rpc/json_rpc_envelope.dart';
import 'fiat_math.dart';

/// Thin JSON-RPC 2.0 client for the OPTIONAL KT gateway (`POST {url}/rpc`).
///
/// The gateway is never required: services hold a [GatewayResolver] that
/// returns null in direct mode. Read-only calls may fall back to direct chain
/// sources. Broadcasts are stricter: only failures proven to occur before an
/// upstream write may fall back, because a timeout can hide an accepted tx.
///
/// Protocol contract (mirrored by the Go service):
/// - `kt_health` () → `{"ok": true, "version": "...", "networks": [...]}`
/// - `kt_getBalances` `{chain, network?, address, tokens?}` → native +
///   per-token rows (a failing token carries a per-token `error` instead of
///   failing the call)
/// - `kt_getPrices` `{symbols}` → `{prices: {SYM: {usd: F}}, cachedAtMs}`
/// - `kt_getChainParams` `{chain, network?, address}` → decimal nonce +
///   3-tier fees
/// - `kt_simulateEvmTransfer` `{chain, network?, from, to, value, data}` →
///   exact pending-state `eth_call` return bytes
/// - `kt_estimateEvmGas` `{chain, network?, from, to, value, data}` →
///   decimal gas estimate
/// - `kt_getEvmSpendableBalances`
///   `{chain, network?, address, tokenContract?}` → uncached pending balances
/// - `kt_getHistory` `{chain, network?, address, limit?}` → `{status, records}`
/// - `kt_searchTokens` `{query?, networks?, limit?}` → verified token catalog
/// - `kt_checkTokenRisk` `{chain, network?, contract}` →
///   `{status: safe|unsafe|unknown, category?, source}`
/// - `kt_getEvmTokenApprovals`
///   `{chain, network?, address, privacyConsent:true}` → outstanding ERC-20
///   allowances; provider/unsupported failures never become an empty list
/// - `kt_broadcast` `{chain, network?, payload}` → `{txHash}`
/// Errors: -32700/-32600/-32601/-32602 protocol, -32000 upstream_error
/// (data.upstream / data.message carry the node's reason), -32001
/// rate_limited, -32002 unsupported, -32003 submission_unknown (a broadcast
/// may have reached the node, so callers must reconcile by local txHash and
/// must not submit it again).
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
       _client = BoundedHttpClient(client ?? http.Client()),
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
  /// body) throw [GatewayTransportException] without retaining the endpoint
  /// URL or response body.
  Future<Object?> _call(String method, [Map<String, Object?>? params]) async {
    final id = ++_nextId;
    final request = <String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': ?params,
    };
    final http.Response resp;
    try {
      resp = await _client
          .post(
            Uri.parse('$baseUrl/rpc'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode(request),
          )
          .timeout(timeout);
    } on Object {
      // ClientException includes its URI. A custom gateway URL may contain a
      // provider credential, so the raw exception must stop here.
      throw const GatewayTransportException();
    }
    if (resp.statusCode != 200) {
      throw GatewayTransportException(
        'gateway returned HTTP ${resp.statusCode}',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(resp.body);
    } on Object {
      // FormatException.toString() may include a snippet of the response.
      throw const GatewayTransportException('invalid gateway response');
    }
    if (!isBoundJsonRpcResponse(request, decoded) || decoded is! Map) {
      throw const GatewayTransportException('invalid gateway response');
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
  Future<String?> _networkParam(Coin chain, {String? networkOverride}) async {
    final id = networkOverride ?? _networks(chain);
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
    return _parseBalances(result, chain);
  }

  GatewayBalances _parseBalances(Object? result, Coin chain) {
    if (result is! Map) throw const FormatException('bad balances result');
    final native = result['native'];
    if (native is! Map) throw const FormatException('missing native balance');
    final (expectedDecimals, expectedSymbol) = switch (chain) {
      Coin.eth => (18, 'ETH'),
      Coin.polygon => (18, 'POL'),
      Coin.base => (18, 'ETH'),
      Coin.arbitrum => (18, 'ETH'),
      Coin.avalanche => (18, 'AVAX'),
      Coin.bnb => (18, 'BNB'),
      Coin.tron => (6, 'TRX'),
      Coin.solana => (9, 'SOL'),
    };
    // Native denomination is a chain protocol constant, not display metadata
    // the gateway is allowed to redefine. Accepting a mismatched scale can
    // turn 1 ETH (1e18 wei) into an apparent 1e18 ETH balance before the later
    // preflight rejects it. Treat the complete chain response as malformed so
    // callers can use their direct-node fallback instead.
    if (native['decimals'] != expectedDecimals ||
        native['symbol'] != expectedSymbol) {
      throw FormatException('native metadata mismatch for ${chain.name}');
    }
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

  /// `kt_getPortfolio` — all active chain balances in one mobile HTTP request.
  ///
  /// Unsupported/custom networks are omitted before the request and returned
  /// in [GatewayPortfolio.failedChains], so callers can fall back directly for
  /// only those chains. Gateway-side failures are isolated the same way.
  Future<GatewayPortfolio> getPortfolio(
    List<GatewayPortfolioQuery> queries,
  ) async {
    final accounts = <Map<String, Object?>>[];
    final failed = <Coin>{};
    for (final query in queries) {
      try {
        final network = await _networkParam(query.chain);
        accounts.add({
          'chain': chainName(query.chain),
          'network': ?network,
          'address': query.address,
          if (query.tokens.isNotEmpty)
            'tokens': [
              for (final token in query.tokens)
                {
                  'contract': token.contract,
                  'decimals': token.decimals,
                  'symbol': token.symbol,
                },
            ],
        });
      } catch (_) {
        failed.add(query.chain);
      }
    }
    if (accounts.isEmpty) {
      return GatewayPortfolio(balances: const {}, failedChains: failed);
    }
    final result = await _call('kt_getPortfolio', {'accounts': accounts});
    if (result is! Map || result['accounts'] is! List) {
      throw const FormatException('bad portfolio result');
    }
    final balances = <Coin, GatewayBalances>{};
    for (final row in result['accounts'] as List) {
      if (row is! Map || row['chain'] is! String) continue;
      final name = row['chain'] as String;
      final chain = Coin.values.where((coin) => coin.name == name).firstOrNull;
      if (chain == null) continue;
      if (row['error'] != null || row['result'] == null) {
        failed.add(chain);
        continue;
      }
      try {
        balances[chain] = _parseBalances(row['result'], chain);
      } catch (_) {
        failed.add(chain);
      }
    }
    for (final query in queries) {
      if (!balances.containsKey(query.chain)) failed.add(query.chain);
    }
    return GatewayPortfolio(
      balances: Map.unmodifiable(balances),
      failedChains: Set.unmodifiable(failed),
    );
  }

  /// `kt_getPrices` — USD spot quotes and optional 24h percentage changes
  /// keyed by symbol (unknown symbols are omitted by the gateway; an empty
  /// map is a valid, useless answer).
  Future<GatewayPrices> getPrices(List<String> symbols) async {
    final result = await _call('kt_getPrices', {'symbols': symbols});
    if (result is! Map) throw const FormatException('bad prices result');
    final prices = result['prices'];
    if (prices is! Map) throw const FormatException('missing prices map');
    final out = <String, double>{};
    final changes = <String, double>{};
    for (final entry in prices.entries) {
      final row = entry.value;
      final usd = row is Map ? positiveFiniteMarketNumber(row['usd']) : null;
      if (entry.key is String && usd != null) {
        final symbol = entry.key as String;
        out[symbol] = usd;
        final change24h = row is Map ? row['change24h'] : null;
        final parsedChange = finiteMarketNumber(change24h);
        if (parsedChange != null) changes[symbol] = parsedChange;
      }
    }
    final rawRates = result['fiatPerUsd'];
    final rates = <String, double>{'USD': 1};
    if (rawRates is Map) {
      for (final entry in rawRates.entries) {
        final currency = entry.key;
        final rate = entry.value;
        final parsedRate = positiveFiniteMarketNumber(rate);
        if (currency is String && parsedRate != null) {
          rates[currency.toUpperCase()] = parsedRate;
        }
      }
    }
    return GatewayPrices(
      usdBySymbol: Map.unmodifiable(out),
      change24hBySymbol: Map.unmodifiable(changes),
      fiatPerUsd: Map.unmodifiable(rates),
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

  /// Exact `eth_call` through the gateway. New transfers use `pending` while
  /// same-nonce replacements use `latest`, because the replacement is an
  /// alternative to (not a successor of) the pending candidate.
  Future<String> simulateEvmTransfer({
    required Coin chain,
    required String from,
    required String to,
    required BigInt value,
    required String data,
    String blockTag = 'pending',
  }) async {
    if (blockTag != 'latest' && blockTag != 'pending') {
      throw ArgumentError.value(blockTag, 'blockTag');
    }
    final result = await _evmCall(
      'kt_simulateEvmTransfer',
      chain: chain,
      from: from,
      to: to,
      value: value,
      data: data,
      blockTag: blockTag,
    );
    final returnData = result['returnData'];
    if (returnData is! String || !_isHexBytes(returnData)) {
      throw const FormatException('bad EVM simulation result');
    }
    return returnData.toLowerCase();
  }

  /// Exact pending-state `eth_estimateGas` through the gateway.
  Future<BigInt> estimateEvmGas({
    required Coin chain,
    required String from,
    required String to,
    required BigInt value,
    required String data,
  }) async {
    final result = await _evmCall(
      'kt_estimateEvmGas',
      chain: chain,
      from: from,
      to: to,
      value: value,
      data: data,
    );
    final gas = BigInt.tryParse(_string(result['gas']));
    if (gas == null || gas <= BigInt.zero) {
      throw const FormatException('bad EVM gas estimate');
    }
    return gas;
  }

  /// Uncached native and optional ERC-20 balance at the pending state. These
  /// values authorize a transfer and must not reuse the portfolio cache.
  Future<GatewayEvmSpendableBalances> getEvmSpendableBalances({
    required Coin chain,
    required String address,
    String? tokenContract,
  }) async {
    final network = await _networkParam(chain);
    final result = await _call('kt_getEvmSpendableBalances', {
      'chain': chainName(chain),
      'network': ?network,
      'address': address,
      'tokenContract': ?tokenContract,
    });
    if (result is! Map) {
      throw const FormatException('bad EVM spendable balances result');
    }
    final native = BigInt.tryParse(
      _string(result['nativePending'] ?? result['native']),
    );
    final nativeLatest = BigInt.tryParse(
      _string(result['nativeLatest'] ?? result['native']),
    );
    final token = tokenContract == null
        ? null
        : BigInt.tryParse(_string(result['token']));
    final pendingAvailable = result['pendingAvailable'];
    if (native == null ||
        nativeLatest == null ||
        native < BigInt.zero ||
        nativeLatest < BigInt.zero ||
        (pendingAvailable != null && pendingAvailable is! bool) ||
        (tokenContract != null && (token == null || token < BigInt.zero))) {
      throw const FormatException('bad EVM spendable balances result');
    }
    return GatewayEvmSpendableBalances(
      native: native,
      nativeLatest: nativeLatest,
      token: token,
      pendingAvailable: pendingAvailable as bool? ?? true,
    );
  }

  Future<Map<Object?, Object?>> _evmCall(
    String method, {
    required Coin chain,
    required String from,
    required String to,
    required BigInt value,
    required String data,
    String? blockTag,
  }) async {
    final network = await _networkParam(chain);
    final result = await _call(method, {
      'chain': chainName(chain),
      'network': ?network,
      'from': from,
      'to': to,
      'value': value.toString(),
      'data': data,
      'blockTag': ?blockTag,
    });
    if (result is! Map) throw FormatException('bad $method result');
    return Map<Object?, Object?>.from(result);
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
      final recordStatus = switch (row['status']) {
        'ok' || 'confirmed' => GatewayTransactionStatus.confirmed,
        'failed' => GatewayTransactionStatus.failed,
        'pending' => GatewayTransactionStatus.pending,
        _ => GatewayTransactionStatus.unknown,
      };
      records.add(
        GatewayHistoryRecord(
          id: row['id'] is String ? row['id'] as String : hash,
          hash: hash,
          outgoing: direction == 'out',
          fromAddress: row['from'] is String ? row['from'] as String : null,
          toAddress: row['to'] is String ? row['to'] as String : null,
          amountRaw: row['amountRaw'] is String
              ? BigInt.tryParse(row['amountRaw'] as String)
              : null,
          decimals: row['decimals'] is int ? row['decimals'] as int : null,
          symbol: row['symbol'] is String ? row['symbol'] as String : null,
          contract: row['contract'] is String
              ? row['contract'] as String
              : null,
          verified: row['verified'] == true,
          timestampMs: ts,
          status: recordStatus,
        ),
      );
    }
    return GatewayHistory.ok(List.unmodifiable(records));
  }

  /// `kt_getTransactionStatus` — direct chain confirmation by transaction
  /// hash/signature. Unlike account history this does not wait for an
  /// explorer/indexer to ingest the block.
  Future<GatewayTransactionStatus> getTransactionStatus({
    required Coin chain,
    required String hash,
    String? network,
  }) async {
    final resolvedNetwork = await _networkParam(
      chain,
      networkOverride: network,
    );
    final result = await _call('kt_getTransactionStatus', {
      'chain': chainName(chain),
      'network': ?resolvedNetwork,
      'hash': hash,
    });
    if (result is! Map || result['status'] is! String) {
      throw const FormatException('bad transaction status result');
    }
    return switch (result['status']) {
      'confirmed' => GatewayTransactionStatus.confirmed,
      'failed' => GatewayTransactionStatus.failed,
      'pending' => GatewayTransactionStatus.pending,
      'unknown' => GatewayTransactionStatus.unknown,
      _ => throw const FormatException('unknown transaction status'),
    };
  }

  /// `kt_searchTokens` — searches the operator-configured verified token
  /// catalog by name, symbol, or contract/mint. An empty query returns the
  /// popular catalog first. Only rows carrying `verified: true` are accepted;
  /// malformed/unverified rows are skipped rather than elevated in the UI.
  Future<List<GatewayOfficialToken>> searchOfficialTokens({
    String query = '',
    List<String> networks = const [],
    int limit = 50,
  }) async {
    final result = await _call('kt_searchTokens', {
      'query': query,
      if (networks.isNotEmpty) 'networks': networks,
      'limit': limit,
    });
    if (result is! Map) {
      throw const FormatException('bad token search result');
    }
    final rows = result['tokens'];
    if (rows is! List) {
      throw const FormatException('missing token search rows');
    }
    final tokens = <GatewayOfficialToken>[];
    for (final row in rows) {
      if (row is! Map || row['verified'] != true) continue;
      final network = row['network'];
      final symbol = row['symbol'];
      final name = row['name'];
      final contract = row['contract'];
      final decimals = row['decimals'];
      if (network is! String ||
          symbol is! String ||
          name is! String ||
          contract is! String ||
          decimals is! int ||
          decimals < 0 ||
          decimals > Amount.maxDecimals) {
        continue;
      }
      tokens.add(
        GatewayOfficialToken(
          network: network,
          symbol: symbol,
          name: name,
          contract: contract,
          decimals: decimals,
          popular: row['popular'] == true,
        ),
      );
    }
    return List.unmodifiable(tokens);
  }

  /// `kt_checkTokenRisk` — exact network + contract/mint assessment. A
  /// transport failure is intentionally NOT converted into `safe`; callers
  /// catch it and render a distinct unavailable/unknown state.
  Future<GatewayTokenRisk> checkTokenRisk({
    required Coin chain,
    required String contract,
  }) async {
    final network = await _networkParam(chain);
    final result = await _call('kt_checkTokenRisk', {
      'chain': chainName(chain),
      'network': ?network,
      'contract': contract,
    });
    if (result is! Map || result['status'] is! String) {
      throw const FormatException('bad token risk result');
    }
    final status = switch (result['status']) {
      'safe' => GatewayTokenRiskStatus.safe,
      'unsafe' => GatewayTokenRiskStatus.unsafe,
      'unknown' => GatewayTokenRiskStatus.unknown,
      _ => throw const FormatException('unknown token risk status'),
    };
    final category = result['category'];
    final source = result['source'];
    if (category != null && category is! String) {
      throw const FormatException('bad token risk category');
    }
    if (source is! String || source.isEmpty) {
      throw const FormatException('missing token risk source');
    }
    return GatewayTokenRisk(
      status: status,
      category: category as String?,
      source: source,
    );
  }

  /// `kt_getEvmTokenApprovals` — outstanding ERC-20 allowances for [address].
  /// This call sends the public wallet address and chain to the Gateway's
  /// configured external approval provider. Callers must obtain explicit
  /// user consent first; the method keeps that proof visible on the wire.
  Future<GatewayTokenApprovals> getEvmTokenApprovals({
    required Coin chain,
    required String address,
    required bool privacyConsent,
  }) async {
    if (!privacyConsent) {
      throw ArgumentError.value(
        privacyConsent,
        'privacyConsent',
        'must be true after explicit user consent',
      );
    }
    final network = await _networkParam(chain);
    final result = await _call('kt_getEvmTokenApprovals', {
      'chain': chainName(chain),
      'network': ?network,
      'address': address,
      'privacyConsent': true,
    });
    if (result is! Map ||
        result['status'] != 'ok' ||
        result['source'] is! String ||
        result['network'] is! String ||
        result['approvals'] is! List) {
      throw const FormatException('bad token approvals result');
    }
    final rows = <GatewayTokenApproval>[];
    for (final raw in result['approvals'] as List) {
      if (raw is! Map) {
        throw const FormatException('bad token approval row');
      }
      final tokenAddress = raw['tokenAddress'];
      final tokenName = raw['tokenName'];
      final tokenSymbol = raw['tokenSymbol'];
      final decimals = raw['decimals'];
      final balance = raw['balance'];
      final spender = raw['spender'];
      final spenderName = raw['spenderName'];
      final spenderTag = raw['spenderTag'];
      final spenderTrusted = raw['spenderTrusted'];
      final amount = raw['amount'];
      final unlimited = raw['unlimited'];
      final approvedAt = raw['approvedAt'];
      final transaction = raw['transaction'];
      final risk = raw['risk'];
      if (tokenAddress is! String ||
          tokenName is! String ||
          tokenSymbol is! String ||
          decimals is! int ||
          balance is! String ||
          spender is! String ||
          spenderName is! String ||
          spenderTag is! String ||
          spenderTrusted is! bool ||
          amount is! String ||
          unlimited is! bool ||
          approvedAt is! int ||
          transaction is! String ||
          (risk != 'unsafe' && risk != 'unknown')) {
        throw const FormatException('bad token approval row');
      }
      rows.add(
        GatewayTokenApproval(
          tokenAddress: tokenAddress,
          tokenName: tokenName,
          tokenSymbol: tokenSymbol,
          decimals: decimals,
          balance: balance,
          spender: spender,
          spenderName: spenderName,
          spenderTag: spenderTag,
          spenderTrusted: spenderTrusted,
          amount: amount,
          unlimited: unlimited,
          approvedAt: approvedAt,
          transaction: transaction,
          risk: risk == 'unsafe'
              ? GatewayTokenApprovalRisk.unsafe
              : GatewayTokenApprovalRisk.unknown,
        ),
      );
    }
    return GatewayTokenApprovals(
      network: result['network'] as String,
      source: result['source'] as String,
      approvals: List.unmodifiable(rows),
    );
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
/// (-32000 upstream_error, -32001 rate_limited, -32002 unsupported, -32003
/// submission_unknown, plus the standard protocol codes); for upstream errors
/// [upstreamMessage] carries the node's own reason.
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

  /// Applied by the gateway before an upstream node is contacted.
  bool get isRateLimited => code == -32001;

  /// The contract's "a node accepted the request and rejected it" code.
  bool get isUpstreamError => code == -32000;

  /// The broadcast was attempted but no authoritative node answer survived.
  bool get isSubmissionUnknown => code == -32003;

  @override
  String toString() =>
      'GatewayException($code, $message'
      '${upstreamMessage == null ? '' : ', upstream: $upstreamMessage'})';
}

/// A privacy-safe gateway transport failure. It never stores the request URL,
/// response body or the lower-level exception text.
final class GatewayTransportException implements Exception {
  const GatewayTransportException([
    this.message = 'gateway transport unavailable',
  ]);

  final String message;

  @override
  String toString() => 'GatewayTransportException: $message';
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

class GatewayPortfolioQuery {
  const GatewayPortfolioQuery({
    required this.chain,
    required this.address,
    this.tokens = const [],
  });

  final Coin chain;
  final String address;
  final List<GatewayTokenQuery> tokens;
}

class GatewayPortfolio {
  const GatewayPortfolio({required this.balances, required this.failedChains});

  final Map<Coin, GatewayBalances> balances;
  final Set<Coin> failedChains;
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
  const GatewayPrices({
    required this.usdBySymbol,
    required this.change24hBySymbol,
    required this.fiatPerUsd,
    required this.cachedAtMs,
  });

  final Map<String, double> usdBySymbol;
  final Map<String, double> change24hBySymbol;
  final Map<String, double> fiatPerUsd;
  final int cachedAtMs;
}

class GatewayChainParams {
  const GatewayChainParams({required this.nonce, required this.fees});

  final int nonce;
  final GasFeeEstimate fees;
}

class GatewayEvmSpendableBalances {
  const GatewayEvmSpendableBalances({
    required this.native,
    required this.nativeLatest,
    required this.token,
    this.pendingAvailable = true,
  });

  /// Pending-state balance after the provider applies known mempool entries.
  final BigInt native;

  /// Latest mined balance before pending entries are applied.
  final BigInt nativeLatest;
  final BigInt? token;
  final bool pendingAvailable;
}

bool _isHexBytes(String value) {
  if (!value.startsWith('0x') || value.length.isOdd) return false;
  for (final unit in value.codeUnits.skip(2)) {
    final isDigit = unit >= 48 && unit <= 57;
    final isLower = unit >= 97 && unit <= 102;
    final isUpper = unit >= 65 && unit <= 70;
    if (!isDigit && !isLower && !isUpper) return false;
  }
  return true;
}

class GatewayHistoryRecord {
  const GatewayHistoryRecord({
    required this.id,
    required this.hash,
    required this.outgoing,
    this.fromAddress,
    this.toAddress,
    required this.amountRaw,
    required this.decimals,
    required this.symbol,
    required this.contract,
    required this.verified,
    required this.timestampMs,
    required this.status,
  });

  final String id;
  final String hash;
  final bool outgoing;
  final String? fromAddress;
  final String? toAddress;
  final BigInt? amountRaw;
  final int? decimals;
  final String? symbol;
  final String? contract;
  final bool verified;
  final int timestampMs;
  final GatewayTransactionStatus status;
}

class GatewayHistory {
  const GatewayHistory.ok(this.records) : unsupported = false;
  const GatewayHistory.unsupported() : unsupported = true, records = const [];

  /// True when the gateway itself reports no history source for the chain.
  final bool unsupported;
  final List<GatewayHistoryRecord> records;
}

enum GatewayTransactionStatus { confirmed, failed, pending, unknown }

/// One operator-verified token identity. The blue check is tied to
/// [network] + [contract], never to [symbol] alone.
class GatewayOfficialToken {
  const GatewayOfficialToken({
    required this.network,
    required this.symbol,
    required this.name,
    required this.contract,
    required this.decimals,
    this.popular = false,
  });

  final String network;
  final String symbol;
  final String name;
  final String contract;
  final int decimals;
  final bool popular;

  String get identityKey =>
      '$network|${contract.startsWith('0x') ? contract.toLowerCase() : contract}';
}

enum GatewayTokenRiskStatus { safe, unsafe, unknown }

/// A successful risk-service response. Network/transport failures are not
/// represented by this type and must stay distinguishable at the UI layer.
class GatewayTokenRisk {
  const GatewayTokenRisk({
    required this.status,
    required this.source,
    this.category,
  });

  final GatewayTokenRiskStatus status;
  final String source;
  final String? category;
}

enum GatewayTokenApprovalRisk { unsafe, unknown }

class GatewayTokenApproval {
  const GatewayTokenApproval({
    required this.tokenAddress,
    required this.tokenName,
    required this.tokenSymbol,
    required this.decimals,
    required this.balance,
    required this.spender,
    required this.spenderName,
    required this.spenderTag,
    required this.spenderTrusted,
    required this.amount,
    required this.unlimited,
    required this.approvedAt,
    required this.transaction,
    required this.risk,
  });

  final String tokenAddress;
  final String tokenName;
  final String tokenSymbol;
  final int decimals;
  final String balance;
  final String spender;
  final String spenderName;
  final String spenderTag;
  final bool spenderTrusted;
  final String amount;
  final bool unlimited;
  final int approvedAt;
  final String transaction;
  final GatewayTokenApprovalRisk risk;
}

class GatewayTokenApprovals {
  const GatewayTokenApprovals({
    required this.network,
    required this.source,
    required this.approvals,
  });

  final String network;
  final String source;
  final List<GatewayTokenApproval> approvals;
}
