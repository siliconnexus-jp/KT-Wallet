import 'address.dart';
import 'amount.dart';

/// Operation kinds the wallet builds/parses in V1.
///
/// [approvalRevoke] is intentionally narrow: it means the exact ERC-20 call
/// `approve(spender, 0)`. Arbitrary approvals and arbitrary contract calls are
/// not represented by this enum and therefore remain outside the signing
/// whitelist.
enum TxOperation { nativeTransfer, tokenTransfer, approvalRevoke }

/// User-entered transfer request, before fees/nonce/blockhash are attached.
class TransferIntent {
  TransferIntent({
    required this.chain,
    required this.operation,
    required this.from,
    required this.to,
    required this.amount,
    this.tokenContract,
    this.tokenSymbol,
  }) {
    if (operation != TxOperation.nativeTransfer && tokenContract == null) {
      throw ArgumentError('token operation requires a contract');
    }
    if (operation == TxOperation.approvalRevoke) {
      final isEvm =
          chain == Chain.ethereum ||
          chain == Chain.polygon ||
          chain == Chain.base ||
          chain == Chain.arbitrum ||
          chain == Chain.avalanche ||
          chain == Chain.bnb;
      if (!isEvm || amount.raw != BigInt.zero) {
        throw ArgumentError(
          'approval revoke requires an EVM chain and zero amount',
        );
      }
    }
  }

  final Chain chain;
  final TxOperation operation;
  final String from;
  final String to;
  final Amount amount;
  final String? tokenContract;
  final String? tokenSymbol;
}

/// Chain-agnostic, human-readable summary of a transaction, produced by the
/// builders and — critically — reproduced by the offline signer directly from
/// the raw transaction bytes (detailed-design.md §4.2, §3.4). Both apps show
/// THIS, never a transport `summary` hint.
class TxPreview {
  const TxPreview({
    required this.chain,
    required this.operation,
    required this.from,
    required this.to,
    required this.amount,
    required this.networkFee,
    required this.maxFee,
    this.tokenContract,
    this.trustedToken = false,
    this.warnings = const [],
  });

  final Chain chain;
  final TxOperation operation;
  final String from;
  final String to;
  final Amount amount;
  final Amount networkFee;
  final Amount maxFee;
  final String? tokenContract;

  /// Whether the token is in the app's trusted list; false → high-risk display
  /// with the raw contract shown (ui-m.md §8.5 unknown-token rule).
  final bool trustedToken;
  final List<String> warnings;

  Amount? get totalNativeSpend =>
      operation == TxOperation.nativeTransfer &&
          amount.decimals == maxFee.decimals
      ? amount + maxFee
      : null;
}
