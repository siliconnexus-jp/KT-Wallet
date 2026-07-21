import 'package:flutter/widgets.dart';

import '../state/wallet_controller.dart';
import 'market_controller.dart';

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

/// Owns the [MarketController]'s lifecycle so `main.dart` only has to mount a
/// single widget in the MaterialApp builder chain. Tests can inject a
/// pre-built [controller]; injected controllers are not disposed here.
class MarketScopeHost extends StatefulWidget {
  const MarketScopeHost({
    super.key,
    required this.wallets,
    this.controller,
    required this.child,
  });

  final WalletController wallets;
  final MarketController? controller;
  final Widget child;

  @override
  State<MarketScopeHost> createState() => _MarketScopeHostState();
}

class _MarketScopeHostState extends State<MarketScopeHost> {
  late final MarketController _controller =
      widget.controller ?? MarketController(wallets: widget.wallets);

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      MarketScope(controller: _controller, child: widget.child);
}
