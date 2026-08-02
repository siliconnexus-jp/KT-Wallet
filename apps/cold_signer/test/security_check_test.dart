import 'package:cold_signer/src/security/security_check.dart';
import 'package:flutter_test/flutter_test.dart';

DeviceState _state({
  bool network = false,
  bool airplane = true,
  bool bluetooth = false,
  bool passcode = true,
  bool biometric = true,
  bool capture = false,
  bool rooted = false,
}) => DeviceState(
  networkReachable: network,
  airplaneMode: airplane,
  bluetoothOn: bluetooth,
  devicePasscodeSet: passcode,
  biometricEnrolled: biometric,
  screenCaptured: capture,
  rootedOrJailbroken: rooted,
);

CheckLevel _levelOf(SecurityVerdict v, String id) =>
    v.results.firstWhere((r) => r.id == id).level;

DeviceCondition _conditionOf(SecurityVerdict v, String id) =>
    v.results.firstWhere((r) => r.id == id).condition;

void main() {
  group('security check matrix (DD §7.2)', () {
    test('a clean offline device passes and can sign', () {
      final v = SecurityChecks.verdict(_state());
      expect(v.overall, CheckLevel.pass);
      expect(v.canSign, isTrue);
    });

    test('network reachable is a BLOCK and forbids signing', () {
      final v = SecurityChecks.verdict(_state(network: true));
      expect(_levelOf(v, 'network'), CheckLevel.block);
      expect(v.canSign, isFalse);
      expect(v.blocking.map((r) => r.id), contains('network'));
    });

    test('no device passcode is a BLOCK', () {
      final v = SecurityChecks.verdict(_state(passcode: false));
      expect(_levelOf(v, 'passcode'), CheckLevel.block);
      expect(v.canSign, isFalse);
    });

    test('screen capture is a BLOCK', () {
      final v = SecurityChecks.verdict(_state(capture: true));
      expect(_levelOf(v, 'screen_capture'), CheckLevel.block);
      expect(v.canSign, isFalse);
    });

    test(
      'bluetooth on / no airplane / no biometric are WARN (non-blocking)',
      () {
        final v = SecurityChecks.verdict(
          _state(bluetooth: true, airplane: false, biometric: false),
        );
        expect(_levelOf(v, 'bluetooth'), CheckLevel.warn);
        expect(_levelOf(v, 'airplane'), CheckLevel.warn);
        expect(_levelOf(v, 'biometric'), CheckLevel.warn);
        expect(v.overall, CheckLevel.warn);
        expect(v.canSign, isTrue);
      },
    );

    test('rooted/jailbroken is a BLOCK (key-holder compromise)', () {
      final v = SecurityChecks.verdict(_state(rooted: true));
      expect(_levelOf(v, 'integrity'), CheckLevel.block);
      expect(v.canSign, isFalse);
    });

    test('block dominates warn in the aggregate verdict', () {
      final v = SecurityChecks.verdict(_state(network: true, bluetooth: true));
      expect(v.overall, CheckLevel.block);
      expect(v.canSign, isFalse);
    });

    test('unknown stays structured and is never converted to pass', () {
      final v = SecurityChecks.verdict(const DeviceState.unknown());
      expect(v.results, hasLength(7));
      for (final result in v.results) {
        expect(result.condition, DeviceCondition.unknown);
        expect(result.level, CheckLevel.warn);
      }
      expect(_conditionOf(v, 'network'), DeviceCondition.unknown);
      expect(v.overall, CheckLevel.warn);
    });
  });
}
