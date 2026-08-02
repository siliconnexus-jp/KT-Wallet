/// Offline security-check engine.
library;

enum CheckLevel { pass, warn, block }

/// A probe must never turn “not measurable” into a green check.
enum DeviceCondition { safe, unsafe, unknown }

class CheckResult {
  const CheckResult(this.id, this.level, this.condition);
  final String id;
  final CheckLevel level;
  final DeviceCondition condition;
}

class DeviceState {
  const DeviceState.unknown()
    : networkReachable = false,
      airplaneMode = false,
      bluetoothOn = false,
      devicePasscodeSet = false,
      biometricEnrolled = false,
      screenCaptured = false,
      rootedOrJailbroken = false,
      network = DeviceCondition.unknown,
      airplane = DeviceCondition.unknown,
      bluetooth = DeviceCondition.unknown,
      passcode = DeviceCondition.unknown,
      biometric = DeviceCondition.unknown,
      screenCapture = DeviceCondition.unknown,
      integrity = DeviceCondition.unknown;

  /// Compatibility constructor for deterministic tests and explicit native
  /// probe results.
  const DeviceState({
    required this.networkReachable,
    required this.airplaneMode,
    required this.bluetoothOn,
    required this.devicePasscodeSet,
    required this.biometricEnrolled,
    required this.screenCaptured,
    required this.rootedOrJailbroken,
  }) : network = networkReachable
           ? DeviceCondition.unsafe
           : DeviceCondition.safe,
       airplane = airplaneMode ? DeviceCondition.safe : DeviceCondition.unsafe,
       bluetooth = bluetoothOn ? DeviceCondition.unsafe : DeviceCondition.safe,
       passcode = devicePasscodeSet
           ? DeviceCondition.safe
           : DeviceCondition.unsafe,
       biometric = biometricEnrolled
           ? DeviceCondition.safe
           : DeviceCondition.unsafe,
       screenCapture = screenCaptured
           ? DeviceCondition.unsafe
           : DeviceCondition.safe,
       integrity = rootedOrJailbroken
           ? DeviceCondition.unsafe
           : DeviceCondition.safe;

  const DeviceState.conditions({
    required this.network,
    required this.airplane,
    required this.bluetooth,
    required this.passcode,
    required this.biometric,
    required this.screenCapture,
    required this.integrity,
  }) : networkReachable = network == DeviceCondition.unsafe,
       airplaneMode = airplane == DeviceCondition.safe,
       bluetoothOn = bluetooth == DeviceCondition.unsafe,
       devicePasscodeSet = passcode == DeviceCondition.safe,
       biometricEnrolled = biometric == DeviceCondition.safe,
       screenCaptured = screenCapture == DeviceCondition.unsafe,
       rootedOrJailbroken = integrity == DeviceCondition.unsafe;

  final bool networkReachable;
  final bool airplaneMode;
  final bool bluetoothOn;
  final bool devicePasscodeSet;
  final bool biometricEnrolled;
  final bool screenCaptured;
  final bool rootedOrJailbroken;

  final DeviceCondition network;
  final DeviceCondition airplane;
  final DeviceCondition bluetooth;
  final DeviceCondition passcode;
  final DeviceCondition biometric;
  final DeviceCondition screenCapture;
  final DeviceCondition integrity;
}

abstract final class SecurityChecks {
  static List<CheckResult> run(DeviceState state) => [
    _result('network', state.network, unsafe: CheckLevel.block),
    _result('airplane', state.airplane, unsafe: CheckLevel.warn),
    _result('bluetooth', state.bluetooth, unsafe: CheckLevel.warn),
    _result('passcode', state.passcode, unsafe: CheckLevel.block),
    _result('biometric', state.biometric, unsafe: CheckLevel.warn),
    _result('screen_capture', state.screenCapture, unsafe: CheckLevel.block),
    _result('integrity', state.integrity, unsafe: CheckLevel.block),
  ];

  static CheckResult _result(
    String id,
    DeviceCondition condition, {
    required CheckLevel unsafe,
  }) => switch (condition) {
    DeviceCondition.safe => CheckResult(id, CheckLevel.pass, condition),
    DeviceCondition.unsafe => CheckResult(id, unsafe, condition),
    DeviceCondition.unknown => CheckResult(id, CheckLevel.warn, condition),
  };

  static SecurityVerdict verdict(DeviceState state) =>
      SecurityVerdict(run(state));
}

class SecurityVerdict {
  SecurityVerdict(this.results);
  final List<CheckResult> results;

  CheckLevel get overall {
    if (results.any((r) => r.level == CheckLevel.block)) {
      return CheckLevel.block;
    }
    if (results.any((r) => r.level == CheckLevel.warn)) {
      return CheckLevel.warn;
    }
    return CheckLevel.pass;
  }

  bool get canSign => overall != CheckLevel.block;

  List<CheckResult> get blocking =>
      results.where((r) => r.level == CheckLevel.block).toList();
}
