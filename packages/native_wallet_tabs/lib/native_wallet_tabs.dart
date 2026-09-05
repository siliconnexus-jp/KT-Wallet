import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';

@immutable
class NativeWalletTab {
  const NativeWalletTab({required this.title, required this.symbol});
  final String title;
  final String symbol;

  Map<String, Object> toMap() => {'title': title, 'symbol': symbol};
}

/// A navigation-only UIKit bridge. Pages and sensitive state stay in Flutter.
class NativeWalletTabs extends StatefulWidget {
  const NativeWalletTabs({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.fallback,
    this.enabled = true,
  }) : assert(items.length >= 2 && items.length <= 5),
       assert(selectedIndex >= 0 && selectedIndex < items.length);

  final List<NativeWalletTab> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget fallback;
  final bool enabled;

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  // Includes a transparent strip above the system bar, but never double-counts
  // the home indicator. Insets in page content use the same value.
  static double extentFor(BuildContext context) =>
      80 + MediaQuery.viewPaddingOf(context).bottom;

  @override
  State<NativeWalletTabs> createState() => _NativeWalletTabsState();
}

class _NativeWalletTabsState extends State<NativeWalletTabs>
    with WidgetsBindingObserver {
  MethodChannel? _channel;
  Map<String, Object>? _configuration;
  int _revision = 0;
  bool _resumed = true;
  bool _unavailable = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _resumed = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() => _resumed = state == AppLifecycleState.resumed);
    if (!_resumed) {
      // Disable immediately, before the next Dart frame is rendered.
      unawaited(_invoke('setEnabled', false));
    }
  }

  bool get _enabled => widget.enabled && _resumed;

  void _created(int id) {
    if (!mounted) return;
    _channel = MethodChannel('kt/native_wallet_tabs/$id')
      ..setMethodCallHandler(_handleNativeCall);
    // Updates can arrive while the platform view is still being created.
    unawaited(_invoke('update', _configuration));
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (!mounted || !_enabled || call.method != 'selected') return;
    final args = call.arguments;
    if (args is! Map) return;
    final index = args['index'];
    if (args['revision'] != _revision ||
        index is! int ||
        index < 0 ||
        index >= widget.items.length) {
      return;
    }
    widget.onSelected(index);
  }

  Future<void> _invoke(String method, Object? arguments) async {
    try {
      await _channel?.invokeMethod<void>(method, arguments);
    } on PlatformException {
      if (mounted && method != 'dispose') setState(() => _unavailable = true);
    } on MissingPluginException {
      if (mounted && method != 'dispose') setState(() => _unavailable = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!NativeWalletTabs.supported || _unavailable) return widget.fallback;
    final next = <String, Object>{
      'items': [for (final item in widget.items) item.toMap()],
      'selectedIndex': widget.selectedIndex,
      'dark': Theme.of(context).brightness == Brightness.dark,
      'highContrast': MediaQuery.highContrastOf(context),
      'enabled': _enabled,
    };
    // Compare the values, not newly allocated list/map identities.
    final old = _configuration;
    final changed =
        old == null ||
        old['selectedIndex'] != next['selectedIndex'] ||
        old['dark'] != next['dark'] ||
        old['highContrast'] != next['highContrast'] ||
        old['enabled'] != next['enabled'] ||
        !listEquals(
          (old['items']! as List<Map<String, Object>>)
              .map((item) => (item['title'], item['symbol']))
              .toList(),
          widget.items.map((item) => (item.title, item.symbol)).toList(),
        );
    if (changed) {
      _configuration = {...next, 'revision': ++_revision};
      // Keep native platform calls outside Flutter's build/layout phase.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_invoke('update', _configuration));
      });
    }
    return SizedBox(
      height: NativeWalletTabs.extentFor(context),
      child: ExcludeSemantics(
        excluding: !_enabled,
        child: IgnorePointer(
          ignoring: !_enabled,
          child: UiKitView(
            viewType: 'kt/native_wallet_tabs',
            creationParams: _configuration,
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: _created,
            // This strip belongs to navigation, even though its material is
            // visually translucent. Otherwise asset-row taps underneath win
            // Flutter's gesture arena and UIKit never receives the touch.
            hitTestBehavior: PlatformViewHitTestBehavior.opaque,
            gestureRecognizers: {
              Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
            },
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _channel?.setMethodCallHandler(null);
    unawaited(_invoke('dispose', null));
    super.dispose();
  }
}
