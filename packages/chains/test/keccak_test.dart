import 'dart:convert';

import 'package:chains/chains.dart';
import 'package:test/test.dart';

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('keccak256 known vectors', () {
    test('empty string', () {
      expect(
        hex(keccak256(const [])),
        'c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470',
      );
    });

    test('"abc"', () {
      expect(
        hex(keccak256(utf8.encode('abc'))),
        '4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45',
      );
    });

    test('longer-than-one-block input (>136 bytes)', () {
      // Reference from pycryptodome keccak-256 of 200×'a' (multi-block absorb).
      expect(
        hex(keccak256(utf8.encode('a' * 200))),
        '96ea54061def936c4be90b518992fdc6f12f535068a256229aca54267b4d084d',
      );
    });

    test('ERC-20 transfer(address,uint256) selector is a9059cbb', () {
      // First 4 bytes of the function-signature hash — validates real EVM use.
      expect(
        hex(keccak256(utf8.encode('transfer(address,uint256)')).sublist(0, 4)),
        'a9059cbb',
      );
    });
  });
}
