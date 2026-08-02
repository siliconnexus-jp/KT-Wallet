import 'dart:async';

import 'package:cold_signer/src/security/device_probe.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Deterministic native boundary for every Cold Signer test entrypoint.
///
/// Widget tests do not run an Android/iOS host. Returning only an explicit
/// biometric result avoids a dangling platform-channel timeout while every
/// other device condition honestly stays `unknown`. Tests of the probe itself
/// inject their own readers and still exercise timeout/error behavior.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  debugNativeDeviceStateReader = () async => const <Object?, Object?>{};
  debugBiometricAvailabilityProbe = () => Future<bool>.error(
    MissingPluginException('No biometric host in widget tests'),
  );
  // `testMain` registers tests and returns before the package:test runner has
  // executed them, so these isolate-local seams must remain installed for the
  // lifetime of this test process.
  await testMain();
}
