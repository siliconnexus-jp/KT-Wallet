import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Native bridge for screenshot notifications. It receives an event only;
/// screenshot pixels and files are never requested or retained.
class ScreenSecurity {
  ScreenSecurity._();

  static const MethodChannel _channel = MethodChannel('kt/screen_security');
  static final StreamController<void> _screenshots =
      StreamController<void>.broadcast();
  static final ValueNotifier<bool> _captured = ValueNotifier(false);
  static bool _installed = false;

  static Stream<void> get screenshots {
    _install();
    return _screenshots.stream;
  }

  /// True while the OS reports active screen recording or mirroring.
  static ValueListenable<bool> get captured {
    _install();
    return _captured;
  }

  static void _install() {
    if (_installed) return;
    _installed = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'screenshotTaken':
          _screenshots.add(null);
        case 'screenCaptureChanged':
          _captured.value = call.arguments == true;
      }
      return null;
    });
  }

  @visibleForTesting
  static void resetForTest() {
    _captured.value = false;
  }
}

/// Rebuilds sensitive content as concealed after the first screenshot event.
///
/// Screenshot callbacks are delivered after the OS has captured the screen,
/// so this cannot redact the image that already exists. It does make the
/// sensitive value disappear immediately and keeps it concealed for the
/// remaining lifetime of this widget. Re-entering the page creates a new
/// widget state and allows the user to review the value again.
class ScreenshotSensitiveBuilder extends StatefulWidget {
  const ScreenshotSensitiveBuilder({
    required this.builder,
    super.key,
    this.screenshotEvents,
  });

  final Widget Function(BuildContext context, bool concealed) builder;
  final Stream<void>? screenshotEvents;

  @override
  State<ScreenshotSensitiveBuilder> createState() =>
      _ScreenshotSensitiveBuilderState();
}

class _ScreenshotSensitiveBuilderState
    extends State<ScreenshotSensitiveBuilder> {
  StreamSubscription<void>? _subscription;
  bool _concealed = false;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _subscription = (widget.screenshotEvents ?? ScreenSecurity.screenshots)
        .listen((_) {
          if (mounted && !_concealed) setState(() => _concealed = true);
        });
  }

  @override
  void didUpdateWidget(ScreenshotSensitiveBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.screenshotEvents != widget.screenshotEvents) {
      _subscription?.cancel();
      _listen();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _concealed);
}

/// App-root security layer that shows a non-blocking screenshot warning.
class ScreenSecurityGuard extends StatefulWidget {
  const ScreenSecurityGuard({
    required this.child,
    super.key,
    this.screenshotEvents,
    this.warningDuration = const Duration(seconds: 6),
    this.locale,
  });

  final Widget child;
  final Stream<void>? screenshotEvents;
  final Duration warningDuration;

  /// Language for the warning. This guard sits ABOVE the app's MaterialApp so
  /// it cannot read `Localizations`; without an explicit value it falls back
  /// to the platform locale, which ignores an in-app language override — the
  /// banner then came out in the phone's language, not the app's.
  final Locale? locale;

  @override
  State<ScreenSecurityGuard> createState() => _ScreenSecurityGuardState();
}

class _ScreenSecurityGuardState extends State<ScreenSecurityGuard>
    with WidgetsBindingObserver {
  StreamSubscription<void>? _subscription;
  Timer? _hideTimer;
  bool _visible = false;
  bool _pending = false;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycle =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    _listen();
  }

  void _listen() {
    _subscription = (widget.screenshotEvents ?? ScreenSecurity.screenshots)
        .listen((_) {
          if (_lifecycle != AppLifecycleState.resumed) {
            _pending = true;
            return;
          }
          _showWarning();
        });
  }

  @override
  void didUpdateWidget(ScreenSecurityGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.screenshotEvents != widget.screenshotEvents) {
      _subscription?.cancel();
      _listen();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state == AppLifecycleState.resumed && _pending) {
      _pending = false;
      _showWarning();
    }
  }

  void _showWarning() {
    _hideTimer?.cancel();
    if (mounted) setState(() => _visible = true);
    _hideTimer = Timer(widget.warningDuration, _hide);
  }

  void _hide() {
    _hideTimer?.cancel();
    if (mounted && _visible) setState(() => _visible = false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  String _message(Locale locale) => switch (locale.languageCode) {
    'zh' => '当前屏幕已被截图，请注意您的钱包安全',
    'ja' => 'スクリーンショットが撮影されました。ウォレットの安全にご注意ください',
    _ => 'A screenshot was taken. Please protect your wallet.',
  };

  @override
  Widget build(BuildContext context) {
    final locale =
        widget.locale ?? WidgetsBinding.instance.platformDispatcher.locale;
    final view = View.of(context);
    final topPadding = MediaQueryData.fromView(view).padding.top;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        textDirection: TextDirection.ltr,
        children: [
          widget.child,
          if (_visible)
            Positioned(
              key: const ValueKey('screen-security-warning'),
              left: 12,
              right: 12,
              top: topPadding + 8,
              child: Material(
                elevation: 12,
                color: const Color(0xFF171C2B),
                shadowColor: Colors.black54,
                borderRadius: BorderRadius.circular(16),
                child: Semantics(
                  liveRegion: true,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.shield_outlined,
                          color: Color(0xFF9B87F5),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _message(locale),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('screen-security-warning-close'),
                          onPressed: _hide,
                          icon: const Icon(Icons.close, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
