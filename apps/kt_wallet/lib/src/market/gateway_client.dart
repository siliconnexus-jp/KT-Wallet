import 'dart:convert';

import 'package:chains/chains.dart' show Addresses, Amount, Chain;
import 'package:chains/rpc.dart' show GasFeeEstimate, GasFeeEstimateTier;
import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:http/http.dart' as http;

import '../rpc/bounded_http_client.dart';
import '../rpc/json_rpc_envelope.dart';
import '../rpc/network_identity_value.dart';
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
/// - `kt_getNetworkIdentity` `{chain, network?}` → live chain id / genesis
///   identity, already checked against the Gateway's reviewed network registry
/// - `kt_simulateEvmTransfer` `{chain, network?, from, to, value, data}` →
///   exact pending-state `eth_call` return bytes
/// - `kt_estimateEvmGas` `{chain, network?, from, to, value, data}` →
///   decimal gas estimate
/// - `kt_getEvmSpendableBalances`
///   `{chain, network?, address, tokenContract?}` → uncached pending balances
/// - `kt_getHistory` `{chain, network?, address, limit?}` →
///   `{chain, network, address, status, records}` with exact owner binding
/// - `kt_getTransactionStatus` `{chain, network?, hash}` →
///   `{network, hash, status}` bound to the exact requested transaction
/// - `kt_searchTokens` `{query?, networks?, limit?}` → verified token catalog
/// - `kt_checkTokenRisk` `{chain, network?, contract}` →
///   `{status: safe|unsafe|unknown, category?, source, network, contract}`
/// - `kt_getEvmTokenApprovals`
///   `{chain, network?, address, privacyConsent:true}` → outstanding ERC-20
///   allowances; provider/unsupported failures never become an empty list
/// - `kt_broadcast` `{chain, network?, payload}` →
///   `{chain, network, txHash}` bound to the resolved signing domain
/// Errors: -32700/-32600/-32601/-32602 protocol, -32000 upstream_error,
/// -32001
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
           : _validatedAdvertisedNetworks(advertisedNetworks);

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

  /// The only remote network identifiers allowed to gain routing authority.
  /// A user-defined network always stays on its user-authoritative direct RPC,
  /// even if a remote Gateway claims to support an identically named id.
  static const Set<String> supportedNetworks = {
    'eth-mainnet',
    'eth-sepolia',
    'polygon-mainnet',
    'polygon-amoy',
    'base-mainnet',
    'base-sepolia',
    'arbitrum-mainnet',
    'arbitrum-sepolia',
    'avalanche-mainnet',
    'avalanche-fuji',
    'bnb-mainnet',
    'bnb-testnet',
    'tron-mainnet',
    'tron-nile',
    'sol-mainnet',
    'sol-devnet',
  };

  static const _healthResultKeys = <String>{
    'ok',
    'version',
    'networks',
    'upstreams',
  };
  static const _approvalResultKeys = <String>{
    'status',
    'source',
    'network',
    'approvals',
  };
  static const _balancesResultKeys = <String>{
    'chain',
    'network',
    'address',
    'native',
    'tokens',
  };
  static const _nativeBalanceKeys = <String>{'raw', 'decimals', 'symbol'};
  static const _tokenBalanceKeys = <String>{
    'contract',
    'raw',
    'decimals',
    'symbol',
  };
  static const _tokenBalanceErrorKeys = <String>{..._tokenBalanceKeys, 'error'};
  static const _portfolioResultKeys = <String>{'accounts'};
  static const _portfolioSuccessRowKeys = <String>{
    'chain',
    'network',
    'address',
    'result',
  };
  static const _portfolioErrorRowKeys = <String>{
    'chain',
    'network',
    'address',
    'error',
  };
  static const _chainParamsResultKeys = <String>{
    'network',
    'address',
    'nonce',
    'fees',
  };
  static const _feeResultKeys = <String>{'slow', 'standard', 'fast'};
  static const _feeTierResultKeys = <String>{
    'maxPriorityFeePerGas',
    'maxFeePerGas',
  };
  static const _evmSimulationResultKeys = <String>{
    'network',
    'from',
    'to',
    'value',
    'data',
    'blockTag',
    'returnData',
  };
  static const _evmGasResultKeys = <String>{
    'network',
    'from',
    'to',
    'value',
    'data',
    'gas',
  };
  static const _evmSpendableResultKeys = <String>{
    'network',
    'address',
    'native',
    'nativePending',
    'nativeLatest',
    'pendingAvailable',
  };
  static const _evmTokenSpendableResultKeys = <String>{
    ..._evmSpendableResultKeys,
    'tokenContract',
    'token',
  };
  static const _officialTokenResultKeys = <String>{'tokens'};
  static const _officialTokenRowKeys = <String>{
    'network',
    'symbol',
    'name',
    'contract',
    'decimals',
    'verified',
  };
  static const _officialTokenPopularRowKeys = <String>{
    ..._officialTokenRowKeys,
    'popular',
  };
  static const _tokenRiskResultKeys = <String>{
    'status',
    'source',
    'network',
    'contract',
  };
  static const _tokenRiskUnsafeResultKeys = <String>{
    ..._tokenRiskResultKeys,
    'category',
  };
  static const _historyResultKeys = <String>{
    'chain',
    'network',
    'address',
    'status',
    'records',
  };
  static const _historyRecordKeys = <String>{
    'id',
    'hash',
    'direction',
    'amountRaw',
    'decimals',
    'symbol',
    'verified',
    'timestampMs',
    'status',
  };
  static const _broadcastResultKeys = <String>{'chain', 'network', 'txHash'};
  static const _pricesResultKeys = <String>{
    'prices',
    'fiatPerUsd',
    'cachedAtMs',
  };
  static const _priceRowKeys = <String>{'usd'};
  static const _priceChangeRowKeys = <String>{'usd', 'change24h'};
  static const _fiatRateKeys = <String>{'USD', 'CNY', 'JPY'};
  static const _tokenRiskCategories = <String>{
    'malicious',
    'phishing',
    'spam',
    'impersonation',
    'honeypot',
    'suspicious',
  };
  static const _approvalRowKeys = <String>{
    'tokenAddress',
    'tokenName',
    'tokenSymbol',
    'decimals',
    'balance',
    'spender',
    'spenderName',
    'spenderTag',
    'spenderTrusted',
    'amount',
    'unlimited',
    'approvedAt',
    'transaction',
    'risk',
  };
  static final _evmAddressPattern = RegExp(r'^0x[0-9a-fA-F]{40}$');
  static final _evmTxHashPattern = RegExp(r'^0x[0-9a-fA-F]{64}$');
  static final _tronTxHashPattern = RegExp(r'^[0-9a-fA-F]{64}$');
  static final _base58AddressPattern = RegExp(r'^[1-9A-HJ-NP-Za-km-z]+$');
  static final _officialTokenSymbolPattern = RegExp(r'^[A-Z0-9._-]{1,12}$');
  static final _semanticVersionPattern = RegExp(
    r'^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$',
  );
  static final _providerDecimalPattern = RegExp(
    r'^[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$',
  );
  static final _canonicalUintPattern = RegExp(r'^(?:0|[1-9][0-9]*)$');
  static final _maxUint256 = (BigInt.one << 256) - BigInt.one;
  static final _maxDartInt = (BigInt.one << 63) - BigInt.one;

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
      decoded = decodeJsonWithoutDuplicateKeys(resp.body);
    } on Object {
      // FormatException.toString() may include a snippet of the response.
      throw const GatewayTransportException('invalid gateway response');
    }
    if (!isBoundJsonRpcResponse(request, decoded) || decoded is! Map) {
      throw const GatewayTransportException('invalid gateway response');
    }
    final error = decoded['error'];
    if (error is Map) {
      throw GatewayException(code: error['code'] as int);
    }
    return decoded['result'];
  }

  /// `kt_health` — true only for the closed, versioned health schema and a
  /// validated subset of [supportedNetworks]. Never throws (any failure is
  /// "not healthy"): this backs the settings screen's test-connection action.
  /// Always hits the wire and refreshes the advertised-network set.
  Future<bool> health() async {
    try {
      final result = await _call('kt_health');
      if (result is! Map || result['ok'] != true) return false;
      _advertised = _parseHealthyResult(result);
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
    return _advertised = _parseHealthyResult(result);
  }

  static Set<String> _parseHealthyResult(Map<Object?, Object?> health) {
    final version = health['version'];
    final upstreams = health['upstreams'];
    if (!_hasExactStringKeys(health, _healthResultKeys) ||
        health['ok'] != true ||
        version is! String ||
        version.length > 64 ||
        !_semanticVersionPattern.hasMatch(version) ||
        upstreams is! Map) {
      throw const FormatException('bad gateway health result');
    }
    final networks = _validatedAdvertisedNetworks(health['networks']);
    for (final entry in upstreams.entries) {
      if (entry.key is! String ||
          !networks.contains(entry.key) ||
          entry.value is! Map) {
        throw const FormatException('bad gateway upstream summary');
      }
    }
    return networks;
  }

  static Set<String> _validatedAdvertisedNetworks(Object? rows) {
    final values = rows is Set<String>
        ? rows.toList(growable: false)
        : rows is List
        ? rows
        : null;
    if (values == null ||
        values.isEmpty ||
        values.length > supportedNetworks.length) {
      throw const FormatException('bad gateway network list');
    }
    final out = <String>{};
    for (final row in values) {
      if (row is! String || !supportedNetworks.contains(row) || !out.add(row)) {
        throw const FormatException('untrusted gateway network');
      }
    }
    return Set.unmodifiable(out);
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
    final expectedNetwork = network ?? _mainnetNetworkId(chain);
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
    return _parseBalances(
      result,
      chain: chain,
      network: expectedNetwork,
      address: address,
      tokens: tokens,
    );
  }

  GatewayBalances _parseBalances(
    Object? result, {
    required Coin chain,
    required String network,
    required String address,
    required List<GatewayTokenQuery> tokens,
  }) {
    if (result is! Map ||
        !_hasExactStringKeys(result, _balancesResultKeys) ||
        result['chain'] != chainName(chain) ||
        result['network'] != network ||
        !_sameAccountAddress(chain, result['address'], address)) {
      throw const FormatException('unbound balances result');
    }
    final native = result['native'];
    if (native is! Map || !_hasExactStringKeys(native, _nativeBalanceKeys)) {
      throw const FormatException('missing native balance');
    }
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
    if (rows is! List || rows.length != tokens.length) {
      throw const FormatException('unbound token balance rows');
    }
    final parsedTokens = <GatewayTokenBalance>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final query = tokens[i];
      if (row is! Map) {
        throw const FormatException('bad token balance row');
      }
      final hasError = row.containsKey('error');
      final expectedKeys = hasError
          ? _tokenBalanceErrorKeys
          : _tokenBalanceKeys;
      final error = hasError ? row['error'] : null;
      if (!_hasExactStringKeys(row, expectedKeys) ||
          row['contract'] is! String ||
          !_tokenIdentityMatches(
            chain,
            query.contract,
            row['contract'] as String,
          ) ||
          row['decimals'] != query.decimals ||
          row['symbol'] != query.symbol ||
          (hasError &&
              (error is! String ||
                  error.isEmpty ||
                  !_isBoundedDisplayText(error, 160)))) {
        throw const FormatException('unbound token balance row');
      }
      final raw = _canonicalUint(row['raw']);
      parsedTokens.add(
        GatewayTokenBalance(
          contract: row['contract'] as String,
          // The remote reason is useful only as an availability signal. Do
          // not retain it: a compromised provider could put wallet addresses,
          // credential URLs, or arbitrary text in this field and have it
          // escape later through logging or diagnostics.
          error: hasError ? GatewayTokenBalance.unavailableError : null,
          raw: hasError ? null : raw,
          decimals: query.decimals,
          symbol: query.symbol,
        ),
      );
    }
    return GatewayBalances(
      native: GatewayNativeBalance(
        raw: _canonicalUint(native['raw']),
        decimals: expectedDecimals,
        symbol: expectedSymbol,
      ),
      tokens: List.unmodifiable(parsedTokens),
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
    if (queries.map((query) => query.chain).toSet().length != queries.length) {
      throw const FormatException('duplicate portfolio chain');
    }
    final accounts = <Map<String, Object?>>[];
    final expectedAccounts =
        <({GatewayPortfolioQuery query, String network})>[];
    final failed = <Coin>{};
    for (final query in queries) {
      try {
        final network = await _networkParam(query.chain);
        final expectedNetwork = network ?? _mainnetNetworkId(query.chain);
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
        expectedAccounts.add((query: query, network: expectedNetwork));
      } catch (_) {
        failed.add(query.chain);
      }
    }
    if (accounts.isEmpty) {
      return GatewayPortfolio(balances: const {}, failedChains: failed);
    }
    final result = await _call('kt_getPortfolio', {'accounts': accounts});
    if (result is! Map ||
        !_hasExactStringKeys(result, _portfolioResultKeys) ||
        result['accounts'] is! List ||
        (result['accounts'] as List).length != expectedAccounts.length) {
      throw const FormatException('bad portfolio result');
    }
    final balances = <Coin, GatewayBalances>{};
    final rows = result['accounts'] as List;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final expected = expectedAccounts[i];
      final query = expected.query;
      if (row is! Map ||
          row['chain'] != chainName(query.chain) ||
          row['network'] != expected.network ||
          !_sameAccountAddress(query.chain, row['address'], query.address)) {
        throw const FormatException('unbound portfolio row');
      }
      if (row.containsKey('error')) {
        final error = row['error'];
        if (!_hasExactStringKeys(row, _portfolioErrorRowKeys) ||
            error is! String ||
            error.isEmpty ||
            !_isBoundedDisplayText(error, 160)) {
          throw const FormatException('bad portfolio error row');
        }
        failed.add(query.chain);
        continue;
      }
      if (!_hasExactStringKeys(row, _portfolioSuccessRowKeys)) {
        throw const FormatException('bad portfolio success row');
      }
      try {
        balances[query.chain] = _parseBalances(
          row['result'],
          chain: query.chain,
          network: expected.network,
          address: query.address,
          tokens: query.tokens,
        );
      } catch (_) {
        failed.add(query.chain);
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
  /// keyed by symbol (unknown symbols are omitted by the gateway; a fresh,
  /// schema-valid empty map is a valid but useless answer).
  Future<GatewayPrices> getPrices(List<String> symbols) async {
    final requested = <String>{};
    final normalizedSymbols = <String>[];
    for (final symbol in symbols) {
      final normalized = symbol.trim().toUpperCase();
      if (!_officialTokenSymbolPattern.hasMatch(normalized)) {
        throw ArgumentError.value(symbol, 'symbols', 'invalid market symbol');
      }
      if (!requested.add(normalized)) {
        throw ArgumentError.value(
          symbols,
          'symbols',
          'duplicate market symbol',
        );
      }
      normalizedSymbols.add(normalized);
    }
    if (requested.isEmpty) {
      throw ArgumentError.value(symbols, 'symbols', 'must not be empty');
    }
    final result = await _call('kt_getPrices', {'symbols': normalizedSymbols});
    if (result is! Map || !_hasExactStringKeys(result, _pricesResultKeys)) {
      throw const FormatException('bad prices result');
    }
    final prices = result['prices'];
    if (prices is! Map) throw const FormatException('missing prices map');
    final out = <String, double>{};
    final changes = <String, double>{};
    for (final entry in prices.entries) {
      final symbol = entry.key;
      final row = entry.value;
      final expectedRowKeys = row is Map && row.containsKey('change24h')
          ? _priceChangeRowKeys
          : _priceRowKeys;
      if (symbol is! String ||
          !requested.contains(symbol) ||
          !_officialTokenSymbolPattern.hasMatch(symbol) ||
          row is! Map ||
          !_hasExactStringKeys(row, expectedRowKeys)) {
        throw const FormatException('unbound price row');
      }
      final usd = positiveFiniteMarketNumber(row['usd']);
      if (usd == null) throw const FormatException('invalid USD price');
      out[symbol] = usd;
      if (row.containsKey('change24h')) {
        final parsedChange = _marketChange(row['change24h']);
        if (parsedChange == null) {
          throw const FormatException('invalid 24 hour change');
        }
        changes[symbol] = parsedChange;
      }
    }
    final rawRates = result['fiatPerUsd'];
    if (rawRates is! Map ||
        rawRates.isEmpty ||
        rawRates.keys.any(
          (key) => key is! String || !_fiatRateKeys.contains(key),
        ) ||
        rawRates['USD'] != 1 ||
        (prices.isNotEmpty && !_hasExactStringKeys(rawRates, _fiatRateKeys))) {
      throw const FormatException('invalid fiat rates');
    }
    final rates = <String, double>{};
    for (final entry in rawRates.entries) {
      final currency = entry.key as String;
      final parsedRate = positiveFiniteMarketNumber(entry.value);
      final inRange = switch (currency) {
        'USD' => parsedRate == 1,
        'CNY' => parsedRate != null && parsedRate >= 0.1 && parsedRate <= 100,
        'JPY' => parsedRate != null && parsedRate >= 1 && parsedRate <= 10000,
        _ => false,
      };
      if (!inRange || parsedRate == null) {
        throw const FormatException('invalid fiat rate');
      }
      rates[currency] = parsedRate;
    }
    final cachedAtMs = result['cachedAtMs'];
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (cachedAtMs is! int ||
        cachedAtMs <= 0 ||
        cachedAtMs < nowMs - const Duration(minutes: 15).inMilliseconds ||
        cachedAtMs > nowMs + const Duration(minutes: 5).inMilliseconds) {
      throw const FormatException('stale market result');
    }
    return GatewayPrices(
      usdBySymbol: Map.unmodifiable(out),
      change24hBySymbol: Map.unmodifiable(changes),
      fiatPerUsd: Map.unmodifiable(rates),
      cachedAtMs: cachedAtMs,
    );
  }

  static double? _marketChange(Object? value) {
    final parsed = finiteMarketNumber(value);
    return parsed != null && parsed >= -100 && parsed <= 1000000000
        ? parsed
        : null;
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
    final expectedNetwork = network ?? _mainnetNetworkId(chain);
    if (result is! Map ||
        !_hasExactStringKeys(result, _chainParamsResultKeys) ||
        result['network'] != expectedNetwork ||
        !_sameEvmAddress(result['address'], address)) {
      throw const FormatException('bad chain params result');
    }
    final fees = result['fees'];
    if (fees is! Map || !_hasExactStringKeys(fees, _feeResultKeys)) {
      throw const FormatException('missing fees');
    }
    GasFeeEstimateTier tier(String name) {
      final t = fees[name];
      if (t is! Map || !_hasExactStringKeys(t, _feeTierResultKeys)) {
        throw FormatException('missing $name fee tier');
      }
      final priority = _canonicalUint(t['maxPriorityFeePerGas']);
      final maxFee = _canonicalUint(t['maxFeePerGas']);
      if (maxFee <= BigInt.zero || priority > maxFee) {
        throw FormatException('invalid $name fee tier');
      }
      return GasFeeEstimateTier(
        maxPriorityFeePerGas: priority,
        maxFeePerGas: maxFee,
      );
    }

    final nonceValue = _canonicalUint(result['nonce'], max: _maxDartInt);
    final slow = tier('slow');
    final standard = tier('standard');
    final fast = tier('fast');
    if (slow.maxPriorityFeePerGas > standard.maxPriorityFeePerGas ||
        standard.maxPriorityFeePerGas > fast.maxPriorityFeePerGas ||
        slow.maxFeePerGas > standard.maxFeePerGas ||
        standard.maxFeePerGas > fast.maxFeePerGas) {
      throw const FormatException('non-monotonic fee tiers');
    }
    return GatewayChainParams(
      nonce: nonceValue.toInt(),
      fees: GasFeeEstimate(slow: slow, standard: standard, fast: fast),
    );
  }

  /// `kt_getNetworkIdentity` — asks the selected Gateway upstream for its live
  /// signing-domain identity. The Gateway also binds the answer to its
  /// reviewed network registry; the App independently compares it with the
  /// active [Network] before any native key access.
  Future<String> getNetworkIdentity({required Coin chain}) async {
    final network = await _networkParam(chain);
    final expectedNetwork = network ?? _mainnetNetworkId(chain);
    final result = await _call('kt_getNetworkIdentity', {
      'chain': chainName(chain),
      'network': ?network,
    });
    if (result is! Map ||
        !_hasExactStringKeys(result, const {'network', 'identity'}) ||
        result['network'] != expectedNetwork ||
        result['identity'] is! String) {
      throw const FormatException('bad network identity result');
    }
    final identity = result['identity'] as String;
    final valid = switch (chain) {
      Coin.eth ||
      Coin.polygon ||
      Coin.base ||
      Coin.arbitrum ||
      Coin.avalanche ||
      Coin.bnb => parseCanonicalEvmDecimalChainId(identity) != null,
      Coin.tron => parseCanonicalTronGenesisBlockId(identity) != null,
      Coin.solana => parseCanonicalSolanaGenesisHash(identity) != null,
    };
    if (!valid) throw const FormatException('invalid network identity');
    return identity;
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
    final gas = _canonicalUint(result['gas']);
    if (gas <= BigInt.zero) {
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
    final expectedNetwork = network ?? _mainnetNetworkId(chain);
    final expectedKeys = tokenContract == null
        ? _evmSpendableResultKeys
        : _evmTokenSpendableResultKeys;
    if (result is! Map ||
        !_hasExactStringKeys(result, expectedKeys) ||
        result['network'] != expectedNetwork ||
        !_sameEvmAddress(result['address'], address) ||
        (tokenContract != null &&
            !_sameEvmAddress(result['tokenContract'], tokenContract))) {
      throw const FormatException('bad EVM spendable balances result');
    }
    final nativeAlias = _canonicalUint(result['native']);
    final native = _canonicalUint(result['nativePending']);
    final nativeLatest = _canonicalUint(result['nativeLatest']);
    final token = tokenContract == null
        ? null
        : _canonicalUint(result['token']);
    final pendingAvailable = result['pendingAvailable'];
    if (nativeAlias != native || pendingAvailable is! bool) {
      throw const FormatException('bad EVM spendable balances result');
    }
    return GatewayEvmSpendableBalances(
      native: native,
      nativeLatest: nativeLatest,
      token: token,
      pendingAvailable: pendingAvailable,
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
    final expectedNetwork = network ?? _mainnetNetworkId(chain);
    final result = await _call(method, {
      'chain': chainName(chain),
      'network': ?network,
      'from': from,
      'to': to,
      'value': value.toString(),
      'data': data,
      'blockTag': ?blockTag,
    });
    final expectedKeys = method == 'kt_simulateEvmTransfer'
        ? _evmSimulationResultKeys
        : _evmGasResultKeys;
    final normalizedValue = '0x${value.toRadixString(16)}';
    if (result is! Map ||
        !_hasExactStringKeys(result, expectedKeys) ||
        result['network'] != expectedNetwork ||
        !_sameEvmAddress(result['from'], from) ||
        !_sameEvmAddress(result['to'], to) ||
        result['value'] != normalizedValue ||
        result['data'] != data.toLowerCase() ||
        (method == 'kt_simulateEvmTransfer' &&
            result['blockTag'] != (blockTag ?? 'pending'))) {
      throw FormatException('bad $method result');
    }
    return Map<Object?, Object?>.from(result);
  }

  /// `kt_getHistory` — recent transactions of the active network of [chain],
  /// or `unsupported` when the gateway has no indexer for it.
  ///
  /// History is a security boundary: a response is accepted only when its
  /// chain/network/owner identity and every row are exact. A malformed row is
  /// fatal for the whole page so the service can fall back without presenting
  /// a partial or cross-account history as authoritative.
  Future<GatewayHistory> getHistory({
    required Coin chain,
    required String address,
    int? limit,
  }) async {
    final network = await _networkParam(chain);
    final expectedNetwork = network ?? _mainnetNetworkId(chain);
    final result = await _call('kt_getHistory', {
      'chain': chainName(chain),
      'network': ?network,
      'address': address,
      'limit': ?limit,
    });
    if (result is! Map ||
        !_hasExactStringKeys(result, _historyResultKeys) ||
        result['chain'] != chainName(chain) ||
        result['network'] != expectedNetwork ||
        !_sameAccountAddress(chain, result['address'], address)) {
      throw const FormatException('unbound history result');
    }
    final status = result['status'];
    final rows = result['records'];
    if (rows is! List) throw const FormatException('missing records list');
    if (status == 'unsupported') {
      if (rows.isNotEmpty) {
        throw const FormatException('unsupported history has records');
      }
      return const GatewayHistory.unsupported();
    }
    if (status != 'ok') throw const FormatException('unknown history status');
    final maximumRows = (limit ?? 20).clamp(1, 100);
    if (rows.length > maximumRows) {
      throw const FormatException('history page exceeds requested limit');
    }
    final records = <GatewayHistoryRecord>[];
    final ids = <String>{};
    for (final row in rows) {
      if (row is! Map) throw const FormatException('bad history row');
      final expectedKeys = <String>{
        ..._historyRecordKeys,
        if (row.containsKey('from')) 'from',
        if (row.containsKey('to')) 'to',
        if (row.containsKey('contract')) 'contract',
      };
      if (!_hasExactStringKeys(row, expectedKeys)) {
        throw const FormatException('unknown history row field');
      }
      final id = row['id'];
      final hash = row['hash'];
      final direction = row['direction'];
      final from = row['from'];
      final to = row['to'];
      final decimals = row['decimals'];
      final symbol = row['symbol'];
      final contract = row['contract'];
      final verified = row['verified'];
      final ts = row['timestampMs'];
      if (id is! String ||
          id.isEmpty ||
          !_isBoundedDisplayText(id, 256) ||
          !ids.add(id) ||
          hash is! String ||
          !_isCanonicalTransactionHash(chain, hash) ||
          (direction != 'in' && direction != 'out') ||
          (from != null && !_isCanonicalChainAddress(chain, from)) ||
          (to != null && !_isCanonicalChainAddress(chain, to)) ||
          (direction == 'out' && !_sameAccountAddress(chain, from, address)) ||
          (direction == 'in' && !_sameAccountAddress(chain, to, address)) ||
          decimals is! int ||
          decimals < 0 ||
          decimals > 36 ||
          symbol is! String ||
          !_officialTokenSymbolPattern.hasMatch(symbol) ||
          verified is! bool ||
          ts is! int ||
          ts < 0 ||
          ts > 253402300799999 ||
          !_isValidHistoryContract(chain, contract)) {
        throw const FormatException('invalid history row semantics');
      }
      final amount = _canonicalUint(row['amountRaw']);
      if (chain == Coin.tron &&
          contract is String &&
          _canonicalUintPattern.hasMatch(contract) &&
          (symbol != 'TRC10' || decimals != 0 || verified)) {
        throw const FormatException('invalid TRC-10 history row');
      }
      final recordStatus = switch (row['status']) {
        'ok' => GatewayTransactionStatus.confirmed,
        'failed' => GatewayTransactionStatus.failed,
        'pending' => GatewayTransactionStatus.pending,
        'unknown' => GatewayTransactionStatus.unknown,
        _ => throw const FormatException('unknown transaction status'),
      };
      records.add(
        GatewayHistoryRecord(
          id: id,
          hash: hash,
          outgoing: direction == 'out',
          fromAddress: from as String?,
          toAddress: to as String?,
          amountRaw: amount,
          decimals: decimals,
          symbol: symbol,
          contract: contract as String?,
          verified: verified,
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
    final expectedNetwork = resolvedNetwork ?? _mainnetNetworkId(chain);
    if (result is! Map ||
        !_hasExactStringKeys(result, const {'network', 'hash', 'status'}) ||
        result['network'] != expectedNetwork ||
        !_sameTransactionHash(chain, result['hash'], hash) ||
        result['status'] is! String) {
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
    if (limit < 1 || limit > 100) {
      throw RangeError.range(limit, 1, 100, 'limit');
    }
    final requestedNetworks = networks.toSet();
    if (requestedNetworks.length != networks.length) {
      throw const FormatException('duplicate token search network');
    }
    final result = await _call('kt_searchTokens', {
      'query': query,
      if (networks.isNotEmpty) 'networks': networks,
      'limit': limit,
    });
    if (result is! Map ||
        !_hasExactStringKeys(result, _officialTokenResultKeys)) {
      throw const FormatException('bad token search result');
    }
    final rows = result['tokens'];
    if (rows is! List || rows.length > limit) {
      throw const FormatException('missing token search rows');
    }
    final tokens = <GatewayOfficialToken>[];
    final identities = <String>{};
    for (final row in rows) {
      if (row is! Map) {
        throw const FormatException('bad official token row');
      }
      final expectedKeys = row.containsKey('popular')
          ? _officialTokenPopularRowKeys
          : _officialTokenRowKeys;
      final network = row['network'];
      final symbol = row['symbol'];
      final name = row['name'];
      final contract = row['contract'];
      final decimals = row['decimals'];
      final popular = row['popular'];
      final chain = network is String
          ? _officialTokenNetworkCoin(network)
          : null;
      if (!_hasExactStringKeys(row, expectedKeys) ||
          row['verified'] != true ||
          (row.containsKey('popular') && popular is! bool) ||
          network is! String ||
          chain == null ||
          (requestedNetworks.isNotEmpty &&
              !requestedNetworks.contains(network)) ||
          symbol is! String ||
          !_officialTokenSymbolPattern.hasMatch(symbol) ||
          name is! String ||
          !_isBoundedDisplayText(name, 80) ||
          name.isEmpty ||
          contract is! String ||
          !_tokenIdentityMatches(chain, contract, contract) ||
          decimals is! int ||
          decimals < 0 ||
          decimals > Amount.maxDecimals ||
          !_officialTokenMatchesQuery(
            chain: chain,
            query: query,
            symbol: symbol,
            name: name,
            contract: contract,
          )) {
        throw const FormatException('unbound official token row');
      }
      final token = GatewayOfficialToken(
        network: network,
        symbol: symbol,
        name: name,
        contract: contract,
        decimals: decimals,
        popular: popular == true,
      );
      if (!identities.add(token.identityKey)) {
        throw const FormatException('duplicate official token identity');
      }
      tokens.add(token);
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
    final expectedNetwork = network ?? _mainnetNetworkId(chain);
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
    final source = result['source'];
    final responseNetwork = result['network'];
    final responseContract = result['contract'];
    final hasCategory = result.containsKey('category');
    final expectedKeys = status == GatewayTokenRiskStatus.unsafe
        ? _tokenRiskUnsafeResultKeys
        : _tokenRiskResultKeys;
    final category = hasCategory ? result['category'] : null;
    final sourceMatchesStatus = switch (status) {
      GatewayTokenRiskStatus.safe =>
        source == 'official_catalog' || source == 'official_catalog+goplus',
      GatewayTokenRiskStatus.unsafe =>
        source == 'operator_registry' || source == 'goplus',
      GatewayTokenRiskStatus.unknown =>
        source == 'operator_registry' || source == 'goplus',
    };
    if (!_hasExactStringKeys(result, expectedKeys) ||
        responseNetwork != expectedNetwork ||
        responseContract is! String ||
        !_tokenIdentityMatches(chain, contract, responseContract) ||
        !sourceMatchesStatus ||
        (status == GatewayTokenRiskStatus.unsafe &&
            (category is! String ||
                !_tokenRiskCategories.contains(category)))) {
      throw const FormatException('unbound token risk result');
    }
    return GatewayTokenRisk(
      status: status,
      category: category as String?,
      source: source as String,
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
    final expectedNetwork = network ?? _mainnetNetworkId(chain);
    final result = await _call('kt_getEvmTokenApprovals', {
      'chain': chainName(chain),
      'network': ?network,
      'address': address,
      'privacyConsent': true,
    });
    if (result is! Map ||
        !_hasExactStringKeys(result, _approvalResultKeys) ||
        result['status'] != 'ok' ||
        result['source'] != 'goplus' ||
        result['network'] != expectedNetwork ||
        result['approvals'] is! List) {
      throw const FormatException('bad token approvals result');
    }
    final rawRows = result['approvals'] as List;
    if (rawRows.length > 500) {
      throw const FormatException('too many token approval rows');
    }
    final rows = <GatewayTokenApproval>[];
    final identities = <String>{};
    for (final raw in rawRows) {
      if (raw is! Map || !_hasExactStringKeys(raw, _approvalRowKeys)) {
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
      final identity = '${tokenAddress.toLowerCase()}|${spender.toLowerCase()}';
      final validUnlimited = unlimited
          ? amount.trim().toLowerCase() == 'unlimited'
          : _isProviderDecimal(amount);
      if (!_evmAddressPattern.hasMatch(tokenAddress) ||
          !_evmAddressPattern.hasMatch(spender) ||
          decimals < 0 ||
          decimals > Amount.maxDecimals ||
          !_isProviderDecimal(balance) ||
          !validUnlimited ||
          !_isApprovalTimestamp(approvedAt) ||
          (transaction.isNotEmpty &&
              !_evmTxHashPattern.hasMatch(transaction)) ||
          !_isBoundedDisplayText(tokenName, 80) ||
          !_isBoundedDisplayText(tokenSymbol, 32) ||
          !_isBoundedDisplayText(spenderName, 80) ||
          !_isBoundedDisplayText(spenderTag, 80) ||
          !identities.add(identity)) {
        throw const FormatException('invalid token approval semantics');
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
  /// [chain] and returns the node's transaction hash. A node rejection arrives
  /// as [GatewayException] code -32000; provider-controlled text is discarded.
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
    final expectedNetwork = network ?? _mainnetNetworkId(chain);
    final result = await _call('kt_broadcast', {
      'chain': chainName(chain),
      'network': ?network,
      'payload': payload,
    });
    final txHash = result is Map ? result['txHash'] : null;
    if (result is! Map ||
        !_hasExactStringKeys(result, _broadcastResultKeys) ||
        result['chain'] != chainName(chain) ||
        result['network'] != expectedNetwork ||
        txHash is! String ||
        !_isCanonicalTransactionHash(chain, txHash)) {
      throw const FormatException('bad broadcast result');
    }
    return txHash;
  }

  void close() => _client.close();

  static BigInt _canonicalUint(Object? value, {BigInt? max}) {
    if (value is! String ||
        value.length > 78 ||
        !_canonicalUintPattern.hasMatch(value)) {
      throw const FormatException('non-canonical unsigned integer');
    }
    final parsed = BigInt.parse(value);
    if (parsed > (max ?? _maxUint256)) {
      throw const FormatException('unsigned integer out of range');
    }
    return parsed;
  }

  static String _mainnetNetworkId(Coin chain) => switch (chain) {
    Coin.eth => 'eth-mainnet',
    Coin.polygon => 'polygon-mainnet',
    Coin.base => 'base-mainnet',
    Coin.arbitrum => 'arbitrum-mainnet',
    Coin.avalanche => 'avalanche-mainnet',
    Coin.bnb => 'bnb-mainnet',
    Coin.tron => 'tron-mainnet',
    Coin.solana => 'sol-mainnet',
  };

  static bool _hasExactStringKeys(
    Map<Object?, Object?> value,
    Set<String> keys,
  ) => value.length == keys.length && value.keys.every(keys.contains);

  static bool _sameEvmAddress(Object? value, String expected) =>
      value is String &&
      _evmAddressPattern.hasMatch(value) &&
      _evmAddressPattern.hasMatch(expected) &&
      value.toLowerCase() == expected.toLowerCase();

  static bool _sameAccountAddress(Coin chain, Object? value, String expected) =>
      value is String && _tokenIdentityMatches(chain, expected, value);

  static bool _sameTransactionHash(Coin chain, Object? value, String expected) {
    if (value is! String ||
        value != value.trim() ||
        expected != expected.trim()) {
      return false;
    }
    return switch (chain) {
      Coin.eth ||
      Coin.polygon ||
      Coin.base ||
      Coin.arbitrum ||
      Coin.avalanche ||
      Coin.bnb =>
        _evmTxHashPattern.hasMatch(value) &&
            _evmTxHashPattern.hasMatch(expected) &&
            value.toLowerCase() == expected.toLowerCase(),
      Coin.tron =>
        _tronTxHashPattern.hasMatch(value) &&
            _tronTxHashPattern.hasMatch(expected) &&
            value.toLowerCase() == expected.toLowerCase(),
      Coin.solana => _sameCanonicalSolanaSignature(value, expected),
    };
  }

  static bool _sameCanonicalSolanaSignature(String value, String expected) {
    return value == expected && parseCanonicalSolanaSignature(value) != null;
  }

  static bool _isCanonicalTransactionHash(Coin chain, String value) =>
      switch (chain) {
        Coin.eth ||
        Coin.polygon ||
        Coin.base ||
        Coin.arbitrum ||
        Coin.avalanche ||
        Coin.bnb => _evmTxHashPattern.hasMatch(value),
        Coin.tron => _tronTxHashPattern.hasMatch(value),
        Coin.solana => _isCanonicalSolanaSignature(value),
      };

  static bool _isCanonicalSolanaSignature(String value) =>
      parseCanonicalSolanaSignature(value) != null;

  static Chain _addressChain(Coin chain) => switch (chain) {
    Coin.eth => Chain.ethereum,
    Coin.polygon => Chain.polygon,
    Coin.base => Chain.base,
    Coin.arbitrum => Chain.arbitrum,
    Coin.avalanche => Chain.avalanche,
    Coin.bnb => Chain.bnb,
    Coin.tron => Chain.tron,
    Coin.solana => Chain.solana,
  };

  static bool _isCanonicalChainAddress(Coin chain, Object? value) =>
      value is String &&
      value == value.trim() &&
      Addresses.validate(_addressChain(chain), value).isValid;

  static bool _isValidHistoryContract(Coin chain, Object? value) {
    if (value == null) return true;
    if (value is! String || value.isEmpty || value != value.trim()) {
      return false;
    }
    if (chain == Coin.tron && _canonicalUintPattern.hasMatch(value)) {
      return value.length <= 78;
    }
    return _isCanonicalChainAddress(chain, value);
  }

  static bool _isProviderDecimal(String value) {
    final normalized = value.trim();
    return normalized.isNotEmpty &&
        normalized.length <= 128 &&
        _providerDecimalPattern.hasMatch(normalized);
  }

  /// Approval evidence uses Unix seconds. Zero means the provider did not
  /// supply a timestamp. A bounded 24-hour future skew matches the Gateway's
  /// upstream validation while independently preventing false future evidence
  /// and values that could make the UI's DateTime conversion throw.
  static bool _isApprovalTimestamp(int seconds) {
    if (seconds < 0) return false;
    final maximum =
        DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/
        1000;
    return seconds <= maximum;
  }

  static bool _tokenIdentityMatches(
    Coin chain,
    String requested,
    String response,
  ) {
    if (requested != requested.trim() || response != response.trim()) {
      return false;
    }
    return switch (chain) {
      Coin.eth ||
      Coin.polygon ||
      Coin.base ||
      Coin.arbitrum ||
      Coin.avalanche ||
      Coin.bnb =>
        _evmAddressPattern.hasMatch(requested) &&
            _evmAddressPattern.hasMatch(response) &&
            requested.toLowerCase() == response.toLowerCase(),
      Coin.tron =>
        requested.length == 34 &&
            response.length == 34 &&
            requested.startsWith('T') &&
            response.startsWith('T') &&
            _base58AddressPattern.hasMatch(requested) &&
            _base58AddressPattern.hasMatch(response) &&
            requested == response,
      Coin.solana =>
        requested.length >= 32 &&
            requested.length <= 44 &&
            response.length >= 32 &&
            response.length <= 44 &&
            _base58AddressPattern.hasMatch(requested) &&
            _base58AddressPattern.hasMatch(response) &&
            requested == response,
    };
  }

  static Coin? _officialTokenNetworkCoin(String network) => switch (network) {
    'eth-mainnet' || 'eth-sepolia' => Coin.eth,
    'polygon-mainnet' || 'polygon-amoy' => Coin.polygon,
    'base-mainnet' || 'base-sepolia' => Coin.base,
    'arbitrum-mainnet' || 'arbitrum-sepolia' => Coin.arbitrum,
    'avalanche-mainnet' || 'avalanche-fuji' => Coin.avalanche,
    'bnb-mainnet' || 'bnb-testnet' => Coin.bnb,
    'tron-mainnet' || 'tron-nile' => Coin.tron,
    'sol-mainnet' || 'sol-devnet' => Coin.solana,
    _ => null,
  };

  static bool _officialTokenMatchesQuery({
    required Coin chain,
    required String query,
    required String symbol,
    required String name,
    required String contract,
  }) {
    final exactQuery = query.trim();
    if (exactQuery.isEmpty) return true;
    final foldedQuery = exactQuery.toLowerCase();
    if (symbol.toLowerCase().contains(foldedQuery) ||
        name.toLowerCase().contains(foldedQuery)) {
      return true;
    }
    return switch (chain) {
      Coin.eth ||
      Coin.polygon ||
      Coin.base ||
      Coin.arbitrum ||
      Coin.avalanche ||
      Coin.bnb => contract.toLowerCase().contains(foldedQuery),
      Coin.tron || Coin.solana => contract.contains(exactQuery),
    };
  }

  static bool _isBoundedDisplayText(String value, int maxRunes) {
    if (value != value.trim() || value.runes.length > maxRunes) return false;
    for (final rune in value.runes) {
      if (rune < 0x20 ||
          rune == 0x7f ||
          (rune >= 0x200b && rune <= 0x200f) ||
          (rune >= 0x202a && rune <= 0x202e) ||
          (rune >= 0x2060 && rune <= 0x2069) ||
          rune == 0xfeff) {
        return false;
      }
    }
    return true;
  }
}

/// A JSON-RPC error answered by the gateway. [code] follows the contract
/// (-32000 upstream_error, -32001 rate_limited, -32002 unsupported, -32003
/// submission_unknown, plus the standard protocol codes). Remote message and
/// data fields are deliberately discarded so provider text cannot reach UI,
/// logs, diagnostics, or future callers through this object.
class GatewayException implements Exception {
  GatewayException({required this.code})
    : message = _gatewayErrorCategory(code);

  final int code;
  final String message;

  /// The contract's "no indexer / not implemented for this chain" code.
  bool get isUnsupported => code == -32002;

  /// Applied by the gateway before an upstream node is contacted.
  bool get isRateLimited => code == -32001;

  /// The contract's "a node accepted the request and rejected it" code.
  bool get isUpstreamError => code == -32000;

  /// The broadcast was attempted but no authoritative node answer survived.
  bool get isSubmissionUnknown => code == -32003;

  @override
  String toString() => 'GatewayException($code, $message)';
}

String _gatewayErrorCategory(int code) => switch (code) {
  -32700 => 'parse_error',
  -32600 => 'invalid_request',
  -32601 => 'method_not_found',
  -32602 => 'invalid_params',
  -32603 => 'internal_error',
  -32000 => 'upstream_error',
  -32001 => 'rate_limited',
  -32002 => 'unsupported',
  -32003 => 'submission_unknown',
  _ => 'gateway_error',
};

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
/// when the row succeeded ([error] == null and the value parsed). [error] is
/// always a local stable category; the provider's reason is never retained.
class GatewayTokenBalance {
  static const unavailableError = 'token_balance_unavailable';

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
