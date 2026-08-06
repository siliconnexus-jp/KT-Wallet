import 'dart:typed_data';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:chains/chains.dart';
import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter/widgets.dart';

/// What the user entered on the Send screen (W4), carried through the
/// confirm → sign-qr → scan-result → broadcast screens so they display the
/// real transaction instead of design-demo constants.
class TransferDraft {
  TransferDraft({
    required this.symbol,
    required this.networkLabel,
    required this.chain,
    required this.recipient,
    required this.amount,
    required this.feeTier,
    this.tokenContract,
    this.tokenProgram,
    TxOperation? operation,
    // A public `operation:` argument intentionally initializes a private field;
    // exposing `_operation` as a named parameter would be unusable to callers.
    // ignore: prefer_initializing_formals
  }) : _operation = operation {
    if (this.operation == TxOperation.approvalRevoke) {
      final evm =
          chain == Chain.ethereum ||
          chain == Chain.polygon ||
          chain == Chain.base ||
          chain == Chain.arbitrum ||
          chain == Chain.avalanche ||
          chain == Chain.bnb;
      if (!evm || tokenContract == null || amount.raw != BigInt.zero) {
        throw ArgumentError(
          'approval revoke requires an EVM token contract and zero amount',
        );
      }
    }
  }

  /// Asset symbol, e.g. `USDT`.
  final String symbol;

  /// Display label of the network, e.g. `TRON · TRC-20`.
  final String networkLabel;

  final Chain chain;

  /// The scale is owned by the exact [Amount]. Keeping a second writable
  /// integer here allowed raw units and Solana `transferChecked` decimals to
  /// disagree inside one draft.
  int get decimals => amount.decimals;

  /// Normalized recipient address (already validated by the input screen).
  final String recipient;

  final Amount amount;

  /// Fee tier index: 0 slow, 1 standard, 2 fast.
  final int feeTier;

  /// Token contract for token transfers; null for native transfers.
  final String? tokenContract;
  final String? tokenProgram;
  final TxOperation? _operation;

  TxOperation get operation =>
      _operation ??
      (tokenContract == null
          ? TxOperation.nativeTransfer
          : TxOperation.tokenTransfer);

  /// Human amount string, e.g. `120 USDT`.
  String get amountText => '${amount.format()} $symbol';
}

/// Exact EIP-1559 envelope approved on the confirm screen. The auth/sign step
/// must consume this same immutable quote rather than silently rebuilding a
/// transaction with different fees after the user has confirmed.
class PreparedEvmTransfer {
  PreparedEvmTransfer({
    required this.chain,
    required this.evmChainId,
    required this.coin,
    required this.operation,
    required this.from,
    required this.recipient,
    required this.amountRaw,
    required this.tokenContract,
    required this.nonce,
    required this.maxPriorityFeePerGas,
    required this.maxFeePerGas,
    required this.gasLimit,
    required Uint8List unsignedTx,
  }) : _unsignedTx = Uint8List.fromList(unsignedTx);

  final Chain chain;
  final int evmChainId;
  final Coin coin;
  final TxOperation operation;
  final String from;
  final String recipient;
  final BigInt amountRaw;
  final String? tokenContract;
  final BigInt nonce;
  final BigInt maxPriorityFeePerGas;
  final BigInt maxFeePerGas;
  final BigInt gasLimit;
  final Uint8List _unsignedTx;
  Uint8List get unsignedTx => Uint8List.fromList(_unsignedTx);

  BigInt get maximumFee => gasLimit * maxFeePerGas;
}

/// Human-readable asset deltas decoded from the exact EIP-1559 bytes that
/// will be signed. This deliberately does not trust a transport summary or a
/// second reconstruction of the user's draft.
class EvmAssetChanges {
  const EvmAssetChanges({
    required this.outgoing,
    required this.maximumNetworkFee,
    required this.recipient,
    required this.tokenContract,
  });

  final Amount outgoing;
  final Amount maximumNetworkFee;
  final String recipient;
  final String? tokenContract;
}

/// Decodes and verifies the exact unsigned envelope approved for signing.
///
/// Any mismatch between the wire bytes, the immutable prepared quote and the
/// user-approved draft is a closed failure. Callers must not render an asset
/// preview or enable signing when this throws.
EvmAssetChanges decodeEvmAssetChanges({
  required PreparedEvmTransfer prepared,
  required TransferDraft draft,
  required int nativeDecimals,
  required String nativeSymbol,
}) {
  final parsed = parseUnsignedTransfer(prepared.chain, prepared.unsignedTx);
  final preparedContract = prepared.tokenContract?.toLowerCase();
  final draftContract = draft.tokenContract?.toLowerCase();
  final parsedContract = parsed.tokenContract?.toLowerCase();
  final expectedOperation = draft.operation;
  final parsedMaximumFee = parsed.maxFeeRaw;

  if (draft.chain != prepared.chain ||
      parsed.chain != prepared.chain ||
      prepared.operation != expectedOperation ||
      parsed.operation != expectedOperation ||
      parsed.to.toLowerCase() != draft.recipient.toLowerCase() ||
      parsed.to.toLowerCase() != prepared.recipient.toLowerCase() ||
      parsed.amountRaw != draft.amount.raw ||
      parsed.amountRaw != prepared.amountRaw ||
      parsedContract != draftContract ||
      parsedContract != preparedContract ||
      parsed.networkId != BigInt.from(prepared.evmChainId) ||
      parsed.nonce != prepared.nonce ||
      parsed.maxPriorityFeePerGas != prepared.maxPriorityFeePerGas ||
      parsed.maxFeePerGas != prepared.maxFeePerGas ||
      parsed.gasLimit != prepared.gasLimit ||
      parsedMaximumFee == null ||
      parsedMaximumFee != prepared.maximumFee) {
    throw const FormatException('prepared EVM transaction does not match');
  }

  return EvmAssetChanges(
    outgoing: Amount(
      raw: parsed.amountRaw,
      decimals: draft.amount.decimals,
      symbol: draft.symbol,
    ),
    maximumNetworkFee: Amount(
      raw: parsedMaximumFee,
      decimals: nativeDecimals,
      symbol: nativeSymbol,
    ),
    recipient: parsed.to,
    tokenContract: parsed.tokenContract,
  );
}

/// Exact TRON raw_data approved on the confirmation screen.
class PreparedTronTransfer {
  PreparedTronTransfer({
    required this.from,
    required this.recipient,
    required this.amountRaw,
    required this.tokenContract,
    required this.maximumFeeSun,
    required this.referenceBlockHeight,
    required this.expiresAt,
    required Uint8List rawTx,
  }) : _rawTx = Uint8List.fromList(rawTx);

  final String from;
  final String recipient;
  final BigInt amountRaw;
  final String? tokenContract;
  final BigInt maximumFeeSun;
  final int referenceBlockHeight;
  final int expiresAt;
  final Uint8List _rawTx;
  Uint8List get rawTx => Uint8List.fromList(_rawTx);
}

/// Exact Solana message approved on the confirmation screen. [rentDeposit]
/// is the recoverable lamport reserve created by this transaction (normally a
/// new ATA); it is deliberately separate from the non-refundable network fee.
class PreparedSolanaTransfer {
  PreparedSolanaTransfer({
    required this.from,
    required this.recipient,
    required this.amountRaw,
    required this.tokenMint,
    required this.tokenProgram,
    required this.networkFeeLamports,
    required this.rentDepositLamports,
    required this.lastValidBlockHeight,
    required Uint8List message,
  }) : _message = Uint8List.fromList(message);

  final String from;
  final String recipient;
  final BigInt amountRaw;
  final String? tokenMint;
  final String? tokenProgram;
  final BigInt networkFeeLamports;
  final BigInt rentDepositLamports;
  final int lastValidBlockHeight;
  final Uint8List _message;
  Uint8List get message => Uint8List.fromList(_message);
}

/// Mutable state of the in-flight transfer flow. One instance lives above the
/// router for the app's lifetime; screens read/write it as the user moves
/// through the flow. Screens rendered without a scope (design gallery index,
/// golden tests) see `null` everywhere and fall back to demo values.
class TransferSession {
  static const quoteValidity = Duration(seconds: 30);

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

  /// True when the signed bytes were submitted but the app did not receive
  /// an authoritative node response. The locally derived hash remains the
  /// recovery key; the UI must warn against sending the transfer again.
  bool broadcastOutcomeUnknown = false;

  /// Stable local row id used as the transaction moves from awaitingSig to
  /// signed/submitted/pending without creating duplicate history entries.
  String? localTransactionId;

  /// Chain-authoritative validity boundaries captured while building the
  /// exact raw transaction. A Pending refresh uses these to distinguish a
  /// temporarily unknown hash from a transaction that can no longer land.
  int? referenceBlockHeight;
  int? expiresAt;
  int? lastValidBlockHeight;

  /// Short-lived EVM quote shown on the confirm page. [preparedNetworkId]
  /// binds it to the exact active network; [preparedAtMs] lets the auth step
  /// reject a stale quote rather than signing parameters the user saw long
  /// ago.
  PreparedEvmTransfer? preparedEvm;
  PreparedTronTransfer? preparedTron;
  PreparedSolanaTransfer? preparedSolana;
  String? preparedNetworkId;
  int? preparedAtMs;

  /// Ephemeral, privacy-sanitized reason from the most recent preparation
  /// attempt. It is never persisted or shown in the consumer UI; physical E2E
  /// evidence can record it instead of reducing every failure to the same
  /// generic fee-estimation message.
  String? preparationFailure;

  /// Returns the exact quote only while it is fresh and still matches every
  /// field the user approved. Any network, sender, recipient, amount or token
  /// drift fails closed.
  PreparedEvmTransfer? validEvmQuote({
    required TransferDraft forDraft,
    required String networkId,
    required int evmChainId,
    required String from,
    int? nowMs,
  }) {
    final prepared = preparedEvm;
    final at = preparedAtMs;
    final age = at == null
        ? null
        : (nowMs ?? DateTime.now().millisecondsSinceEpoch) - at;
    if (prepared == null ||
        preparedNetworkId != networkId ||
        age == null ||
        age < 0 ||
        age > quoteValidity.inMilliseconds ||
        prepared.chain != forDraft.chain ||
        prepared.operation != forDraft.operation ||
        prepared.evmChainId != evmChainId ||
        prepared.from.toLowerCase() != from.toLowerCase() ||
        prepared.recipient.toLowerCase() != forDraft.recipient.toLowerCase() ||
        prepared.amountRaw != forDraft.amount.raw ||
        (prepared.tokenContract?.toLowerCase() ?? '') !=
            (forDraft.tokenContract?.toLowerCase() ?? '')) {
      return null;
    }
    return prepared;
  }

  PreparedTronTransfer? validTronQuote({
    required TransferDraft forDraft,
    required String networkId,
    required String from,
    int? nowMs,
  }) {
    final prepared = preparedTron;
    if (!_quoteIsFresh(networkId: networkId, nowMs: nowMs) ||
        prepared == null ||
        forDraft.chain != Chain.tron ||
        prepared.from != from ||
        prepared.recipient != forDraft.recipient ||
        prepared.amountRaw != forDraft.amount.raw ||
        (prepared.tokenContract ?? '') != (forDraft.tokenContract ?? '')) {
      return null;
    }
    return prepared;
  }

  PreparedSolanaTransfer? validSolanaQuote({
    required TransferDraft forDraft,
    required String networkId,
    required String from,
    int? nowMs,
  }) {
    final prepared = preparedSolana;
    if (!_quoteIsFresh(networkId: networkId, nowMs: nowMs) ||
        prepared == null ||
        forDraft.chain != Chain.solana ||
        prepared.from != from ||
        prepared.recipient != forDraft.recipient ||
        prepared.amountRaw != forDraft.amount.raw ||
        (prepared.tokenMint ?? '') != (forDraft.tokenContract ?? '') ||
        (prepared.tokenProgram ?? '') != (forDraft.tokenProgram ?? '')) {
      return null;
    }
    return prepared;
  }

  bool _quoteIsFresh({required String networkId, int? nowMs}) {
    final at = preparedAtMs;
    final age = at == null
        ? null
        : (nowMs ?? DateTime.now().millisecondsSinceEpoch) - at;
    return preparedNetworkId == networkId &&
        age != null &&
        age >= 0 &&
        age <= quoteValidity.inMilliseconds;
  }

  /// Starts a distinct user transfer. A session lives for the app lifetime,
  /// so assigning only [draft] would accidentally reuse the previous
  /// transaction's database id and broadcast result.
  void begin(TransferDraft next) {
    clear();
    draft = next;
  }

  void clear() {
    draft = null;
    request = null;
    result = null;
    broadcastTxHash = null;
    broadcastOutcomeUnknown = false;
    localTransactionId = null;
    referenceBlockHeight = null;
    expiresAt = null;
    lastValidBlockHeight = null;
    preparedEvm = null;
    preparedTron = null;
    preparedSolana = null;
    preparedNetworkId = null;
    preparedAtMs = null;
    preparationFailure = null;
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
