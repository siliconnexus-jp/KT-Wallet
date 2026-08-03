// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:math' as math;

import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter/widgets.dart';
import 'package:wallet_data/wallet_data.dart' as db;

import '../state/wallet_controller.dart';
import '../observability/experience_metrics.dart';
import 'history_service.dart';
import 'history_snapshot.dart';
import 'token_balance_service.dart';
import 'transaction_status_service.dart';

bool _isEvmCoinName(String coin) =>
    coin == Coin.eth.name ||
    coin == Coin.polygon.name ||
    coin == Coin.base.name ||
    coin == Coin.arbitrum.name ||
    coin == Coin.avalanche.name ||
    coin == Coin.bnb.name;

typedef _HistoryIdentity = ({
  Coin coin,
  String networkId,
  String normalizedHash,
});

Coin? _coinForName(String name) {
  for (final coin in Coin.values) {
    if (coin.name == name) return coin;
  }
  return null;
}

String _normalizeHistoryHash(Coin coin, String hash) =>
    coin == Coin.solana ? hash : hash.toLowerCase();

_HistoryIdentity? _recordIdentity(ChainTxRecord record) {
  final networkId = record.networkId;
  if (networkId == null || networkId.isEmpty || record.hash.isEmpty) {
    return null;
  }
  return (
    coin: record.coin,
    networkId: networkId,
    normalizedHash: _normalizeHistoryHash(record.coin, record.hash),
  );
}

_HistoryIdentity? _transactionIdentity(db.Transaction transaction) {
  final coin = _coinForName(transaction.coin);
  final networkId = transaction.networkId;
  final hash = transaction.hash;
  if (coin == null ||
      networkId == null ||
      networkId.isEmpty ||
      hash == null ||
      hash.isEmpty) {
    return null;
  }
  return (
    coin: coin,
    networkId: networkId,
    normalizedHash: _normalizeHistoryHash(coin, hash),
  );
}

Future<void> _forEachBounded<T>(
  List<T> values, {
  required int concurrency,
  required Future<void> Function(T value) action,
}) async {
  if (values.isEmpty) return;
  if (concurrency <= 0) throw ArgumentError.value(concurrency, 'concurrency');
  var nextIndex = 0;

  Future<void> worker() async {
    while (nextIndex < values.length) {
      // Dart runs this read/increment without an await, so workers cannot
      // claim the same item even though their network work overlaps.
      final value = values[nextIndex++];
      await action(value);
    }
  }

  await Future.wait([
    for (var i = 0; i < math.min(concurrency, values.length); i++) worker(),
  ]);
}

/// Live transaction history for the current wallet, per chain. Mirrors the
/// [MarketController] lifecycle patterns (generation-guarded refresh, wallet
/// switch listener) but is owned by the history surface, not `main.dart` — it
/// is mounted lazily when the full history page or an asset history section
/// builds under a live market context.
class HistoryController extends ChangeNotifier with WidgetsBindingObserver {
  /// Keeps a large restored Pending set from exhausting the device HTTP pool
  /// or triggering a synchronized Gateway/RPC rate-limit burst.
  static const pendingStatusConcurrency = 4;

  HistoryController({
    required WalletController wallets,
    HistoryService? service,
    TransactionStatusService? statusService,
    Set<String> Function()? activeNetworkIds,
    String? Function(Coin coin)? activeNetworkId,
    Listenable? networkChanges,
    bool Function()? canRefresh,
    HistorySnapshotStore? snapshots,
    String Function()? snapshotScope,
    this.pollInterval = const Duration(seconds: 8),
  }) : _wallets = wallets,
       _service = service ?? HistoryService(),
       _statusService =
           statusService ??
           TransactionStatusService(
             onEvmNonceObserved: (transaction, nonce) async {
               await wallets.setTransactionNonceIfAbsentForWallet(
                 transaction.walletId,
                 transaction.id,
                 nonce,
               );
             },
           ),
       _activeNetworkIds = activeNetworkIds,
       _activeNetworkId = activeNetworkId,
       _networkChanges = networkChanges,
       _canRefresh = canRefresh ?? _alwaysRefresh,
       _snapshots = snapshots,
       _snapshotScope = snapshotScope ?? _defaultSnapshotScope {
    _walletId = _wallets.current?.id;
    _wallets.addListener(_onWalletsChanged);
    _networkChanges?.addListener(_onNetworkChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  final WalletController _wallets;
  final HistoryService _service;
  final TransactionStatusService _statusService;
  final Duration pollInterval;

  /// The ACTIVE network ids, re-read on every refresh: locally recorded rows
  /// from another network instance (a Sepolia transfer while mainnet is
  /// selected) must not appear in this list. Null (older wiring, tests
  /// injecting their own controller) keeps every network, as before.
  final Set<String> Function()? _activeNetworkIds;
  final String? Function(Coin coin)? _activeNetworkId;
  final Listenable? _networkChanges;
  final bool Function() _canRefresh;
  final HistorySnapshotStore? _snapshots;
  final String Function() _snapshotScope;
  static bool _alwaysRefresh() => true;
  static String _defaultSnapshotScope() => 'default';
  bool _refreshRequested = false;
  bool _disposed = false;

  Future<List<db.Transaction>> _loadLocalTransactions() =>
      _wallets.localTransactions(networkIds: _activeNetworkIds?.call());

  Future<List<db.Transaction>> _loadPendingTransactions() =>
      _wallets.localPendingTransactions();

  String? _walletId;
  String? _activeSnapshotScope;
  int _generation = 0;
  bool _refreshing = false;
  bool _hasRefreshed = false;
  bool _showingCachedData = false;
  bool _loadingMore = false;
  DateTime? _lastUpdatedAt;
  int _remoteLimit = HistoryService.pageSize;
  final List<TransactionStatusNotice> _notices = [];
  Timer? _pollTimer;
  List<db.Transaction> _localTransactions = const [];
  bool _hasPendingTransactions = false;

  Map<Coin, HistoryResult> _results = {
    for (final coin in Coin.values) coin: const HistoryResult.loading(),
  };

  HistoryResult resultFor(Coin coin) =>
      _results[coin] ?? const HistoryResult.unsupported();

  /// True until the first refresh completes (rows render structural placeholders).
  bool get isLoading => !_hasRefreshed;
  bool get isRefreshing => _refreshing;
  bool get isLoadingMore => _loadingMore;
  bool get showingCachedData => _showingCachedData;
  DateTime? get lastUpdatedAt => _lastUpdatedAt;
  TransactionStatusNotice? get notice =>
      _notices.isEmpty ? null : _notices.first;

  void clearNotice(TransactionStatusNotice notice) {
    _notices.remove(notice);
  }

  /// Atomically drains every status transition produced by the latest poll.
  ///
  /// A refresh can settle several transactions concurrently. A single
  /// nullable notice silently discarded all but the last one; consumers now
  /// receive the complete ordered batch and can present it sequentially.
  List<TransactionStatusNotice> takeNotices() {
    if (_notices.isEmpty) return const [];
    final notices = List<TransactionStatusNotice>.unmodifiable(_notices);
    _notices.clear();
    return notices;
  }

  /// True while at least one chain filled the current result window. Increasing
  /// the window is cursor-like from the UI's perspective and remains bounded
  /// by the Gateway's 100-record contract.
  bool get canLoadMore =>
      !_refreshing &&
      _remoteLimit < 100 &&
      _results.values.any(
        (result) =>
            result.status == HistoryStatus.ok &&
            result.records.length >= _remoteLimit,
      );

  /// At least one chain returned a real (possibly empty) history.
  bool get hasLiveRecords =>
      _results.values.any((r) => r.status == HistoryStatus.ok);

  /// Every chain reported "no keyless history API".
  bool get allUnsupported =>
      !isLoading &&
      _results.values.every((r) => r.status == HistoryStatus.unsupported);

  /// Every supported chain errored (for example, the RPC is unavailable).
  bool get isError => !isLoading && !hasLiveRecords && !allUnsupported;

  db.Transaction? localTransactionForRecord(ChainTxRecord record) {
    final identity = _recordIdentity(record);
    if (identity == null) return null;
    for (final transaction in _localTransactions) {
      if (_transactionIdentity(transaction) == identity) return transaction;
    }
    return null;
  }

  /// All successfully fetched records across chains, newest first.
  List<ChainTxRecord> get records {
    final merged = [
      for (final result in _results.values)
        if (result.status == HistoryStatus.ok) ...result.records,
    ];
    final remoteIdentities = <_HistoryIdentity>{};
    for (final record in merged) {
      final identity = _recordIdentity(record);
      if (identity != null) remoteIdentities.add(identity);
    }
    for (final transaction in _localTransactions) {
      final hash = transaction.hash;
      final coin = _coinForName(transaction.coin);
      if (hash == null || hash.isEmpty || coin == null) continue;
      final identity = _transactionIdentity(transaction);
      if (identity != null && remoteIdentities.contains(identity)) continue;
      if (transaction.status == db.TxStatus.failed ||
          transaction.status == db.TxStatus.expired ||
          transaction.status == db.TxStatus.dropped ||
          transaction.status == db.TxStatus.replaced) {
        continue;
      }
      merged.add(
        ChainTxRecord(
          // Rows written by this app store the coin as its enum name.
          coin: coin,
          networkId: transaction.networkId,
          hash: hash,
          outgoing: transaction.direction == db.TxDirection.outgoing,
          fromAddress: transaction.fromAddr,
          toAddress: transaction.toAddr,
          amountText: _localAmountText(transaction),
          assetContract: transaction.contract,
          timestamp: DateTime.fromMillisecondsSinceEpoch(transaction.createdAt),
          status: switch (transaction.status) {
            db.TxStatus.confirmed => ChainTxStatus.confirmed,
            db.TxStatus.failed || db.TxStatus.expired => ChainTxStatus.failed,
            db.TxStatus.submitted ||
            db.TxStatus.broadcast ||
            db.TxStatus.pending =>
              transaction.lastCheckOutcome == db.TxCheckOutcome.unknown
                  ? ChainTxStatus.unknown
                  : ChainTxStatus.pending,
            _ => ChainTxStatus.unknown,
          },
        ),
      );
    }
    merged.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return List.unmodifiable(merged);
  }

  String? _localAmountText(db.Transaction transaction) {
    if (transaction.operation == db.TxOperationKind.approvalRevoke) {
      return null;
    }
    final raw = BigInt.tryParse(transaction.amountRaw);
    final coin = Coin.values
        .where((candidate) => candidate.name == transaction.coin)
        .firstOrNull;
    if (raw == null || coin == null) return null;
    final contract = transaction.contract;
    if (contract != null) {
      final networkId = transaction.networkId;
      final tokens = networkId == null
          ? const <TokenInfo>[]
          : builtinTokensByNetworkId[networkId] ?? const <TokenInfo>[];
      final token = tokens
          .where(
            (candidate) => contract.startsWith('0x')
                ? candidate.contract.toLowerCase() == contract.toLowerCase()
                : candidate.contract == contract,
          )
          .firstOrNull;
      if (token == null) return null;
      return _formatLocalAmount(raw, token.decimals, token.symbol);
    }
    final (decimals, symbol) = switch (coin) {
      Coin.polygon => (18, 'POL'),
      Coin.avalanche => (18, 'AVAX'),
      Coin.bnb => (18, 'BNB'),
      Coin.tron => (6, 'TRX'),
      Coin.solana => (9, 'SOL'),
      _ => (18, 'ETH'),
    };
    return _formatLocalAmount(raw, decimals, symbol);
  }

  String _formatLocalAmount(BigInt raw, int decimals, String symbol) {
    final scale = BigInt.from(10).pow(decimals);
    final whole = raw ~/ scale;
    final remainder = (raw % scale).toString().padLeft(decimals, '0');
    final fraction = remainder
        .substring(0, remainder.length.clamp(0, 8))
        .replaceFirst(RegExp(r'0+$'), '');
    return '$whole${fraction.isEmpty ? '' : '.$fraction'} $symbol';
  }

  /// First-build refresh: no-op if one already ran or is running.
  void refreshIfNeeded() {
    if (_disposed) return;
    if (!_canRefresh()) {
      _refreshRequested = true;
      return;
    }
    if (_hasRefreshed || _refreshing) return;
    refresh();
  }

  void configurationReady() {
    if (_disposed) return;
    if (!_canRefresh() || !_refreshRequested) return;
    _refreshRequested = false;
    refreshIfNeeded();
  }

  /// Fetches every chain's history concurrently for the current wallet.
  /// A refresh superseded by a newer one (wallet switched mid-flight)
  /// discards its results.
  Future<void> refresh({bool loadingMore = false}) async {
    if (_disposed) return;
    if (!_canRefresh()) {
      _refreshRequested = true;
      return;
    }
    final wallet = _wallets.current;
    if (wallet == null || _refreshing) return;
    final metricStopwatch = Stopwatch()..start();
    final generation = ++_generation;
    final scope = _snapshotScope();
    final contextChanged =
        wallet.id != _walletId || scope != _activeSnapshotScope;
    _walletId = wallet.id;
    _activeSnapshotScope = scope;
    _refreshing = true;
    _loadingMore = loadingMore;
    final coins = wallet.addresses.enabledCoins;
    if (contextChanged) {
      // Wallet/network identity changes are a synchronous privacy boundary.
      // Remove the previous wallet's local rows and queued status notices
      // before any snapshot or database await can yield back to the UI.
      _pollTimer?.cancel();
      _localTransactions = const [];
      _hasPendingTransactions = false;
      _notices.clear();
      _remoteLimit = HistoryService.pageSize;
      _hasRefreshed = false;
      _showingCachedData = false;
      _lastUpdatedAt = null;
      _results = {
        for (final coin in coins) coin: const HistoryResult.loading(),
      };
      notifyListeners();
    }

    if (contextChanged && _snapshots != null) {
      final snapshot = await _snapshots.load(wallet.id, scope);
      if (generation != _generation) return;
      if (snapshot != null) {
        _results = {
          for (final coin in coins)
            coin:
                snapshot.results[coin] ??
                _results[coin] ??
                const HistoryResult.loading(),
        };
        _hasRefreshed = true;
        _showingCachedData = true;
        _lastUpdatedAt = snapshot.savedAt;
      }
    }
    _localTransactions = await _loadLocalTransactions();
    if (generation != _generation) return;
    final pendingTransactions = await _loadPendingTransactions();
    if (generation != _generation) return;
    _hasPendingTransactions = pendingTransactions.isNotEmpty;
    // A locally submitted incoming/outgoing row is useful immediately; do not
    // keep it behind the slowest explorer request.
    notifyListeners();

    final historyFuture = Future.wait([
      for (final coin in coins)
        _service
            .fetch(
              coin,
              wallet.addresses.forCoin(coin),
              limit: _remoteLimit,
              networkId: _activeNetworkId?.call(coin),
            )
            .then((result) {
              if (generation == _generation) {
                final previous = _results[coin];
                // Keep a restored/last-good chain visible while its live
                // explorer call fails. The final merge marks it stale.
                if (!(result.status == HistoryStatus.error &&
                    previous?.status == HistoryStatus.ok)) {
                  _results = {..._results, coin: result};
                }
                notifyListeners();
              }
              return (coin, result);
            }),
    ]);
    final statusFuture = _refreshPendingStatuses(
      generation,
      pendingTransactions,
    );
    final entries = await historyFuture;
    await statusFuture;

    if (generation != _generation) return; // superseded — drop stale results
    final liveFetchSucceeded = entries.any(
      (entry) => entry.$2.status == HistoryStatus.ok,
    );
    var retainedCached = false;
    _results = {
      for (final (coin, result) in entries)
        coin:
            result.status == HistoryStatus.error &&
                _results[coin]?.status == HistoryStatus.ok
            ? () {
                retainedCached = true;
                return _results[coin]!;
              }()
            : result,
    };
    _localTransactions = await _loadLocalTransactions();
    if (generation != _generation) return;
    final remainingPending = await _loadPendingTransactions();
    if (generation != _generation) return;
    _hasPendingTransactions = remainingPending.isNotEmpty;
    final remoteByIdentity = <_HistoryIdentity, ChainTxRecord>{};
    for (final result in _results.values) {
      if (result.status != HistoryStatus.ok) continue;
      for (final record in result.records) {
        final identity = _recordIdentity(record);
        if (identity != null) remoteByIdentity[identity] = record;
      }
    }
    for (final local in _localTransactions) {
      final hash = local.hash;
      final identity = _transactionIdentity(local);
      final remote = identity == null ? null : remoteByIdentity[identity];
      // Account-history absence is never finality evidence. An indexer can be
      // delayed, rate-limited or temporarily incomplete, so only the
      // hash-specific status service or an explicit terminal history status
      // may settle a local row.
      if (remote == null ||
          local.status == db.TxStatus.confirmed ||
          local.status == db.TxStatus.failed) {
        continue;
      }
      final next = switch (remote.status) {
        ChainTxStatus.confirmed => db.TxStatus.confirmed,
        ChainTxStatus.failed => db.TxStatus.failed,
        ChainTxStatus.pending || ChainTxStatus.unknown => null,
      };
      if (next == null) continue;
      final confirmedHash = hash!;
      if (_isEvmCoinName(local.coin)) {
        await _wallets.settleEvmTransactionForWallet(
          walletId: local.walletId,
          id: local.id,
          status: next,
          hash: confirmedHash,
        );
      } else {
        await _wallets.updateTransactionStatusForWallet(
          local.walletId,
          local.id,
          next,
          hash: confirmedHash,
          clearLastCheckOutcome: true,
        );
      }
      _enqueueNotice(
        TransactionStatusNotice(
          hash: confirmedHash,
          coin: Coin.values.firstWhere(
            (coin) => coin.name == local.coin,
            orElse: () => Coin.eth,
          ),
          confirmed: next == db.TxStatus.confirmed,
        ),
      );
    }
    _localTransactions = await _loadLocalTransactions();
    if (generation != _generation) return;
    _refreshing = false;
    _loadingMore = false;
    _hasRefreshed = true;
    _showingCachedData = retainedCached;
    final now = DateTime.now();
    _lastUpdatedAt = retainedCached ? (_lastUpdatedAt ?? now) : now;
    _schedulePoll();
    notifyListeners();

    if (_snapshots != null &&
        _results.values.any((result) => result.status == HistoryStatus.ok)) {
      _snapshots
          .save(
            wallet.id,
            HistorySnapshot(
              scope: scope,
              savedAt: _lastUpdatedAt!,
              results: _results,
            ),
          )
          .ignore();
    }
    ExperienceMetrics.instance.record(
      loadingMore
          ? ExperienceMetricNames.historyLoadMore
          : ExperienceMetricNames.historyRefresh,
      metricStopwatch.elapsed,
      success: liveFetchSucceeded,
    );
  }

  /// Expands the per-chain history window by one page. The service and
  /// Gateway remain bounded at 100 records so a tap cannot fan out into an
  /// unbounded explorer crawl.
  Future<void> loadMore() async {
    if (_disposed) return;
    if (!canLoadMore) return;
    _remoteLimit = math.min(100, _remoteLimit + HistoryService.pageSize);
    await refresh(loadingMore: true);
  }

  Future<void> _refreshPendingStatuses(
    int generation,
    List<db.Transaction> transactions,
  ) async {
    final pending = transactions
        .where(
          (transaction) =>
              transaction.hash != null &&
              (transaction.status == db.TxStatus.submitted ||
                  transaction.status == db.TxStatus.pending ||
                  transaction.status == db.TxStatus.broadcast),
        )
        .toList(growable: false);
    await _forEachBounded(
      pending,
      concurrency: pendingStatusConcurrency,
      action: (transaction) async {
        // Do not even start a queued network lookup after wallet/network
        // context changed or the owning route was disposed.
        if (generation != _generation) return;
        var status = ChainTransactionStatus.unknown;
        try {
          status = await _statusService.check(transaction);
        } catch (_) {
          // One malformed provider/resolver implementation is still only
          // unknown evidence for this hash. It cannot abort peer lookups or
          // invent a terminal state for the transaction.
        }
        if (generation != _generation) return;
        final checkedAt = DateTime.now().millisecondsSinceEpoch;
        final next = switch (status) {
          ChainTransactionStatus.confirmed => db.TxStatus.confirmed,
          ChainTransactionStatus.failed => db.TxStatus.failed,
          ChainTransactionStatus.pending => db.TxStatus.pending,
          ChainTransactionStatus.replaced => db.TxStatus.replaced,
          ChainTransactionStatus.expired => db.TxStatus.expired,
          ChainTransactionStatus.unknown => null,
        };
        final outcome = switch (status) {
          ChainTransactionStatus.pending => db.TxCheckOutcome.pending,
          ChainTransactionStatus.unknown => db.TxCheckOutcome.unknown,
          _ => null,
        };
        final terminal =
            status == ChainTransactionStatus.confirmed ||
            status == ChainTransactionStatus.failed ||
            status == ChainTransactionStatus.replaced ||
            status == ChainTransactionStatus.expired;
        final changed = next != null && next != transaction.status;
        final persisted = changed ? next : transaction.status;
        if (_isEvmCoinName(transaction.coin) &&
            changed &&
            (persisted == db.TxStatus.confirmed ||
                persisted == db.TxStatus.failed)) {
          await _wallets.settleEvmTransactionForWallet(
            walletId: transaction.walletId,
            id: transaction.id,
            status: persisted,
            hash: transaction.hash,
            lastCheckedAt: checkedAt,
          );
        } else {
          await _wallets.updateTransactionStatusForWallet(
            transaction.walletId,
            transaction.id,
            persisted,
            hash: transaction.hash,
            lastCheckedAt: checkedAt,
            lastCheckOutcome: outcome,
            clearLastCheckOutcome: terminal,
          );
        }
        if (changed) {
          if (next == db.TxStatus.confirmed ||
              next == db.TxStatus.failed ||
              next == db.TxStatus.expired) {
            final startedAt = transaction.broadcastAt ?? transaction.createdAt;
            final elapsedMs = checkedAt - startedAt;
            if (elapsedMs >= 0) {
              ExperienceMetrics.instance.record(
                ExperienceMetricNames.transactionFinality,
                Duration(milliseconds: elapsedMs),
                success: next == db.TxStatus.confirmed,
              );
            }
            _enqueueNotice(
              TransactionStatusNotice(
                hash: transaction.hash!,
                coin: Coin.values.firstWhere(
                  (coin) => coin.name == transaction.coin,
                  orElse: () => Coin.eth,
                ),
                confirmed: next == db.TxStatus.confirmed,
              ),
            );
          }
        }
      },
    );
  }

  void _enqueueNotice(TransactionStatusNotice notice) {
    if (_disposed) return;
    final duplicate = _notices.any(
      (queued) =>
          queued.hash == notice.hash && queued.confirmed == notice.confirmed,
    );
    if (!duplicate) _notices.add(notice);
  }

  void _schedulePoll() {
    if (_disposed) return;
    _pollTimer?.cancel();
    if (!_hasPendingTransactions) return;
    _pollTimer = Timer(pollInterval, _pollPending);
  }

  Future<void> _pollPending() async {
    if (_disposed) return;
    if (_refreshing) {
      _schedulePoll();
      return;
    }
    final generation = _generation;
    final pending = await _loadPendingTransactions();
    if (generation != _generation) return;
    _hasPendingTransactions = pending.isNotEmpty;
    await _refreshPendingStatuses(generation, pending);
    if (generation != _generation) return;
    _localTransactions = await _loadLocalTransactions();
    if (generation != _generation) return;
    final remainingPending = await _loadPendingTransactions();
    if (generation != _generation) return;
    _hasPendingTransactions = remainingPending.isNotEmpty;
    _schedulePoll();
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    if (state == AppLifecycleState.resumed) {
      if (_hasRefreshed) {
        _pollPending();
      } else {
        refresh();
      }
    } else {
      _pollTimer?.cancel();
    }
  }

  void _onWalletsChanged() {
    if (_disposed) return;
    final id = _wallets.current?.id;
    if (id == _walletId) return;
    if (id == null) {
      _clearWalletState();
      return;
    }
    _refreshing = false;
    refresh();
  }

  /// Clears every wallet-derived row and invalidates in-flight explorer/RPC
  /// work when deletion removes the final wallet. Without the generation
  /// change, a late response could restore the deleted wallet's history.
  void _clearWalletState() {
    _generation++;
    _walletId = null;
    _activeSnapshotScope = null;
    _refreshRequested = false;
    _refreshing = false;
    _loadingMore = false;
    _hasRefreshed = false;
    _showingCachedData = false;
    _lastUpdatedAt = null;
    _remoteLimit = HistoryService.pageSize;
    _pollTimer?.cancel();
    _localTransactions = const [];
    _hasPendingTransactions = false;
    _notices.clear();
    _results = {
      for (final coin in Coin.values) coin: const HistoryResult.loading(),
    };
    notifyListeners();
  }

  void _onNetworkChanged() {
    if (_disposed) return;
    if (_wallets.current != null) {
      _generation++;
      _refreshing = false;
      _activeSnapshotScope = null;
      refresh();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // Invalidates every async refresh/poll callback before the notifier is
    // disposed. Explorer and RPC futures cannot be cancelled, but their late
    // answers must never publish into a route that has already gone away.
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _wallets.removeListener(_onWalletsChanged);
    _networkChanges?.removeListener(_onNetworkChanged);
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }
}

class TransactionStatusNotice {
  const TransactionStatusNotice({
    required this.hash,
    required this.coin,
    required this.confirmed,
  });

  final String hash;
  final Coin coin;
  final bool confirmed;
}

/// Provides a [HistoryController] to history surfaces and rebuilds dependents
/// when it notifies. Like [MarketScope] there is no implicit controller:
/// tests may inject one through this scope; production history surfaces mount
/// one lazily when a live market context exists.
class HistoryScope extends InheritedNotifier<HistoryController> {
  const HistoryScope({
    super.key,
    required HistoryController controller,
    this.autoRefresh = false,
    required super.child,
  }) : super(notifier: controller);

  /// Production's app-wide host opts in. Tests and galleries can inject a
  /// controller without an unexpected network refresh.
  final bool autoRefresh;

  /// The controller, or null when no scope is mounted. Registers a dependency
  /// — rebuilds the caller on refresh.
  static HistoryController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HistoryScope>()?.notifier;

  static bool shouldAutoRefresh(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HistoryScope>()?.autoRefresh ??
      false;
}
