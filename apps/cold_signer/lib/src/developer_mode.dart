import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;

/// True only for local Debug builds that may render the deterministic screen
/// gallery. Profile is treated like Release because it can be distributed and
/// must not expose fixture-backed onboarding or signing screens.
bool get developerFixturesEnabled => kDebugMode;

@visibleForTesting
bool resolveDeveloperFixturesEnabled({required bool isDebugBuild}) =>
    isDebugBuild;
