import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Android FLAG_SECURE toggle (blocks screenshots and hides the app in the
/// recents switcher).
///
/// Two independent reasons can raise it and the flag stays up while EITHER
/// holds:
///
/// * [modeSecure] — the whole embedded signer mode, latched for its lifetime.
/// * [retain] / [release] — a single sensitive screen inside the online
///   wallet. Recovery phrases are shown there too (backup, verify, import,
///   the view-phrase sheet), and those screens used to be freely
///   screenshottable even while telling the user "don't screenshot this".
///
/// Prefer wrapping content in [SecureContent] over calling retain/release
/// by hand — it balances the pair against the widget lifecycle for you.
///
/// iOS has no OS-level way to block screenshots (there is no FLAG_SECURE
/// equivalent — apps can at most react after the fact), so no iOS handler is
/// registered and the call is an honest silent no-op there, as it is in
/// widget tests where no platform channel exists at all.
abstract final class SecureScreen {
  static const _channel = MethodChannel('kt/secure_screen');

  static bool _modeSecure = false;
  static int _holders = 0;

  /// Last value pushed to the platform, so a rebuild storm does not turn into
  /// a channel-call storm.
  static bool? _applied;

  /// Whether the flag is currently meant to be up. Exposed for tests.
  @visibleForTesting
  static bool get isSecure => _modeSecure || _holders > 0;

  /// Number of live [SecureContent] holders. Exposed for tests; a non-zero
  /// value after navigating away means a leak.
  @visibleForTesting
  static int get holders => _holders;

  @visibleForTesting
  static void resetForTest() {
    _modeSecure = false;
    _holders = 0;
    _applied = null;
  }

  /// Mode-level latch. Idempotent — safe to assign on every build.
  static set modeSecure(bool secure) {
    if (_modeSecure == secure) return;
    _modeSecure = secure;
    _sync();
  }

  /// Marks sensitive content as on screen. Must be balanced with [release].
  static void retain() {
    _holders++;
    _sync();
  }

  /// Drops one [retain]. Never goes negative: an unbalanced release must not
  /// be able to lower the flag while real sensitive content is still up.
  static void release() {
    if (_holders == 0) return;
    _holders--;
    _sync();
  }

  static void _sync() {
    final secure = isSecure;
    if (_applied == secure) return;
    _applied = secure;
    // Best-effort: never throws.
    _channel.invokeMethod<void>('setSecure', secure).catchError((_) {
      // No handler (iOS / tests / hot restart edge): keep going.
    });
  }
}

/// Holds [SecureScreen] up for as long as this subtree is mounted.
///
/// Wrap any screen or sheet that can put a recovery phrase — whole or partial
/// — in front of the user.
class SecureContent extends StatefulWidget {
  const SecureContent({super.key, required this.child});

  final Widget child;

  @override
  State<SecureContent> createState() => _SecureContentState();
}

class _SecureContentState extends State<SecureContent> {
  @override
  void initState() {
    super.initState();
    SecureScreen.retain();
  }

  @override
  void dispose() {
    SecureScreen.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
