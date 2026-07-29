// ignore_for_file: prefer_initializing_formals

import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter/widgets.dart';
import 'package:wallet_data/wallet_data.dart' as db;

import '../state/wallet_controller.dart';
import 'history_service.dart';

/// Live transaction history for the current wallet, per chain. Mirrors the
/// [MarketController] lifecycle patterns (generation-guarded refresh, wallet
/// switch listener) but is owned by the history surface, not `main.dart` — it
/// is mounted lazily when the full history page or an asset history section
/// builds under a live market context.
class HistoryController extends ChangeNotifier {
  HistoryController({
    required WalletController wallets,
    HistoryService? service,
    Set<String> Function()? activeNetworkIds,
    Listenable? networkChanges,
  }) : _wallets = wallets,
       _service = service ?? HistoryService(),
       _activeNetworkIds = activeNetworkIds,
       _networkChanges = networkChanges {
    _walletId = _wallets.current?.id;
    _wallets.addListener(_onWalletsChanged);
    _networkChanges?.addListener(_onNetworkChanged);
  }

  final WalletController _wallets;
  final HistoryService _service;

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
  List<db.Transaction> _localTransactions = const [];

  Map<Coin, HistoryResult> _results = {
    for (final coin in Coin.values) coin: const HistoryResult.loading(),
  };

  HistoryResult resultFor(Coin coin) =>
      _results[coin] ?? const HistoryResult.unsupported();

  /// True until the first refresh completes (rows render structural placeholders).
  bool get isLoading => !_hasRefreshed || _refreshing;

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
          outgoing: true,
          amountText: null,
          assetContract: transaction.contract,
          timestamp: DateTime.fromMillisecondsSinceEpoch(transaction.createdAt),
          confirmed: transaction.status == db.TxStatus.confirmed,
        ),
      );
    }
    merged.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return List.unmodifiable(merged);
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
    if (wallet == null) return;
    final generation = ++_generation;
    _refreshing = true;
    final coins = wallet.addresses.enabledCoins;
    _results = {for (final coin in coins) coin: const HistoryResult.loading()};
    notifyListeners();

    final entries = await Future.wait([
      for (final coin in coins)
        _service
            .fetch(coin, wallet.addresses.forCoin(coin))
            .then((result) => (coin, result)),
    ]);

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
    notifyListeners();
  }

  void _onWalletsChanged() {
    final id = _wallets.current?.id;
    if (id == _walletId) return;
    _walletId = id;
    if (id != null) refresh();
  }

  void _onNetworkChanged() {
    if (_wallets.current != null) refresh();
  }

  @override
  void dispose() {
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
