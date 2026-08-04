import 'dart:convert';
import 'dart:typed_data';

import 'package:chains/chains.dart'
    show
        Addresses,
        Amount,
        Chain,
        base58Decode,
        base58Encode,
        sha256,
        solanaToken2022Program,
        solanaTokenProgram;
import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:http/http.dart' as http;

import '../rpc/bounded_http_client.dart';
import '../rpc/json_rpc_envelope.dart';
import 'balance_service.dart' show RpcEndpointResolver, defaultRpcEndpointFor;
import 'gateway_client.dart';
import 'token_balance_service.dart';

/// Default TronGrid REST base URL.
const String defaultTronHistoryApiUrl = 'https://api.trongrid.io';

/// Per-chain history fetch outcome.
enum HistoryStatus { loading, ok, error, unsupported }

/// Chain-authoritative execution state for a history row.
///
/// `unknown` deliberately remains distinct from `failed`: an indexer can
/// return a transfer before it has enough finality metadata, or omit status
/// fields during an outage. Neither case proves that the transaction reverted.
enum ChainTxStatus { pending, confirmed, failed, unknown }

/// One on-chain transaction, normalized for display.
class ChainTxRecord {
  const ChainTxRecord({
    required this.coin,
    this.networkId,
    required this.hash,
    required this.outgoing,
    this.id,
    this.fromAddress,
    this.toAddress,
    this.amountText,
    this.assetContract,
    this.assetSymbol,
    this.assetVerified = true,
    required this.timestamp,
    ChainTxStatus? status,
    bool? confirmed,
  }) : assert(
         status != null || confirmed != null,
         'A chain record must carry an explicit execution status.',
       ),
       assert(
         status == null ||
             confirmed == null ||
             confirmed == (status == ChainTxStatus.confirmed),
         'Legacy confirmed and status disagree.',
       ),
       status =
           status ??
           (confirmed == true ? ChainTxStatus.confirmed : ChainTxStatus.failed);

  /// Which chain this record came from. The merged cross-chain list drops the
  /// per-chain grouping, so without it the detail screen could not tell which
  /// explorer a hash belongs to.
  final Coin coin;

  /// Concrete network instance that produced this record (`eth-mainnet`,
  /// `eth-sepolia`, a custom network id, ...).
  ///
  /// Legacy snapshots may not carry it. Callers must then leave network
  /// labels, explorer links and receipt QR codes unavailable rather than
  /// guessing from the currently selected environment.
  final String? networkId;

  final String hash;

  /// Stable transfer-event identity. Unlike [hash], this distinguishes
  /// multiple token transfer logs emitted by one transaction.
  final String? id;

  /// Direction relative to the queried address (from == address → outgoing).
  final bool outgoing;

  /// Real participants exposed by the chain/indexer. Either side may remain
  /// null when a legacy source cannot prove it; callers must not invent one.
  final String? fromAddress;
  final String? toAddress;

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

  /// Exact state reported by the chain/indexer. `unknown` is never rendered or
  /// persisted as failure.
  final ChainTxStatus status;

  ChainTxRecord onNetwork(String id) => ChainTxRecord(
    coin: coin,
    networkId: id,
    hash: hash,
    id: this.id,
    outgoing: outgoing,
    fromAddress: fromAddress,
    toAddress: toAddress,
    amountText: amountText,
    assetContract: assetContract,
    assetSymbol: assetSymbol,
    assetVerified: assetVerified,
    timestamp: timestamp,
    status: status,
  );

  ChainTxRecord onNetworkIfKnown(String? id) =>
      id == null ? this : onNetwork(id);

  ChainTxRecord withStatus(ChainTxStatus value) => ChainTxRecord(
    coin: coin,
    networkId: networkId,
    hash: hash,
    id: id,
    outgoing: outgoing,
    fromAddress: fromAddress,
    toAddress: toAddress,
    amountText: amountText,
    assetContract: assetContract,
    assetSymbol: assetSymbol,
    assetVerified: assetVerified,
    timestamp: timestamp,
    status: value,
  );

  bool get confirmed => status == ChainTxStatus.confirmed;
  bool get failed => status == ChainTxStatus.failed;
  bool get pending => status == ChainTxStatus.pending;
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
  }) : _client = BoundedHttpClient(client ?? http.Client()),
       _endpoints = endpoints ?? defaultRpcEndpointFor,
       _gateway = gateway ?? _noGateway,
       _tokenRegistry = tokenRegistry ?? _mainnetTokenRegistry;

  static GatewayClient? _noGateway() => null;

  final http.Client _client;
  int _nextJsonRpcId = 0;

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
  Future<HistoryResult> fetch(
    Coin coin,
    String address, {
    int limit = pageSize,
    String? networkId,
  }) async {
    final effectiveLimit = limit.clamp(1, 100);
    final gateway = _gateway();
    if (gateway != null) {
      try {
        final history = await gateway.getHistory(
          chain: coin,
          address: address,
          limit: effectiveLimit,
        );
        if (history.unsupported) return const HistoryResult.unsupported();
        final records = [
          for (final record in history.records)
            _mapGatewayRecord(coin, record).onNetworkIfKnown(networkId),
        ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return HistoryResult.ok(
          List.unmodifiable(records.take(effectiveLimit)),
        );
      } catch (_) {
        // Gateway unreachable/erroring: fall through to direct chain APIs.
      }
    }
    final result = switch (coin) {
      Coin.tron => await _fetchTron(address, effectiveLimit),
      Coin.eth ||
      Coin.polygon ||
      Coin.base ||
      Coin.arbitrum ||
      Coin.avalanche ||
      Coin.bnb => await _fetchEvm(coin, address, effectiveLimit),
      Coin.solana => await _fetchSolana(address, effectiveLimit),
    };
    if (result.status != HistoryStatus.ok || networkId == null) return result;
    return HistoryResult.ok(
      List.unmodifiable(
        result.records.map((record) => record.onNetwork(networkId)),
      ),
    );
  }

  Future<HistoryResult> _fetchEvm(Coin coin, String address, int limit) async {
    try {
      final lower = _evmAddress(address, 'history owner').toLowerCase();
      final base = _evmHistoryApi(coin);

      Future<List<Map<Object?, Object?>>> fetchList(String action) async {
        final uri = Uri.parse(base).replace(
          queryParameters: {
            'module': 'account',
            'action': action,
            'address': address,
            'page': '1',
            'offset': '$limit',
            'sort': 'desc',
          },
        );
        final response = await _client.get(uri).timeout(timeout);
        if (response.statusCode != 200) {
          throw http.ClientException('HTTP ${response.statusCode}', uri);
        }
        final body = decodeJsonWithoutDuplicateKeys(response.body);
        final rows = _evmExplorerRows(body, limit: limit);
        return [
          for (final row in rows)
            switch (action) {
              'txlist' => _evmNormalRow(row),
              'tokentx' => _evmTokenRow(row),
              'txlistinternal' => _evmInternalRow(row),
              _ => throw const FormatException('unknown explorer action'),
            },
        ];
      }

      final results = await (
        fetchList('txlist'),
        fetchList('tokentx'),
        fetchList('txlistinternal'),
      ).wait;
      final normalItems = results.$1;
      final tokenItems = results.$2;
      final internalItems = results.$3;

      final registry = _tokenRegistry();
      final records = <ChainTxRecord>[];
      final normalMovements = <String>{};

      for (final item in normalItems) {
        _evmRowTouchesOwner(item, lower);
        normalMovements.add(_evmMovementKey(item));
      }
      for (final item in tokenItems) {
        _evmRowTouchesOwner(item, lower);
      }
      for (final item in internalItems) {
        _evmRowTouchesOwner(item, lower);
      }

      void appendNative(Map<Object?, Object?> item, {required bool internal}) {
        final hash = internal
            ? _evmInternalHash(item)
            : item['hash']! as String;
        final rawFrom = item['from']! as String;
        final rawTo = item['to']! as String;
        final from = rawFrom.toLowerCase();
        final value = BigInt.parse(item['value']! as String);
        if (value == BigInt.zero) return;
        if (internal && normalMovements.contains(_evmMovementKey(item))) {
          return;
        }
        final seconds = int.parse(item['timeStamp']! as String);
        final trace = internal ? _evmInternalTrace(item) : null;
        records.add(
          ChainTxRecord(
            coin: coin,
            id: internal ? '$hash:internal:$trace' : hash,
            hash: hash,
            outgoing: from == lower,
            fromAddress: rawFrom,
            toAddress: rawTo.isEmpty ? null : rawTo,
            amountText: _formatAmount(value, 18, _nativeSymbol(coin)),
            timestamp: DateTime.fromMillisecondsSinceEpoch(
              seconds * 1000,
              isUtc: true,
            ),
            status: _evmExplorerExecutionStatus(item),
          ),
        );
      }

      for (final item in normalItems) {
        appendNative(item, internal: false);
      }
      for (final item in internalItems) {
        appendNative(item, internal: true);
      }
      for (final (index, item) in tokenItems.indexed) {
        final hash = item['hash']! as String;
        final contract = item['contractAddress']! as String;
        final rawFrom = item['from']! as String;
        final rawTo = item['to']! as String;
        final from = rawFrom.toLowerCase();
        final seconds = int.parse(item['timeStamp']! as String);
        final raw = BigInt.parse(item['value']! as String);
        TokenInfo? official;
        for (final token in registry) {
          if (token.chain == coin &&
              token.contract.toLowerCase() == contract.toLowerCase()) {
            official = token;
            break;
          }
        }
        final claimedDecimals = int.parse(item['tokenDecimal']! as String);
        if (official != null && official.decimals != claimedDecimals) {
          throw const FormatException('official token decimals mismatch');
        }
        final claimedSymbol = (item['tokenSymbol']! as String).trim();
        final decimals = official?.decimals ?? claimedDecimals;
        final symbol =
            official?.symbol ??
            (claimedSymbol.isEmpty ? 'TOKEN' : claimedSymbol.toUpperCase());
        final logIndex = item['logIndex'] as String? ?? '$index';
        records.add(
          ChainTxRecord(
            coin: coin,
            id: '$hash:token:${contract.toLowerCase()}:$logIndex',
            hash: hash,
            outgoing: from == lower,
            fromAddress: rawFrom,
            toAddress: rawTo,
            amountText: _formatAmount(raw, decimals, symbol),
            assetContract: contract,
            assetSymbol: symbol,
            assetVerified: official != null,
            timestamp: DateTime.fromMillisecondsSinceEpoch(
              seconds * 1000,
              isUtc: true,
            ),
            status: _evmTokenTransferExecutionStatus(item),
          ),
        );
      }

      records.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final seen = <String>{};
      final deduped = records
          .where((record) {
            return seen.add(record.id ?? record.hash);
          })
          .take(limit);
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

  /// Etherscan-compatible providers are inconsistent about which execution
  /// field they include. Missing evidence is not success, and contradictory
  /// fields are not proof of either terminal outcome.
  ChainTxStatus _evmExplorerExecutionStatus(Map<dynamic, dynamic> item) {
    final evidence = <ChainTxStatus>{};
    final isError = item['isError'];
    if (isError != null) {
      switch ('$isError'.trim()) {
        case '0':
          evidence.add(ChainTxStatus.confirmed);
        case '1':
          evidence.add(ChainTxStatus.failed);
      }
    }
    final receipt = item['txreceipt_status'];
    if (receipt != null) {
      switch ('$receipt'.trim()) {
        case '1':
          evidence.add(ChainTxStatus.confirmed);
        case '0':
          evidence.add(ChainTxStatus.failed);
      }
    }
    if (evidence.length != 1) return ChainTxStatus.unknown;
    return evidence.single;
  }

  /// Token-transfer endpoints return receipt log events, not arbitrary
  /// transactions. Their documented rows omit `isError` and
  /// `txreceipt_status`; a canonical indexed block location is therefore
  /// positive execution evidence. Explicit status fields still take
  /// precedence, and malformed or contradictory values remain unknown.
  ChainTxStatus _evmTokenTransferExecutionStatus(Map<dynamic, dynamic> item) {
    if (item.containsKey('isError') || item.containsKey('txreceipt_status')) {
      return _evmExplorerExecutionStatus(item);
    }
    final blockNumber = BigInt.tryParse('${item['blockNumber'] ?? ''}');
    final transactionIndex = int.tryParse('${item['transactionIndex'] ?? ''}');
    final confirmations = BigInt.tryParse('${item['confirmations'] ?? ''}');
    if (blockNumber == null ||
        blockNumber <= BigInt.zero ||
        transactionIndex == null ||
        transactionIndex < 0 ||
        confirmations == null ||
        confirmations.isNegative ||
        !_isEvmBlockHash(item['blockHash'])) {
      return ChainTxStatus.unknown;
    }
    return ChainTxStatus.confirmed;
  }

  bool _isEvmBlockHash(Object? raw) {
    if (raw is! String) return false;
    final value = raw.trim();
    if (value.length != 66 || !value.startsWith('0x')) return false;
    for (final codeUnit in value.codeUnits.skip(2)) {
      final digit = codeUnit >= 0x30 && codeUnit <= 0x39;
      final lower = codeUnit >= 0x61 && codeUnit <= 0x66;
      final upper = codeUnit >= 0x41 && codeUnit <= 0x46;
      if (!digit && !lower && !upper) return false;
    }
    return true;
  }

  Future<HistoryResult> _fetchSolana(String address, int limit) async {
    try {
      _solanaPublicKey(address, 'history owner');
      final rpc = _endpoints(Coin.solana);
      final bySignature = <String, _SolanaHistoryCandidate>{};

      Future<void> collectSignatures(String account) async {
        _solanaPublicKey(account, 'history account');
        final result = await _solanaCall(rpc, 'getSignaturesForAddress', [
          account,
          {'commitment': 'confirmed', 'limit': limit},
        ]);
        if (result is! List || result.length > limit) {
          throw const FormatException('bad signatures');
        }
        for (final raw in result) {
          final item = _parseSolanaSignatureRow(raw);
          final existing = bySignature[item.signature];
          if (existing == null) {
            bySignature[item.signature] = _SolanaHistoryCandidate(
              evidence: item,
              queriedAccounts: {account},
            );
          } else {
            if (!existing.evidence.sameEvidence(item)) {
              throw const FormatException('conflicting signature evidence');
            }
            existing.queriedAccounts.add(account);
          }
        }
      }

      // The owner account is not required to appear in an incoming SPL
      // transfer. Query each owned ATA as well, otherwise token deposits can
      // be invisible even though the balance is already present.
      await collectSignatures(address);
      final tokenAccounts = <String>{};
      for (final program in [solanaTokenProgram, solanaToken2022Program]) {
        final result = await _solanaCall(rpc, 'getTokenAccountsByOwner', [
          address,
          {'programId': program},
          {'encoding': 'jsonParsed', 'commitment': 'confirmed'},
        ]);
        for (final account in _parseSolanaOwnedTokenAccounts(
          result,
          owner: address,
          tokenProgram: program,
        )) {
          if (!tokenAccounts.add(account)) {
            throw const FormatException(
              'token account returned by multiple programs',
            );
          }
        }
      }
      if (tokenAccounts.length > 16) {
        // Returning only the first accounts would turn an incomplete history
        // into an authoritative empty/complete result. The Gateway indexer is
        // the supported path for larger portfolios.
        throw const FormatException('too many token accounts for direct mode');
      }
      await Future.wait([
        for (final account in tokenAccounts) collectSignatures(account),
      ]);

      final signatures = bySignature.values.toList()
        ..sort((a, b) {
          final left = a.evidence.blockTime ?? 0;
          final right = b.evidence.blockTime ?? 0;
          return right.compareTo(left);
        });
      final records = <ChainTxRecord>[];
      for (final candidate in signatures.take(limit * 3)) {
        final signature = candidate.evidence.signature;
        final transaction = await _solanaCall(rpc, 'getTransaction', [
          signature,
          {
            'encoding': 'jsonParsed',
            'maxSupportedTransactionVersion': 0,
            'commitment': 'confirmed',
          },
        ]);
        final parsed = _parseSolanaHistoryTransaction(
          transaction,
          candidate: candidate,
        );
        final timestamp = DateTime.fromMillisecondsSinceEpoch(
          parsed.blockTime * 1000,
          isUtc: true,
        );
        final tokenDeltas = _solanaTokenDeltas(parsed.meta, address);
        if (tokenDeltas.isNotEmpty) {
          for (final entry in tokenDeltas.entries) {
            final delta = entry.value.amount;
            if (delta == BigInt.zero) continue;
            final parties = _solanaTransferParties(
              parsed.message,
              parsed.meta,
              address,
              mint: entry.key,
            );
            final official = _findSolanaToken(entry.key);
            final symbol = official?.symbol ?? 'SPL';
            final decimals = official?.decimals ?? entry.value.decimals;
            records.add(
              ChainTxRecord(
                coin: Coin.solana,
                id: '$signature:spl:${entry.key}',
                hash: signature,
                outgoing: delta.isNegative,
                fromAddress:
                    parties.from ?? (delta.isNegative ? address : null),
                toAddress: parties.to ?? (delta.isNegative ? null : address),
                amountText: _formatAmount(delta.abs(), decimals, symbol),
                assetContract: entry.key,
                assetSymbol: symbol,
                assetVerified: official != null,
                timestamp: timestamp,
                status: parsed.status,
              ),
            );
          }
        } else {
          final transfer = _solanaNativeTransfer(parsed, address);
          if (transfer == null || transfer.amount == BigInt.zero) continue;
          records.add(
            ChainTxRecord(
              coin: Coin.solana,
              id: signature,
              hash: signature,
              outgoing: transfer.amount.isNegative,
              fromAddress: transfer.from,
              toAddress: transfer.to,
              amountText: _formatAmount(transfer.amount.abs(), 9, 'SOL'),
              timestamp: timestamp,
              status: parsed.status,
            ),
          );
        }
        if (records.length >= limit) break;
      }
      records.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return HistoryResult.ok(List.unmodifiable(records.take(limit)));
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
        if (existing != null && existing.decimals != decimals) {
          throw const FormatException('token decimals changed within balance');
        }
        final total = (existing?.amount ?? BigInt.zero) + raw;
        if (total > _solanaMaximumU64) {
          throw const FormatException('token owner balance overflow');
        }
        target[mint] = (amount: total, decimals: decimals);
      }
    }

    collect(meta['preTokenBalances'], before);
    collect(meta['postTokenBalances'], after);
    final deltas = <String, ({BigInt amount, int decimals})>{};
    for (final mint in {...before.keys, ...after.keys}) {
      final previous = before[mint];
      final current = after[mint];
      if (previous != null &&
          current != null &&
          previous.decimals != current.decimals) {
        throw const FormatException(
          'token decimals changed across transaction',
        );
      }
      final decimals = current?.decimals ?? previous?.decimals ?? 0;
      final amount =
          (current?.amount ?? BigInt.zero) - (previous?.amount ?? BigInt.zero);
      if (amount != BigInt.zero) {
        deltas[mint] = (amount: amount, decimals: decimals);
      }
    }
    return deltas;
  }

  /// Extracts wallet-level participants from parsed System/SPL transfer
  /// instructions. SPL instructions carry token-account addresses, so the
  /// pre/post balance owner metadata is used to resolve those back to wallets.
  ({String? from, String? to}) _solanaTransferParties(
    Map<dynamic, dynamic> message,
    Map<dynamic, dynamic> meta,
    String owner, {
    String? mint,
  }) {
    final rawKeys = message['accountKeys'];
    if (rawKeys is! List) return (from: null, to: null);
    final keys = [
      for (final key in rawKeys)
        if (key is String)
          key
        else if (key is Map && key['pubkey'] is String)
          key['pubkey'] as String
        else
          '',
    ];
    final tokenAccounts = <String, ({String owner, String mint})>{};
    void collectOwners(Object? rows) {
      if (rows is! List) return;
      for (final row in rows) {
        if (row is! Map ||
            row['accountIndex'] is! int ||
            row['owner'] is! String ||
            row['mint'] is! String) {
          continue;
        }
        final index = row['accountIndex'] as int;
        if (index >= 0 && index < keys.length && keys[index].isNotEmpty) {
          tokenAccounts[keys[index]] = (
            owner: row['owner'] as String,
            mint: row['mint'] as String,
          );
        }
      }
    }

    collectOwners(meta['preTokenBalances']);
    collectOwners(meta['postTokenBalances']);

    final instructions = message['instructions'];
    if (instructions is! List) return (from: null, to: null);
    for (final instruction in instructions) {
      if (instruction is! Map || instruction['parsed'] is! Map) continue;
      final program = instruction['program'];
      if (program != 'spl-token' && program != 'spl-token-2022') continue;
      final parsed = instruction['parsed'] as Map;
      if (parsed['type'] != 'transfer' && parsed['type'] != 'transferChecked') {
        continue;
      }
      final info = parsed['info'];
      if (info is! Map) continue;
      String source;
      String destination;
      try {
        source = _solanaPublicKey(info['source'], 'token transfer source');
        destination = _solanaPublicKey(
          info['destination'],
          'token transfer destination',
        );
      } catch (_) {
        continue;
      }
      final sourceAccount = tokenAccounts[source];
      final destinationAccount = tokenAccounts[destination];
      if (mint != null &&
          sourceAccount?.mint != mint &&
          destinationAccount?.mint != mint) {
        continue;
      }
      String? authority;
      try {
        if (info['authority'] != null) {
          authority = _solanaPublicKey(
            info['authority'],
            'token transfer authority',
          );
        }
      } catch (_) {
        authority = null;
      }
      final from = sourceAccount?.owner ?? authority;
      final to = destinationAccount?.owner;
      if (from == owner || to == owner) return (from: from, to: to);
    }
    return (from: null, to: null);
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
    final request = <String, Object?>{
      'jsonrpc': '2.0',
      'id': ++_nextJsonRpcId,
      'method': method,
      'params': params,
    };
    final response = await _client
        .post(
          uri,
          headers: const {'content-type': 'application/json'},
          body: jsonEncode(request),
        )
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw http.ClientException('HTTP ${response.statusCode}', uri);
    }
    final body = decodeJsonWithoutDuplicateKeys(response.body);
    if (!isBoundJsonRpcResponse(request, body) ||
        body is! Map ||
        body.containsKey('error')) {
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
      fromAddress: record.fromAddress,
      toAddress: record.toAddress,
      amountText: raw != null && decimals != null && symbol != null
          ? _formatAmount(raw, decimals, symbol)
          : null,
      assetContract: record.contract,
      assetSymbol: symbol,
      assetVerified: record.verified,
      timestamp: DateTime.fromMillisecondsSinceEpoch(record.timestampMs),
      status: switch (record.status) {
        GatewayTransactionStatus.confirmed => ChainTxStatus.confirmed,
        GatewayTransactionStatus.failed => ChainTxStatus.failed,
        GatewayTransactionStatus.pending => ChainTxStatus.pending,
        GatewayTransactionStatus.unknown => ChainTxStatus.unknown,
      },
    );
  }

  /// TRC-20, TRX/TRC-10 and contract-created internal transfers, fetched
  /// concurrently and merged newest-first.
  Future<HistoryResult> _fetchTron(String address, int limit) async {
    try {
      final validation = Addresses.validate(Chain.tron, address);
      if (!validation.isValid) {
        throw const FormatException('invalid TRON history owner');
      }
      final myHex = tronAddressHex(address);
      if (myHex == null) {
        throw const FormatException('invalid TRON history owner');
      }
      final (trc20, native, internal) = await (
        _getTronData(
          '$tronApiUrl/v1/accounts/$address/transactions/trc20'
          '?limit=$limit&only_confirmed=true&order_by=block_timestamp,desc',
          limit,
        ),
        _getTronData(
          '$tronApiUrl/v1/accounts/$address/transactions'
          '?limit=$limit&only_confirmed=true&order_by=block_timestamp,desc',
          limit,
        ),
        _getTronData(
          '$tronApiUrl/v1/accounts/$address/internal-transactions'
          '?limit=$limit&only_confirmed=true&order_by=block_timestamp,desc',
          limit,
        ),
      ).wait;

      final records = <ChainTxRecord>[];
      for (final item in trc20) {
        final record = _parseTrc20(item, address, myHex);
        if (record != null) records.add(record);
      }
      for (final item in native) {
        records.addAll(_parseNative(item, myHex, address));
      }
      for (final item in internal) {
        records.addAll(_parseTronInternal(item, myHex, address));
      }
      records.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final seen = <String>{};
      final deduped = records
          .where((record) {
            return seen.add(record.id ?? record.hash);
          })
          .take(limit);
      return HistoryResult.ok(List.unmodifiable(deduped));
    } catch (_) {
      // ClientException / TimeoutException / FormatException / a 4xx for the
      // Invalid or checksum-failing addresses mean "no trustworthy history".
      return const HistoryResult.error();
    }
  }

  /// GETs one TronGrid history endpoint and returns its complete first page.
  /// Duplicate/unknown members, provider-declared failure and pages larger
  /// than the requested limit all fail closed.
  Future<List<Map<Object?, Object?>>> _getTronData(
    String url,
    int limit,
  ) async {
    final resp = await _client.get(Uri.parse(url)).timeout(timeout);
    if (resp.statusCode != 200) {
      throw http.ClientException('HTTP ${resp.statusCode}', Uri.parse(url));
    }
    return _tronHistoryRows(
      decodeJsonWithoutDuplicateKeys(resp.body),
      limit: limit,
    );
  }

  /// One item of `/v1/accounts/{addr}/transactions/trc20`:
  /// `{transaction_id, token_info: {symbol, decimals, ...}, block_timestamp,
  ///   from, to, type, value}` (addresses in base58).
  ChainTxRecord? _parseTrc20(
    Map<Object?, Object?> raw,
    String address,
    String myHex,
  ) {
    final item = _tronExactMap(
      raw,
      allowed: const {
        'transaction_id',
        'token_info',
        'block_timestamp',
        'from',
        'to',
        'type',
        'value',
      },
      required: const {'type'},
      schema: 'TRC-20 history row',
    );
    final type = _tronRequiredString(item, 'type');
    _tronText(type, 'TRC-20 event type', 64);
    // Approval and NFT events are not fungible asset movements.
    if (type != 'Transfer') return null;

    final hash = _tronTransactionId(
      _tronRequiredString(item, 'transaction_id'),
      'TRC-20 transaction id',
    );
    final from = _tronRequiredString(item, 'from');
    final to = _tronRequiredString(item, 'to');
    final fromHex = _tronAddressHexStrict(from, 'TRC-20 sender');
    final toHex = _tronAddressHexStrict(to, 'TRC-20 recipient');
    if (fromHex != myHex && toHex != myHex) {
      throw const FormatException('TRC-20 row is not bound to owner');
    }
    final valueText = _tronRequiredString(item, 'value');
    final value = _tronUint(valueText, 256, 'TRC-20 value');
    final ts = _tronTimestampMs(item['block_timestamp']);

    final info = _tronExactMap(
      item['token_info'],
      allowed: const {'symbol', 'address', 'decimals', 'name'},
      required: const {'symbol', 'address', 'decimals'},
      schema: 'TRC-20 token info',
    );
    final claimedSymbol = _tronRequiredString(info, 'symbol');
    _tronText(claimedSymbol, 'TRC-20 token symbol', 128, allowEmpty: true);
    if (info.containsKey('name')) {
      _tronText(
        _tronRequiredString(info, 'name'),
        'TRC-20 token name',
        256,
        allowEmpty: true,
      );
    }
    final contract = _tronRequiredString(info, 'address');
    _tronAddressHexStrict(contract, 'TRC-20 contract');
    final claimedDecimals = _tronUint(
      info['decimals'],
      8,
      'TRC-20 decimals',
    ).toInt();
    if (claimedDecimals > Amount.maxDecimals) {
      throw const FormatException('unsupported TRC-20 decimals');
    }

    TokenInfo? official;
    for (final token in _tokenRegistry()) {
      if (token.chain == Coin.tron && token.contract == contract) {
        official = token;
        break;
      }
    }
    if (official != null && official.decimals != claimedDecimals) {
      throw const FormatException('official TRC-20 decimals mismatch');
    }
    final decimals = official?.decimals ?? claimedDecimals;
    final symbol =
        official?.symbol ??
        (claimedSymbol.isEmpty ? 'TOKEN' : claimedSymbol.toUpperCase());
    final amountText = _formatAmount(value, decimals, symbol);
    if (amountText == null) {
      throw const FormatException('unrenderable TRC-20 amount');
    }
    return ChainTxRecord(
      coin: Coin.tron,
      id: _tronTrc20EventId(hash, contract, from, to, valueText),
      hash: hash,
      outgoing: fromHex == myHex,
      fromAddress: fromHex == myHex ? address : _tronDisplayAddress(from),
      toAddress: toHex == myHex ? address : _tronDisplayAddress(to),
      amountText: amountText,
      assetContract: contract,
      assetSymbol: symbol,
      assetVerified: official != null,
      timestamp: DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true),
      // The trc20 endpoint serves confirmed transfer events.
      confirmed: true,
    );
  }

  /// One item of `/v1/accounts/{addr}/transactions`:
  /// `{txID, ret: [{contractRet}], block_timestamp, raw_data: {contract:
  ///   [{type, parameter: {value: {amount, owner_address, to_address}}}]}}`
  /// (addresses in 41-prefixed hex). Supports native TRX TransferContract and
  /// TRC-10 TransferAssetContract; TRC-20 events come from their own endpoint.
  List<ChainTxRecord> _parseNative(
    Map<Object?, Object?> raw,
    String myHex,
    String myAddress,
  ) {
    final item = _tronExactMap(
      raw,
      allowed: const {
        'ret',
        'signature',
        'txID',
        'net_usage',
        'raw_data_hex',
        'net_fee',
        'energy_usage',
        'blockNumber',
        'block_timestamp',
        'energy_fee',
        'energy_usage_total',
        'raw_data',
        'internal_transactions',
        'fee_limit',
        'ref_block_bytes',
        'ref_block_hash',
        'expiration',
        'timestamp',
      },
      required: const {'txID', 'block_timestamp', 'raw_data'},
      schema: 'TRON native history row',
    );
    final hash = _tronTransactionId(
      _tronRequiredString(item, 'txID'),
      'TRON transaction id',
    );
    final ts = _tronTimestampMs(item['block_timestamp']);
    final status = _tronContractExecutionStatus(item);
    final rawData = _tronExactMap(
      item['raw_data'],
      allowed: const {
        'contract',
        'ref_block_bytes',
        'ref_block_hash',
        'expiration',
        'timestamp',
        'fee_limit',
        'data',
      },
      required: const {'contract'},
      schema: 'TRON raw transaction',
    );
    final contracts = rawData['contract'];
    if (contracts is! List || contracts.length > 64) {
      throw const FormatException('invalid TRON contract list');
    }
    final records = <ChainTxRecord>[];
    for (final (index, rawContract) in contracts.indexed) {
      final contract = _tronExactMap(
        rawContract,
        allowed: const {'parameter', 'type', 'Permission_id', 'permission_id'},
        required: const {'parameter', 'type'},
        schema: 'TRON transaction contract',
      );
      if (contract.containsKey('Permission_id') &&
          contract.containsKey('permission_id')) {
        throw const FormatException('ambiguous TRON permission id');
      }
      final type = _tronRequiredString(contract, 'type');
      _tronText(type, 'TRON contract type', 128);
      final parameter = _tronExactMap(
        contract['parameter'],
        allowed: const {'value', 'type_url'},
        required: const {'value'},
        schema: 'TRON contract parameter',
      );
      final valueRaw = parameter['value'];
      if (valueRaw is! Map) {
        throw const FormatException('invalid TRON contract value');
      }
      if (type != 'TransferContract' && type != 'TransferAssetContract') {
        continue;
      }
      if (parameter.containsKey('type_url')) {
        final typeUrl = _tronRequiredString(parameter, 'type_url');
        if (typeUrl != 'type.googleapis.com/protocol.$type') {
          throw const FormatException('mismatched TRON contract type URL');
        }
      }
      final value = _tronExactMap(
        valueRaw,
        allowed: const {'amount', 'owner_address', 'to_address', 'asset_name'},
        required: const {'amount', 'owner_address', 'to_address'},
        schema: 'TRON transfer value',
      );
      final amount = _tronUint(value['amount'], 63, 'TRON transfer amount');
      final owner = _tronRequiredString(value, 'owner_address');
      final recipient = _tronRequiredString(value, 'to_address');
      final ownerHex = _tronAddressHexStrict(owner, 'TRON transfer sender');
      final recipientHex = _tronAddressHexStrict(
        recipient,
        'TRON transfer recipient',
      );
      if (ownerHex != myHex && recipientHex != myHex) {
        throw const FormatException('TRON transfer is not bound to owner');
      }
      var tokenId = '';
      if (type == 'TransferAssetContract') {
        tokenId = _tronRequiredString(value, 'asset_name');
        _tronUint(tokenId, 64, 'TRC-10 token id');
      } else if (value.containsKey('asset_name')) {
        throw const FormatException('TRX transfer carries asset id');
      }
      final isTrc10 = tokenId.isNotEmpty;
      var id = hash;
      if (index > 0) id += ':contract:$index';
      if (isTrc10) id += ':trc10:$tokenId';
      records.add(
        ChainTxRecord(
          coin: Coin.tron,
          id: id,
          hash: hash,
          outgoing: ownerHex == myHex,
          fromAddress: ownerHex == myHex
              ? myAddress
              : _tronDisplayAddress(owner),
          toAddress: recipientHex == myHex
              ? myAddress
              : _tronDisplayAddress(recipient),
          amountText: _formatAmount(
            amount,
            isTrc10 ? 0 : 6,
            isTrc10 ? 'TRC10' : 'TRX',
          ),
          assetContract: isTrc10 ? tokenId : null,
          assetSymbol: isTrc10 ? 'TRC10' : null,
          assetVerified: !isTrc10,
          timestamp: DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true),
          status: status,
        ),
      );
    }
    return records;
  }

  ChainTxStatus _tronContractExecutionStatus(Map<Object?, Object?> item) {
    if (!item.containsKey('ret')) return ChainTxStatus.unknown;
    final ret = item['ret'];
    if (ret is! List || ret.length > 64) {
      throw const FormatException('invalid TRON receipt list');
    }
    if (ret.isEmpty) return ChainTxStatus.unknown;
    var status = ChainTxStatus.confirmed;
    for (final raw in ret) {
      final row = _tronExactMap(
        raw,
        allowed: const {'contractRet', 'fee'},
        required: const {'contractRet'},
        schema: 'TRON receipt',
      );
      final result = _tronRequiredString(
        row,
        'contractRet',
      ).trim().toUpperCase();
      if (!_tronReceiptResults.contains(result)) {
        throw const FormatException('unknown TRON receipt result');
      }
      if (result != 'SUCCESS') status = ChainTxStatus.failed;
      if (row.containsKey('fee')) {
        _tronUint(row['fee'], 63, 'TRON receipt fee');
      }
    }
    return status;
  }

  List<ChainTxRecord> _parseTronInternal(
    Map<Object?, Object?> raw,
    String myHex,
    String myAddress,
  ) {
    final item = _tronExactMap(
      raw,
      allowed: const {
        'internal_tx_id',
        'data',
        'block_timestamp',
        'to_address',
        'tx_id',
        'from_address',
      },
      required: const {
        'internal_tx_id',
        'data',
        'block_timestamp',
        'to_address',
        'tx_id',
        'from_address',
      },
      schema: 'TRON internal history row',
    );
    final hash = _tronTransactionId(
      _tronRequiredString(item, 'tx_id'),
      'TRON internal parent id',
    );
    final internalId = _tronTransactionId(
      _tronRequiredString(item, 'internal_tx_id'),
      'TRON internal trace id',
    );
    final from = _tronRequiredString(item, 'from_address');
    final to = _tronRequiredString(item, 'to_address');
    final fromHex = _tronAddressHexStrict(from, 'TRON internal sender');
    final toHex = _tronAddressHexStrict(to, 'TRON internal recipient');
    if (fromHex != myHex && toHex != myHex) {
      throw const FormatException('TRON internal row is not bound to owner');
    }
    final timestamp = _tronTimestampMs(item['block_timestamp']);
    final data = _tronExactMap(
      item['data'],
      allowed: const {
        'note',
        'rejected',
        'call_value',
        'call_token_value',
        'token_id',
      },
      required: const {},
      schema: 'TRON internal data',
    );
    if (data.containsKey('note')) {
      _tronText(
        _tronRequiredString(data, 'note'),
        'TRON internal note',
        256,
        allowEmpty: true,
      );
    }
    final status = switch (data['rejected']) {
      null => ChainTxStatus.unknown,
      false => ChainTxStatus.confirmed,
      true => ChainTxStatus.failed,
      _ => throw const FormatException('invalid TRON rejected flag'),
    };
    final trx = _tronOptionalScalar(
      data['call_value'],
      63,
      'TRON internal TRX value',
    );
    final token = _tronOptionalScalar(
      data['call_token_value'],
      63,
      'TRON internal token value',
    );
    final tokenIdValue = _tronOptionalScalar(
      data['token_id'],
      64,
      'TRON internal token id',
    );
    if (token != null &&
        token != BigInt.zero &&
        (tokenIdValue == null || tokenIdValue == BigInt.zero)) {
      throw const FormatException('missing TRON internal token id');
    }
    final records = <ChainTxRecord>[];
    ChainTxRecord record(BigInt amount, {String? tokenId}) {
      final isTrc10 = tokenId != null;
      var id = '$hash:internal:$internalId';
      if (isTrc10) id += ':trc10:$tokenId';
      return ChainTxRecord(
        coin: Coin.tron,
        id: id,
        hash: hash,
        outgoing: fromHex == myHex,
        fromAddress: fromHex == myHex ? myAddress : _tronDisplayAddress(from),
        toAddress: toHex == myHex ? myAddress : _tronDisplayAddress(to),
        amountText: _formatAmount(
          amount,
          isTrc10 ? 0 : 6,
          isTrc10 ? 'TRC10' : 'TRX',
        ),
        assetContract: tokenId,
        assetSymbol: isTrc10 ? 'TRC10' : null,
        assetVerified: !isTrc10,
        timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true),
        status: status,
      );
    }

    if (trx != null && trx != BigInt.zero) records.add(record(trx));
    if (token != null && token != BigInt.zero) {
      records.add(record(token, tokenId: tokenIdValue.toString()));
    }
    return records;
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

const Set<String> _tronReceiptResults = {
  'SUCCESS',
  'REVERT',
  'BAD_JUMP_DESTINATION',
  'OUT_OF_MEMORY',
  'PRECOMPILED_CONTRACT',
  'STACK_TOO_SMALL',
  'STACK_TOO_LARGE',
  'ILLEGAL_OPERATION',
  'STACK_OVERFLOW',
  'OUT_OF_ENERGY',
  'OUT_OF_TIME',
  'JVM_STACK_OVER_FLOW',
  'TRANSFER_FAILED',
  'INVALID_CODE',
};

List<Map<Object?, Object?>> _tronHistoryRows(
  Object? raw, {
  required int limit,
}) {
  final envelope = _tronExactMap(
    raw,
    allowed: const {'data', 'success', 'meta'},
    required: const {'data', 'success'},
    schema: 'TronGrid history envelope',
  );
  if (envelope['success'] != true) {
    throw const FormatException('TronGrid history was not successful');
  }
  final data = envelope['data'];
  if (data is! List || data.length > limit) {
    throw const FormatException('invalid TronGrid history data');
  }
  if (envelope.containsKey('meta')) {
    final meta = _tronExactMap(
      envelope['meta'],
      allowed: const {'at', 'page_size', 'fingerprint', 'links'},
      required: const {},
      schema: 'TronGrid history meta',
    );
    for (final key in const ['at', 'page_size']) {
      if (meta.containsKey(key)) {
        _tronUint(meta[key], 64, 'TronGrid meta $key');
      }
    }
    if (meta.containsKey('fingerprint')) {
      _tronText(
        _tronRequiredString(meta, 'fingerprint'),
        'TronGrid fingerprint',
        2048,
      );
    }
    if (meta.containsKey('links')) {
      final links = _tronExactMap(
        meta['links'],
        allowed: const {'next'},
        required: const {'next'},
        schema: 'TronGrid history links',
      );
      _tronText(_tronRequiredString(links, 'next'), 'TronGrid next link', 8192);
    }
  }
  final rows = <Map<Object?, Object?>>[];
  for (final row in data) {
    if (row is! Map || row.keys.any((key) => key is! String)) {
      throw const FormatException('bad TronGrid history row');
    }
    rows.add(row);
  }
  return rows;
}

Map<Object?, Object?> _tronExactMap(
  Object? raw, {
  required Set<String> allowed,
  required Set<String> required,
  required String schema,
}) {
  if (raw is! Map ||
      raw.keys.any((key) => key is! String || !allowed.contains(key)) ||
      required.any((key) => !raw.containsKey(key))) {
    throw FormatException('bad $schema');
  }
  return raw;
}

String _tronRequiredString(Map<Object?, Object?> row, String key) {
  final value = row[key];
  if (value is! String) throw FormatException('bad TronGrid field $key');
  return value;
}

BigInt _tronUint(Object? raw, int bits, String label) {
  final value = switch (raw) {
    final int number when number >= 0 => '$number',
    final String text => text,
    _ => throw FormatException('bad $label'),
  };
  if (value.isEmpty || value.length > 78) throw FormatException('bad $label');
  for (final code in value.codeUnits) {
    if (code < 0x30 || code > 0x39) throw FormatException('bad $label');
  }
  final parsed = BigInt.tryParse(value);
  if (parsed == null || parsed.isNegative || parsed.bitLength > bits) {
    throw FormatException('bad $label');
  }
  return parsed;
}

BigInt? _tronOptionalScalar(Object? raw, int bits, String label) {
  if (raw == null) return null;
  Object? value = raw;
  if (value is Map) {
    final scalar = _tronExactMap(
      value,
      allowed: const {'_'},
      required: const {'_'},
      schema: '$label scalar',
    );
    value = scalar['_'];
  }
  return _tronUint(value, bits, label);
}

int _tronTimestampMs(Object? raw) {
  final value = _tronUint(raw, 63, 'TronGrid timestamp');
  if (value == BigInt.zero || value > BigInt.from(253402300799999)) {
    throw const FormatException('bad TronGrid timestamp');
  }
  return value.toInt();
}

String _tronTransactionId(String value, String label) {
  if (value.length != 64) throw FormatException('bad $label');
  for (final code in value.codeUnits) {
    final digit = code >= 0x30 && code <= 0x39;
    final lower = code >= 0x61 && code <= 0x66;
    final upper = code >= 0x41 && code <= 0x46;
    if (!digit && !lower && !upper) throw FormatException('bad $label');
  }
  return value;
}

String _tronAddressHexStrict(String value, String label) {
  final normalized = value;
  if (normalized.length == 42 && normalized.toLowerCase().startsWith('41')) {
    for (final code in normalized.codeUnits) {
      final digit = code >= 0x30 && code <= 0x39;
      final lower = code >= 0x61 && code <= 0x66;
      final upper = code >= 0x41 && code <= 0x46;
      if (!digit && !lower && !upper) throw FormatException('bad $label');
    }
    return normalized.toLowerCase();
  }
  final validation = Addresses.validate(Chain.tron, normalized);
  final hex = validation.isValid ? tronAddressHex(normalized) : null;
  if (hex == null) throw FormatException('bad $label');
  return hex;
}

String _tronDisplayAddress(String value) =>
    tronHexAddressToBase58(value) ?? value;

void _tronText(
  String value,
  String label,
  int maxBytes, {
  bool allowEmpty = false,
}) {
  if ((!allowEmpty && value.isEmpty) || utf8.encode(value).length > maxBytes) {
    throw FormatException('bad $label');
  }
  for (final rune in value.runes) {
    if (rune < 0x20 || rune == 0x7f) throw FormatException('bad $label');
  }
}

String _tronTrc20EventId(
  String hash,
  String contract,
  String from,
  String to,
  String value,
) {
  final digest = sha256(
    utf8.encode([hash.toLowerCase(), contract, from, to, value].join('\u0000')),
  );
  final suffix = digest
      .take(8)
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '$hash:trc20:$contract:$suffix';
}

const Set<String> _evmNormalFields = {
  'blockNumber',
  'blockHash',
  'timeStamp',
  'hash',
  'nonce',
  'transactionIndex',
  'from',
  'to',
  'value',
  'gas',
  'gasPrice',
  'input',
  'methodId',
  'functionName',
  'contractAddress',
  'cumulativeGasUsed',
  'txreceipt_status',
  'gasUsed',
  'confirmations',
  'isError',
  'maxFeePerGas',
  'maxPriorityFeePerGas',
  'type',
  'l1Fee',
  'l1GasPrice',
  'l1GasUsed',
  'l1FeeScalar',
  'blobGasUsed',
  'blobGasPrice',
  'authorizationList',
};

const Set<String> _evmTokenFields = {
  'blockNumber',
  'timeStamp',
  'hash',
  'nonce',
  'blockHash',
  'from',
  'contractAddress',
  'to',
  'value',
  'tokenName',
  'tokenSymbol',
  'tokenDecimal',
  'transactionIndex',
  'gas',
  'gasPrice',
  'gasUsed',
  'cumulativeGasUsed',
  'input',
  'methodId',
  'functionName',
  'confirmations',
  'logIndex',
  'isError',
  'txreceipt_status',
  'maxFeePerGas',
  'maxPriorityFeePerGas',
  'type',
  'l1Fee',
  'l1GasPrice',
  'l1GasUsed',
  'l1FeeScalar',
  'blobGasUsed',
  'blobGasPrice',
  'authorizationList',
};

const Set<String> _evmInternalFields = {
  'blockNumber',
  'timeStamp',
  'hash',
  'transactionHash',
  'from',
  'to',
  'value',
  'contractAddress',
  'input',
  'type',
  'callType',
  'gas',
  'gasUsed',
  'traceId',
  'index',
  'isError',
  'txreceipt_status',
  'errCode',
};

List<Object?> _evmExplorerRows(Object? raw, {required int limit}) {
  final envelope = _evmExactMap(
    raw,
    allowed: const {'status', 'message', 'result'},
    required: const {'status', 'message', 'result'},
    schema: 'explorer envelope',
  );
  final status = _evmRequiredString(envelope, 'status');
  final message = _evmRequiredString(envelope, 'message');
  final result = envelope['result'];
  if (message.length > 256 || result is! List || result.length > limit) {
    throw const FormatException('bad explorer envelope');
  }
  if (status == '1' && message == 'OK') return result;
  if (status == '0' && message == 'No transactions found' && result.isEmpty) {
    return result;
  }
  throw const FormatException('explorer rejected request');
}

Map<Object?, Object?> _evmNormalRow(Object? raw) {
  final row = _evmExactMap(
    raw,
    allowed: _evmNormalFields,
    required: const {'hash', 'from', 'to', 'value', 'timeStamp'},
    schema: 'normal transaction',
  );
  _evmHash(_evmRequiredString(row, 'hash'), 'transaction hash');
  _evmAddress(_evmRequiredString(row, 'from'), 'transaction sender');
  _evmAddress(
    _evmRequiredString(row, 'to'),
    'transaction recipient',
    allowEmpty: true,
  );
  _evmUnsignedDecimal(_evmRequiredString(row, 'value'), 'transaction value');
  _evmTimestamp(_evmRequiredString(row, 'timeStamp'));
  _evmOptionalExecutionFlag(row, 'isError');
  _evmOptionalExecutionFlag(row, 'txreceipt_status');
  return row;
}

Map<Object?, Object?> _evmTokenRow(Object? raw) {
  final row = _evmExactMap(
    raw,
    allowed: _evmTokenFields,
    required: const {
      'blockNumber',
      'timeStamp',
      'hash',
      'blockHash',
      'from',
      'to',
      'value',
      'tokenSymbol',
      'tokenDecimal',
      'contractAddress',
      'transactionIndex',
      'confirmations',
    },
    schema: 'token transaction',
  );
  final block = _evmUnsigned64(
    _evmRequiredString(row, 'blockNumber'),
    'token block number',
  );
  if (block == BigInt.zero) {
    throw const FormatException('bad token block number');
  }
  _evmTimestamp(_evmRequiredString(row, 'timeStamp'));
  _evmHash(_evmRequiredString(row, 'hash'), 'token transaction hash');
  _evmHash(_evmRequiredString(row, 'blockHash'), 'token block hash');
  _evmAddress(_evmRequiredString(row, 'from'), 'token sender');
  _evmAddress(_evmRequiredString(row, 'to'), 'token recipient');
  _evmAddress(_evmRequiredString(row, 'contractAddress'), 'token contract');
  _evmUnsignedDecimal(_evmRequiredString(row, 'value'), 'token value');
  _evmText(_evmRequiredString(row, 'tokenSymbol'), 'token symbol', 128);
  final decimals = _evmUnsigned64(
    _evmRequiredString(row, 'tokenDecimal'),
    'token decimals',
  );
  if (decimals > BigInt.from(Amount.maxDecimals)) {
    throw const FormatException('bad token decimals');
  }
  _evmUnsigned64(
    _evmRequiredString(row, 'transactionIndex'),
    'token transaction index',
  );
  _evmUnsigned64(
    _evmRequiredString(row, 'confirmations'),
    'token confirmations',
  );
  if (row.containsKey('logIndex')) {
    _evmUnsigned64(_evmRequiredString(row, 'logIndex'), 'token log index');
  }
  _evmOptionalExecutionFlag(row, 'isError');
  _evmOptionalExecutionFlag(row, 'txreceipt_status');
  return row;
}

Map<Object?, Object?> _evmInternalRow(Object? raw) {
  final row = _evmExactMap(
    raw,
    allowed: _evmInternalFields,
    required: const {'timeStamp', 'from', 'to', 'value'},
    schema: 'internal transaction',
  );
  final hasHash = row.containsKey('hash');
  final hasTransactionHash = row.containsKey('transactionHash');
  final hasTrace = row.containsKey('traceId');
  final hasIndex = row.containsKey('index');
  if (hasHash == hasTransactionHash || hasTrace == hasIndex) {
    throw const FormatException('ambiguous internal transaction identity');
  }
  _evmHash(_evmInternalHash(row), 'internal transaction hash');
  _evmTrace(_evmInternalTrace(row));
  _evmAddress(_evmRequiredString(row, 'from'), 'internal sender');
  _evmAddress(
    _evmRequiredString(row, 'to'),
    'internal recipient',
    allowEmpty: true,
  );
  _evmUnsignedDecimal(_evmRequiredString(row, 'value'), 'internal value');
  _evmTimestamp(_evmRequiredString(row, 'timeStamp'));
  _evmOptionalExecutionFlag(row, 'isError');
  _evmOptionalExecutionFlag(row, 'txreceipt_status');
  return row;
}

Map<Object?, Object?> _evmExactMap(
  Object? raw, {
  required Set<String> allowed,
  required Set<String> required,
  required String schema,
}) {
  if (raw is! Map ||
      raw.keys.any((key) => key is! String || !allowed.contains(key)) ||
      required.any((key) => !raw.containsKey(key))) {
    throw FormatException('bad $schema');
  }
  return raw;
}

String _evmRequiredString(Map<Object?, Object?> row, String key) {
  final value = row[key];
  if (value is! String) throw FormatException('bad explorer field $key');
  return value;
}

void _evmOptionalExecutionFlag(Map<Object?, Object?> row, String key) {
  if (!row.containsKey(key)) return;
  final value = _evmRequiredString(row, key);
  if (value != '' && value != '0' && value != '1') {
    throw FormatException('bad explorer field $key');
  }
}

String _evmHash(String value, String label) {
  if (value.length != 66 || !_evmHex(value)) {
    throw FormatException('bad $label');
  }
  return value;
}

String _evmAddress(String value, String label, {bool allowEmpty = false}) {
  if ((allowEmpty && value.isEmpty) || (value.length == 42 && _evmHex(value))) {
    return value;
  }
  throw FormatException('bad $label');
}

bool _evmHex(String value) {
  if (!value.startsWith('0x')) return false;
  for (final code in value.codeUnits.skip(2)) {
    final digit = code >= 0x30 && code <= 0x39;
    final lower = code >= 0x61 && code <= 0x66;
    final upper = code >= 0x41 && code <= 0x46;
    if (!digit && !lower && !upper) return false;
  }
  return true;
}

BigInt _evmUnsignedDecimal(String value, String label) {
  if (value.isEmpty || value.length > 78) {
    throw FormatException('bad $label');
  }
  for (final code in value.codeUnits) {
    if (code < 0x30 || code > 0x39) throw FormatException('bad $label');
  }
  final parsed = BigInt.tryParse(value);
  if (parsed == null || parsed.isNegative || parsed.bitLength > 256) {
    throw FormatException('bad $label');
  }
  return parsed;
}

BigInt _evmUnsigned64(String value, String label) {
  final parsed = _evmUnsignedDecimal(value, label);
  if (parsed.bitLength > 64) throw FormatException('bad $label');
  return parsed;
}

int _evmTimestamp(String value) {
  final parsed = _evmUnsignedDecimal(value, 'transaction timestamp');
  // Dart DateTime supports a wider range than the product/UI should accept.
  // Year 9999 is a closed, deterministic upper bound for chain evidence.
  if (parsed == BigInt.zero || parsed > BigInt.from(253402300799)) {
    throw const FormatException('bad transaction timestamp');
  }
  return parsed.toInt();
}

void _evmText(String value, String label, int maxBytes) {
  if (utf8.encode(value).length > maxBytes) throw FormatException('bad $label');
  for (final rune in value.runes) {
    if (rune < 0x20 || rune == 0x7f) throw FormatException('bad $label');
  }
}

String _evmInternalHash(Map<Object?, Object?> row) => _evmRequiredString(
  row,
  row.containsKey('hash') ? 'hash' : 'transactionHash',
);

String _evmInternalTrace(Map<Object?, Object?> row) =>
    _evmRequiredString(row, row.containsKey('traceId') ? 'traceId' : 'index');

void _evmTrace(String value) {
  if (value.isEmpty || value.length > 128) {
    throw const FormatException('bad internal trace id');
  }
  for (final segment in value.split('_')) {
    if (segment.isEmpty ||
        segment.codeUnits.any((code) => code < 0x30 || code > 0x39)) {
      throw const FormatException('bad internal trace id');
    }
  }
}

void _evmRowTouchesOwner(Map<Object?, Object?> row, String owner) {
  final from = (row['from']! as String).toLowerCase();
  final to = (row['to']! as String).toLowerCase();
  if (from != owner && to != owner) {
    throw const FormatException('explorer row is not bound to owner');
  }
}

String _evmMovementKey(Map<Object?, Object?> row) => [
  row.containsKey('hash') ? row['hash'] : row['transactionHash'],
  (row['from']! as String).toLowerCase(),
  (row['to']! as String).toLowerCase(),
  row['value'],
  row['timeStamp'],
].join('\u0000');

final BigInt _solanaMaximumU64 = (BigInt.one << 64) - BigInt.one;

class _SolanaSignatureEvidence {
  const _SolanaSignatureEvidence({
    required this.signature,
    required this.slot,
    required this.error,
    required this.memo,
    required this.blockTime,
    required this.confirmationStatus,
    required this.transactionIndex,
  });

  final String signature;
  final int slot;
  final Object? error;
  final String? memo;
  final int? blockTime;
  final String? confirmationStatus;
  final int? transactionIndex;

  bool sameEvidence(_SolanaSignatureEvidence other) =>
      slot == other.slot &&
      _deepJsonEquals(error, other.error) &&
      memo == other.memo &&
      blockTime == other.blockTime &&
      confirmationStatus == other.confirmationStatus &&
      transactionIndex == other.transactionIndex;
}

class _SolanaHistoryCandidate {
  _SolanaHistoryCandidate({
    required this.evidence,
    required this.queriedAccounts,
  });

  final _SolanaSignatureEvidence evidence;
  final Set<String> queriedAccounts;
}

class _ParsedSolanaHistoryTransaction {
  const _ParsedSolanaHistoryTransaction({
    required this.meta,
    required this.message,
    required this.accountKeys,
    required this.blockTime,
    required this.status,
  });

  final Map<Object?, Object?> meta;
  final Map<Object?, Object?> message;
  final List<String> accountKeys;
  final int blockTime;
  final ChainTxStatus status;
}

_SolanaSignatureEvidence _parseSolanaSignatureRow(Object? raw) {
  final row = _solanaExactMap(
    raw,
    allowed: const {
      'signature',
      'slot',
      'err',
      'memo',
      'blockTime',
      'confirmationStatus',
      'transactionIndex',
    },
    required: const {
      'signature',
      'slot',
      'err',
      'memo',
      'blockTime',
      'confirmationStatus',
    },
    schema: 'signature_row',
  );
  final error = row['err'];
  if (error != null && error is! Map) {
    throw const FormatException('bad signature error');
  }
  final memo = row['memo'];
  if (memo != null && (memo is! String || memo.length > 1024)) {
    throw const FormatException('bad signature memo');
  }
  final blockTime = row['blockTime'];
  if (blockTime != null && (blockTime is! int || blockTime < 0)) {
    throw const FormatException('bad signature block time');
  }
  final confirmationStatus = row['confirmationStatus'];
  if (confirmationStatus != null &&
      confirmationStatus != 'confirmed' &&
      confirmationStatus != 'finalized') {
    throw const FormatException('bad signature confirmation');
  }
  final rawTransactionIndex = row['transactionIndex'];
  final transactionIndex = rawTransactionIndex == null
      ? null
      : _solanaU64(rawTransactionIndex, 'signature transaction index');
  return _SolanaSignatureEvidence(
    signature: _solanaSignature(row['signature'], 'history signature'),
    slot: _solanaU64(row['slot'], 'signature slot'),
    error: error,
    memo: memo as String?,
    blockTime: blockTime as int?,
    confirmationStatus: confirmationStatus as String?,
    transactionIndex: transactionIndex,
  );
}

Set<String> _parseSolanaOwnedTokenAccounts(
  Object? raw, {
  required String owner,
  required String tokenProgram,
}) {
  final envelope = _solanaValueEnvelope(raw, 'owned token accounts');
  final rows = envelope['value'];
  if (rows is! List || rows.length > 10000) {
    throw const FormatException('bad owned token accounts');
  }
  final accounts = <String>{};
  for (final rawRow in rows) {
    final row = _solanaExactMap(
      rawRow,
      allowed: const {'account', 'pubkey'},
      required: const {'account', 'pubkey'},
      schema: 'owned_token_account_row',
    );
    final pubkey = _solanaPublicKey(row['pubkey'], 'owned token account');
    if (!accounts.add(pubkey)) {
      throw const FormatException('duplicate owned token account');
    }
    final account = _solanaConsumedMap(
      row['account'],
      consumed: const {'data', 'executable', 'lamports', 'owner', 'rentEpoch'},
      schema: 'owned_token_account',
    );
    if (account['executable'] != false ||
        _solanaPublicKey(account['owner'], 'owned token program') !=
            tokenProgram) {
      throw const FormatException('bad owned token program');
    }
    _solanaU64(account['lamports'], 'owned token lamports');
    _solanaUnsignedNumber(account['rentEpoch'], 'owned token rent epoch');
    final data = _solanaExactMap(
      account['data'],
      allowed: const {'parsed', 'program', 'space'},
      required: const {'parsed', 'program'},
      schema: 'owned_token_data',
    );
    final parsedProgram = data['program'];
    if (parsedProgram is! String ||
        (tokenProgram == solanaTokenProgram && parsedProgram != 'spl-token') ||
        (tokenProgram == solanaToken2022Program &&
            parsedProgram != 'spl-token' &&
            parsedProgram != 'spl-token-2022')) {
      throw const FormatException('bad parsed token program');
    }
    final parsed = _solanaExactMap(
      data['parsed'],
      allowed: const {'info', 'type'},
      required: const {'info', 'type'},
      schema: 'owned_parsed_token_account',
    );
    if (parsed['type'] != 'account') {
      throw const FormatException('bad parsed token account type');
    }
    final info = _solanaConsumedMap(
      parsed['info'],
      consumed: const {'isNative', 'mint', 'owner', 'state', 'tokenAmount'},
      schema: 'owned_token_info',
    );
    if (info['isNative'] is! bool ||
        _solanaPublicKey(info['owner'], 'owned token owner') != owner) {
      throw const FormatException('bad owned token identity');
    }
    _solanaPublicKey(info['mint'], 'owned token mint');
    if (info['state'] != 'initialized' && info['state'] != 'frozen') {
      throw const FormatException('bad owned token state');
    }
    _parseSolanaTokenAmount(info['tokenAmount']);
  }
  return accounts;
}

_ParsedSolanaHistoryTransaction _parseSolanaHistoryTransaction(
  Object? raw, {
  required _SolanaHistoryCandidate candidate,
}) {
  final result = _solanaExactMap(
    raw,
    allowed: const {
      'blockTime',
      'meta',
      'slot',
      'transaction',
      'transactionIndex',
      'version',
    },
    required: const {'blockTime', 'meta', 'slot', 'transaction', 'version'},
    schema: 'transaction_result',
  );
  final slot = _solanaU64(result['slot'], 'transaction slot');
  if (slot != candidate.evidence.slot) {
    throw const FormatException('transaction slot mismatch');
  }
  final rawTransactionIndex = result['transactionIndex'];
  final transactionIndex = rawTransactionIndex == null
      ? null
      : _solanaU64(rawTransactionIndex, 'transaction index');
  if (transactionIndex != candidate.evidence.transactionIndex) {
    throw const FormatException('transaction index mismatch');
  }
  final version = result['version'];
  if (version != 'legacy' && version != 0) {
    throw const FormatException('unsupported transaction version');
  }
  final transactionBlockTime = result['blockTime'];
  if (transactionBlockTime != null &&
      (transactionBlockTime is! int || transactionBlockTime < 0)) {
    throw const FormatException('bad transaction block time');
  }
  final signatureBlockTime = candidate.evidence.blockTime;
  if (transactionBlockTime != null &&
      signatureBlockTime != null &&
      transactionBlockTime != signatureBlockTime) {
    throw const FormatException('transaction block time mismatch');
  }
  final blockTime = (transactionBlockTime as int?) ?? signatureBlockTime;
  if (blockTime == null) {
    throw const FormatException('transaction time unavailable');
  }

  final transaction = _solanaExactMap(
    result['transaction'],
    allowed: const {'message', 'signatures'},
    required: const {'message', 'signatures'},
    schema: 'parsed_transaction',
  );
  final signatures = transaction['signatures'];
  if (signatures is! List || signatures.isEmpty || signatures.length > 64) {
    throw const FormatException('bad transaction signatures');
  }
  final seenSignatures = <String>{};
  for (final rawSignature in signatures) {
    final signature = _solanaSignature(rawSignature, 'transaction signature');
    if (!seenSignatures.add(signature)) {
      throw const FormatException('duplicate transaction signature');
    }
  }
  if (!seenSignatures.contains(candidate.evidence.signature)) {
    throw const FormatException('transaction signature mismatch');
  }

  final message = _solanaConsumedMap(
    transaction['message'],
    consumed: const {'accountKeys', 'instructions'},
    schema: 'parsed_transaction_message',
  );
  final rawKeys = message['accountKeys'];
  if (rawKeys is! List || rawKeys.isEmpty || rawKeys.length > 256) {
    throw const FormatException('bad transaction account keys');
  }
  final accountKeys = <String>[];
  for (final rawKey in rawKeys) {
    if (rawKey is String) {
      accountKeys.add(_solanaPublicKey(rawKey, 'transaction account key'));
      continue;
    }
    final key = _solanaExactMap(
      rawKey,
      allowed: const {'pubkey', 'signer', 'source', 'writable'},
      required: const {'pubkey', 'signer', 'source', 'writable'},
      schema: 'parsed_transaction_account_key',
    );
    if (key['signer'] is! bool ||
        key['writable'] is! bool ||
        (key['source'] != 'transaction' && key['source'] != 'lookupTable')) {
      throw const FormatException('bad parsed account key metadata');
    }
    accountKeys.add(
      _solanaPublicKey(key['pubkey'], 'parsed transaction account key'),
    );
  }
  if (!candidate.queriedAccounts.any(accountKeys.contains)) {
    throw const FormatException('transaction does not contain queried account');
  }
  if (message['instructions'] is! List ||
      (message['instructions'] as List).length > 256) {
    throw const FormatException('bad transaction instructions');
  }

  final meta = _solanaConsumedMap(
    result['meta'],
    consumed: const {
      'err',
      'fee',
      'preBalances',
      'postBalances',
      'preTokenBalances',
      'postTokenBalances',
    },
    schema: 'transaction_meta',
  );
  final metaError = meta['err'];
  if (metaError != null && metaError is! Map) {
    throw const FormatException('bad transaction error');
  }
  final status = _solanaExecutionStatus(candidate.evidence, metaError);
  _solanaU64(meta['fee'], 'transaction fee');
  final preBalances = _solanaBalanceVector(
    meta['preBalances'],
    accountKeys.length,
    'pre balances',
  );
  final postBalances = _solanaBalanceVector(
    meta['postBalances'],
    accountKeys.length,
    'post balances',
  );
  if (preBalances.length != postBalances.length) {
    throw const FormatException('transaction balance width mismatch');
  }
  final beforeTokens = _parseSolanaTokenBalanceRows(
    meta['preTokenBalances'],
    accountKeys.length,
    'pre token balances',
  );
  final afterTokens = _parseSolanaTokenBalanceRows(
    meta['postTokenBalances'],
    accountKeys.length,
    'post token balances',
  );
  for (final index in {...beforeTokens.keys, ...afterTokens.keys}) {
    final before = beforeTokens[index];
    final after = afterTokens[index];
    if (before != null &&
        after != null &&
        (before.mint != after.mint ||
            before.owner != after.owner ||
            before.program != after.program ||
            before.decimals != after.decimals)) {
      throw const FormatException('token balance identity mismatch');
    }
  }
  return _ParsedSolanaHistoryTransaction(
    meta: meta,
    message: message,
    accountKeys: List.unmodifiable(accountKeys),
    blockTime: blockTime,
    status: status,
  );
}

ChainTxStatus _solanaExecutionStatus(
  _SolanaSignatureEvidence signature,
  Object? transactionError,
) {
  if (!_deepJsonEquals(signature.error, transactionError)) {
    throw const FormatException('transaction execution evidence mismatch');
  }
  return transactionError == null
      ? ChainTxStatus.confirmed
      : ChainTxStatus.failed;
}

({BigInt amount, String? from, String? to})? _solanaNativeTransfer(
  _ParsedSolanaHistoryTransaction transaction,
  String owner,
) {
  final instructions = transaction.message['instructions'] as List;
  var amount = BigInt.zero;
  final outgoingDestinations = <String>{};
  final incomingSources = <String>{};
  for (final rawInstruction in instructions) {
    if (rawInstruction is! Map || rawInstruction['program'] != 'system') {
      continue;
    }
    final parsed = rawInstruction['parsed'];
    if (parsed is! Map || parsed['type'] != 'transfer') continue;
    final info = _solanaExactMap(
      parsed['info'],
      allowed: const {'destination', 'lamports', 'source'},
      required: const {'destination', 'lamports', 'source'},
      schema: 'system_transfer_info',
    );
    final source = _solanaPublicKey(info['source'], 'system transfer source');
    final destination = _solanaPublicKey(
      info['destination'],
      'system transfer destination',
    );
    final lamports = BigInt.from(
      _solanaU64(info['lamports'], 'system transfer amount'),
    );
    if (source == owner) {
      amount -= lamports;
      outgoingDestinations.add(destination);
    }
    if (destination == owner) {
      amount += lamports;
      incomingSources.add(source);
    }
  }
  if (amount == BigInt.zero) return null;
  final ownerIndex = transaction.accountKeys.indexOf(owner);
  if (ownerIndex < 0) {
    throw const FormatException('owner absent from native transfer');
  }
  final pre = (transaction.meta['preBalances'] as List)[ownerIndex] as int;
  final post = (transaction.meta['postBalances'] as List)[ownerIndex] as int;
  final balanceDelta = BigInt.from(post) - BigInt.from(pre);
  if ((amount.isNegative &&
          (!balanceDelta.isNegative || balanceDelta.abs() < amount.abs())) ||
      (!amount.isNegative &&
          (balanceDelta.isNegative || balanceDelta < amount))) {
    throw const FormatException('native transfer balance mismatch');
  }
  final outgoing = amount.isNegative;
  return (
    amount: amount,
    from: outgoing
        ? owner
        : (incomingSources.length == 1 ? incomingSources.single : null),
    to: outgoing
        ? (outgoingDestinations.length == 1
              ? outgoingDestinations.single
              : null)
        : owner,
  );
}

class _SolanaTokenBalanceRow {
  const _SolanaTokenBalanceRow({
    required this.mint,
    required this.owner,
    required this.program,
    required this.amount,
    required this.decimals,
  });

  final String mint;
  final String owner;
  final String program;
  final BigInt amount;
  final int decimals;
}

Map<int, _SolanaTokenBalanceRow> _parseSolanaTokenBalanceRows(
  Object? raw,
  int accountCount,
  String label,
) {
  if (raw is! List || raw.length > accountCount) {
    throw FormatException('bad $label');
  }
  final rows = <int, _SolanaTokenBalanceRow>{};
  for (final rawRow in raw) {
    final row = _solanaExactMap(
      rawRow,
      allowed: const {
        'accountIndex',
        'mint',
        'owner',
        'programId',
        'uiTokenAmount',
      },
      required: const {
        'accountIndex',
        'mint',
        'owner',
        'programId',
        'uiTokenAmount',
      },
      schema: 'token_balance_row',
    );
    final index = row['accountIndex'];
    if (index is! int || index < 0 || index >= accountCount) {
      throw const FormatException('bad token account index');
    }
    final program = _solanaPublicKey(row['programId'], 'token balance program');
    if (program != solanaTokenProgram && program != solanaToken2022Program) {
      throw const FormatException('bad token balance program');
    }
    final amount = _parseSolanaTokenAmount(row['uiTokenAmount']);
    final parsed = _SolanaTokenBalanceRow(
      mint: _solanaPublicKey(row['mint'], 'token balance mint'),
      owner: _solanaPublicKey(row['owner'], 'token balance owner'),
      program: program,
      amount: amount.amount,
      decimals: amount.decimals,
    );
    for (final existing in rows.values) {
      if (existing.mint == parsed.mint &&
          (existing.program != parsed.program ||
              existing.decimals != parsed.decimals)) {
        throw const FormatException('inconsistent token mint metadata');
      }
    }
    if (rows[index] != null) {
      throw const FormatException('duplicate token balance account index');
    }
    rows[index] = parsed;
  }
  return rows;
}

({BigInt amount, int decimals}) _parseSolanaTokenAmount(Object? raw) {
  final amount = _solanaExactMap(
    raw,
    allowed: const {'amount', 'decimals', 'uiAmount', 'uiAmountString'},
    required: const {'amount', 'decimals', 'uiAmount', 'uiAmountString'},
    schema: 'token_amount',
  );
  final rawAmount = amount['amount'];
  if (rawAmount is! String ||
      rawAmount.length > 20 ||
      !RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(rawAmount)) {
    throw const FormatException('bad token amount');
  }
  final value = BigInt.parse(rawAmount);
  if (value > _solanaMaximumU64) {
    throw const FormatException('token amount overflow');
  }
  final decimals = amount['decimals'];
  if (decimals is! int || decimals < 0 || decimals > 255) {
    throw const FormatException('bad token decimals');
  }
  final uiAmount = amount['uiAmount'];
  if (uiAmount != null &&
      (uiAmount is! num || !uiAmount.isFinite || uiAmount < 0)) {
    throw const FormatException('bad UI token amount');
  }
  if (amount['uiAmountString'] !=
      _canonicalSolanaTokenAmount(value, decimals)) {
    throw const FormatException('inconsistent UI token amount');
  }
  return (amount: value, decimals: decimals);
}

List<int> _solanaBalanceVector(Object? raw, int width, String label) {
  if (raw is! List || raw.length != width) {
    throw FormatException('bad $label');
  }
  return [for (final value in raw) _solanaU64(value, label)];
}

Map<Object?, Object?> _solanaValueEnvelope(Object? raw, String label) {
  final envelope = _solanaExactMap(
    raw,
    allowed: const {'context', 'value'},
    required: const {'context', 'value'},
    schema: '${label}_response',
  );
  final context = _solanaExactMap(
    envelope['context'],
    allowed: const {'apiVersion', 'slot'},
    required: const {'slot'},
    schema: '${label}_context',
  );
  _solanaU64(context['slot'], '$label context slot');
  if (context['apiVersion'] case final Object? version?) {
    if (version is! String || version.isEmpty || version.length > 64) {
      throw FormatException('bad $label context version');
    }
  }
  return envelope;
}

Map<Object?, Object?> _solanaExactMap(
  Object? raw, {
  required Set<String> allowed,
  required Set<String> required,
  required String schema,
}) {
  if (raw is! Map ||
      raw.keys.any((key) => key is! String || !allowed.contains(key)) ||
      required.any((key) => !raw.containsKey(key))) {
    throw FormatException('bad $schema');
  }
  return raw;
}

Map<Object?, Object?> _solanaConsumedMap(
  Object? raw, {
  required Set<String> consumed,
  required String schema,
}) {
  if (raw is! Map ||
      raw.length > 128 ||
      raw.keys.any((key) => key is! String)) {
    throw FormatException('bad $schema');
  }
  for (final key in raw.keys.cast<String>()) {
    for (final canonical in consumed) {
      if (key.toLowerCase() == canonical.toLowerCase() && key != canonical) {
        throw FormatException('ambiguous $schema');
      }
    }
  }
  if (consumed.any((key) => !raw.containsKey(key))) {
    throw FormatException('incomplete $schema');
  }
  return raw;
}

int _solanaU64(Object? raw, String label) {
  if (raw is! int || raw < 0 || BigInt.from(raw) > _solanaMaximumU64) {
    throw FormatException('bad $label');
  }
  return raw;
}

void _solanaUnsignedNumber(Object? raw, String label) {
  if (raw is int && raw >= 0) return;
  if (raw is double &&
      raw.isFinite &&
      raw >= 0 &&
      raw == raw.truncateToDouble()) {
    return;
  }
  throw FormatException('bad $label');
}

String _solanaPublicKey(Object? raw, String label) {
  if (raw is! String || raw.length > 64) throw FormatException('bad $label');
  try {
    final bytes = base58Decode(raw);
    if (bytes.length != 32 || base58Encode(bytes) != raw) {
      throw FormatException('bad $label');
    }
  } catch (_) {
    throw FormatException('bad $label');
  }
  return raw;
}

String _solanaSignature(Object? raw, String label) {
  if (raw is! String || raw.length > 96) throw FormatException('bad $label');
  try {
    final bytes = base58Decode(raw);
    if (bytes.length != 64 || base58Encode(bytes) != raw) {
      throw FormatException('bad $label');
    }
  } catch (_) {
    throw FormatException('bad $label');
  }
  return raw;
}

String _canonicalSolanaTokenAmount(BigInt amount, int decimals) {
  var digits = amount.toString();
  if (decimals == 0) return digits;
  if (digits.length <= decimals) {
    digits = '${'0' * (decimals - digits.length + 1)}$digits';
  }
  final point = digits.length - decimals;
  final fraction = digits.substring(point).replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty
      ? digits.substring(0, point)
      : '${digits.substring(0, point)}.$fraction';
}

bool _deepJsonEquals(Object? left, Object? right) {
  if (identical(left, right) || left == right) return true;
  if (left is List && right is List && left.length == right.length) {
    for (var index = 0; index < left.length; index += 1) {
      if (!_deepJsonEquals(left[index], right[index])) return false;
    }
    return true;
  }
  if (left is Map && right is Map && left.length == right.length) {
    for (final key in left.keys) {
      if (!right.containsKey(key) || !_deepJsonEquals(left[key], right[key])) {
        return false;
      }
    }
    return true;
  }
  return false;
}

/// Decodes a base58check TRON address ("T...") to its lowercase 21-byte hex
/// form ("41..."), as used in TronGrid raw_data. Returns null for anything
/// that isn't a checksum-valid TRON address.
String? tronAddressHex(String address) {
  try {
    if (!Addresses.validate(Chain.tron, address).isValid) return null;
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

/// Converts TronGrid's 41-prefixed raw address to the base58check form shown
/// to users. Invalid input remains unknown instead of being reformatted.
String? tronHexAddressToBase58(String hex) {
  final normalized = hex.trim().toLowerCase();
  if (normalized.length != 42 || !normalized.startsWith('41')) return null;
  final payload = Uint8List(21);
  for (var i = 0; i < payload.length; i++) {
    final value = int.tryParse(
      normalized.substring(i * 2, i * 2 + 2),
      radix: 16,
    );
    if (value == null) return null;
    payload[i] = value;
  }
  final checksum = sha256(sha256(payload)).sublist(0, 4);
  return base58Encode(Uint8List.fromList([...payload, ...checksum]));
}
