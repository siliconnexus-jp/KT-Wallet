/// Chain-agnostic money type. Amounts are exact integers of the smallest chain
/// unit (wei / SUN / lamports / token base units); a `decimals` scale maps to
/// the human-readable value. Doubles are never used for money
/// (detailed-design.md §4.1) — enforced by lint (no-double-in-amount).
class Amount {
  Amount({required this.raw, required this.decimals, this.symbol = ''}) {
    if (raw < BigInt.zero) {
      throw AmountError('amount cannot be negative: $raw');
    }
    if (decimals < 0 || decimals > 36) {
      throw AmountError('unreasonable decimals: $decimals');
    }
  }

  /// Value in the smallest unit (never negative).
  final BigInt raw;

  /// Number of fractional digits in the human-readable value.
  final int decimals;

  /// Display symbol (e.g. "USDT"); optional, not part of equality.
  final String symbol;

  /// Grouping characters stripped before parsing. A comma is DELIBERATELY not
  /// in this set: on comma-decimal locales (de/fr/es/pt…) the numeric keypad's
  /// decimal key emits ',', so stripping it would silently turn "1,5" into
  /// "15" — a 10x overpayment with every balance check still passing. Callers
  /// that want locale input must convert the separator explicitly first.
  static final _groupingChars = RegExp(r'[_\s]');
  static final _commaChars = RegExp(r'[,，]');

  /// Parses a human-readable decimal string ("120.5") into base units.
  /// Rejects more fractional digits than [decimals] (no silent truncation).
  factory Amount.parse(String value, int decimals, {String symbol = ''}) {
    if (_commaChars.hasMatch(value)) {
      throw AmountError(
        'comma is ambiguous (decimal separator vs grouping): $value',
      );
    }
    final cleaned = value.replaceAll(_groupingChars, '');
    if (cleaned.isEmpty) throw AmountError('empty amount');
    if (cleaned.startsWith('-')) throw AmountError('negative amount');
    final parts = cleaned.split('.');
    if (parts.length > 2) throw AmountError('malformed amount: $value');

    final intPart = parts[0].isEmpty ? '0' : parts[0];
    final fracPart = parts.length == 2 ? parts[1] : '';
    if (!RegExp(r'^\d+$').hasMatch(intPart) ||
        (fracPart.isNotEmpty && !RegExp(r'^\d+$').hasMatch(fracPart))) {
      throw AmountError('non-numeric amount: $value');
    }
    if (fracPart.length > decimals) {
      throw AmountError(
          'too many fractional digits for $decimals-decimal token');
    }
    final scaled = intPart + fracPart.padRight(decimals, '0');
    return Amount(raw: BigInt.parse(scaled), decimals: decimals, symbol: symbol);
  }

  static Amount zero(int decimals, {String symbol = ''}) =>
      Amount(raw: BigInt.zero, decimals: decimals, symbol: symbol);

  Amount operator +(Amount other) {
    _sameScale(other);
    return Amount(raw: raw + other.raw, decimals: decimals, symbol: symbol);
  }

  /// Subtraction; throws if the result would be negative (no underflow).
  Amount operator -(Amount other) {
    _sameScale(other);
    if (other.raw > raw) throw AmountError('subtraction underflow');
    return Amount(raw: raw - other.raw, decimals: decimals, symbol: symbol);
  }

  bool operator >=(Amount other) {
    _sameScale(other);
    return raw >= other.raw;
  }

  bool operator <=(Amount other) {
    _sameScale(other);
    return raw <= other.raw;
  }

  void _sameScale(Amount other) {
    if (decimals != other.decimals) {
      throw AmountError('decimal mismatch: $decimals vs ${other.decimals}');
    }
  }

  /// Formats to a human-readable string, trimming trailing zeros. [maxFraction]
  /// caps the fractional digits shown (rounding toward zero for display only —
  /// the underlying [raw] is unchanged).
  String format({int? maxFraction}) {
    final s = raw.toString().padLeft(decimals + 1, '0');
    final intPart = s.substring(0, s.length - decimals);
    var fracPart = decimals == 0 ? '' : s.substring(s.length - decimals);
    if (maxFraction != null && fracPart.length > maxFraction) {
      fracPart = fracPart.substring(0, maxFraction);
    }
    fracPart = fracPart.replaceFirst(RegExp(r'0+$'), '');
    return fracPart.isEmpty ? intPart : '$intPart.$fracPart';
  }

  @override
  bool operator ==(Object other) =>
      other is Amount && other.raw == raw && other.decimals == decimals;

  @override
  int get hashCode => Object.hash(raw, decimals);

  @override
  String toString() => '${format()} $symbol'.trim();
}

class AmountError implements Exception {
  AmountError(this.message);
  final String message;
  @override
  String toString() => 'AmountError: $message';
}
