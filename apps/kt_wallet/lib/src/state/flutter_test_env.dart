import 'dart:io' show Platform;

import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, visibleForTesting;

/// True inside `flutter test`. MethodChannel plugins are unavailable there:
/// their futures never even complete under the fake-async test zone, so
/// plugin-backed calls must be bypassed up front, not caught after the fact
/// (same convention as cold_signer's SecureVaultStorage).
/// Release and profile builds reject the process marker at the compile-time
/// boundary, so it can never enable a test-only memory fallback.
bool get isFlutterTestEnv =>
    kDebugMode && !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

@visibleForTesting
bool resolveFlutterTestFallback({
  required bool isDebugBuild,
  required bool isWeb,
  required bool markerPresent,
}) => isDebugBuild && !isWeb && markerPresent;
