import 'package:chains/chains.dart';
import 'package:test/test.dart';

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('ERC-20 transfer calldata', () {
    test('selector is a9059cbb', () {
      expect(_hex(Erc20.transferSelector), 'a9059cbb');
    });

    test('encodes a known transfer (100 USDT, 6 decimals) exactly', () {
      // 100 USDT = 100_000_000 base units = 0x05f5e100.
      final calldata = Erc20.transferCalldata(
        to: '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
        amount: BigInt.from(100000000),
      );
      expect(
        _hex(calldata),
        'a9059cbb'
        '0000000000000000000000005aaeb6053f3e94c9b9a09f33669435e7ef1beaed'
        '0000000000000000000000000000000000000000000000000000000005f5e100',
      );
      expect(calldata.length, 68);
    });

    test('amount 0 encodes to a zero uint256', () {
      final calldata = Erc20.transferCalldata(
        to: '0x0000000000000000000000000000000000000001',
        amount: BigInt.zero,
      );
      expect(_hex(calldata).substring(8 + 64), '0' * 64);
    });

    test('large uint256 (max) encodes without loss', () {
      final max = (BigInt.one << 256) - BigInt.one;
      final calldata = Erc20.transferCalldata(
        to: '0x0000000000000000000000000000000000000001',
        amount: max,
      );
      expect(_hex(calldata).substring(8 + 64), 'f' * 64);
    });

    test('rejects a non-20-byte address', () {
      expect(
        () => Erc20.transferCalldata(to: '0x1234', amount: BigInt.one),
        throwsArgumentError,
      );
    });

    test('rejects a negative amount', () {
      expect(
        () => Erc20.transferCalldata(
          to: '0x0000000000000000000000000000000000000001',
          amount: BigInt.from(-1),
        ),
        throwsArgumentError,
      );
    });

    test('rejects an amount >= 2^256 instead of truncating', () {
      expect(
        () => Erc20.transferCalldata(
          to: '0x0000000000000000000000000000000000000001',
          amount: BigInt.one << 256,
        ),
        throwsArgumentError,
      );
    });
  });

  group('TxPreview', () {
    test('native transfer total spend = amount + maxFee', () {
      final preview = TxPreview(
        chain: Chain.ethereum,
        operation: TxOperation.nativeTransfer,
        from: '0xfrom',
        to: '0xto',
        amount: Amount.parse('1', 18, symbol: 'ETH'),
        networkFee: Amount.parse('0.001', 18, symbol: 'ETH'),
        maxFee: Amount.parse('0.002', 18, symbol: 'ETH'),
      );
      expect(preview.totalNativeSpend!.format(), '1.002');
    });

    test('token transfer has no native total (fee currency differs)', () {
      final preview = TxPreview(
        chain: Chain.tron,
        operation: TxOperation.tokenTransfer,
        from: 'Tfrom',
        to: 'Tto',
        amount: Amount.parse('100', 6, symbol: 'USDT'),
        networkFee: Amount.parse('13.7', 6, symbol: 'TRX'),
        maxFee: Amount.parse('27.4', 6, symbol: 'TRX'),
        tokenContract: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
      );
      expect(preview.totalNativeSpend, isNull);
    });

    test('token transfer intent requires a contract', () {
      expect(
        () => TransferIntent(
          chain: Chain.ethereum,
          operation: TxOperation.tokenTransfer,
          from: '0xfrom',
          to: '0xto',
          amount: Amount.parse('1', 6),
        ),
        throwsArgumentError,
      );
    });
  });

  group('Erc20.transferCalldata recipient validation', () {
    // Regression: token transfers used to skip Addresses.validate entirely
    // (only the byte length was checked), so a mistyped mixed-case address
    // sailed through and the tokens landed somewhere unspendable. Native
    // transfers were always validated — these lock the parity.
    const valid = '0x925fEA1c0dbf3B011391bbed682E32861BE73213';

    test('accepts an EIP-55 correct address', () {
      expect(
        Erc20.transferCalldata(to: valid, amount: BigInt.from(1000000)).length,
        68,
      );
    });

    test('rejects a broken EIP-55 checksum', () {
      final flipped = '${valid.substring(0, valid.length - 1)}D';
      expect(Addresses.validate(Chain.ethereum, flipped).isValid, isFalse);
      expect(
        () => Erc20.transferCalldata(to: flipped, amount: BigInt.from(1)),
        throwsArgumentError,
      );
    });

    test('rejects a non-EVM address', () {
      expect(
        () => Erc20.transferCalldata(
          to: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
          amount: BigInt.from(1),
        ),
        throwsArgumentError,
      );
    });
  });
}
