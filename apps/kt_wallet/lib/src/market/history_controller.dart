import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter/widgets.dart';

import '../state/wallet_controller.dart';
import 'history_service.dart';

/// Live transaction history for the current wallet, per chain. Mirrors the
/// [MarketController] lifecycle patterns (generation-guarded refresh, wallet
/// switch listener) but is owned by the records tab, not `main.dart` — it is
/// mounted lazily the first time the tab builds under a live market context.
class HistoryController extends ChangeNotifier {
  HistoryController({
    required WalletController wallets,
    HistoryService? service,
  })  :
        // ignore: prefer_initializing_formals
        _wallets = wallets,
        _service = service ?? HistoryService() {
    _walletId = _wallets.current?.id;
    _wallets.addListener(_onWalletsChanged);
  }

  final WalletController _wallets;
  final HistoryService _service;

  String? _walletId;
  int _generation = 0;
  bool _refreshing = false;
  bool _hasRefreshed = false;

  Map<Coin, HistoryResult> _results = {
    for (final coin in Coin.values) coin: const HistoryResult.loading(),
  };

  HistoryResult resultFor(Coin coin) => _results[coin]!;

  /// True until the first refresh completes (rows render '--' placeholders).
  bool get isLoading => !_hasRefreshed || _refreshing;

  /// At least one chain returned a real (possibly empty) history.
  bool get hasLiveRecords =>
      _results.values.any((r) => r.status == HistoryStatus.ok);

  /// Every chain reported "no keyless history API" — the tab shows the
  /// unsupported empty-state line instead of demo rows.
  bool get allUnsupported =>
      !isLoading &&
      _results.values.every((r) => r.status == HistoryStatus.unsupported);

  /// Every supported chain errored (e.g. the demo mock address was rejected):
  /// the tab falls back to demo rows behind the offline banner.
  bool get isError => !isLoading && !hasLiveRecords && !allUnsupported;

  /// All successfully fetched records across chains, newest first.
  List<ChainTxRecord> get records {
    final merged = [
      for (final result in _results.values)
        if (result.status == HistoryStatus.ok) ...result.records,
    ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
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
    _results = {
      for (final coin in Coin.values) coin: const HistoryResult.loading(),
    };
    notifyListeners();

    final entries = await Future.wait([
      for (final coin in Coin.values)
        _service
            .fetch(coin, wallet.addresses.forCoin(coin))
            .then((result) => (coin, result)),
    ]);

    if (generation != _generation) return; // superseded — drop stale results
    _results = {for (final (coin, result) in entries) coin: result};
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

  @override
  void dispose() {
    _wallets.removeListener(_onWalletsChanged);
    super.dispose();
  }
}

/// Provides a [HistoryController] to the records tab and rebuilds dependents
/// when it notifies. Like [MarketScope] there is NO fallback: without a scope
/// (and without a live market context to lazily mount one) the tab renders
/// the demo records byte-for-byte. Tests inject a controller through this
/// scope; production mounts one lazily inside the records tab itself.
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
