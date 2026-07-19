import 'package:chains/chains.dart';

/// Validates transfer inputs before a transaction is built (ui-m.md §8.9,
/// detailed-design.md §6.5). Reuses chains address/amount logic; adds
/// balance/fee/max checks.
enum TransferProblem {
  ok,
  invalidAddress,
  wrongNetworkAddress,
  zeroAmount,
  insufficientBalance,
  insufficientForFee, // native transfer: amount + fee > balance
  dust,
}

class TransferCheck {
  const TransferCheck(this.problem, {this.normalizedTo});
  final TransferProblem problem;
  final String? normalizedTo;
  bool get ok => problem == TransferProblem.ok;
}

abstract final class TransferValidation {
  /// [nativeBalance] and [tokenBalance] are the spendable amounts; [fee] is the
  /// max network fee in the NATIVE unit. For a native transfer, amount + fee
  /// must fit the native balance; for a token transfer, amount fits the token
  /// balance and fee fits the native balance separately.
  static TransferCheck validate({
    required Chain chain,
    required String to,
    required Amount amount,
    required bool isTokenTransfer,
    required Amount nativeBalance,
    required Amount maxFee,
    Amount? tokenBalance,
    Amount? dustThreshold,
  }) {
    final addr = Addresses.validate(chain, to);
    if (!addr.isValid) {
      // Distinguish a well-formed address for the wrong chain from garbage.
      final looksLikeOtherChain = _matchesAnyOtherChain(chain, to);
      return TransferCheck(looksLikeOtherChain
          ? TransferProblem.wrongNetworkAddress
          : TransferProblem.invalidAddress);
    }

    if (amount.raw == BigInt.zero) {
      return const TransferCheck(TransferProblem.zeroAmount);
    }
    if (dustThreshold != null) {
      _requireSameScale(amount, dustThreshold, 'dust threshold');
      // Strictly below the threshold is dust; exactly at it is allowed.
      if (amount.raw < dustThreshold.raw) {
        return const TransferCheck(TransferProblem.dust);
      }
    }

    if (isTokenTransfer) {
      final tb = tokenBalance;
      if (tb == null) {
        return const TransferCheck(TransferProblem.insufficientBalance);
      }
      _requireSameScale(amount, tb, 'token balance');
      if (amount.raw > tb.raw) {
        return const TransferCheck(TransferProblem.insufficientBalance);
      }
      if (maxFee.raw > nativeBalance.raw) {
        return const TransferCheck(TransferProblem.insufficientForFee);
      }
    } else {
      _requireSameScale(amount, nativeBalance, 'native balance');
      _requireSameScale(maxFee, nativeBalance, 'fee');
      if (amount.raw > nativeBalance.raw) {
        return const TransferCheck(TransferProblem.insufficientBalance);
      }
      if (amount.raw + maxFee.raw > nativeBalance.raw) {
        return const TransferCheck(TransferProblem.insufficientForFee);
      }
    }
    return TransferCheck(TransferProblem.ok, normalizedTo: addr.normalized);
  }

  /// Max sendable for a NATIVE transfer = balance − maxFee (never negative).
  static Amount maxNative({required Amount balance, required Amount maxFee}) {
    _requireSameScale(balance, maxFee, 'fee');
    if (maxFee.raw >= balance.raw) {
      return Amount.zero(balance.decimals, symbol: balance.symbol);
    }
    return balance - maxFee;
  }

  static void _requireSameScale(Amount a, Amount b, String what) {
    if (a.decimals != b.decimals) {
      throw ArgumentError('$what decimals mismatch: ${a.decimals} vs ${b.decimals}');
    }
  }

  static bool _matchesAnyOtherChain(Chain chain, String address) {
    for (final other in Chain.values) {
      if (other == chain) continue;
      if (Addresses.validate(other, address).isValid) return true;
    }
    return false;
  }
}
