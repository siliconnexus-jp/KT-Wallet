import 'dart:convert';

import 'package:chains/chains.dart' show Amount, base58Decode;
import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:http/http.dart' as http;

import 'balance_service.dart' show RpcEndpointResolver, defaultRpcEndpointFor;
import 'gateway_client.dart';

/// Default TronGrid REST base URL.
const String defaultTronHistoryApiUrl = 'https://api.trongrid.io';

/// Per-chain history fetch outcome.
enum HistoryStatus { loading, ok, error, unsupported }

/// One on-chain transaction, normalized for display.
class ChainTxRecord {
  const ChainTxRecord({
    required this.hash,
    required this.outgoing,
    this.amountText,
    required this.timestamp,
    required this.confirmed,
  });

  final String hash;

  /// Direction relative to the queried address (from == address → outgoing).
  final bool outgoing;

  /// Formatted "120.5 USDT" when the amount and symbol were parseable, null
  /// otherwise — the UI renders '--' instead of inventing a number.
  final String? amountText;

  final DateTime timestamp;

  /// Whether the chain reports the transaction as executed successfully.
  final bool confirmed;
}

/// Records for one chain, or the reason there aren't any.
/// [records] is non-empty only when [status] == [HistoryStatus.ok].
class HistoryResult {
  const HistoryResult.loading()
    : status = HistoryStatus.loading,
      records = const [];
  const HistoryResult.ok(this.records) : status = HistoryStatus.ok;
  const HistoryResult.error()
    : status = HistoryStatus.error,
      records = const [];
  const HistoryResult.unsupported()
    : status = HistoryStatus.unsupported,
      records = const [];

  final HistoryStatus status;
  final List<ChainTxRecord> records;
}

/// Fetches recent transactions directly from public chain APIs. The optional
/// gateway is tried first, but every supported chain has a direct path.
class HistoryService {
  HistoryService({
    http.Client? client,
    RpcEndpointResolver? endpoints,
    GatewayResolver? gateway,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client(),
       _endpoints = endpoints ?? defaultRpcEndpointFor,
       _gateway = gateway ?? _noGateway;

  static GatewayClient? _noGateway() => null;

  final http.Client _client;

  /// Per-chain endpoint resolver (settings overrides in production; the
  /// built-in defaults otherwise). Resolved on every fetch.
  final RpcEndpointResolver _endpoints;

  /// Optional gateway (null in direct mode), resolved on every fetch.
  final GatewayResolver _gateway;
  final Duration timeout;

  /// The TronGrid base URL in effect for the next fetch.
  String get tronApiUrl => _endpoints(Coin.tron);

  /// Max records requested per endpoint and returned after the merge.
  static const int pageSize = 20;

  /// Fetches recent transactions for [coin]/[address]. Never throws: every
  /// failure (HTTP status, timeout, malformed body) collapses to
  /// [HistoryStatus.error].
  ///
  /// With a gateway configured, `kt_getHistory` is asked first. If it is
  /// unreachable, the request falls through to the chain's public API.
  Future<HistoryResult> fetch(Coin coin, String address) async {
    final gateway = _gateway();
    if (gateway != null) {
      try {
        final history = await gateway.getHistory(
          chain: coin,
          address: address,
          limit: pageSize,
        );
        if (history.unsupported) return const HistoryResult.unsupported();
        final records = [
          for (final record in history.records) _mapGatewayRecord(record),
        ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return HistoryResult.ok(List.unmodifiable(records.take(pageSize)));
      } catch (_) {
        // Gateway unreachable/erroring: fall through to direct chain APIs.
      }
    }
    switch (coin) {
      case Coin.tron:
        return _fetchTron(address);
      case Coin.eth:
      case Coin.polygon:
      case Coin.base:
      case Coin.arbitrum:
      case Coin.avalanche:
        return _fetchEvm(coin, address);
      case Coin.solana:
        return _fetchSolana(address);
    }
  }

  Future<HistoryResult> _fetchEvm(Coin coin, String address) async {
    try {
      if (coin == Coin.avalanche) {
        return _fetchAvalanche(address);
      }
      final base = _blockscoutApi(coin);
      final uri = Uri.parse(
        '$base/addresses/$address/transactions?items_count=$pageSize',
      );
      final response = await _client.get(uri).timeout(timeout);
      if (response.statusCode != 200) {
        throw http.ClientException('HTTP ${response.statusCode}', uri);
      }
      final body = jsonDecode(response.body);
      final items = body is Map ? body['items'] : null;
      if (items is! List) throw const FormatException('missing items');
      final lower = address.toLowerCase();
      final records = <ChainTxRecord>[];
      for (final item in items) {
        if (item is! Map) continue;
        final hash = item['hash'];
        final timestamp = DateTime.tryParse('${item['timestamp']}');
        if (hash is! String || timestamp == null) continue;
        final from = item['from'];
        final fromHash = from is Map ? from['hash'] : null;
        final value = BigInt.tryParse('${item['value'] ?? ''}');
        records.add(
          ChainTxRecord(
            hash: hash,
            outgoing: fromHash is String && fromHash.toLowerCase() == lower,
            amountText: value == null
                ? null
                : _formatAmount(value, 18, _nativeSymbol(coin)),
            timestamp: timestamp,
            confirmed: item['status'] == 'ok',
          ),
        );
      }
      return HistoryResult.ok(List.unmodifiable(records.take(pageSize)));
    } catch (_) {
      return const HistoryResult.error();
    }
  }

  Future<HistoryResult> _fetchAvalanche(String address) async {
    final endpoint = _endpoints(Coin.avalanche).toLowerCase();
    final testnet = endpoint.contains('test') || endpoint.contains('fuji');
    final network = testnet ? 'testnet' : 'mainnet';
    final chainId = testnet ? 43113 : 43114;
    try {
      final uri = Uri.parse(
        'https://api.routescan.io/v2/network/$network/evm/$chainId/etherscan/api'
        '?module=account&action=txlist&address=$address&page=1'
        '&offset=$pageSize&sort=desc',
      );
      final response = await _client.get(uri).timeout(timeout);
      if (response.statusCode != 200) {
        throw http.ClientException('HTTP ${response.statusCode}', uri);
      }
      final body = jsonDecode(response.body);
      final items = body is Map ? body['result'] : null;
      if (items is! List) throw const FormatException('missing result');
      final lower = address.toLowerCase();
      final records = <ChainTxRecord>[];
      for (final item in items) {
        if (item is! Map || item['hash'] is! String) continue;
        final seconds = int.tryParse('${item['timeStamp']}');
        if (seconds == null) continue;
        final value = BigInt.tryParse('${item['value']}');
        records.add(
          ChainTxRecord(
            hash: item['hash'] as String,
            outgoing: '${item['from']}'.toLowerCase() == lower,
            amountText: value == null ? null : _formatAmount(value, 18, 'AVAX'),
            timestamp: DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
            confirmed: item['isError'] != '1',
          ),
        );
      }
      return HistoryResult.ok(List.unmodifiable(records));
    } catch (_) {
      return const HistoryResult.error();
    }
  }

  String _blockscoutApi(Coin coin) {
    final endpoint = _endpoints(coin).toLowerCase();
    final testnet = endpoint.contains('sepolia') || endpoint.contains('amoy');
    return switch (coin) {
      Coin.eth =>
        testnet
            ? 'https://eth-sepolia.blockscout.com/api/v2'
            : 'https://eth.blockscout.com/api/v2',
      Coin.polygon =>
        testnet
            ? 'https://polygon-amoy.blockscout.com/api/v2'
            : 'https://polygon.blockscout.com/api/v2',
      Coin.base =>
        testnet
            ? 'https://base-sepolia.blockscout.com/api/v2'
            : 'https://base.blockscout.com/api/v2',
      Coin.arbitrum =>
        testnet
            ? 'https://arbitrum-sepolia.blockscout.com/api/v2'
            : 'https://arbitrum.blockscout.com/api/v2',
      Coin.avalanche => throw ArgumentError('Avalanche uses Routescan'),
      _ => throw ArgumentError('not EVM: $coin'),
    };
  }

  String _nativeSymbol(Coin coin) => switch (coin) {
    Coin.polygon => 'POL',
    Coin.avalanche => 'AVAX',
    _ => 'ETH',
  };

  Future<HistoryResult> _fetchSolana(String address) async {
    try {
      final rpc = _endpoints(Coin.solana);
      final signatures = await _solanaCall(rpc, 'getSignaturesForAddress', [
        address,
        {'limit': pageSize},
      ]);
      if (signatures is! List) throw const FormatException('bad signatures');
      final records = <ChainTxRecord>[];
      for (final item in signatures) {
        if (item is! Map || item['signature'] is! String) continue;
        final blockTime = item['blockTime'];
        records.add(
          ChainTxRecord(
            hash: item['signature'] as String,
            outgoing: false,
            timestamp: blockTime is int
                ? DateTime.fromMillisecondsSinceEpoch(blockTime * 1000)
                : DateTime.fromMillisecondsSinceEpoch(0),
            confirmed: item['err'] == null,
          ),
        );
      }
      return HistoryResult.ok(List.unmodifiable(records));
    } catch (_) {
      return const HistoryResult.error();
    }
  }

  Future<Object?> _solanaCall(
    String url,
    String method,
    List<Object?> params,
  ) async {
    final uri = Uri.parse(url);
    final response = await _client
        .post(
          uri,
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'method': method,
            'params': params,
          }),
        )
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw http.ClientException('HTTP ${response.statusCode}', uri);
    }
    final body = jsonDecode(response.body);
    if (body is! Map || body['error'] != null) {
      throw const FormatException('RPC error');
    }
    return body['result'];
  }

  /// Normalizes one gateway record onto the display shape; an unparseable
  /// amount renders as '--' (null), never a made-up number.
  ChainTxRecord _mapGatewayRecord(GatewayHistoryRecord record) {
    final raw = record.amountRaw;
    final decimals = record.decimals;
    final symbol = record.symbol;
    return ChainTxRecord(
      hash: record.hash,
      outgoing: record.outgoing,
      amountText: raw != null && decimals != null && symbol != null
          ? _formatAmount(raw, decimals, symbol)
          : null,
      timestamp: DateTime.fromMillisecondsSinceEpoch(record.timestampMs),
      confirmed: !record.failed,
    );
  }

  /// TRC-20 transfers + native transactions, fetched concurrently, merged
  /// newest-first and de-duplicated by hash (a TRC-20 transfer also appears in
  /// the native list as its TriggerSmartContract wrapper — the TRC-20 entry,
  /// which knows the token amount, wins).
  Future<HistoryResult> _fetchTron(String address) async {
    try {
      final (trc20, native) = await (
        _getData(
          '$tronApiUrl/v1/accounts/$address/transactions/trc20?limit=$pageSize',
        ),
        _getData(
          '$tronApiUrl/v1/accounts/$address/transactions?limit=$pageSize',
        ),
      ).wait;

      final myHex = tronAddressHex(address);
      final byHash = <String, ChainTxRecord>{};
      for (final item in native) {
        final record = item is Map ? _parseNative(item, myHex) : null;
        if (record != null) byHash[record.hash] = record;
      }
      for (final item in trc20) {
        final record = item is Map ? _parseTrc20(item, address) : null;
        if (record != null) byHash[record.hash] = record; // TRC-20 entry wins
      }
      final records = byHash.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return HistoryResult.ok(List.unmodifiable(records.take(pageSize)));
    } catch (_) {
      // ClientException / TimeoutException / FormatException / a 4xx for the
      // demo mock addresses — all mean "no trustworthy history".
      return const HistoryResult.error();
    }
  }

  /// GETs a TronGrid endpoint and returns its `data` list, throwing on any
  /// non-200 / malformed response.
  Future<List<Object?>> _getData(String url) async {
    final resp = await _client.get(Uri.parse(url)).timeout(timeout);
    if (resp.statusCode != 200) {
      throw http.ClientException('HTTP ${resp.statusCode}', Uri.parse(url));
    }
    final body = jsonDecode(resp.body);
    if (body is! Map) throw const FormatException('non-object body');
    final data = body['data'];
    if (data is! List) throw const FormatException('missing data list');
    return data;
  }

  /// One item of `/v1/accounts/{addr}/transactions/trc20`:
  /// `{transaction_id, token_info: {symbol, decimals, ...}, block_timestamp,
  ///   from, to, type, value}` (addresses in base58).
  ChainTxRecord? _parseTrc20(Map<dynamic, dynamic> item, String address) {
    final hash = item['transaction_id'];
    final ts = item['block_timestamp'];
    if (hash is! String || ts is! int) return null;
    String? amountText;
    final info = item['token_info'];
    final value = item['value'];
    if (info is Map && value is String) {
      final decimals = info['decimals'];
      final symbol = info['symbol'];
      final raw = BigInt.tryParse(value);
      if (decimals is int && symbol is String && raw != null) {
        amountText = _formatAmount(raw, decimals, symbol);
      }
    }
    return ChainTxRecord(
      hash: hash,
      outgoing: item['from'] == address,
      amountText: amountText,
      timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
      // The trc20 endpoint serves confirmed transfer events.
      confirmed: true,
    );
  }

  /// One item of `/v1/accounts/{addr}/transactions`:
  /// `{txID, ret: [{contractRet}], block_timestamp, raw_data: {contract:
  ///   [{type, parameter: {value: {amount, owner_address, to_address}}}]}}`
  /// (addresses in 41-prefixed hex). Only plain TRX `TransferContract`
  /// entries become rows — TRC-20 transfers arrive via the trc20 endpoint and
  /// other contract types have no displayable amount/direction.
  ChainTxRecord? _parseNative(Map<dynamic, dynamic> item, String? myHex) {
    final hash = item['txID'];
    final ts = item['block_timestamp'];
    if (hash is! String || ts is! int) return null;
    final rawData = item['raw_data'];
    final contracts = rawData is Map ? rawData['contract'] : null;
    if (contracts is! List || contracts.isEmpty) return null;
    final contract = contracts.first;
    if (contract is! Map || contract['type'] != 'TransferContract') return null;
    final parameter = contract['parameter'];
    final value = parameter is Map ? parameter['value'] : null;
    if (value is! Map) return null;

    var confirmed = true;
    final ret = item['ret'];
    if (ret is List && ret.isNotEmpty && ret.first is Map) {
      confirmed = (ret.first as Map)['contractRet'] == 'SUCCESS';
    }
    final amount = value['amount'];
    final owner = value['owner_address'];
    return ChainTxRecord(
      hash: hash,
      // Hex owner vs our base58-decoded address; an undecodable address (the
      // demo mocks) can't match, so those rows read as incoming — moot in
      // practice because TronGrid rejects mock addresses before this point.
      outgoing:
          myHex != null && owner is String && owner.toLowerCase() == myHex,
      amountText: amount is int && amount >= 0
          ? _formatAmount(BigInt.from(amount), 6, 'TRX')
          : null,
      timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
      confirmed: confirmed,
    );
  }

  /// "120.5 USDT"-style text, or null when the values don't form a valid
  /// [Amount] (e.g. absurd decimals) — never a made-up number.
  static String? _formatAmount(BigInt raw, int decimals, String symbol) {
    try {
      final amount = Amount(raw: raw, decimals: decimals, symbol: symbol);
      return '${amount.format(maxFraction: 6)} $symbol';
    } catch (_) {
      return null;
    }
  }

  void close() => _client.close();
}

/// Decodes a base58check TRON address ("T...") to its lowercase 21-byte hex
/// form ("41..."), as used in TronGrid raw_data. Returns null for anything
/// that isn't a well-formed address (e.g. the demo mock placeholders).
String? tronAddressHex(String address) {
  try {
    final bytes = base58Decode(address);
    // 21-byte payload (0x41 prefix + 20-byte key hash) + 4-byte checksum.
    if (bytes.length != 25 || bytes[0] != 0x41) return null;
    return bytes
        .sublist(0, 21)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  } catch (_) {
    return null;
  }
}
