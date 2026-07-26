/// Native-backed security probe that reports unmeasurable states honestly.
library;

import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'security_check.dart';

const _deviceSecurityChannel = MethodChannel('kt/device_security');

Future<DeviceState> probeDeviceState() async {
  Map<Object?, Object?> native = const {};
  try {
    native =
        await _deviceSecurityChannel.invokeMapMethod<Object?, Object?>(
          'getState',
        ) ??
        const {};
  } on PlatformException {
    // A missing or failed native probe is unknown, never a green check.
  } on MissingPluginException {
    // Widget tests and unsupported platforms do not have the native channel.
  }

  var biometric = _condition(native['biometric']);
  if (biometric == DeviceCondition.unknown) {
    try {
      final auth = LocalAuthentication();
      final available =
          await auth.canCheckBiometrics &&
          (await auth.getAvailableBiometrics()).isNotEmpty;
      biometric =
          available ? DeviceCondition.safe : DeviceCondition.unsafe;
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

DeviceCondition _condition(Object? value) => switch (value) {
  'safe' => DeviceCondition.safe,
  'unsafe' => DeviceCondition.unsafe,
  _ => DeviceCondition.unknown,
};
