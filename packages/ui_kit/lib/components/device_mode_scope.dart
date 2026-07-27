import 'package:flutter/widgets.dart';

/// Marks a subtree as running embedded in the combined single-installer app
/// (kt_wallet's first-launch device-mode picker).
///
/// When present, [exitMode] clears the persisted device-mode choice and
/// returns the user to the mode picker. When absent (e.g. the standalone
/// cold_signer build, or screens pumped directly in tests/goldens), UI that
/// depends on it — such as the "device mode" settings row — hides itself.
class DeviceModeScope extends InheritedWidget {
  const DeviceModeScope({
    super.key,
    required this.exitMode,
    required super.child,
  });

  /// Leaves the current mode and returns to the device-mode picker.
  final VoidCallback exitMode;

  /// The enclosing scope, or `null` when running standalone.
  static DeviceModeScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DeviceModeScope>();

  @override
  bool updateShouldNotify(DeviceModeScope oldWidget) =>
      exitMode != oldWidget.exitMode;
}
