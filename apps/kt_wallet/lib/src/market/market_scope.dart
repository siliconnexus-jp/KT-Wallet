import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

import '../state/app_prefs.dart';
import '../state/wallet_controller.dart';
import 'balance_service.dart';
import 'gateway_client.dart';
import 'market_controller.dart';
import 'price_service.dart';
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

/// Builds the gateway resolver backing the OPTIONAL gateway mode: it returns
/// a [GatewayClient] for the currently persisted `gateway.url`, or null when
/// the preference is blank (direct mode — the default) or no [prefs] is
/// wired. The client is cached per URL so repeated fetches reuse one
/// http.Client; saving a new URL (or clearing it) applies from the very next
/// call, same as the RPC override resolver.
GatewayResolver prefsGatewayResolver(AppPrefsController? prefs) {
  GatewayClient? cached;
  String? cachedUrl;
  return () {
    final url = prefs?.gatewayUrl;
    if (url == null || url.isEmpty) return null;
    if (cached == null || cachedUrl != url) {
      cached = GatewayClient(baseUrl: url);
      cachedUrl = url;
    }
    return cached;
  };
}

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
  /// One shared gateway resolver for all market services: they reuse a single
  /// [GatewayClient] (and its http.Client) while the URL is unchanged.
  late final GatewayResolver _gateway = prefsGatewayResolver(widget.prefs);

  late final MarketController _controller = widget.controller ??
      MarketController(
        wallets: widget.wallets,
        balances: BalanceService(
            endpoints: prefsRpcEndpoints(widget.prefs), gateway: _gateway),
        tokens: TokenBalanceService(
            endpoints: prefsRpcEndpoints(widget.prefs), gateway: _gateway),
        prices: PriceService(gateway: _gateway),
      );

  /// Last-seen effective endpoints (per-chain RPC + the gateway URL), to
  /// refresh only on actual network-config changes (not on unrelated
  /// preference edits like the fiat currency).
  List<String>? _lastEndpoints;

  List<String> _snapshotEndpoints() {
    final resolve = prefsRpcEndpoints(widget.prefs);
    return [
      for (final coin in Coin.values) resolve(coin),
      // Saving or clearing the gateway URL changes where every balance comes
      // from — refetch, exactly like an RPC override change.
      widget.prefs?.gatewayUrl ?? '',
    ];
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
