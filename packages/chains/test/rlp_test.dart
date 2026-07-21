import 'dart:convert';
import 'dart:typed_data';

import 'package:chains/chains.dart';
import 'package:test/test.dart';

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  // Classic vectors from the Ethereum RLP spec (ethereum/wiki RLP page).
  group('Rlp.encodeBytes', () {
    test('empty string is 0x80', () {
      expect(_hex(Rlp.encodeBytes(const [])), '80');
    });

    test('single byte < 0x80 encodes as itself', () {
      expect(_hex(Rlp.encodeBytes(const [0x00])), '00');
      expect(_hex(Rlp.encodeBytes(const [0x0f])), '0f');
      expect(_hex(Rlp.encodeBytes(const [0x7f])), '7f');
    });

    test('single byte >= 0x80 gets a length header', () {
      expect(_hex(Rlp.encodeBytes(const [0x80])), '8180');
      expect(_hex(Rlp.encodeBytes(const [0xff])), '81ff');
    });

    test('"dog" is 0x83 646f67', () {
      expect(_hex(Rlp.encodeBytes(utf8.encode('dog'))), '83646f67');
    });

    test('55-byte string still uses the short header (0xb7)', () {
      final encoded = Rlp.encodeBytes(List.filled(55, 0x61));
      expect(encoded[0], 0xb7);
      expect(encoded.length, 56);
    });

    test('56-byte string switches to the long header (0xb8 38)', () {
      // The spec's "Lorem ipsum dolor sit amet, consectetur adipisicing elit"
      // example is exactly 56 bytes → 0xb8 0x38 prefix.
      final s = 'Lorem ipsum dolor sit amet, consectetur adipisicing elit';
      final encoded = Rlp.encodeBytes(utf8.encode(s));
      expect(encoded.length, 58);
      expect(_hex(encoded.sublist(0, 2)), 'b838');
      expect(utf8.decode(encoded.sublist(2)), s);
    });

    test('1024-byte string uses a 2-byte length (0xb9 0400)', () {
      final encoded = Rlp.encodeBytes(Uint8List(1024));
      expect(_hex(encoded.sublist(0, 3)), 'b90400');
      expect(encoded.length, 1024 + 3);
    });
  });

  group('Rlp.encodeList', () {
    test('empty list is 0xc0', () {
      expect(_hex(Rlp.encodeList(const [])), 'c0');
    });

    test('["cat","dog"] is 0xc8 8363617483646f67', () {
      final encoded = Rlp.encodeList([
        Rlp.encodeBytes(utf8.encode('cat')),
        Rlp.encodeBytes(utf8.encode('dog')),
      ]);
      expect(_hex(encoded), 'c88363617483646f67');
    });

    test('set-theoretic nesting [ [], [[]], [ [], [[]] ] ]', () {
      final empty = Rlp.encodeList(const []);
      final encoded = Rlp.encodeList([
        empty,
        Rlp.encodeList([empty]),
        Rlp.encodeList([empty, Rlp.encodeList([empty])]),
      ]);
      expect(_hex(encoded), 'c7c0c1c0c3c0c1c0');
    });

    test('payload > 55 bytes switches to the long header (0xf8)', () {
      final item = Rlp.encodeBytes(List.filled(54, 0x61)); // 55 encoded bytes
      final encoded = Rlp.encodeList([item, Rlp.encodeBytes(const [0x01])]);
      expect(_hex(encoded.sublist(0, 2)), 'f838');
      expect(encoded.length, 58);
    });
  });

  group('Rlp integers', () {
    test('zero encodes as the empty string (0x80)', () {
      expect(Rlp.bigIntBytes(BigInt.zero), isEmpty);
      expect(_hex(Rlp.encodeBigInt(BigInt.zero)), '80');
    });

    test('15 encodes as the single byte 0x0f', () {
      expect(_hex(Rlp.bigIntBytes(BigInt.from(15))), '0f');
      expect(_hex(Rlp.encodeBigInt(BigInt.from(15))), '0f');
    });

    test('1024 encodes as 0x82 0400', () {
      expect(_hex(Rlp.bigIntBytes(BigInt.from(1024))), '0400');
      expect(_hex(Rlp.encodeBigInt(BigInt.from(1024))), '820400');
    });

    test('minimal big-endian bytes have no leading zero', () {
      expect(_hex(Rlp.bigIntBytes(BigInt.from(0x0100))), '0100');
      expect(_hex(Rlp.bigIntBytes(BigInt.parse('ff00000000', radix: 16))),
          'ff00000000');
      expect(Rlp.bigIntBytes((BigInt.one << 256) - BigInt.one).length, 32);
    });

    test('rejects negative scalars', () {
      expect(() => Rlp.bigIntBytes(BigInt.from(-1)), throwsArgumentError);
      expect(() => Rlp.encodeBigInt(BigInt.from(-1)), throwsArgumentError);
    });
  });
}
