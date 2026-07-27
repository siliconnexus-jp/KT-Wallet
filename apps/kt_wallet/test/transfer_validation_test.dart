import 'package:chains/chains.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/transfer/transfer_validation.dart';

const _evm = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';
const _tron = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';

Amount _eth(String v) => Amount.parse(v, 18, symbol: 'ETH');
Amount _usdt(String v) => Amount.parse(v, 6, symbol: 'USDT');

void main() {
  group('address checks', () {
    test('valid EVM address passes and is normalized', () {
      final r = TransferValidation.validate(
        chain: Chain.ethereum,
        to: _evm.toLowerCase(),
        amount: _eth('1'),
        isTokenTransfer: false,
        nativeBalance: _eth('10'),
        maxFee: _eth('0.01'),
      );
      expect(r.ok, isTrue);
      expect(r.normalizedTo, _evm);
    });

    test('TRON address in an EVM transfer → wrongNetworkAddress', () {
      final r = TransferValidation.validate(
        chain: Chain.ethereum,
        to: _tron,
        amount: _eth('1'),
        isTokenTransfer: false,
        nativeBalance: _eth('10'),
        maxFee: _eth('0.01'),
      );
      expect(r.problem, TransferProblem.wrongNetworkAddress);
    });

    test('garbage address → invalidAddress', () {
      final r = TransferValidation.validate(
        chain: Chain.ethereum,
        to: 'nonsense',
        amount: _eth('1'),
        isTokenTransfer: false,
        nativeBalance: _eth('10'),
        maxFee: _eth('0.01'),
      );
      expect(r.problem, TransferProblem.invalidAddress);
    });
  });

  group('amount / balance / fee checks', () {
    test('zero amount rejected', () {
      final r = TransferValidation.validate(
        chain: Chain.ethereum,
        to: _evm,
        amount: _eth('0'),
        isTokenTransfer: false,
        nativeBalance: _eth('10'),
        maxFee: _eth('0.01'),
      );
      expect(r.problem, TransferProblem.zeroAmount);
    });

    test('native: amount over balance → insufficientBalance', () {
      final r = TransferValidation.validate(
        chain: Chain.ethereum,
        to: _evm,
        amount: _eth('20'),
        isTokenTransfer: false,
        nativeBalance: _eth('10'),
        maxFee: _eth('0.01'),
      );
      expect(r.problem, TransferProblem.insufficientBalance);
    });

    test(
      'native: amount fits but amount+fee does not → insufficientForFee',
      () {
        final r = TransferValidation.validate(
          chain: Chain.ethereum,
          to: _evm,
          amount: _eth('10'),
          isTokenTransfer: false,
          nativeBalance: _eth('10'),
          maxFee: _eth('0.01'),
        );
        expect(r.problem, TransferProblem.insufficientForFee);
      },
    );

    test('token: amount over token balance → insufficientBalance', () {
      final r = TransferValidation.validate(
        chain: Chain.tron,
        to: _tron,
        amount: _usdt('100'),
        isTokenTransfer: true,
        tokenBalance: _usdt('50'),
        nativeBalance: Amount.parse('1000', 6, symbol: 'TRX'),
        maxFee: Amount.parse('13.7', 6, symbol: 'TRX'),
      );
      expect(r.problem, TransferProblem.insufficientBalance);
    });

    test('token: fee exceeds native balance → insufficientForFee', () {
      final r = TransferValidation.validate(
        chain: Chain.tron,
        to: _tron,
        amount: _usdt('10'),
        isTokenTransfer: true,
        tokenBalance: _usdt('50'),
        nativeBalance: Amount.parse('5', 6, symbol: 'TRX'),
        maxFee: Amount.parse('13.7', 6, symbol: 'TRX'),
      );
      expect(r.problem, TransferProblem.insufficientForFee);
    });

    test('token transfer with enough of both passes', () {
      final r = TransferValidation.validate(
        chain: Chain.tron,
        to: _tron,
        amount: _usdt('10'),
        isTokenTransfer: true,
        tokenBalance: _usdt('50'),
        nativeBalance: Amount.parse('1000', 6, symbol: 'TRX'),
        maxFee: Amount.parse('13.7', 6, symbol: 'TRX'),
      );
      expect(r.ok, isTrue);
    });
  });

  group('dust threshold', () {
    test('below threshold is dust, exactly at threshold is allowed', () {
      TransferCheck check(String amt) => TransferValidation.validate(
        chain: Chain.ethereum,
        to: _evm,
        amount: _eth(amt),
        isTokenTransfer: false,
        nativeBalance: _eth('10'),
        maxFee: _eth('0.001'),
        dustThreshold: _eth('0.0001'),
      );
      expect(check('0.00005').problem, TransferProblem.dust);
      expect(check('0.0001').ok, isTrue); // exactly at threshold: allowed
      expect(check('0.0002').ok, isTrue);
    });

    test('mismatched decimals throws (no silent misclassification)', () {
      expect(
        () => TransferValidation.validate(
          chain: Chain.ethereum,
          to: _evm,
          amount: _eth('1'),
          isTokenTransfer: false,
          nativeBalance: _eth('10'),
          maxFee: _eth('0.001'),
          dustThreshold: _usdt('0.5'), // 6-decimal threshold vs 18-decimal amt
        ),
        throwsArgumentError,
      );
    });
  });

  group('maxNative', () {
    test('max sendable = balance - maxFee', () {
      final max = TransferValidation.maxNative(
        balance: _eth('2'),
        maxFee: _eth('0.01'),
      );
      expect(max.format(), '1.99');
    });

    test('fee >= balance yields zero, never negative', () {
      final max = TransferValidation.maxNative(
        balance: _eth('0.005'),
        maxFee: _eth('0.01'),
      );
      expect(max.raw, BigInt.zero);
    });
  });
}
