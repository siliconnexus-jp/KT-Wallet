import 'package:chains/rpc.dart';

import '../../l10n/app_localizations.dart';

/// Converts a bounded node-rejection reason into user-facing copy.
///
/// Never accept a provider string here. RPC error bodies are untrusted and
/// can contain credentials, URLs or injected text; only the structured enum
/// may cross into the presentation layer.
String localizedRpcRejection(AppLocalizations l10n, RpcRejectionKind kind) =>
    switch (kind) {
      RpcRejectionKind.insufficientFunds => l10n.rpcRejectInsufficientFunds,
      RpcRejectionKind.nonceTooLow => l10n.rpcRejectNonceTooLow,
      RpcRejectionKind.nonceTooHigh => l10n.rpcRejectNonceTooHigh,
      RpcRejectionKind.replacementFeeTooLow =>
        l10n.rpcRejectReplacementFeeTooLow,
      RpcRejectionKind.feeTooLow => l10n.rpcRejectFeeTooLow,
      RpcRejectionKind.gasLimitTooLow => l10n.rpcRejectGasLimitTooLow,
      RpcRejectionKind.blockGasLimitExceeded => l10n.rpcRejectBlockGasLimit,
      RpcRejectionKind.feeCapBelowBaseFee => l10n.rpcRejectFeeCapBelowBase,
      RpcRejectionKind.alreadyKnown => l10n.rpcRejectAlreadyKnown,
      RpcRejectionKind.executionReverted => l10n.rpcRejectExecutionReverted,
      RpcRejectionKind.invalidSender => l10n.rpcRejectInvalidSender,
      RpcRejectionKind.expiredReference => l10n.rpcRejectExpiredReference,
      RpcRejectionKind.accountInUse => l10n.rpcRejectAccountInUse,
      RpcRejectionKind.simulationFailed => l10n.rpcRejectSimulationFailed,
      RpcRejectionKind.invalidSignature => l10n.rpcRejectInvalidSignature,
      RpcRejectionKind.rejected => l10n.rpcRejectGeneric,
    };
