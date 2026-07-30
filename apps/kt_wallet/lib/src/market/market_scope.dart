import 'package:chains/chains.dart' show Chain;
import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

import '../state/app_prefs.dart';
import '../state/networks.dart';
import '../state/wallet_controller.dart';
import 'balance_service.dart';
import 'gateway_client.dart';
import 'market_controller.dart';
import 'market_snapshot.dart';
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
    final element = context
        .getElementForInheritedWidgetOfExactType<MarketScope>();
    return (element?.widget as MarketScope?)?.notifier;
  }
}

/// The [Chain] (protocol family) served by an RPC-endpoint [Coin] slot.
Chain chainForRpcCoin(Coin coin) => switch (coin) {
  Coin.eth => Chain.ethereum,
  Coin.polygon => Chain.polygon,
  Coin.base => Chain.base,
  Coin.arbitrum => Chain.arbitrum,
  Coin.avalanche => Chain.avalanche,
  Coin.bnb => Chain.bnb,
  Coin.tron => Chain.tron,
  Coin.solana => Chain.solana,
};

/// Builds the effective per-chain endpoint resolver, precedence highest first:
///
/// 1. the user's persisted AppPrefs RPC override (existing behavior — an
///    explicit URL the user typed always wins);
/// 2. the ACTIVE network's rpcUrl from the [NetworkController] (environment
///    switch / per-chain pin / custom network);
/// 3. the built-in mainnet default.
///
/// Both sources are re-read on every call, so a settings change or network
/// switch applies from the very next fetch. Passing null for either source
/// skips that level (a null [networks] reproduces the pre-network behavior
/// exactly, because the mainnet profile's URLs equal the built-in defaults).
RpcEndpointResolver effectiveRpcEndpoints(
  AppPrefsController? prefs,
  NetworkController? networks,
) =>
    (Coin coin) =>
        prefs?.rpcOverride(coin) ??
        networks?.activeFor(chainForRpcCoin(coin)).rpcUrl ??
        defaultRpcEndpointFor(coin);

/// Back-compat name: prefs override → built-in default (no network source).
RpcEndpointResolver prefsRpcEndpoints(AppPrefsController? prefs) =>
    effectiveRpcEndpoints(prefs, null);

/// Builds the token-registry resolver for the active networks: each chain
/// contributes the built-in tokens of its ACTIVE network id (mainnet ids keep
/// today's entries; testnets and custom networks have none — mainnet
/// contracts must never be queried elsewhere). A null [networks] resolves the
/// full mainnet registry, i.e. today's behavior.
TokenRegistryResolver networkTokenRegistry(NetworkController? networks) =>
    () => networks == null
    ? builtinTokens
    : [
        for (final chain in Chain.values)
          ...builtinTokensByNetworkId[networks.activeFor(chain).id] ??
              const <TokenInfo>[],
      ];

/// Links an [AppPrefsController] to the app's active-network source.
///
/// WHY: the gateway's chain-scoped methods must carry the ACTIVE network id
/// (an omitted one means MAINNET), but most call sites build their gateway
/// resolver from prefs alone — `prefsGatewayResolver(AppPrefsScope.maybeOf(
/// context))`. [MarketScopeHost], mounted app-wide directly under the
/// [NetworkScope], publishes the live [NetworkController] here, so every
/// resolver built from the same prefs controller scopes its calls to the same
/// networks. Keyed by prefs instance rather than global, so tests that build
/// their own controller are never affected by another test's wiring; an
/// unlinked controller simply resolves to null (no `network` param, today's
/// behavior).
final Expando<NetworkController> _networkSourceFor = Expando(
  'kt.activeNetworkSource',
);
final Expando<_GatewayClientSlot> _gatewayClientFor = Expando(
  'kt.sharedGatewayClient',
);

class _GatewayClientSlot {
  String? url;
  GatewayClient? client;
}

/// The active network id of [coin]'s chain family for [prefs]-scoped callers,
/// preferring an explicitly passed [networks] source over the linked one.
String? _activeNetworkId(
  AppPrefsController? prefs,
  NetworkController? networks,
  Coin coin,
) {
  final source = networks ?? (prefs == null ? null : _networkSourceFor[prefs]);
  return source?.activeFor(chainForRpcCoin(coin)).id;
}

/// Builds the gateway resolver backing the OPTIONAL gateway mode: it returns
/// a [GatewayClient] for the effective `gateway.url`, or null when the user
/// explicitly selected direct mode or no [prefs] is wired. Fresh installs use
/// the KT production Gateway. The client is cached per URL so repeated fetches reuse one
/// http.Client; saving a new URL (or clearing it) applies from the very next
/// call, same as the RPC override resolver.
///
/// The client is network-scoped: every chain-scoped call carries the active
/// network id from [networks] (or, when omitted, from the source linked to
/// [prefs] by [MarketScopeHost]), and the gateway is bypassed entirely for a
/// network it does not advertise. The lookup happens per call, so switching
/// environment or pinning a network applies from the very next request
/// without rebuilding the client.
GatewayResolver prefsGatewayResolver(
  AppPrefsController? prefs, [
  NetworkController? networks,
]) {
  if (prefs != null && networks != null) {
    _networkSourceFor[prefs] = networks;
  }
  return () {
    final url = prefs?.gatewayUrl;
    if (url == null || url.isEmpty) return null;
    final slot = _gatewayClientFor[prefs!] ??= _GatewayClientSlot();
    if (slot.client == null || slot.url != url) {
      slot.client?.close();
      slot.client = GatewayClient(
        baseUrl: url,
        networks: (coin) => _activeNetworkId(prefs, null, coin),
        // Mobile networks should not spend the full direct-RPC timeout merely
        // discovering that the preferred Gateway is unreachable.
        timeout: const Duration(seconds: 4),
      );
      slot.url = url;
    }
    return slot.client;
  };
}

/// Owns the [MarketController]'s lifecycle so `main.dart` only has to mount a
/// single widget in the MaterialApp builder chain. Tests can inject a
/// pre-built [controller]; injected controllers are not disposed here.
///
/// When [prefs] is provided, the built controller's services resolve their
/// endpoints through the persisted RPC overrides, and changing an override
/// (in network settings) triggers a market refresh.
///
/// The active-network source is the enclosing [NetworkScope] (mounted above
/// this host in main.dart) or the injected [networks] override (tests); the
/// effective endpoint per chain is prefs override → active network → default,
/// the token registry follows the active network ids, prices are suppressed
/// for testnet chains, and any network change triggers a refresh exactly like
/// a prefs endpoint change.
class MarketScopeHost extends StatefulWidget {
  const MarketScopeHost({
    super.key,
    required this.wallets,
    this.controller,
    this.prefs,
    this.networks,
    this.ready = true,
    required this.child,
  });

  final WalletController wallets;
  final MarketController? controller;
  final AppPrefsController? prefs;

  /// Explicit active-network source override (tests); production leaves this
  /// null and the enclosing [NetworkScope] is used.
  final NetworkController? networks;
  final bool ready;

  final Widget child;

  @override
  State<MarketScopeHost> createState() => _MarketScopeHostState();
}

class _MarketScopeHostState extends State<MarketScopeHost> {
  /// One shared gateway resolver for all market services: they reuse a single
  /// [GatewayClient] (and its http.Client) while the URL is unchanged.
  late final GatewayResolver _gateway = prefsGatewayResolver(widget.prefs);

  /// The active-network source in effect (injected override or the enclosing
  /// [NetworkScope]); resolved in [didChangeDependencies] BEFORE the first
  /// build touches [_controller], and read through this field by the service
  /// resolvers on every fetch.
  NetworkController? _networks;

  late final MarketController _controller =
      widget.controller ??
      MarketController(
        wallets: widget.wallets,
        balances: BalanceService(endpoints: _endpoints, gateway: _gateway),
        tokens: TokenBalanceService(
          endpoints: _endpoints,
          gateway: _gateway,
          registry: () => networkTokenRegistry(_networks)(),
        ),
        prices: PriceService(gateway: _gateway),
        isTestnet: (coin) =>
            _networks?.activeFor(chainForRpcCoin(coin)).isTestnet ?? false,
        snapshots: WalletMarketSnapshotStore(widget.wallets),
        snapshotScope: () => [
          for (final coin in Coin.values)
            _networks?.activeFor(chainForRpcCoin(coin)).id ?? 'mainnet',
        ].join('|'),
        canRefresh: () => widget.ready,
      );

  /// Effective endpoint for [coin] at call time (prefs override → active
  /// network → default); a closure over the mutable [_networks] field so the
  /// `late final` services always see the current source.
  String _endpoints(Coin coin) =>
      effectiveRpcEndpoints(widget.prefs, _networks)(coin);

  /// Last-seen effective network config (per-chain endpoints, active network
  /// ids and the gateway URL), to refresh only on actual changes (not on
  /// unrelated preference edits like the fiat currency).
  List<String>? _lastEndpoints;

  List<String> _snapshotEndpoints() {
    return [
      for (final coin in Coin.values) _endpoints(coin),
      // The active network id can change what is fetched (token registry,
      // testnet fiat suppression) even when two networks share an endpoint.
      for (final coin in Coin.values)
        _networks?.activeFor(chainForRpcCoin(coin)).id ?? '',
      // Saving or clearing the gateway URL changes where every balance comes
      // from — refetch, exactly like an RPC override change.
      widget.prefs?.gatewayUrl ?? '',
    ];
  }

  @override
  void initState() {
    super.initState();
    widget.prefs?.addListener(_onConfigChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final networks = widget.networks ?? NetworkScope.maybeOf(context);
    if (!identical(networks, _networks)) {
      _networks?.removeListener(_onConfigChanged);
      _networks = networks;
      _networks?.addListener(_onConfigChanged);
    }
    // Publish the active-network source for every gateway resolver built from
    // this prefs controller (see [_networkSourceFor]); null unlinks it.
    final prefs = widget.prefs;
    if (prefs != null) _networkSourceFor[prefs] = _networks;
    // (Re-)baseline against the current source so the next change notification
    // compares against reality, not a snapshot from another source.
    _lastEndpoints = _snapshotEndpoints();
  }

  void _onConfigChanged() {
    final now = _snapshotEndpoints();
    if (listEquals(now, _lastEndpoints)) return;
    _lastEndpoints = now;
    if (!widget.ready) return;
    // Balances fetched from the old node are stale the moment the endpoint
    // (or active network) changes; refetch (the generation guard drops any
    // in-flight results).
    _controller.refresh();
  }

  @override
  void didUpdateWidget(MarketScopeHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.ready && widget.ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.refreshIfNeeded();
      });
    }
  }

  @override
  void dispose() {
    widget.prefs?.removeListener(_onConfigChanged);
    _networks?.removeListener(_onConfigChanged);
    // Unlink only our own publication: a replacement host may already have
    // linked the same prefs controller to its own source.
    final prefs = widget.prefs;
    if (prefs != null && identical(_networkSourceFor[prefs], _networks)) {
      _networkSourceFor[prefs] = null;
    }
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      MarketScope(controller: _controller, child: widget.child);
}
