import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// True inside `flutter test`. MethodChannel plugins are unavailable there:
/// their futures never even complete under the fake-async test zone, so
/// plugin-backed calls must be bypassed up front, not caught after the fact
/// (same convention as cold_signer's SecureVaultStorage).
bool get isFlutterTestEnv =>
    !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
