import 'dart:math' as math;

import 'package:chains/chains.dart' show Amount;

/// Converts an exact on-chain [amount] and a display-only market [unitPrice]
/// to fiat without allowing malformed market data or floating-point overflow
/// to become a visible balance. Transaction construction never uses this.
double? fiatValueForDisplay(Amount? amount, double? unitPrice) {
  if (amount == null ||
      unitPrice == null ||
      !unitPrice.isFinite ||
      unitPrice <= 0) {
    return null;
  }
  final raw = amount.raw.toDouble();
  final scale = math.pow(10, amount.decimals).toDouble();
  if (!raw.isFinite || !scale.isFinite || scale <= 0) return null;
  final value = raw / scale * unitPrice;
  return value.isFinite && value >= 0 ? value : null;
}

/// Multiplies display-only fiat values while preserving the unavailable state
/// for invalid/overflowing FX data.
double? multiplyFiatForDisplay(double? value, double? rate) {
  if (value == null ||
      rate == null ||
      !value.isFinite ||
      value < 0 ||
      !rate.isFinite ||
      rate <= 0) {
    return null;
  }
  final converted = value * rate;
  return converted.isFinite ? converted : null;
}

double? positiveFiniteMarketNumber(Object? value) {
  if (value is! num) return null;
  final parsed = value.toDouble();
  return parsed.isFinite && parsed > 0 ? parsed : null;
}

double? finiteMarketNumber(Object? value) {
  if (value is! num) return null;
  final parsed = value.toDouble();
  return parsed.isFinite ? parsed : null;
}
