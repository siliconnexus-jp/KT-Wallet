// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter/widgets.dart';
import 'package:wallet_data/wallet_data.dart' as db;

import '../state/wallet_controller.dart';
import 'history_service.dart';
import 'token_balance_service.dart';
import 'transaction_status_service.dart';

/// Live transaction history for the current wallet, per chain. Mirrors the
/// [MarketController] lifecycle patterns (generation-guarded refresh, wallet
/// switch listener) but is owned by the history surface, not `main.dart` — it
/// is mounted lazily when the full history page or an asset history section
/// builds under a live market context.
class HistoryController extends ChangeNotifier with WidgetsBindingObserver {
  HistoryController({
    required WalletController wallets,
    HistoryService? service,
    TransactionStatusService? statusService,
    Set<String> Function()? activeNetworkIds,
    Listenable? networkChanges,
    this.pollInterval = const Duration(seconds: 8),
  }) : _wallets = wallets,
       _service = service ?? HistoryService(),
       _statusService = statusService ?? TransactionStatusService(),
       _activeNetworkIds = activeNetworkIds,
       _networkChanges = networkChanges {
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
  final Listenable? _networkChanges;

  Future<List<db.Transaction>> _loadLocalTransactions() =>
      _wallets.localTransactions(networkIds: _activeNetworkIds?.call());

  String? _walletId;
  int _generation = 0;
  bool _refreshing = false;
  bool _hasRefreshed = false;
  Timer? _pollTimer;
  List<db.Transaction> _localTransactions = const [];

  Map<Coin, HistoryResult> _results = {
    for (final coin in Coin.values) coin: const HistoryResult.loading(),
  };

  HistoryResult resultFor(Coin coin) =>
      _results[coin] ?? const HistoryResult.unsupported();

  /// True until the first refresh completes (rows render structural placeholders).
  bool get isLoading => !_hasRefreshed;
  bool get isRefreshing => _refreshing;

  /// At least one chain returned a real (possibly empty) history.
  bool get hasLiveRecords =>
      _results.values.any((r) => r.status == HistoryStatus.ok);

  /// Every chain reported "no keyless history API".
  bool get allUnsupported =>
      !isLoading &&
      _results.values.every((r) => r.status == HistoryStatus.unsupported);

  /// Every supported chain errored (for example, the RPC is unavailable).
  bool get isError => !isLoading && !hasLiveRecords && !allUnsupported;

  db.Transaction? localTransactionForHash(String hash) {
    for (final transaction in _localTransactions) {
      if (transaction.hash == hash) return transaction;
    }
    return null;
  }

  /// All successfully fetched records across chains, newest first.
  List<ChainTxRecord> get records {
    final merged = [
      for (final result in _results.values)
        if (result.status == HistoryStatus.ok) ...result.records,
    ];
    final remoteHashes = {for (final record in merged) record.hash};
    for (final transaction in _localTransactions) {
      final hash = transaction.hash;
      if (hash == null || remoteHashes.contains(hash)) continue;
      if (transaction.status == db.TxStatus.failed ||
          transaction.status == db.TxStatus.expired ||
          transaction.status == db.TxStatus.dropped ||
          transaction.status == db.TxStatus.replaced) {
        continue;
      }
      merged.add(
        ChainTxRecord(
          // Rows written by this app store the coin as its enum name.
          coin: Coin.values.firstWhere(
            (c) => c.name == transaction.coin,
            orElse: () => Coin.eth,
          ),
          hash: hash,
          outgoing: transaction.direction == db.TxDirection.outgoing,
          fromAddress: transaction.fromAddr,
          toAddress: transaction.toAddr,
          amountText: _localAmountText(transaction),
          assetContract: transaction.contract,
          timestamp: DateTime.fromMillisecondsSinceEpoch(transaction.createdAt),
          confirmed: transaction.status == db.TxStatus.confirmed,
        ),
      );
    }
    merged.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return List.unmodifiable(merged);
  }

  String? _localAmountText(db.Transaction transaction) {
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
    if (_hasRefreshed || _refreshing) return;
    refresh();
  }

  /// Fetches every chain's history concurrently for the current wallet.
  /// A refresh superseded by a newer one (wallet switched mid-flight)
  /// discards its results.
  Future<void> refresh() async {
    final wallet = _wallets.current;
    if (wallet == null || _refreshing) return;
    final generation = ++_generation;
    _refreshing = true;
    final coins = wallet.addresses.enabledCoins;
    if (!_hasRefreshed) {
      _results = {
        for (final coin in coins) coin: const HistoryResult.loading(),
      };
    }
    _localTransactions = await _loadLocalTransactions();
    if (generation != _generation) return;
    // A locally submitted incoming/outgoing row is useful immediately; do not
    // keep it behind the slowest explorer request.
    notifyListeners();

    final historyFuture = Future.wait([
      for (final coin in coins)
        _service.fetch(coin, wallet.addresses.forCoin(coin)).then((result) {
          if (generation == _generation) {
            _results = {..._results, coin: result};
            notifyListeners();
          }
          return (coin, result);
        }),
    ]);
    final statusFuture = _refreshPendingStatuses(
      generation,
      _localTransactions,
    );
    final entries = await historyFuture;
    await statusFuture;

    if (generation != _generation) return; // superseded — drop stale results
    _results = {for (final (coin, result) in entries) coin: result};
    _localTransactions = await _loadLocalTransactions();
    if (generation != _generation) return;
    final remoteByHash = {
      for (final result in _results.values)
        if (result.status == HistoryStatus.ok)
          for (final record in result.records) record.hash: record,
    };
    for (final local in _localTransactions) {
      final hash = local.hash;
      final remote = hash == null ? null : remoteByHash[hash];
      if (remote == null) {
        final submittedAt = local.broadcastAt ?? local.createdAt;
        final stale =
            DateTime.now().millisecondsSinceEpoch - submittedAt >
            const Duration(hours: 24).inMilliseconds;
        if (stale && local.status == db.TxStatus.pending) {
          await _wallets.updateTransactionStatus(
            local.id,
            db.TxStatus.dropped,
            hash: hash,
          );
        }
        continue;
      }
      if (local.status == db.TxStatus.confirmed) continue;
      await _wallets.updateTransactionStatus(
        local.id,
        remote.confirmed ? db.TxStatus.confirmed : db.TxStatus.failed,
        hash: hash,
      );
    }
    _localTransactions = await _loadLocalTransactions();
    if (generation != _generation) return;
    _refreshing = false;
    _hasRefreshed = true;
    _schedulePoll();
    notifyListeners();
  }

  Future<void> _refreshPendingStatuses(
    int generation,
    List<db.Transaction> transactions,
  ) async {
    final pending = transactions.where(
      (transaction) =>
          transaction.hash != null &&
          (transaction.status == db.TxStatus.submitted ||
              transaction.status == db.TxStatus.pending ||
              transaction.status == db.TxStatus.broadcast),
    );
    await Future.wait([
      for (final transaction in pending)
        _statusService.check(transaction).then((status) async {
          if (generation != _generation) return;
          final next = switch (status) {
            ChainTransactionStatus.confirmed => db.TxStatus.confirmed,
            ChainTransactionStatus.failed => db.TxStatus.failed,
            ChainTransactionStatus.pending => db.TxStatus.pending,
            ChainTransactionStatus.unknown => null,
          };
          if (next != null && next != transaction.status) {
            await _wallets.updateTransactionStatus(
              transaction.id,
              next,
              hash: transaction.hash,
            );
          }
        }),
    ]);
  }

  void _schedulePoll() {
    _pollTimer?.cancel();
    final hasPending = _localTransactions.any(
      (transaction) =>
          transaction.status == db.TxStatus.submitted ||
          transaction.status == db.TxStatus.pending ||
          transaction.status == db.TxStatus.broadcast,
    );
    if (!hasPending) return;
    _pollTimer = Timer(pollInterval, _pollPending);
  }

  Future<void> _pollPending() async {
    if (_refreshing) {
      _schedulePoll();
      return;
    }
    final generation = _generation;
    final local = await _loadLocalTransactions();
    if (generation != _generation) return;
    await _refreshPendingStatuses(generation, local);
    if (generation != _generation) return;
    _localTransactions = await _loadLocalTransactions();
    if (generation != _generation) return;
    _schedulePoll();
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
    final id = _wallets.current?.id;
    if (id == _walletId) return;
    _walletId = id;
    if (id != null) {
      _refreshing = false;
      refresh();
    }
  }

  void _onNetworkChanged() {
    if (_wallets.current != null) {
      _generation++;
      _refreshing = false;
      refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _wallets.removeListener(_onWalletsChanged);
    _networkChanges?.removeListener(_onNetworkChanged);
    super.dispose();
  }
}

/// Provides a [HistoryController] to history surfaces and rebuilds dependents
/// when it notifies. Like [MarketScope] there is no implicit controller:
/// tests may inject one through this scope; production history surfaces mount
/// one lazily when a live market context exists.
class HistoryScope extends InheritedNotifier<HistoryController> {
  const HistoryScope({
    super.key,
    required HistoryController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller, or null when no scope is mounted. Registers a dependency
  /// — rebuilds the caller on refresh.
  static HistoryController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HistoryScope>()?.notifier;
}
