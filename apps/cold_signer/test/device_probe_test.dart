import 'dart:async';

import 'package:cold_signer/src/security/device_probe.dart';
import 'package:cold_signer/src/security/security_check.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'native timeout returns unknown rather than hanging or passing',
    () async {
      final state = await probeDeviceState(
        nativeReader: () => Completer<Map<Object?, Object?>>().future,
        biometricProbe: () async => true,
        timeout: const Duration(milliseconds: 5),
      );

      expect(state.network, DeviceCondition.unknown);
      expect(state.airplane, DeviceCondition.unknown);
      expect(state.passcode, DeviceCondition.unknown);
      expect(state.biometric, DeviceCondition.safe);
      expect(state.integrity, DeviceCondition.unknown);
    },
  );

  test('biometric timeout remains unknown', () async {
    final state = await probeDeviceState(
      nativeReader: () async => <Object?, Object?>{
        'network': 'safe',
        'airplane': 'safe',
        'passcode': 'safe',
        'biometric': 'unknown',
        'screenCapture': 'safe',
        'integrity': 'unknown',
      },
      biometricProbe: () => Completer<bool>().future,
      timeout: const Duration(milliseconds: 5),
    );

    expect(state.network, DeviceCondition.safe);
    expect(state.biometric, DeviceCondition.unknown);
    expect(state.integrity, DeviceCondition.unknown);
  });

  test('native explicit unsafe evidence is preserved', () async {
    var biometricFallbackCalled = false;
    final state = await probeDeviceState(
      nativeReader: () async => <Object?, Object?>{
        'network': 'unsafe',
        'airplane': 'unsafe',
        'bluetooth': 'unsafe',
        'passcode': 'safe',
        'biometric': 'safe',
        'screenCapture': 'unsafe',
        'integrity': 'unsafe',
      },
      biometricProbe: () async {
        biometricFallbackCalled = true;
        return true;
      },
    );

    expect(biometricFallbackCalled, isFalse);
    expect(state.network, DeviceCondition.unsafe);
    expect(state.airplane, DeviceCondition.unsafe);
    expect(state.bluetooth, DeviceCondition.unsafe);
    expect(state.passcode, DeviceCondition.safe);
    expect(state.biometric, DeviceCondition.safe);
    expect(state.screenCapture, DeviceCondition.unsafe);
    expect(state.integrity, DeviceCondition.unsafe);
  });
}
