import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../l10n/app_localizations.dart';

/// Pushes native privacy-cover copy used while the app is backgrounded.
///
/// Screenshots are intentionally allowed on both platforms. Screenshot and
/// recording signals are handled by [ScreenSecurity] so the app can warn the
/// user and conceal recovery words without relying on Android `FLAG_SECURE`.
abstract final class SecureScreen {
  static const _channel = MethodChannel('kt/secure_screen');

  /// Last copy pushed to the platform, so a rebuild storm is not a call storm.
  static (String, String, String)? _pushedStrings;

  /// Hands the privacy-overlay wording to the native side.
  ///
  /// That overlay is drawn by the OS layer while the app is backgrounded, so
  /// it cannot read [AppLocalizations]. It used to pick its own copy from the
  /// SYSTEM language, which ignored an in-app language override — a user on a
  /// Japanese phone who set the app to Chinese got a Japanese overlay. The ARB
  /// stays the single source of truth; the platform just renders what it is
  /// told, falling back to its built-in table before Dart has spoken (the
  /// very first frames of a cold start).
  static void setPrivacyStrings({
    required String appName,
    required String active,
    required String hidden,
  }) {
    final next = (appName, active, hidden);
    if (_pushedStrings == next) return;
    _pushedStrings = next;
    _channel
        .invokeMethod<void>('setPrivacyStrings', {
          'appName': appName,
          'active': active,
          'hidden': hidden,
        })
        .catchError((_) {
          // No handler (tests / older host): the native fallback still shows.
        });
  }

  @visibleForTesting
  static void resetPrivacyStringsForTest() => _pushedStrings = null;
}

/// Conceals sensitive content while the OS reports active recording/mirroring.
///
/// Wrap any screen or sheet that can put a recovery phrase — whole or partial
/// — in front of the user.
class SecureContent extends StatelessWidget {
  const SecureContent({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: ScreenSecurity.captured,
    builder: (context, captured, _) {
      if (captured) return const _CaptureBlocked();
      return child;
    },
    child: child,
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
