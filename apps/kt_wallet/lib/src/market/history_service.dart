import 'dart:convert';

import 'package:chains/chains.dart' show Amount, base58Decode;
import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:http/http.dart' as http;

import 'balance_service.dart' show RpcEndpointResolver, defaultRpcEndpointFor;
import 'gateway_client.dart';

/// TronGrid REST base URL — the only chain with a keyless public history API.
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

/// Fetches recent transaction history where a keyless public API exists.
///
/// HONESTY NOTE on coverage:
/// - TRON: TronGrid serves both TRC-20 transfers and native transactions
///   without an API key, so TRON history is fetched for real. Today's demo
///   wallets carry mock addresses that TronGrid rejects (4xx/empty) — that
///   surfaces as a graceful [HistoryStatus.error], rendered as the demo
///   fallback, never a crash or a fabricated "live" list.
/// - Ethereum/Polygon: readable history needs an indexer (Etherscan-family
///   APIs require keys; raw JSON-RPC has no per-address tx index), so they
///   return [HistoryStatus.unsupported] instead of pretending.
/// - Solana: `getSignaturesForAddress` is keyless but yields only signatures;
///   turning those into readable transfer rows requires per-tx decoding well
///   beyond this plumbing pass — also [HistoryStatus.unsupported].
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
  /// [HistoryStatus.error]; chains without a keyless API return
  /// [HistoryStatus.unsupported].
  ///
  /// GATEWAY SEMANTICS: with a gateway configured, `kt_getHistory` is asked
  /// for EVERY chain — this is what UNLOCKS eth/polygon/solana history
  /// (indexer keys live server-side); "unsupported" is returned only when the
  /// gateway itself says so, or in direct mode. On a gateway failure, TRON
  /// falls back to the direct TronGrid path (the one keyless API we have);
  /// the other chains have no direct path, so they surface an honest
  /// [HistoryStatus.error] rather than pretending "unsupported".
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
        // Gateway unreachable/erroring: only TRON has a direct alternative.
        if (coin != Coin.tron) return const HistoryResult.error();
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
      case Coin.solana:
        return const HistoryResult.unsupported();
    }
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
