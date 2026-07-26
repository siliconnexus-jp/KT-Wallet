/// Watch-wallet transfer flow (detailed-design.md §6.3 AirgapFlow):
/// draft → confirming → qrDisplaying → scanningResult → verifying →
/// broadcastConfirm → broadcasting → done, plus cancel and an expiry timer that
/// can fire from any live state.
library;

enum AirgapState {
  draft,
  confirming,
  qrDisplaying, // sign-request QR shown to the offline device
  scanningResult, // scanning the signed result
  verifying,
  broadcastConfirm,
  broadcasting,
  done,
  failed,
  cancelled,
  expired,
}

enum AirgapEvent {
  reviewed,
  confirm, // build sign-request, write sign_requests row
  resultScanned,
  verifyOk,
  verifyFailed, // reqId/walletId/signer/expiry mismatch → back to scanning
  broadcast,
  broadcastOk,
  broadcastError,
  cancel,
  expire,
}

class AirgapTransition {
  const AirgapTransition(this.from, this.event, this.to);
  final AirgapState from;
  final AirgapEvent event;
  final AirgapState to;
}

class IllegalAirgapTransition implements Exception {
  IllegalAirgapTransition(this.state, this.event);
  final AirgapState state;
  final AirgapEvent event;
  @override
  String toString() => 'IllegalAirgapTransition($state, $event)';
}

/// Live states from which the expiry timer or cancel may fire.
const _liveStates = {
  AirgapState.confirming,
  AirgapState.qrDisplaying,
  AirgapState.scanningResult,
  AirgapState.verifying,
  AirgapState.broadcastConfirm,
};

List<AirgapTransition> _buildTransitions() => [
  const AirgapTransition(
    AirgapState.draft,
    AirgapEvent.reviewed,
    AirgapState.confirming,
  ),
  const AirgapTransition(
    AirgapState.confirming,
    AirgapEvent.confirm,
    AirgapState.qrDisplaying,
  ),
  const AirgapTransition(
    AirgapState.qrDisplaying,
    AirgapEvent.resultScanned,
    AirgapState.scanningResult,
  ),
  const AirgapTransition(
    AirgapState.scanningResult,
    AirgapEvent.verifyOk,
    AirgapState.verifying,
  ),
  const AirgapTransition(
    AirgapState.verifying,
    AirgapEvent.verifyOk,
    AirgapState.broadcastConfirm,
  ),
  const AirgapTransition(
    AirgapState.verifying,
    AirgapEvent.verifyFailed,
    AirgapState.scanningResult,
  ),
  const AirgapTransition(
    AirgapState.broadcastConfirm,
    AirgapEvent.broadcast,
    AirgapState.broadcasting,
  ),
  const AirgapTransition(
    AirgapState.broadcasting,
    AirgapEvent.broadcastOk,
    AirgapState.done,
  ),
  const AirgapTransition(
    AirgapState.broadcasting,
    AirgapEvent.broadcastError,
    AirgapState.failed,
  ),
  // cancel + expire fire from any live state.
  for (final s in _liveStates)
    AirgapTransition(s, AirgapEvent.cancel, AirgapState.cancelled),
  for (final s in _liveStates)
    AirgapTransition(s, AirgapEvent.expire, AirgapState.expired),
];

final airgapTransitions = _buildTransitions();

AirgapState airgapApply(AirgapState state, AirgapEvent event) {
  for (final t in airgapTransitions) {
    if (t.from == state && t.event == event) return t.to;
  }
  throw IllegalAirgapTransition(state, event);
}

class AirgapFlow {
  AirgapFlow() : _state = AirgapState.draft;
  AirgapState _state;
  AirgapState get state => _state;
  AirgapState dispatch(AirgapEvent e) => _state = airgapApply(_state, e);
}
