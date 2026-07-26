import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Native bridge for screenshot notifications. It receives an event only;
/// screenshot pixels and files are never requested or retained.
class ScreenSecurity {
  ScreenSecurity._();

  static const MethodChannel _channel = MethodChannel('kt/screen_security');
  static final StreamController<void> _screenshots =
      StreamController<void>.broadcast();
  static bool _installed = false;

  static Stream<void> get screenshots {
    _install();
    return _screenshots.stream;
  }

  static void _install() {
    if (_installed) return;
    _installed = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'screenshotTaken') _screenshots.add(null);
    });
  }
}

/// App-root security layer that shows a non-blocking screenshot warning.
class ScreenSecurityGuard extends StatefulWidget {
  const ScreenSecurityGuard({
    required this.child,
    super.key,
    this.screenshotEvents,
    this.warningDuration = const Duration(seconds: 6),
  });

  final Widget child;
  final Stream<void>? screenshotEvents;
  final Duration warningDuration;

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
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
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
