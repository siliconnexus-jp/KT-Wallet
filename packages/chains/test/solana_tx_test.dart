import 'dart:convert';
import 'dart:typed_data';

// Imported via src/ because the barrel export lands separately; the package:
// form keeps the library identity identical to production imports.
import 'package:chains/src/base58.dart';
import 'package:chains/src/solana_tx.dart';
import 'package:test/test.dart';

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('compact-u16 (shortvec)', () {
    // Boundary vectors straight from the Solana shortvec spec/tests.
    test('spec boundary values encode exactly', () {
      expect(SolanaMessage.encodeCompactU16(0), [0x00]);
      expect(SolanaMessage.encodeCompactU16(127), [0x7f]);
      expect(SolanaMessage.encodeCompactU16(128), [0x80, 0x01]);
      expect(SolanaMessage.encodeCompactU16(16383), [0xff, 0x7f]);
      expect(SolanaMessage.encodeCompactU16(16384), [0x80, 0x80, 0x01]);
      expect(SolanaMessage.encodeCompactU16(0xffff), [0xff, 0xff, 0x03]);
    });

    test('rejects values outside u16', () {
      expect(() => SolanaMessage.encodeCompactU16(-1), throwsArgumentError);
      expect(() => SolanaMessage.encodeCompactU16(0x10000), throwsArgumentError);
    });
  });

  group('SolanaMessage.systemTransfer', () {
    test('reproduces a real mainnet transfer byte-for-byte', () {
      // Confirmed mainnet-beta transaction, fetched 2026-07-21 from
      // https://api.mainnet-beta.solana.com via getBlock(slot 434253204,
      // encoding base64): a pure single-instruction legacy System transfer.
      // Signature (base58):
      //   3weaqtHUfh9JXnec2za1vEThWjAaWdikZ7qCPdwanoJvwJcXj3rdFEAh7znwYtzt
      //   FttE3qURkCcfbN1gcM2kgTVd
      // The wire format is compact-u16 signature count, then 64-byte
      // signatures, then the message — ed25519-verifiable against key 0.
      const txBase64 =
          'AZMpDLR2bcZIs2z6fk31D4rngVa2r2zAjANyg53cZYZW7o/PU+tlBnhatKJthafn'
          'dn5zoGJDx1KE7H8kk+s51wwBAAEDwcK3VWhSC1mprB2eipa4YIShnA4n7sVixUGa'
          'V1l9fDgjPbSa/Z5DK41SPk9JLZXPYOg5HrHPxvuLDYjBJoc49QAAAAAAAAAAAAAA'
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAcJRp1kJK5X4oNdSW4Bg2C+o8dsGvZXqu5fop'
          '7vV14yQBAgIAAQwCAAAA2FvqHwAAAAA=';
      final tx = base64Decode(txBase64);

      // Strip the signature section: count is 1 (single-byte shortvec),
      // followed by one 64-byte signature.
      expect(tx[0], 1);
      final signature = tx.sublist(1, 65);
      expect(
        base58Encode(Uint8List.fromList(signature)),
        '3weaqtHUfh9JXnec2za1vEThWjAaWdikZ7qCPdwanoJvwJcXj3rdFEAh7znwYtzt'
        'FttE3qURkCcfbN1gcM2kgTVd',
      );
      final messageBytes = tx.sublist(65);

      // Fields parsed from that same transaction.
      final message = SolanaMessage.systemTransfer(
        from: 'E3Mtq85xCJFWvGfNfirkXpSDb51TE8uxwjpaPWgfcbE7',
        to: '3NZqqivKZWVvgwaAtwYnwuv6K3WUiDuEir3eU3i1mWiQ',
        lamports: BigInt.from(535452632),
        recentBlockhash: '8aTvLzNp2HD5c168HzMhWLyaQVDfYLVX9UdJ58MrpeKu',
      );
      expect(_hex(message.serialize()), _hex(messageBytes));
      // signingBytes is exactly the serialized message: ed25519 signs these
      // bytes directly, with no pre-hash.
      expect(_hex(message.signingBytes), _hex(messageBytes));
    });

    test('locks the independently derived 1 SOL vector', () {
      // Expected bytes computed with an independent Python reference
      // (own base58 + shortvec + layout per the Solana spec, shortvec
      // validated against the spec examples and the whole reference
      // validated byte-for-byte against the mainnet transaction above) —
      // same approach as the RLP/EIP-1559 vectors in evm_tx_test.dart.
      final message = SolanaMessage.systemTransfer(
        from: '4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T',
        to: 'FDQB1yWWkVeMTHXCVAK7UAGMDX6WUduBmVZLTmiHssbg',
        lamports: BigInt.from(1000000000), // 1 SOL
        recentBlockhash: 'DzfXchZJoLMG3cNftcf2sw7qatkkuwQf4xH15N5wkKAb',
      );
      expect(
        _hex(message.serialize()),
        '01000103'
        '321cfa5add185e8893a5fd88013ec4d7e122ded46354cadff50d956395e75b60'
        'd330c9c35aa870bba1890f51ab3920e49a33333e552e41c1c329bdded06e6353'
        '0000000000000000000000000000000000000000000000000000000000000000'
        'c111e9ae55678cea3e7b6af8eeb315247fbc190cb70c344b7e19665cf035ac8c'
        '01020200010c0200000000ca9a3b00000000',
      );
    });

    test('header and account ordering follow the spec', () {
      final message = SolanaMessage.systemTransfer(
        from: '4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T',
        to: 'FDQB1yWWkVeMTHXCVAK7UAGMDX6WUduBmVZLTmiHssbg',
        lamports: BigInt.two,
        recentBlockhash: 'DzfXchZJoLMG3cNftcf2sw7qatkkuwQf4xH15N5wkKAb',
      );
      expect(message.numRequiredSignatures, 1);
      expect(message.numReadonlySignedAccounts, 0);
      expect(message.numReadonlyUnsignedAccounts, 1);
      expect(message.accountKeys, hasLength(3));
      // from = fee-payer signer at 0, to = writable non-signer at 1,
      // System Program readonly at 2.
      expect(base58Encode(message.accountKeys[0]),
          '4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T');
      expect(base58Encode(message.accountKeys[1]),
          'FDQB1yWWkVeMTHXCVAK7UAGMDX6WUduBmVZLTmiHssbg');
      expect(message.accountKeys[2], List.filled(32, 0)); // system program
      final ix = message.instructions.single;
      expect(ix.programIdIndex, 2);
      expect(ix.accountIndices, [0, 1]);
      // u32 LE discriminant 2, then u64 LE lamports.
      expect(_hex(ix.data), '020000000200000000000000');
    });
  });

  group('SolanaMessage.splTransfer', () {
    test('locks the independently derived 25 USDC-raw vector', () {
      // Expected bytes from the same cross-checked Python reference as the
      // System-transfer vector above; token accounts are passed explicitly
      // (ATA derivation is out of scope, see solana_tx.dart).
      final message = SolanaMessage.splTransfer(
        source: 'Bi9EDynRhtGiiG9wDCzhc5w2yGz8TSaamm9AUJhjZ2u5',
        destination: '7VHUFJHWu2CuExkJcJrzhQPJ2oygupTWkL2A2For4BmE',
        owner: '4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T',
        amount: BigInt.from(25000000),
        recentBlockhash: 'DzfXchZJoLMG3cNftcf2sw7qatkkuwQf4xH15N5wkKAb',
      );
      expect(
        _hex(message.serialize()),
        '01000104'
        '321cfa5add185e8893a5fd88013ec4d7e122ded46354cadff50d956395e75b60'
        '9f1efc615a840ba6f18d9bc3b1c694823a3bb6550468a341f681a852ee0a2250'
        '606501b302e1801892f80a2979f585f8855d0f2034790a2455f744fac503d7b5'
        '06ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a9'
        'c111e9ae55678cea3e7b6af8eeb315247fbc190cb70c344b7e19665cf035ac8c'
        '010303010200090340787d0100000000',
      );
    });

    test('header, ordering and instruction accounts follow the spec', () {
      final message = SolanaMessage.splTransfer(
        source: 'Bi9EDynRhtGiiG9wDCzhc5w2yGz8TSaamm9AUJhjZ2u5',
        destination: '7VHUFJHWu2CuExkJcJrzhQPJ2oygupTWkL2A2For4BmE',
        owner: '4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T',
        amount: BigInt.one,
        recentBlockhash: 'DzfXchZJoLMG3cNftcf2sw7qatkkuwQf4xH15N5wkKAb',
      );
      expect(message.numRequiredSignatures, 1);
      expect(message.numReadonlySignedAccounts, 0);
      expect(message.numReadonlyUnsignedAccounts, 1);
      expect(message.accountKeys, hasLength(4));
      // owner = fee-payer signer at 0, source/destination writable at 1/2,
      // Token Program readonly last.
      expect(base58Encode(message.accountKeys[0]),
          '4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T');
      expect(base58Encode(message.accountKeys[1]),
          'Bi9EDynRhtGiiG9wDCzhc5w2yGz8TSaamm9AUJhjZ2u5');
      expect(base58Encode(message.accountKeys[2]),
          '7VHUFJHWu2CuExkJcJrzhQPJ2oygupTWkL2A2For4BmE');
      expect(base58Encode(message.accountKeys[3]), solanaTokenProgram);
      final ix = message.instructions.single;
      expect(ix.programIdIndex, 3);
      // SPL Transfer account order: source, destination, owner.
      expect(ix.accountIndices, [1, 2, 0]);
      // u8 discriminant 3, then u64 LE amount.
      expect(_hex(ix.data), '030100000000000000');
    });
  });

  group('validation', () {
    const goodFrom = '4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T';
    const goodTo = 'FDQB1yWWkVeMTHXCVAK7UAGMDX6WUduBmVZLTmiHssbg';
    const goodHash = 'DzfXchZJoLMG3cNftcf2sw7qatkkuwQf4xH15N5wkKAb';

    SolanaMessage build({String? from, String? to, BigInt? lamports}) =>
        SolanaMessage.systemTransfer(
          from: from ?? goodFrom,
          to: to ?? goodTo,
          lamports: lamports ?? BigInt.one,
          recentBlockhash: goodHash,
        );

    test('rejects a pubkey that decodes to fewer than 32 bytes', () {
      expect(() => build(from: 'abc'), throwsArgumentError);
    });

    test('rejects a pubkey that decodes to more than 32 bytes', () {
      expect(() => build(to: '${goodTo}1'), throwsArgumentError);
    });

    test('rejects a base58 string with invalid characters', () {
      // 0, O, I and l are not in the base58 alphabet.
      expect(() => build(from: 'O0Il'), throwsArgumentError);
    });

    test('rejects negative and >u64 amounts', () {
      expect(() => build(lamports: BigInt.from(-1)), throwsArgumentError);
      expect(() => build(lamports: BigInt.one << 64), throwsArgumentError);
    });

    test('u64 max lamports still encodes', () {
      final message = build(lamports: (BigInt.one << 64) - BigInt.one);
      final data = message.instructions.single.data;
      expect(_hex(data.sublist(4)), 'ffffffffffffffff');
    });

    test('rejects instruction indices outside the key table', () {
      expect(
        () => SolanaMessage(
          numRequiredSignatures: 1,
          numReadonlySignedAccounts: 0,
          numReadonlyUnsignedAccounts: 1,
          accountKeys: [
            SolanaMessage.pubkeyBytes(goodFrom),
            SolanaMessage.pubkeyBytes(goodTo),
            SolanaMessage.pubkeyBytes(solanaSystemProgram),
          ],
          recentBlockhash: SolanaMessage.pubkeyBytes(goodHash),
          instructions: [
            SolanaInstruction(
              programIdIndex: 3, // out of range
              accountIndices: const [0, 1],
              data: Uint8List(0),
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('rejects a header with more readonly signers than signers', () {
      expect(
        () => SolanaMessage(
          numRequiredSignatures: 1,
          numReadonlySignedAccounts: 1,
          numReadonlyUnsignedAccounts: 0,
          accountKeys: [SolanaMessage.pubkeyBytes(goodFrom)],
          recentBlockhash: SolanaMessage.pubkeyBytes(goodHash),
          instructions: const [],
        ),
        throwsArgumentError,
      );
    });
  });
}
