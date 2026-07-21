import 'package:flutter/services.dart';

/// Android FLAG_SECURE toggle for the embedded signer mode (blocks
/// screenshots and hides the app in the recents switcher).
///
/// iOS has no OS-level way to block screenshots (there is no FLAG_SECURE
/// equivalent — apps can at most react after the fact), so no iOS handler is
/// registered and the call is an honest silent no-op there, as it is in
/// widget tests where no platform channel exists at all.
abstract final class SecureScreen {
  static const _channel = MethodChannel('kt/secure_screen');

  /// Best-effort: never throws.
  static Future<void> set(bool secure) async {
    try {
      await _channel.invokeMethod<void>('setSecure', secure);
    } catch (_) {
      // No handler (iOS / tests / hot restart edge): keep going.
    }
  }
}
