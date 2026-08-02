import 'package:chains/chains.dart';
import 'package:test/test.dart';

void main() {
  group('EVM EIP-55 (spec vectors)', () {
    const spec = [
      '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
      '0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359',
      '0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB',
      '0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb',
    ];

    test('toChecksumAddress matches the EIP-55 reference vectors', () {
      for (final a in spec) {
        expect(Addresses.toChecksumAddress(a.toLowerCase()), a);
      }
    });

    test('accepts correctly-checksummed and normalizes all-lowercase', () {
      for (final chain in [Chain.ethereum, Chain.polygon]) {
        final r = Addresses.validate(chain, spec[0]);
        expect(r.isValid, isTrue);
        expect(r.normalized, spec[0]);

        final lower = Addresses.validate(chain, spec[0].toLowerCase());
        expect(lower.isValid, isTrue);
        expect(lower.normalized, spec[0]);
      }
    });

    test('rejects a mixed-case checksum mismatch', () {
      // Flip the case of one letter in a valid checksummed address.
      final broken = spec[0].replaceFirst('A', 'a');
      final r = Addresses.validate(Chain.ethereum, broken);
      expect(r.isValid, isFalse);
      expect(r.reason, contains('checksum'));
    });

    test('rejects wrong length / non-hex', () {
      expect(Addresses.validate(Chain.ethereum, '0x1234').isValid, isFalse);
      expect(
        Addresses.validate(
          Chain.ethereum,
          '0xZZ6916095ca1df60bB79Ce92cE3Ea74c37c5d359',
        ).isValid,
        isFalse,
      );
    });
  });

  group('TRON Base58Check', () {
    // USDT-TRON contract address — a real, checksum-valid TRON address.
    const usdt = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';

    test('accepts a valid address', () {
      final r = Addresses.validate(Chain.tron, usdt);
      expect(r.isValid, isTrue, reason: r.reason);
      expect(r.normalized, usdt);
    });

    test('rejects a checksum-corrupted address', () {
      final broken = '${usdt.substring(0, usdt.length - 1)}x';
      expect(Addresses.validate(Chain.tron, broken).isValid, isFalse);
    });

    test('rejects an address not starting with T', () {
      expect(
        Addresses.validate(Chain.tron, usdt.substring(1)).isValid,
        isFalse,
      );
    });
  });

  group('Solana', () {
    const wrappedSol = 'So11111111111111111111111111111111111111112';

    test('accepts a valid 32-byte key', () {
      final r = Addresses.validate(Chain.solana, wrappedSol);
      expect(r.isValid, isTrue, reason: r.reason);
    });

    test('rejects invalid base58 characters', () {
      expect(
        Addresses.validate(Chain.solana, 'not_base58_0OIl').isValid,
        isFalse,
      );
    });
  });

  group('cross-chain mispaste detection (ui-m.md §10.3)', () {
    const evm = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';
    const tron = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';
    const sol = 'So11111111111111111111111111111111111111112';

    test('TRON address in an EVM transfer is rejected', () {
      expect(Addresses.validate(Chain.ethereum, tron).isValid, isFalse);
    });

    test('EVM address in a TRON transfer is rejected', () {
      expect(Addresses.validate(Chain.tron, evm).isValid, isFalse);
    });

    test('EVM address in a Solana transfer is rejected', () {
      expect(Addresses.validate(Chain.solana, evm).isValid, isFalse);
    });

    test('Solana address in a TRON transfer is rejected', () {
      expect(Addresses.validate(Chain.tron, sol).isValid, isFalse);
    });
  });

  group('base58 roundtrip', () {
    test('encode/decode is lossless including leading zeros', () {
      for (final s in [
        'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
        'So11111111111111111111111111111111111111112',
      ]) {
        expect(base58Encode(base58Decode(s)), s);
      }
    });
  });

  group('chain-aware address identity', () {
    test('EVM identity ignores checksum presentation case', () {
      const checksum = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';
      expect(
        Addresses.equal(Chain.ethereum, checksum, checksum.toLowerCase()),
        isTrue,
      );
      expect(
        Addresses.equal(Chain.bnb, checksum.toUpperCase(), checksum),
        isTrue,
      );
    });

    test('TRON and Solana Base58 identity remains case-sensitive', () {
      const tron = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';
      const solana = 'So11111111111111111111111111111111111111112';
      expect(Addresses.equal(Chain.tron, tron, tron), isTrue);
      expect(Addresses.equal(Chain.tron, tron, tron.toLowerCase()), isFalse);
      expect(Addresses.equal(Chain.solana, solana, solana), isTrue);
      expect(
        Addresses.equal(Chain.solana, solana, solana.toLowerCase()),
        isFalse,
      );
    });
  });
}
