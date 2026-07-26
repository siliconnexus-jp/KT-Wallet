import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:chains/chains.dart';
import 'package:flutter/widgets.dart';

/// What the user entered on the Send screen (W4), carried through the
/// confirm → sign-qr → scan-result → broadcast screens so they display the
/// real transaction instead of design-demo constants.
class TransferDraft {
  TransferDraft({
    required this.symbol,
    required this.networkLabel,
    required this.chain,
    required this.decimals,
    required this.recipient,
    required this.amount,
    required this.feeTier,
    this.tokenContract,
  });

  /// Asset symbol, e.g. `USDT`.
  final String symbol;

  /// Display label of the network, e.g. `TRON · TRC-20`.
  final String networkLabel;

  final Chain chain;
  final int decimals;

  /// Normalized recipient address (already validated by the input screen).
  final String recipient;

  final Amount amount;

  /// Fee tier index: 0 slow, 1 standard, 2 fast.
  final int feeTier;

  /// Token contract for token transfers; null for native transfers.
  final String? tokenContract;

  TxOperation get operation => tokenContract == null
      ? TxOperation.nativeTransfer
      : TxOperation.tokenTransfer;

  /// Human amount string, e.g. `120 USDT`.
  String get amountText => '${amount.format()} $symbol';
}

/// Mutable state of the in-flight transfer flow. One instance lives above the
/// router for the app's lifetime; screens read/write it as the user moves
/// through the flow. Screens rendered without a scope (design gallery index,
/// golden tests) see `null` everywhere and fall back to demo values.
class TransferSession {
  /// Set by the transfer input screen on 下一步.
  TransferDraft? draft;

  /// The outstanding sign-request built by W6 (sign-qr). The scanned result
  /// must answer exactly this request (same reqId).
  SignRequest? request;

  /// The protocol-decoded result produced by the (simulated) W7 scan.
  SignResult? result;

  /// The tx hash the broadcast step actually produced: the node's answer for
  /// a real broadcast, or the demo hash on the simulated short-circuit. W9
  /// prefers this over [result]'s pre-broadcast hash when set.
  String? broadcastTxHash;

  void clear() {
    draft = null;
    request = null;
    result = null;
    broadcastTxHash = null;
  }
}

/// Lightweight inherited access to the app-wide [TransferSession]. The session
/// object itself is mutable and never replaced, so lookups use
/// [BuildContext.getInheritedWidgetOfExactType] (no rebuild dependency).
class TransferSessionScope extends InheritedWidget {
  const TransferSessionScope({
    super.key,
    required this.session,
    required super.child,
  });

  final TransferSession session;

  static TransferSession? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<TransferSessionScope>()?.session;

  @override
  bool updateShouldNotify(TransferSessionScope oldWidget) =>
      session != oldWidget.session;
}
