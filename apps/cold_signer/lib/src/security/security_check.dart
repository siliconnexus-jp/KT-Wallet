/// Offline security-check engine (detailed-design.md §7.2, ui-m.md §9.2).
///
/// Each check probes a device condition and maps the result to a level. The
/// aggregate verdict gates entry to the signing path: any `block` forbids
/// signing entirely.
library;

enum CheckLevel { pass, warn, block }

/// One check's outcome.
class CheckResult {
  const CheckResult(this.id, this.level, {this.detail});
  final String id;
  final CheckLevel level;
  final String? detail;
}

/// Raw device probe inputs, injected so the engine is pure and testable. In the
/// app these are filled from NWPathMonitor / ConnectivityManager / platform
/// APIs (detailed-design.md §4, §7.2).
class DeviceState {
  const DeviceState({
    required this.networkReachable,
    required this.airplaneMode,
    required this.bluetoothOn,
    required this.devicePasscodeSet,
    required this.biometricEnrolled,
    required this.screenCaptured,
    required this.rootedOrJailbroken,
  });

  final bool networkReachable;
  final bool airplaneMode;
  final bool bluetoothOn;
  final bool devicePasscodeSet;
  final bool biometricEnrolled;
  final bool screenCaptured;
  final bool rootedOrJailbroken;
}

/// The check matrix from detailed-design.md §7.2. `block`-level failures stop
/// the signing path via [SecurityVerdict.canSign].
abstract final class SecurityChecks {
  static List<CheckResult> run(DeviceState s) => [
        CheckResult(
          'network',
          s.networkReachable ? CheckLevel.block : CheckLevel.pass,
          detail: s.networkReachable ? '检测到网络连接' : '无网络',
        ),
        CheckResult(
          'airplane',
          s.airplaneMode ? CheckLevel.pass : CheckLevel.warn,
        ),
        CheckResult(
          'bluetooth',
          s.bluetoothOn ? CheckLevel.warn : CheckLevel.pass,
        ),
        CheckResult(
          'passcode',
          s.devicePasscodeSet ? CheckLevel.pass : CheckLevel.block,
        ),
        CheckResult(
          'biometric',
          s.biometricEnrolled ? CheckLevel.pass : CheckLevel.warn,
        ),
        CheckResult(
          'screen_capture',
          s.screenCaptured ? CheckLevel.block : CheckLevel.pass,
        ),
        CheckResult(
          // A rooted/jailbroken device is a full compromise of the key holder;
          // block signing outright (ui-m.md §9.2 "禁止签名").
          'integrity',
          s.rootedOrJailbroken ? CheckLevel.block : CheckLevel.pass,
        ),
      ];

  static SecurityVerdict verdict(DeviceState s) =>
      SecurityVerdict(run(s));
}

/// Aggregate verdict over a set of check results.
class SecurityVerdict {
  SecurityVerdict(this.results);
  final List<CheckResult> results;

  CheckLevel get overall {
    if (results.any((r) => r.level == CheckLevel.block)) return CheckLevel.block;
    if (results.any((r) => r.level == CheckLevel.warn)) return CheckLevel.warn;
    return CheckLevel.pass;
  }

  /// Signing is only allowed when nothing is at `block` level.
  bool get canSign => overall != CheckLevel.block;

  List<CheckResult> get blocking =>
      results.where((r) => r.level == CheckLevel.block).toList();
}
