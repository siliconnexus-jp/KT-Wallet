import 'dart:convert';

import 'package:chains/chains.dart';
import 'package:test/test.dart';

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('sha256 known vectors (FIPS 180-4)', () {
    test('empty', () {
      expect(
        _hex(sha256(const [])),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('"abc"', () {
      expect(
        _hex(sha256(utf8.encode('abc'))),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('multi-block (896-bit message)', () {
      final msg = 'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq';
      expect(
        _hex(sha256(utf8.encode(msg))),
        '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
      );
    });

    test('double-sha256 (used for Base58Check)', () {
      // sha256(sha256("")) — sanity for the checksum construction.
      final once = sha256(const []);
      expect(
        _hex(sha256(once)),
        '5df6e0e2761359d30a8275058e299fcc0381534545f55cf43e41983f5d4c9456',
      );
    });
  });
}
