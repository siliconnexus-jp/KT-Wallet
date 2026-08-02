import 'package:flutter/widgets.dart';

import 'wallet_controller.dart';

/// Provides the app-wide [WalletController] to the widget tree and rebuilds
/// dependents when it changes.
class WalletScope extends InheritedNotifier<WalletController> {
  const WalletScope({
    super.key,
    required WalletController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The live controller. Tests and galleries must inject their own explicit
  /// fixture scope; production and standalone widgets both fail closed.
  static WalletController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<WalletScope>();
    final controller = scope?.notifier;
    if (controller != null) return controller;
    throw FlutterError(
      'WalletScope.of() called outside the production WalletScope.',
    );
  }

  /// Returns null for intentionally standalone renders. Screens may use this
  /// to show an unavailable state, but never to acquire fixture wallet data.
  static WalletController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WalletScope>()?.notifier;
}
