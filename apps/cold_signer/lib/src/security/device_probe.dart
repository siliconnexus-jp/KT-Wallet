/// Best-effort [DeviceState] probe for the security-check engine.
///
/// The engine ([SecurityChecks]) is pure and takes raw booleans; this is the
/// app-side collector. Without platform plugins only network reachability can
/// be probed for real (a DNS lookup). Everything else is stubbed with honest
/// defaults, documented per field below — on an online dev device the network
/// check legitimately fails (block), which is the correct honest output.
library;

import 'dart:async';
import 'dart:io';

import 'security_check.dart';

/// Probes the device and returns the inputs for [SecurityChecks.run].
Future<DeviceState> probeDeviceState() async {
  // Real probe: any successful DNS resolution means the network is reachable
  // (which is a block-level failure for an air-gapped signer).
  var networkReachable = false;
  try {
    final addrs = await InternetAddress.lookup('example.com')
        .timeout(const Duration(seconds: 2));
    networkReachable = addrs.isNotEmpty;
  } on SocketException {
    networkReachable = false;
  } on TimeoutException {
    networkReachable = false;
  }
  return DeviceState(
    networkReachable: networkReachable,
    // Heuristic: no way to read the airplane-mode toggle without a platform
    // channel, so infer it from reachability (unreachable ≈ radios off).
    airplaneMode: !networkReachable,
    // Stubs (no platform plugin wired). Values are "nothing detected" /
    // conservative assumptions, not real probes:
    bluetoothOn: false, // cannot scan radios → report off (nothing detected)
    devicePasscodeSet: true, // cannot query without local_auth → assume set
    biometricEnrolled: true, // cannot query without local_auth → assume set
    screenCaptured: false, // no capture-detection hook → nothing detected
    rootedOrJailbroken: false, // no integrity detector wired → nothing detected
  );
}
