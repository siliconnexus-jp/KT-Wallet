/// Offline signing session state machine (detailed-design.md §7.3).
///
/// scanning → validating → reviewing → authenticating → signed → result
/// with rejection (unsupported/user-reject) and void branches. Pure logic; the
/// UI drives it with events and renders [state].
library;

enum SignState { scanning, validating, riskBlocked, reviewing, rejected, authenticating, signed, resultDisplaying, voided }

enum SignEvent {
  framesComplete, // aggregator assembled a payload
  validationPassed,
  // Any non-ok validation result (unsupported tx, duplicate, expired,
  // foreign wallet, clock skew) — all route to riskBlocked. The caller must
  // fire validationPassed ONLY for a ValidationCode.ok result.
  validationRejected,
  userReject,
  userConfirm,
  authOk,
  authFailed,
  signComplete,
  voidSignature,
}

class SignTransition {
  const SignTransition(this.from, this.event, this.to);
  final SignState from;
  final SignEvent event;
  final SignState to;
}

/// Illegal (state, event) pairs throw this.
class IllegalSignTransition implements Exception {
  IllegalSignTransition(this.state, this.event);
  final SignState state;
  final SignEvent event;
  @override
  String toString() => 'IllegalSignTransition($state, $event)';
}

/// The full legal transition table (also consumed by tests to prove every
/// other (state,event) pair is rejected).
const signTransitions = <SignTransition>[
  SignTransition(SignState.scanning, SignEvent.framesComplete, SignState.validating),
  SignTransition(SignState.validating, SignEvent.validationPassed, SignState.reviewing),
  SignTransition(SignState.validating, SignEvent.validationRejected, SignState.riskBlocked),
  SignTransition(SignState.reviewing, SignEvent.userReject, SignState.rejected),
  SignTransition(SignState.reviewing, SignEvent.userConfirm, SignState.authenticating),
  SignTransition(SignState.authenticating, SignEvent.authOk, SignState.signed),
  SignTransition(SignState.authenticating, SignEvent.authFailed, SignState.reviewing),
  SignTransition(SignState.authenticating, SignEvent.userReject, SignState.rejected),
  SignTransition(SignState.signed, SignEvent.signComplete, SignState.resultDisplaying),
  SignTransition(SignState.resultDisplaying, SignEvent.voidSignature, SignState.voided),
];

/// Pure transition function.
SignState signApply(SignState state, SignEvent event) {
  for (final t in signTransitions) {
    if (t.from == state && t.event == event) return t.to;
  }
  throw IllegalSignTransition(state, event);
}

/// The record-store status that must be persisted when the session reaches each
/// state. `signed` is included (not just `resultDisplaying`) so the reqId is
/// persisted the instant authentication succeeds — a crash after auth but
/// before the result QR is shown must NOT leave the request re-signable
/// (DD §13.5).
const signRecordStatus = {
  SignState.riskBlocked: 'rejected',
  SignState.rejected: 'rejected',
  SignState.signed: 'signed',
  SignState.resultDisplaying: 'signed',
  SignState.voided: 'signed', // stays signed but reqId permanently refused
};

/// States with no outgoing legal transition (the session is finished).
const signTerminalStates = {SignState.riskBlocked, SignState.rejected, SignState.voided};

/// Stateful driver that tracks the current state.
class SignSession {
  SignSession() : _state = SignState.scanning;
  SignState _state;
  SignState get state => _state;

  SignState dispatch(SignEvent event) => _state = signApply(_state, event);

  /// The status to persist for the current state, if any (null when the state
  /// does not require a record write).
  String? get recordStatus => signRecordStatus[_state];

  bool get isTerminal => signTerminalStates.contains(_state);
}
