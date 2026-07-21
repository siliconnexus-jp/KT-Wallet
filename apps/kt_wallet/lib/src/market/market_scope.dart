import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

import '../state/app_prefs.dart';
import '../state/wallet_controller.dart';
import 'balance_service.dart';
import 'market_controller.dart';
import 'token_balance_service.dart';

/// Provides the app-wide [MarketController] and rebuilds dependents when it
/// notifies. Unlike [WalletScope] there is deliberately NO fallback: screens
/// rendered without a scope (gallery / goldens / plain widget tests) get null
/// from [maybeOf] and draw today's demo constants byte-for-byte.
class MarketScope extends InheritedNotifier<MarketController> {
  const MarketScope({
    super.key,
    required MarketController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The live controller, or null when no scope is mounted (demo rendering).
  /// Registers a dependency — rebuilds the caller on refresh.
  static MarketController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MarketScope>()?.notifier;

  /// Reads the controller without registering a dependency — safe outside
  /// build (post-frame refresh triggers, pull-to-refresh callbacks).
  static MarketController? read(BuildContext context) {
    final element =
        context.getElementForInheritedWidgetOfExactType<MarketScope>();
    return (element?.widget as MarketScope?)?.notifier;
  }
}

/// Builds the effective per-chain endpoint resolver: the user's persisted
/// override when [prefs] carries one, else the built-in default. Passing a
/// null [prefs] (no scope mounted) resolves the defaults everywhere.
RpcEndpointResolver prefsRpcEndpoints(AppPrefsController? prefs) =>
    (Coin coin) => prefs?.rpcOverride(coin) ?? defaultRpcEndpointFor(coin);

/// Owns the [MarketController]'s lifecycle so `main.dart` only has to mount a
/// single widget in the MaterialApp builder chain. Tests can inject a
/// pre-built [controller]; injected controllers are not disposed here.
///
/// When [prefs] is provided, the built controller's services resolve their
/// endpoints through the persisted RPC overrides, and changing an override
/// (in network settings) triggers a market refresh.
class MarketScopeHost extends StatefulWidget {
  const MarketScopeHost({
    super.key,
    required this.wallets,
    this.controller,
    this.prefs,
    required this.child,
  });

  final WalletController wallets;
  final MarketController? controller;
  final AppPrefsController? prefs;
  final Widget child;

  @override
  State<MarketScopeHost> createState() => _MarketScopeHostState();
}

class _MarketScopeHostState extends State<MarketScopeHost> {
  late final MarketController _controller = widget.controller ??
      MarketController(
        wallets: widget.wallets,
        balances: BalanceService(endpoints: prefsRpcEndpoints(widget.prefs)),
        tokens: TokenBalanceService(endpoints: prefsRpcEndpoints(widget.prefs)),
      );

  /// Last-seen effective endpoints, to refresh only on actual RPC changes
  /// (not on unrelated preference edits like the fiat currency).
  List<String>? _lastEndpoints;

  List<String> _snapshotEndpoints() {
    final resolve = prefsRpcEndpoints(widget.prefs);
    return [for (final coin in Coin.values) resolve(coin)];
  }

  @override
  void initState() {
    super.initState();
    if (widget.prefs != null) {
      _lastEndpoints = _snapshotEndpoints();
      widget.prefs!.addListener(_onPrefsChanged);
    }
  }

  void _onPrefsChanged() {
    final now = _snapshotEndpoints();
    if (listEquals(now, _lastEndpoints)) return;
    _lastEndpoints = now;
    // Balances fetched from the old node are stale the moment the endpoint
    // changes; refetch (the generation guard drops any in-flight results).
    _controller.refresh();
  }

  @override
  void dispose() {
    widget.prefs?.removeListener(_onPrefsChanged);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      MarketScope(controller: _controller, child: widget.child);
}
