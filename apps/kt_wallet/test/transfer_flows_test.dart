import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/transfer/airgap_flow.dart';
import 'package:kt_wallet/src/transfer/local_sign_flow.dart';
import 'package:test_support/test_support.dart';

void main() {
  group('LocalSignFlow (hot wallet, DD §6.3)', () {
    test('full transition table: legal land right, all others throw', () {
      final report = verifyTransitionTable<LocalState, LocalEvent>(
        states: LocalState.values,
        events: LocalEvent.values,
        apply: localApply,
        allowed: [
          for (final t in localTransitions)
            TransitionCase(t.from, t.event, t.to),
        ],
      );
      expect(report.ok, isTrue, reason: report.toString());
    });

    test('happy path: draft → done', () {
      final f = LocalSignFlow();
      f.dispatch(LocalEvent.reviewed);
      f.dispatch(LocalEvent.confirm);
      f.dispatch(LocalEvent.authOk);
      f.dispatch(LocalEvent.signOk);
      f.dispatch(LocalEvent.broadcastOk);
      expect(f.state, LocalState.done);
    });

    test('auth cancel returns to confirming, not a dead end', () {
      final f = LocalSignFlow();
      f.dispatch(LocalEvent.reviewed);
      f.dispatch(LocalEvent.confirm);
      f.dispatch(LocalEvent.authFailedOrCancelled);
      expect(f.state, LocalState.confirming);
    });

    test(
      'broadcast error → failed; only explicit retry rebuilds (no auto-retry)',
      () {
        final f = LocalSignFlow();
        f.dispatch(LocalEvent.reviewed);
        f.dispatch(LocalEvent.confirm);
        f.dispatch(LocalEvent.authOk);
        f.dispatch(LocalEvent.signOk);
        f.dispatch(LocalEvent.broadcastError);
        expect(f.state, LocalState.failed);
        // There is no broadcasting→broadcasting or auto-loop; retry is manual.
        f.dispatch(LocalEvent.retry);
        expect(f.state, LocalState.confirming);
      },
    );

    test('cannot sign without confirming (illegal jump throws)', () {
      final f = LocalSignFlow();
      expect(
        () => f.dispatch(LocalEvent.authOk),
        throwsA(isA<IllegalLocalTransition>()),
      );
    });
  });

  group('AirgapFlow (watch wallet, DD §6.3)', () {
    test('full transition table: legal land right, all others throw', () {
      final report = verifyTransitionTable<AirgapState, AirgapEvent>(
        states: AirgapState.values,
        events: AirgapEvent.values,
        apply: airgapApply,
        allowed: [
          for (final t in airgapTransitions)
            TransitionCase(t.from, t.event, t.to),
        ],
      );
      expect(report.ok, isTrue, reason: report.toString());
    });

    test('happy path: draft → done', () {
      final f = AirgapFlow();
      f.dispatch(AirgapEvent.reviewed);
      f.dispatch(AirgapEvent.confirm);
      f.dispatch(AirgapEvent.resultScanned);
      f.dispatch(AirgapEvent.verifyOk); // scanning → verifying
      f.dispatch(AirgapEvent.verifyOk); // verifying → broadcastConfirm
      f.dispatch(AirgapEvent.broadcast);
      f.dispatch(AirgapEvent.broadcastOk);
      expect(f.state, AirgapState.done);
    });

    test('signature verify failure returns to scanning', () {
      final f = AirgapFlow();
      f.dispatch(AirgapEvent.reviewed);
      f.dispatch(AirgapEvent.confirm);
      f.dispatch(AirgapEvent.resultScanned);
      f.dispatch(AirgapEvent.verifyOk);
      f.dispatch(AirgapEvent.verifyFailed);
      expect(f.state, AirgapState.scanningResult);
    });

    test('expiry can fire from any live state', () {
      for (final reach in [
        [AirgapEvent.reviewed],
        [AirgapEvent.reviewed, AirgapEvent.confirm],
        [AirgapEvent.reviewed, AirgapEvent.confirm, AirgapEvent.resultScanned],
      ]) {
        final f = AirgapFlow();
        for (final e in reach) {
          f.dispatch(e);
        }
        f.dispatch(AirgapEvent.expire);
        expect(f.state, AirgapState.expired);
      }
    });

    test('cancel can fire from any live state', () {
      final f = AirgapFlow();
      f.dispatch(AirgapEvent.reviewed);
      f.dispatch(AirgapEvent.confirm);
      f.dispatch(AirgapEvent.cancel);
      expect(f.state, AirgapState.cancelled);
    });

    test('broadcast error → failed (no auto-retry)', () {
      final f = AirgapFlow();
      f.dispatch(AirgapEvent.reviewed);
      f.dispatch(AirgapEvent.confirm);
      f.dispatch(AirgapEvent.resultScanned);
      f.dispatch(AirgapEvent.verifyOk);
      f.dispatch(AirgapEvent.verifyOk);
      f.dispatch(AirgapEvent.broadcast);
      f.dispatch(AirgapEvent.broadcastError);
      expect(f.state, AirgapState.failed);
    });
  });
}
