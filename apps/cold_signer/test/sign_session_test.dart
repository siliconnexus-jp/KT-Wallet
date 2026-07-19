import 'package:cold_signer/src/signing/sign_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_support/test_support.dart';

void main() {
  group('sign session state machine (DD §7.3)', () {
    test('every (state, event) pair: legal transitions land right, rest throw',
        () {
      final report = verifyTransitionTable<SignState, SignEvent>(
        states: SignState.values,
        events: SignEvent.values,
        apply: signApply,
        allowed: [
          for (final t in signTransitions)
            TransitionCase(t.from, t.event, t.to),
        ],
      );
      expect(report.ok, isTrue, reason: report.toString());
    });

    test('happy path: scan → sign → result', () {
      final s = SignSession();
      expect(s.state, SignState.scanning);
      s.dispatch(SignEvent.framesComplete);
      expect(s.state, SignState.validating);
      s.dispatch(SignEvent.validationPassed);
      expect(s.state, SignState.reviewing);
      s.dispatch(SignEvent.userConfirm);
      expect(s.state, SignState.authenticating);
      s.dispatch(SignEvent.authOk);
      expect(s.state, SignState.signed);
      s.dispatch(SignEvent.signComplete);
      expect(s.state, SignState.resultDisplaying);
      // resultDisplaying is recorded as signed but can still be voided.
      expect(s.recordStatus, 'signed');
    });

    test('any rejected validation blocks and records rejected', () {
      final s = SignSession();
      s.dispatch(SignEvent.framesComplete);
      s.dispatch(SignEvent.validationRejected);
      expect(s.state, SignState.riskBlocked);
      expect(s.recordStatus, 'rejected');
      expect(s.isTerminal, isTrue);
    });

    test('reqId is recorded as signed the instant auth succeeds', () {
      final s = SignSession();
      s.dispatch(SignEvent.framesComplete);
      s.dispatch(SignEvent.validationPassed);
      s.dispatch(SignEvent.userConfirm);
      s.dispatch(SignEvent.authOk);
      // signed state already carries a 'signed' record status — a crash here
      // must not leave the request re-signable.
      expect(s.state, SignState.signed);
      expect(s.recordStatus, 'signed');
    });

    test('auth failure returns to reviewing (retry), not signed', () {
      final s = SignSession();
      s.dispatch(SignEvent.framesComplete);
      s.dispatch(SignEvent.validationPassed);
      s.dispatch(SignEvent.userConfirm);
      s.dispatch(SignEvent.authFailed);
      expect(s.state, SignState.reviewing);
    });

    test('user can reject during review or auth', () {
      final s = SignSession();
      s.dispatch(SignEvent.framesComplete);
      s.dispatch(SignEvent.validationPassed);
      s.dispatch(SignEvent.userReject);
      expect(s.state, SignState.rejected);
      expect(s.recordStatus, 'rejected');
    });

    test('voiding a signed result keeps it recorded as signed', () {
      final s = SignSession();
      for (final e in [
        SignEvent.framesComplete,
        SignEvent.validationPassed,
        SignEvent.userConfirm,
        SignEvent.authOk,
        SignEvent.signComplete,
        SignEvent.voidSignature,
      ]) {
        s.dispatch(e);
      }
      expect(s.state, SignState.voided);
      // Still "signed" for replay purposes — reqId permanently refused.
      expect(s.recordStatus, 'signed');
      expect(s.isTerminal, isTrue);
    });

    test('cannot sign without passing validation (illegal jump throws)', () {
      final s = SignSession();
      expect(() => s.dispatch(SignEvent.authOk),
          throwsA(isA<IllegalSignTransition>()));
    });
  });
}
