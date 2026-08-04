import 'dart:convert';
import 'dart:typed_data';

import 'package:chains/chains.dart'
    show
        Amount,
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
      final base = _evmHistoryApi(coin);

      Future<List<dynamic>> fetchList(String action) async {
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

      final results = await (
        fetchList('txlist'),
        fetchList('tokentx'),
        fetchList('txlistinternal').catchError((_) => const <dynamic>[]),
      ).wait;
      final normalItems = results.$1;
      final tokenItems = results.$2;
      // Internal transfers are enrichment on explorers that implement it; a
      // failure must not hide otherwise trustworthy native/token rows.
      final internalItems = results.$3;

      final lower = address.toLowerCase();
      final registry = _tokenRegistry();
      final records = <ChainTxRecord>[];

      void appendNative(
        Map<dynamic, dynamic> item, {
        required bool internal,
        required int index,
      }) {
        final hash = internal
            ? (item['hash'] ?? item['transactionHash'])
            : item['hash'];
        if (hash is! String || hash.isEmpty) return;
        final rawFrom = '${item['from'] ?? ''}'.trim();
        final rawTo = '${item['to'] ?? ''}'.trim();
        final from = rawFrom.toLowerCase();
        final to = rawTo.toLowerCase();
        if (from != lower && to != lower) return;
        final seconds = int.tryParse('${item['timeStamp'] ?? ''}');
        final value = BigInt.tryParse('${item['value'] ?? ''}');
        if (seconds == null || value == null || value == BigInt.zero) return;
        final trace = '${item['traceId'] ?? item['index'] ?? index}';
        records.add(
          ChainTxRecord(
            coin: coin,
            id: internal ? '$hash:internal:$trace' : hash,
            hash: hash,
            outgoing: from == lower,
            fromAddress: rawFrom.isEmpty ? null : rawFrom,
            toAddress: rawTo.isEmpty ? null : rawTo,
            amountText: _formatAmount(value, 18, _nativeSymbol(coin)),
            timestamp: DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
            status: _evmExplorerExecutionStatus(item),
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
        final rawFrom = '${item['from'] ?? ''}'.trim();
        final rawTo = '${item['to'] ?? ''}'.trim();
        final from = rawFrom.toLowerCase();
        final to = rawTo.toLowerCase();
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
            fromAddress: rawFrom.isEmpty ? null : rawFrom,
            toAddress: rawTo.isEmpty ? null : rawTo,
            amountText: decimals == null
                ? null
                : _formatAmount(raw, decimals, symbol),
            assetContract: contract,
            assetSymbol: symbol,
            assetVerified: official != null,
            timestamp: DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
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
    final body = jsonDecode(response.body);
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
      final (trc20, native, internal) = await (
        _getData(
          '$tronApiUrl/v1/accounts/$address/transactions/trc20'
          '?limit=$limit&only_confirmed=true',
        ),
        _getData(
          '$tronApiUrl/v1/accounts/$address/transactions'
          '?limit=$limit&only_confirmed=true',
        ),
        _getData(
          '$tronApiUrl/v1/accounts/$address/internal-transactions'
          '?limit=$limit&only_confirmed=true',
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
        final record = item is Map ? _parseNative(item, myHex, address) : null;
        if (record != null && !tokenHashes.contains(record.hash)) {
          records.add(record);
        }
      }
      for (final item in internal) {
        final record = item is Map
            ? _parseTronInternal(item, myHex, address)
            : null;
        if (record != null) records.add(record);
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
      fromAddress: item['from'] is String ? item['from'] as String : null,
      toAddress: item['to'] is String ? item['to'] as String : null,
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
  ChainTxRecord? _parseNative(
    Map<dynamic, dynamic> item,
    String? myHex,
    String myAddress,
  ) {
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

    final status = _tronContractExecutionStatus(item);
    final amount = _parseChainInteger(value['amount']);
    if (amount == null || amount.isNegative) return null;
    final owner = value['owner_address'];
    final recipient = value['to_address'];
    final ownerHex = owner is String ? owner.toLowerCase() : '';
    final recipientHex = recipient is String ? recipient.toLowerCase() : '';
    if (myHex != null && ownerHex != myHex && recipientHex != myHex) {
      return null;
    }
    final ownerText = owner is String
        ? (ownerHex == myHex
              ? myAddress
              : tronHexAddressToBase58(owner) ?? owner)
        : null;
    final recipientText = recipient is String
        ? (recipientHex == myHex
              ? myAddress
              : tronHexAddressToBase58(recipient) ?? recipient)
        : null;
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
      outgoing: myHex != null && ownerHex == myHex,
      fromAddress: ownerText,
      toAddress: recipientText,
      amountText: _formatAmount(
        amount,
        isTrc10 ? 0 : 6,
        isTrc10 ? 'TRC10' : 'TRX',
      ),
      assetContract: isTrc10 ? tokenId : null,
      assetSymbol: isTrc10 ? 'TRC10' : null,
      assetVerified: !isTrc10,
      timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
      status: status,
    );
  }

  ChainTxStatus _tronContractExecutionStatus(Map<dynamic, dynamic> item) {
    final ret = item['ret'];
    if (ret is! List || ret.isEmpty || ret.first is! Map) {
      return ChainTxStatus.unknown;
    }
    final value = (ret.first as Map)['contractRet'];
    if (value is! String || value.trim().isEmpty) {
      return ChainTxStatus.unknown;
    }
    return value.trim().toUpperCase() == 'SUCCESS'
        ? ChainTxStatus.confirmed
        : ChainTxStatus.failed;
  }

  ChainTxRecord? _parseTronInternal(
    Map<dynamic, dynamic> item,
    String? myHex,
    String myAddress,
  ) {
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
      fromAddress: from == myHex
          ? myAddress
          : tronHexAddressToBase58(from) ?? from,
      toAddress: to == myHex ? myAddress : tronHexAddressToBase58(to) ?? to,
      amountText: _formatAmount(
        amount,
        isTrc10 ? 0 : 6,
        isTrc10 ? 'TRC10' : 'TRX',
      ),
      assetContract: isTrc10 ? tokenId : null,
      assetSymbol: isTrc10 ? 'TRC10' : null,
      assetVerified: !isTrc10,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
      status: switch (data['rejected']) {
        false => ChainTxStatus.confirmed,
        true => ChainTxStatus.failed,
        _ => ChainTxStatus.unknown,
      },
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
