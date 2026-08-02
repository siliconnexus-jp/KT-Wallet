/// Native-backed security probe that reports unmeasurable states honestly.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'security_check.dart';

const _deviceSecurityChannel = MethodChannel('kt/device_security');
const _defaultProbeTimeout = Duration(seconds: 2);

typedef NativeDeviceStateReader = Future<Map<Object?, Object?>> Function();
typedef BiometricAvailabilityProbe = Future<bool> Function();

/// Suite-wide seams for widget environments that do not have a native host.
/// Individual calls still take precedence; production never assigns these.
@visibleForTesting
NativeDeviceStateReader? debugNativeDeviceStateReader;

@visibleForTesting
BiometricAvailabilityProbe? debugBiometricAvailabilityProbe;

/// Reads the native security state without allowing a stuck platform callback
/// to keep the signer in an indeterminate loading state forever.
///
/// A timeout is reported as [DeviceCondition.unknown], never as a successful
/// check. The injectable readers are intentionally test-only seams; production
/// callers use the native channel and `local_auth` defaults.
Future<DeviceState> probeDeviceState({
  @visibleForTesting NativeDeviceStateReader? nativeReader,
  @visibleForTesting BiometricAvailabilityProbe? biometricProbe,
  @visibleForTesting Duration timeout = _defaultProbeTimeout,
}) async {
  Map<Object?, Object?> native = const {};
  try {
    native =
        await (nativeReader ??
                debugNativeDeviceStateReader ??
                _readNativeState)()
            .timeout(timeout);
  } on TimeoutException {
    // A stalled native monitor is unknown, never a green check.
  } on PlatformException {
    // A missing or failed native probe is unknown, never a green check.
  } on MissingPluginException {
    // Widget tests and unsupported platforms do not have the native channel.
  }

  var biometric = _condition(native['biometric']);
  if (biometric == DeviceCondition.unknown) {
    try {
      final available =
          await (biometricProbe ??
                  debugBiometricAvailabilityProbe ??
                  _probeBiometrics)()
              .timeout(timeout);
      biometric = available ? DeviceCondition.safe : DeviceCondition.unsafe;
    } on TimeoutException {
      biometric = DeviceCondition.unknown;
    } on PlatformException {
      biometric = DeviceCondition.unknown;
    } on MissingPluginException {
      biometric = DeviceCondition.unknown;
    }
  }

  return DeviceState.conditions(
    network: _condition(native['network']),
    airplane: _condition(native['airplane']),
    bluetooth: _condition(native['bluetooth']),
    passcode: _condition(native['passcode']),
    biometric: biometric,
    screenCapture: _condition(native['screenCapture']),
    integrity: _condition(native['integrity']),
  );
}

Future<Map<Object?, Object?>> _readNativeState() async =>
    await _deviceSecurityChannel.invokeMapMethod<Object?, Object?>(
      'getState',
    ) ??
    const {};

Future<bool> _probeBiometrics() async {
  final auth = LocalAuthentication();
  return await auth.canCheckBiometrics &&
      (await auth.getAvailableBiometrics()).isNotEmpty;
}

DeviceCondition _condition(Object? value) => switch (value) {
  'safe' => DeviceCondition.safe,
  'unsafe' => DeviceCondition.unsafe,
  _ => DeviceCondition.unknown,
};
