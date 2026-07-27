import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../l10n/app_localizations.dart';

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

/// Screen-capture signals the OS gives us when it cannot stop the capture.
///
/// Android needs none of this — FLAG_SECURE blocks screenshots, recordings and
/// the recents thumbnail outright. iOS has no equivalent, so the platform side
/// reports what it CAN see and the two cases are handled differently:
///
/// * **recording / mirroring** is preventable — [captured] stays true for the
///   whole session, and [SecureContent] blanks itself while it does.
/// * **a screenshot** has already happened by the time we hear about it. All
///   that is left is to tell the user their recovery phrase is now in the
///   photo library, which is exactly the thing the on-screen warning told them
///   not to do.
abstract final class ScreenCapture {
  static const _channel = MethodChannel('kt/screen_security');

  /// True while the screen is being recorded, mirrored or AirPlayed (iOS).
  static final ValueNotifier<bool> captured = ValueNotifier(false);

  /// Increments on every screenshot the OS reports (iOS).
  static final ValueNotifier<int> screenshots = ValueNotifier(0);

  static bool _installed = false;

  /// Starts listening. Idempotent; safe to call from a build.
  static void install() {
    if (_installed) return;
    _installed = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'screenCaptureChanged':
          captured.value = call.arguments == true;
        case 'screenshotTaken':
          screenshots.value++;
      }
      return null;
    });
  }

  @visibleForTesting
  static void resetForTest() {
    captured.value = false;
    screenshots.value = 0;
  }
}

/// Holds [SecureScreen] up for as long as this subtree is mounted, and — where
/// the OS will not do it for us — reacts to capture.
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
  /// Screenshot count when this screen appeared, so the warning only fires for
  /// screenshots taken WHILE the phrase was on screen.
  late final int _screenshotsAtEntry;

  @override
  void initState() {
    super.initState();
    SecureScreen.retain();
    ScreenCapture.install();
    _screenshotsAtEntry = ScreenCapture.screenshots.value;
  }

  @override
  void dispose() {
    SecureScreen.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: ScreenCapture.captured,
    builder: (context, captured, _) {
      if (captured) return const _CaptureBlocked();
      return ValueListenableBuilder<int>(
        valueListenable: ScreenCapture.screenshots,
        builder: (context, count, child) => Stack(
          children: [
            child!,
            if (count > _screenshotsAtEntry)
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(child: _ScreenshotWarning()),
              ),
          ],
        ),
        child: widget.child,
      );
    },
  );
}

/// Replaces sensitive content while the screen is being recorded or mirrored.
class _CaptureBlocked extends StatelessWidget {
  const _CaptureBlocked();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ColoredBox(
      color: WalletColors.bg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.videocam_off_outlined,
                size: 52,
                color: WalletColors.text3,
              ),
              const SizedBox(height: 14),
              Text(
                l10n.screenCaptureBlocked,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: WalletColors.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.screenCaptureBlockedHint,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: WalletColors.text2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown after the OS reports a screenshot of a screen holding a phrase. The
/// phrase is already in the photo library; the only honest advice is to move
/// the funds.
class _ScreenshotWarning extends StatelessWidget {
  const _ScreenshotWarning();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WalletColors.red,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: Colors.white,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.screenshotWarning,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
