/// Hot-wallet transfer flow (detailed-design.md §6.3 LocalSignFlow):
/// draft → confirming → authenticating → signing → broadcasting → done,
/// with a fast-fail failed state. No QR anywhere.
library;

enum LocalState {
  draft,
  confirming,
  authenticating,
  signing,
  broadcasting,
  done,
  failed,
}

enum LocalEvent {
  reviewed, // fee/balance checks passed
  confirm,
  authOk,
  authFailedOrCancelled,
  signOk,
  signError,
  broadcastOk,
  broadcastError,
  retry, // from failed, rebuild with fresh nonce/blockhash
}

class LocalTransition {
  const LocalTransition(this.from, this.event, this.to);
  final LocalState from;
  final LocalEvent event;
  final LocalState to;
}

class IllegalLocalTransition implements Exception {
  IllegalLocalTransition(this.state, this.event);
  final LocalState state;
  final LocalEvent event;
  @override
  String toString() => 'IllegalLocalTransition($state, $event)';
}

const localTransitions = <LocalTransition>[
  LocalTransition(LocalState.draft, LocalEvent.reviewed, LocalState.confirming),
  LocalTransition(LocalState.confirming, LocalEvent.confirm, LocalState.authenticating),
  LocalTransition(LocalState.authenticating, LocalEvent.authOk, LocalState.signing),
  // Auth lockout/cancel returns to the confirm screen, not a dead end.
  LocalTransition(LocalState.authenticating, LocalEvent.authFailedOrCancelled, LocalState.confirming),
  LocalTransition(LocalState.signing, LocalEvent.signOk, LocalState.broadcasting),
  LocalTransition(LocalState.signing, LocalEvent.signError, LocalState.failed),
  LocalTransition(LocalState.broadcasting, LocalEvent.broadcastOk, LocalState.done),
  LocalTransition(LocalState.broadcasting, LocalEvent.broadcastError, LocalState.failed),
  // Broadcast is NEVER auto-retried; a failed tx is rebuilt only on explicit
  // user retry (fresh nonce/blockhash) — INV-15.
  LocalTransition(LocalState.failed, LocalEvent.retry, LocalState.confirming),
];

LocalState localApply(LocalState state, LocalEvent event) {
  for (final t in localTransitions) {
    if (t.from == state && t.event == event) return t.to;
  }
  throw IllegalLocalTransition(state, event);
}

class LocalSignFlow {
  LocalSignFlow() : _state = LocalState.draft;
  LocalState _state;
  LocalState get state => _state;
  LocalState dispatch(LocalEvent e) => _state = localApply(_state, e);
}
