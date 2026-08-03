import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;

/// True only for local Debug builds that may render deterministic gallery and
/// test fixtures. Profile is production-like: it can be distributed for
/// performance testing and must never expose demo wallets, scans or success
/// paths merely because it is not a Release build.
bool get developerFixturesEnabled => kDebugMode;

@visibleForTesting
bool resolveDeveloperFixturesEnabled({required bool isDebugBuild}) =>
    isDebugBuild;
