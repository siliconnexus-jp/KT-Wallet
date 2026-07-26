/// Offline security-check engine.
library;

enum CheckLevel { pass, warn, block }

/// A probe must never turn “not measurable” into a green check.
enum DeviceCondition { safe, unsafe, unknown }

class CheckResult {
  const CheckResult(this.id, this.level, {this.detail});
  final String id;
  final CheckLevel level;
  final String? detail;
}

class DeviceState {
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
  })  : network = networkReachable
            ? DeviceCondition.unsafe
            : DeviceCondition.safe,
        airplane = airplaneMode
            ? DeviceCondition.safe
            : DeviceCondition.unsafe,
        bluetooth = bluetoothOn
            ? DeviceCondition.unsafe
            : DeviceCondition.safe,
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
  })  : networkReachable = network == DeviceCondition.unsafe,
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
        _result(
          'network',
          state.network,
          unsafe: CheckLevel.block,
          safeDetail: '无网络',
          unsafeDetail: '检测到网络连接',
        ),
        _result(
          'airplane',
          state.airplane,
          unsafe: CheckLevel.warn,
          safeDetail: '飞行模式已开启',
          unsafeDetail: '飞行模式未开启',
        ),
        _result(
          'bluetooth',
          state.bluetooth,
          unsafe: CheckLevel.warn,
          safeDetail: '蓝牙已关闭',
          unsafeDetail: '蓝牙已开启',
        ),
        _result(
          'passcode',
          state.passcode,
          unsafe: CheckLevel.block,
          safeDetail: '设备密码已设置',
          unsafeDetail: '设备密码未设置',
        ),
        _result(
          'biometric',
          state.biometric,
          unsafe: CheckLevel.warn,
          safeDetail: '生物识别可用',
          unsafeDetail: '生物识别不可用',
        ),
        _result(
          'screen_capture',
          state.screenCapture,
          unsafe: CheckLevel.block,
          safeDetail: '未检测到录屏',
          unsafeDetail: '检测到屏幕录制',
        ),
        _result(
          'integrity',
          state.integrity,
          unsafe: CheckLevel.block,
          safeDetail: '系统完整性正常',
          unsafeDetail: '检测到 root 或越狱',
        ),
      ];

  static CheckResult _result(
    String id,
    DeviceCondition condition, {
    required CheckLevel unsafe,
    required String safeDetail,
    required String unsafeDetail,
  }) =>
      switch (condition) {
        DeviceCondition.safe =>
          CheckResult(id, CheckLevel.pass, detail: safeDetail),
        DeviceCondition.unsafe =>
          CheckResult(id, unsafe, detail: unsafeDetail),
        DeviceCondition.unknown =>
          CheckResult(id, CheckLevel.warn, detail: '无法确认'),
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
