import 'package:chains/chains.dart';
import 'package:test/test.dart';

void main() {
  group('Amount.parse', () {
    test('parses integer and fractional values at various decimals', () {
      expect(Amount.parse('1', 18).raw, BigInt.parse('1000000000000000000'));
      expect(Amount.parse('120.5', 6).raw, BigInt.from(120500000));
      expect(Amount.parse('0.000000001', 9).raw, BigInt.one); // 1 lamport
      expect(Amount.parse('0', 6).raw, BigInt.zero);
    });

    test('strips underscore and whitespace grouping', () {
      expect(Amount.parse('1_000', 0).raw, BigInt.from(1000));
      expect(Amount.parse('1 000.5', 2).raw, BigInt.from(100050));
    });

    // Regression: a comma used to be stripped as a thousands separator, so on
    // comma-decimal locales (de/fr/es/pt…) the keypad's decimal key turned
    // "1,5" into "15" — a 10x overpayment that passed every balance check.
    test('rejects commas as ambiguous instead of guessing', () {
      expect(() => Amount.parse('1,5', 18), throwsA(isA<AmountError>()));
      expect(() => Amount.parse('1,000.5', 2), throwsA(isA<AmountError>()));
      expect(() => Amount.parse('1，5', 18), throwsA(isA<AmountError>()));
    });

    test('rejects more fractional digits than decimals (no truncation)', () {
      expect(() => Amount.parse('1.1234567', 6), throwsA(isA<AmountError>()));
      expect(() => Amount.parse('0.1', 0), throwsA(isA<AmountError>()));
    });

    test('rejects negative and malformed input', () {
      expect(() => Amount.parse('-1', 6), throwsA(isA<AmountError>()));
      expect(() => Amount.parse('1.2.3', 6), throwsA(isA<AmountError>()));
      expect(() => Amount.parse('abc', 6), throwsA(isA<AmountError>()));
      expect(() => Amount.parse('', 6), throwsA(isA<AmountError>()));
    });

    test('decimals boundaries 6/9/18', () {
      expect(Amount.parse('1', 6).raw, BigInt.from(1000000));
      expect(Amount.parse('1', 9).raw, BigInt.from(1000000000));
      expect(Amount.parse('1', 18).raw, BigInt.parse('1000000000000000000'));
    });

    test('preserves values beyond IEEE-754 precision exactly', () {
      final amount = Amount.parse('9007199254740993.000000000000000001', 18);
      expect(amount.raw, BigInt.parse('9007199254740993000000000000000001'));
      expect(amount.format(), '9007199254740993.000000000000000001');
    });
  });

  group('Amount.format', () {
    test('round-trips and trims trailing zeros', () {
      expect(Amount.parse('120.50', 6).format(), '120.5');
      expect(Amount.parse('1000', 18).format(), '1000');
      expect(Amount.parse('0.1', 18).format(), '0.1');
    });

    test('exact decimal precision (no float error)', () {
      final sum = Amount.parse('0.1', 18) + Amount.parse('0.2', 18);
      expect(sum.format(), '0.3'); // would be 0.30000000000000004 as double
    });

    test('maxFraction caps displayed digits', () {
      expect(Amount.parse('1.23456789', 18).format(maxFraction: 4), '1.2345');
    });

    test('zero decimals', () {
      expect(Amount.parse('42', 0).format(), '42');
    });
  });

  group('Amount arithmetic', () {
    test('add and subtract at same scale', () {
      final a = Amount.parse('10', 6);
      final b = Amount.parse('3.5', 6);
      expect((a + b).format(), '13.5');
      expect((a - b).format(), '6.5');
    });

    test('subtraction underflow throws', () {
      expect(
        () => Amount.parse('1', 6) - Amount.parse('2', 6),
        throwsA(isA<AmountError>()),
      );
    });

    test('decimal-scale mismatch throws', () {
      expect(
        () => Amount.parse('1', 6) + Amount.parse('1', 9),
        throwsA(isA<AmountError>()),
      );
    });

    test('comparisons', () {
      expect(Amount.parse('5', 6) >= Amount.parse('5', 6), isTrue);
      expect(Amount.parse('5', 6) <= Amount.parse('6', 6), isTrue);
      expect(Amount.parse('7', 6) >= Amount.parse('6', 6), isTrue);
    });

    test('equality ignores symbol', () {
      expect(
        Amount(raw: BigInt.one, decimals: 6, symbol: 'A'),
        Amount(raw: BigInt.one, decimals: 6, symbol: 'B'),
      );
    });
  });

  group('constructor guards', () {
    test('negative raw rejected', () {
      expect(
        () => Amount(raw: BigInt.from(-1), decimals: 6),
        throwsA(isA<AmountError>()),
      );
    });

    test('unreasonable decimals rejected', () {
      expect(
        () => Amount(raw: BigInt.one, decimals: 99),
        throwsA(isA<AmountError>()),
      );
      expect(
        () => Amount(raw: BigInt.one, decimals: Amount.maxDecimals + 1),
        throwsA(isA<AmountError>()),
      );
    });
  });
}
