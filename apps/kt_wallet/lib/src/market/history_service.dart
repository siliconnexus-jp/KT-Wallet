import 'dart:convert';

import 'package:chains/chains.dart'
    show Amount, base58Decode, solanaToken2022Program, solanaTokenProgram;
import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:http/http.dart' as http;

import 'balance_service.dart' show RpcEndpointResolver, defaultRpcEndpointFor;
import 'gateway_client.dart';
import 'token_balance_service.dart';

/// Default TronGrid REST base URL.
const String defaultTronHistoryApiUrl = 'https://api.trongrid.io';

/// Per-chain history fetch outcome.
enum HistoryStatus { loading, ok, error, unsupported }

/// One on-chain transaction, normalized for display.
class ChainTxRecord {
  const ChainTxRecord({
    required this.coin,
    required this.hash,
    required this.outgoing,
    this.id,
    this.amountText,
    this.assetContract,
    this.assetSymbol,
    this.assetVerified = true,
    required this.timestamp,
    required this.confirmed,
  });

  /// Which chain this record came from. The merged cross-chain list drops the
  /// per-chain grouping, so without it the detail screen could not tell which
  /// explorer a hash belongs to.
  final Coin coin;

  final String hash;

  /// Stable transfer-event identity. Unlike [hash], this distinguishes
  /// multiple token transfer logs emitted by one transaction.
  final String? id;

  /// Direction relative to the queried address (from == address → outgoing).
  final bool outgoing;

  /// Formatted "120.5 USDT" when the amount and symbol were parseable, null
  /// otherwise — the UI renders '--' instead of inventing a number.
  final String? amountText;

  /// Token contract/mint when this is a token transfer.
  final String? assetContract;

  /// Claimed/verified token symbol without the formatted amount.
  final String? assetSymbol;

  /// False for a token not present in KT Wallet's per-network registry.
  final bool assetVerified;

  bool get impersonatesProtectedSymbol =>
      !assetVerified && isProtectedTokenSymbol(assetSymbol);

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
    TokenRegistryResolver? tokenRegistry,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client(),
       _endpoints = endpoints ?? defaultRpcEndpointFor,
       _gateway = gateway ?? _noGateway,
       _tokenRegistry = tokenRegistry ?? _mainnetTokenRegistry;

  static GatewayClient? _noGateway() => null;

  final http.Client _client;

  /// Per-chain endpoint resolver (settings overrides in production; the
  /// built-in defaults otherwise). Resolved on every fetch.
  final RpcEndpointResolver _endpoints;

  /// Optional gateway (null in direct mode), resolved on every fetch.
  final GatewayResolver _gateway;
  final TokenRegistryResolver _tokenRegistry;
  final Duration timeout;

  /// The TronGrid base URL in effect for the next fetch.
  String get tronApiUrl => _endpoints(Coin.tron);

  static List<TokenInfo> _mainnetTokenRegistry() => builtinTokens;

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
          for (final record in history.records) _mapGatewayRecord(coin, record),
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
      case Coin.bnb:
        return _fetchEvm(coin, address);
      case Coin.solana:
        return _fetchSolana(address);
    }
  }

  Future<HistoryResult> _fetchEvm(Coin coin, String address) async {
    try {
      final base = _evmHistoryApi(coin);

      Future<List<dynamic>> fetchList(String action) async {
        final uri = Uri.parse(base).replace(
          queryParameters: {
            'module': 'account',
            'action': action,
            'address': address,
            'page': '1',
            'offset': '$pageSize',
            'sort': 'desc',
          },
        );
        final response = await _client.get(uri).timeout(timeout);
        if (response.statusCode != 200) {
          throw http.ClientException('HTTP ${response.statusCode}', uri);
        }
        final body = jsonDecode(response.body);
        if (body is! Map) throw const FormatException('non-object body');
        final result = body['result'];
        if (result is List) return result;
        // Etherscan-compatible APIs use this shape for a valid empty page.
        if (body['status'] == '0' &&
            '${body['message']}'.toLowerCase().contains('no transactions')) {
          return const [];
        }
        // In particular, Routescan currently returns a null result for BNB.
        // Treat that as unavailable rather than telling users the wallet has
        // no transactions.
        throw const FormatException('missing transaction result');
      }

      final normalItems = await fetchList('txlist');
      final tokenItems = await fetchList('tokentx');
      List<dynamic> internalItems = const [];
      try {
        internalItems = await fetchList('txlistinternal');
      } catch (_) {
        // Internal transfers are enrichment on explorers that implement it;
        // a failure must not hide otherwise trustworthy native/token rows.
      }

      final lower = address.toLowerCase();
      final registry = _tokenRegistry();
      final records = <ChainTxRecord>[];

      void appendNative(
        Map<dynamic, dynamic> item, {
        required bool internal,
        required int index,
      }) {
        final hash = item['hash'];
        if (hash is! String || hash.isEmpty) return;
        final from = '${item['from'] ?? ''}'.toLowerCase();
        final to = '${item['to'] ?? ''}'.toLowerCase();
        if (from != lower && to != lower) return;
        final seconds = int.tryParse('${item['timeStamp'] ?? ''}');
        final value = BigInt.tryParse('${item['value'] ?? ''}');
        if (seconds == null || value == null || value == BigInt.zero) return;
        final trace = '${item['traceId'] ?? index}';
        records.add(
          ChainTxRecord(
            coin: coin,
            id: internal ? '$hash:internal:$trace' : hash,
            hash: hash,
            outgoing: from == lower,
            amountText: _formatAmount(value, 18, _nativeSymbol(coin)),
            timestamp: DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
            confirmed: item['isError'] != '1',
          ),
        );
      }

      for (final (index, item) in normalItems.indexed) {
        if (item is Map) appendNative(item, internal: false, index: index);
      }
      for (final (index, item) in internalItems.indexed) {
        if (item is Map) appendNative(item, internal: true, index: index);
      }
      for (final (index, item) in tokenItems.indexed) {
        if (item is! Map) continue;
        final hash = item['hash'];
        final contract = '${item['contractAddress'] ?? ''}'.trim();
        final from = '${item['from'] ?? ''}'.toLowerCase();
        final to = '${item['to'] ?? ''}'.toLowerCase();
        final seconds = int.tryParse('${item['timeStamp'] ?? ''}');
        final raw = BigInt.tryParse('${item['value'] ?? ''}');
        if (hash is! String ||
            hash.isEmpty ||
            contract.isEmpty ||
            (from != lower && to != lower) ||
            seconds == null ||
            raw == null) {
          continue;
        }
        TokenInfo? official;
        for (final token in registry) {
          if (token.chain == coin &&
              token.contract.toLowerCase() == contract.toLowerCase()) {
            official = token;
            break;
          }
        }
        final claimedDecimals = int.tryParse('${item['tokenDecimal'] ?? ''}');
        final claimedSymbol = '${item['tokenSymbol'] ?? ''}'.trim();
        final decimals = official?.decimals ?? claimedDecimals;
        final symbol =
            official?.symbol ??
            (claimedSymbol.isEmpty ? 'TOKEN' : claimedSymbol.toUpperCase());
        final logIndex = '${item['logIndex'] ?? index}';
        records.add(
          ChainTxRecord(
            coin: coin,
            id: '$hash:token:${contract.toLowerCase()}:$logIndex',
            hash: hash,
            outgoing: from == lower,
            amountText: decimals == null
                ? null
                : _formatAmount(raw, decimals, symbol),
            assetContract: contract,
            assetSymbol: symbol,
            assetVerified: official != null,
            timestamp: DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
            confirmed: item['isError'] != '1',
          ),
        );
      }

      records.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final seen = <String>{};
      final deduped = records
          .where((record) {
            return seen.add(record.id ?? record.hash);
          })
          .take(pageSize);
      return HistoryResult.ok(List.unmodifiable(deduped));
    } catch (_) {
      return const HistoryResult.error();
    }
  }

  String _evmHistoryApi(Coin coin) {
    final endpoint = _endpoints(coin).toLowerCase();
    final testnet =
        endpoint.contains('sepolia') ||
        endpoint.contains('amoy') ||
        endpoint.contains('test') ||
        endpoint.contains('fuji');
    return switch (coin) {
      Coin.eth =>
        testnet
            ? 'https://eth-sepolia.blockscout.com/api'
            : 'https://eth.blockscout.com/api',
      Coin.polygon =>
        testnet
            ? 'https://polygon-amoy.blockscout.com/api'
            : 'https://polygon.blockscout.com/api',
      Coin.base =>
        testnet
            ? 'https://base-sepolia.blockscout.com/api'
            : 'https://base.blockscout.com/api',
      Coin.arbitrum =>
        testnet
            ? 'https://arbitrum-sepolia.blockscout.com/api'
            : 'https://arbitrum.blockscout.com/api',
      Coin.avalanche =>
        'https://api.routescan.io/v2/network/'
            '${testnet ? 'testnet' : 'mainnet'}/evm/'
            '${testnet ? 43113 : 43114}/etherscan/api',
      Coin.bnb =>
        'https://api.routescan.io/v2/network/'
            '${testnet ? 'testnet' : 'mainnet'}/evm/'
            '${testnet ? 97 : 56}/etherscan/api',
      _ => throw ArgumentError('not EVM: $coin'),
    };
  }

  String _nativeSymbol(Coin coin) => switch (coin) {
    Coin.polygon => 'POL',
    Coin.avalanche => 'AVAX',
    Coin.bnb => 'BNB',
    _ => 'ETH',
  };

  Future<HistoryResult> _fetchSolana(String address) async {
    try {
      final rpc = _endpoints(Coin.solana);
      final bySignature = <String, Map<dynamic, dynamic>>{};

      Future<void> collectSignatures(String account) async {
        final result = await _solanaCall(rpc, 'getSignaturesForAddress', [
          account,
          {'limit': pageSize},
        ]);
        if (result is! List) throw const FormatException('bad signatures');
        for (final item in result) {
          if (item is Map && item['signature'] is String) {
            bySignature[item['signature'] as String] = item;
          }
        }
      }

      // The owner account is not required to appear in an incoming SPL
      // transfer. Query each owned ATA as well, otherwise token deposits can
      // be invisible even though the balance is already present.
      await collectSignatures(address);
      final tokenAccounts = <String>{};
      for (final program in [solanaTokenProgram, solanaToken2022Program]) {
        try {
          final result = await _solanaCall(rpc, 'getTokenAccountsByOwner', [
            address,
            {'programId': program},
            {'encoding': 'jsonParsed'},
          ]);
          final value = result is Map ? result['value'] : null;
          if (value is List) {
            for (final row in value) {
              if (row is Map && row['pubkey'] is String) {
                tokenAccounts.add(row['pubkey'] as String);
              }
            }
          }
        } catch (_) {
          // Token discovery is enrichment. The owner signature history still
          // remains a valid fallback when an RPC omits this method.
        }
      }
      final boundedAccounts = tokenAccounts.take(16);
      await Future.wait([
        for (final account in boundedAccounts)
          collectSignatures(account).catchError((_) {}),
      ]);

      final signatures = bySignature.values.toList()
        ..sort((a, b) {
          final left = a['blockTime'] is int ? a['blockTime'] as int : 0;
          final right = b['blockTime'] is int ? b['blockTime'] as int : 0;
          return right.compareTo(left);
        });
      final records = <ChainTxRecord>[];
      var detailFailed = false;
      for (final item in signatures.take(pageSize * 3)) {
        final signature = item['signature'];
        if (signature is! String) continue;
        Object? transaction;
        try {
          transaction = await _solanaCall(rpc, 'getTransaction', [
            signature,
            {
              'encoding': 'jsonParsed',
              'maxSupportedTransactionVersion': 0,
              'commitment': 'confirmed',
            },
          ]);
        } catch (_) {
          detailFailed = true;
          continue;
        }
        if (transaction is! Map) continue;
        final blockTime = item['blockTime'];
        final timestamp = blockTime is int
            ? DateTime.fromMillisecondsSinceEpoch(blockTime * 1000)
            : DateTime.fromMillisecondsSinceEpoch(0);
        final meta = transaction['meta'];
        final message = transaction['transaction'] is Map
            ? (transaction['transaction'] as Map)['message']
            : null;
        if (meta is! Map || message is! Map) continue;

        final tokenDeltas = _solanaTokenDeltas(meta, address);
        if (tokenDeltas.isNotEmpty) {
          for (final entry in tokenDeltas.entries) {
            final delta = entry.value.amount;
            if (delta == BigInt.zero) continue;
            final official = _findSolanaToken(entry.key);
            final symbol = official?.symbol ?? 'SPL';
            final decimals = official?.decimals ?? entry.value.decimals;
            records.add(
              ChainTxRecord(
                coin: Coin.solana,
                id: '$signature:spl:${entry.key}',
                hash: signature,
                outgoing: delta.isNegative,
                amountText: _formatAmount(delta.abs(), decimals, symbol),
                assetContract: entry.key,
                assetSymbol: symbol,
                assetVerified: official != null,
                timestamp: timestamp,
                confirmed: item['err'] == null && meta['err'] == null,
              ),
            );
          }
        } else {
          final keys = message['accountKeys'];
          final preBalances = meta['preBalances'];
          final postBalances = meta['postBalances'];
          if (keys is! List || preBalances is! List || postBalances is! List) {
            continue;
          }
          final ownerIndex = keys.indexWhere((key) {
            if (key is String) return key == address;
            return key is Map && key['pubkey'] == address;
          });
          if (ownerIndex < 0 ||
              ownerIndex >= preBalances.length ||
              ownerIndex >= postBalances.length) {
            continue;
          }
          final before = BigInt.tryParse('${preBalances[ownerIndex]}');
          final after = BigInt.tryParse('${postBalances[ownerIndex]}');
          if (before == null || after == null || before == after) continue;
          final delta = after - before;
          records.add(
            ChainTxRecord(
              coin: Coin.solana,
              id: signature,
              hash: signature,
              outgoing: delta.isNegative,
              amountText: _formatAmount(delta.abs(), 9, 'SOL'),
              timestamp: timestamp,
              confirmed: item['err'] == null && meta['err'] == null,
            ),
          );
        }
        if (records.length >= pageSize) break;
      }
      if (records.isEmpty && signatures.isNotEmpty && detailFailed) {
        return const HistoryResult.error();
      }
      records.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return HistoryResult.ok(List.unmodifiable(records.take(pageSize)));
    } catch (_) {
      return const HistoryResult.error();
    }
  }

  Map<String, ({BigInt amount, int decimals})> _solanaTokenDeltas(
    Map<dynamic, dynamic> meta,
    String owner,
  ) {
    final before = <String, ({BigInt amount, int decimals})>{};
    final after = <String, ({BigInt amount, int decimals})>{};

    void collect(
      Object? rows,
      Map<String, ({BigInt amount, int decimals})> target,
    ) {
      if (rows is! List) return;
      for (final row in rows) {
        if (row is! Map || row['owner'] != owner) continue;
        final mint = row['mint'];
        final uiAmount = row['uiTokenAmount'];
        if (mint is! String || uiAmount is! Map) continue;
        final raw = BigInt.tryParse('${uiAmount['amount'] ?? ''}');
        final decimals = uiAmount['decimals'];
        if (raw == null || decimals is! int) continue;
        final existing = target[mint];
        target[mint] = (
          amount: (existing?.amount ?? BigInt.zero) + raw,
          decimals: decimals,
        );
      }
    }

    collect(meta['preTokenBalances'], before);
    collect(meta['postTokenBalances'], after);
    final deltas = <String, ({BigInt amount, int decimals})>{};
    for (final mint in {...before.keys, ...after.keys}) {
      final previous = before[mint];
      final current = after[mint];
      final decimals = current?.decimals ?? previous?.decimals ?? 0;
      final amount =
          (current?.amount ?? BigInt.zero) - (previous?.amount ?? BigInt.zero);
      if (amount != BigInt.zero) {
        deltas[mint] = (amount: amount, decimals: decimals);
      }
    }
    return deltas;
  }

  TokenInfo? _findSolanaToken(String mint) {
    for (final token in _tokenRegistry()) {
      if (token.chain == Coin.solana && token.contract == mint) return token;
    }
    return null;
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
  ChainTxRecord _mapGatewayRecord(Coin coin, GatewayHistoryRecord record) {
    final raw = record.amountRaw;
    final decimals = record.decimals;
    final symbol = record.symbol;
    return ChainTxRecord(
      coin: coin,
      id: record.id,
      hash: record.hash,
      outgoing: record.outgoing,
      amountText: raw != null && decimals != null && symbol != null
          ? _formatAmount(raw, decimals, symbol)
          : null,
      assetContract: record.contract,
      assetSymbol: symbol,
      assetVerified: record.verified,
      timestamp: DateTime.fromMillisecondsSinceEpoch(record.timestampMs),
      confirmed: !record.failed,
    );
  }

  /// TRC-20, TRX/TRC-10 and contract-created internal transfers, fetched
  /// concurrently and merged newest-first.
  Future<HistoryResult> _fetchTron(String address) async {
    try {
      final (trc20, native, internal) = await (
        _getData(
          '$tronApiUrl/v1/accounts/$address/transactions/trc20?limit=$pageSize',
        ),
        _getData(
          '$tronApiUrl/v1/accounts/$address/transactions?limit=$pageSize',
        ),
        _getData(
          '$tronApiUrl/v1/accounts/$address/internal-transactions'
          '?limit=$pageSize&only_confirmed=true',
        ),
      ).wait;

      final myHex = tronAddressHex(address);
      final records = <ChainTxRecord>[];
      final tokenHashes = <String>{};
      for (final item in trc20) {
        final record = item is Map ? _parseTrc20(item, address) : null;
        if (record != null) {
          records.add(record);
          tokenHashes.add(record.hash);
        }
      }
      for (final item in native) {
        final record = item is Map ? _parseNative(item, myHex) : null;
        if (record != null && !tokenHashes.contains(record.hash)) {
          records.add(record);
        }
      }
      for (final item in internal) {
        final record = item is Map ? _parseTronInternal(item, myHex) : null;
        if (record != null) records.add(record);
      }
      records.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final seen = <String>{};
      final deduped = records
          .where((record) {
            return seen.add(record.id ?? record.hash);
          })
          .take(pageSize);
      return HistoryResult.ok(List.unmodifiable(deduped));
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
    String? assetSymbol;
    String? assetContract;
    var assetVerified = false;
    final info = item['token_info'];
    final value = item['value'];
    if (info is Map && value is String) {
      var decimals = info['decimals'];
      var symbol = info['symbol'];
      final contract = info['address'];
      if (contract is String && contract.trim().isNotEmpty) {
        assetContract = contract.trim();
        for (final token in _tokenRegistry()) {
          final sameContract = token.contract.toLowerCase().startsWith('0x')
              ? token.contract.toLowerCase() == assetContract.toLowerCase()
              : token.contract == assetContract;
          if (sameContract) {
            symbol = token.symbol;
            decimals = token.decimals;
            assetVerified = true;
            break;
          }
        }
      }
      final raw = BigInt.tryParse(value);
      if (decimals is int && symbol is String && raw != null) {
        assetSymbol = symbol.toUpperCase();
        amountText = _formatAmount(raw, decimals, symbol);
      }
    }
    return ChainTxRecord(
      coin: Coin.tron,
      id: '$hash:trc20:${assetContract ?? 'unknown'}',
      hash: hash,
      outgoing: item['from'] == address,
      amountText: amountText,
      assetContract: assetContract,
      assetSymbol: assetSymbol,
      assetVerified: assetVerified,
      timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
      // The trc20 endpoint serves confirmed transfer events.
      confirmed: true,
    );
  }

  /// One item of `/v1/accounts/{addr}/transactions`:
  /// `{txID, ret: [{contractRet}], block_timestamp, raw_data: {contract:
  ///   [{type, parameter: {value: {amount, owner_address, to_address}}}]}}`
  /// (addresses in 41-prefixed hex). Supports native TRX TransferContract and
  /// TRC-10 TransferAssetContract; TRC-20 events come from their own endpoint.
  ChainTxRecord? _parseNative(Map<dynamic, dynamic> item, String? myHex) {
    final hash = item['txID'];
    final ts = item['block_timestamp'];
    if (hash is! String || ts is! int) return null;
    final rawData = item['raw_data'];
    final contracts = rawData is Map ? rawData['contract'] : null;
    if (contracts is! List || contracts.isEmpty) return null;
    final contract = contracts.first;
    if (contract is! Map) return null;
    final type = contract['type'];
    if (type != 'TransferContract' && type != 'TransferAssetContract') {
      return null;
    }
    final parameter = contract['parameter'];
    final value = parameter is Map ? parameter['value'] : null;
    if (value is! Map) return null;

    var confirmed = true;
    final ret = item['ret'];
    if (ret is List && ret.isNotEmpty && ret.first is Map) {
      confirmed = (ret.first as Map)['contractRet'] == 'SUCCESS';
    }
    final amount = _parseChainInteger(value['amount']);
    if (amount == null || amount.isNegative) return null;
    final owner = value['owner_address'];
    final tokenId = type == 'TransferAssetContract'
        ? '${value['asset_name'] ?? ''}'.trim()
        : '';
    final isTrc10 = tokenId.isNotEmpty;
    return ChainTxRecord(
      coin: Coin.tron,
      id: isTrc10 ? '$hash:trc10:$tokenId' : hash,
      hash: hash,
      // Hex owner vs our base58-decoded address; an undecodable address (the
      // demo mocks) can't match, so those rows read as incoming — moot in
      // practice because TronGrid rejects mock addresses before this point.
      outgoing:
          myHex != null && owner is String && owner.toLowerCase() == myHex,
      amountText: _formatAmount(
        amount,
        isTrc10 ? 0 : 6,
        isTrc10 ? 'TRC10' : 'TRX',
      ),
      assetContract: isTrc10 ? tokenId : null,
      assetSymbol: isTrc10 ? 'TRC10' : null,
      assetVerified: !isTrc10,
      timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
      confirmed: confirmed,
    );
  }

  ChainTxRecord? _parseTronInternal(Map<dynamic, dynamic> item, String? myHex) {
    final hash = item['tx_id'];
    final internalId = item['internal_tx_id'];
    final timestamp = item['block_timestamp'];
    final from = '${item['from_address'] ?? ''}'.toLowerCase();
    final to = '${item['to_address'] ?? ''}'.toLowerCase();
    if (hash is! String ||
        internalId is! String ||
        timestamp is! int ||
        myHex == null ||
        (from != myHex && to != myHex)) {
      return null;
    }
    final data = item['data'];
    if (data is! Map) return null;
    final tokenId = '${data['token_id'] ?? ''}'.trim();
    final isTrc10 = tokenId.isNotEmpty;
    final valueContainer = isTrc10
        ? data['call_token_value']
        : data['call_value'];
    final amount = valueContainer is Map
        ? _parseChainInteger(valueContainer['_'])
        : _parseChainInteger(valueContainer);
    if (amount == null || amount == BigInt.zero || amount.isNegative) {
      return null;
    }
    return ChainTxRecord(
      coin: Coin.tron,
      id: '$hash:internal:$internalId',
      hash: hash,
      outgoing: from == myHex,
      amountText: _formatAmount(
        amount,
        isTrc10 ? 0 : 6,
        isTrc10 ? 'TRC10' : 'TRX',
      ),
      assetContract: isTrc10 ? tokenId : null,
      assetSymbol: isTrc10 ? 'TRC10' : null,
      assetVerified: !isTrc10,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
      confirmed: data['rejected'] != true,
    );
  }

  static BigInt? _parseChainInteger(Object? value) {
    if (value is int) return BigInt.from(value);
    if (value is String) return BigInt.tryParse(value);
    return BigInt.tryParse('$value');
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
