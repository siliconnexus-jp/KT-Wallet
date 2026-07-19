import 'dart:typed_data';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('CBOR roundtrip', () {
    test('unsigned ints across head-size boundaries', () {
      for (final v in [0, 23, 24, 255, 256, 65535, 65536, 4294967296]) {
        expect(cborDecode(cborEncode(v)), v, reason: '$v');
      }
    });

    test('text and byte strings', () {
      expect(cborDecode(cborEncode('héllo')), 'héllo');
      final bytes = Uint8List.fromList([0, 1, 2, 253, 254, 255]);
      expect(cborDecode(cborEncode(bytes)), bytes);
    });

    test('arrays and nested maps', () {
      final value = {
        0: 1,
        1: [10, 20, 30],
        2: {0: 'a', 1: 'b'},
      };
      expect(cborDecode(cborEncode(value)), value);
    });

    test('map encoding is deterministic regardless of insertion order', () {
      final a = cborEncode({2: 'x', 0: 'y', 1: 'z'});
      final b = cborEncode({0: 'y', 1: 'z', 2: 'x'});
      expect(a, b);
    });
  });

  group('CBOR decode is strict and total', () {
    test('trailing bytes rejected', () {
      final good = cborEncode(1);
      final withTrailing = Uint8List.fromList([...good, 0x00]);
      expect(() => cborDecode(withTrailing), throwsA(isA<CborError>()));
    });

    test('truncated byte string rejected', () {
      // 0x42 = bytes of length 2, but only one byte follows.
      expect(
        () => cborDecode(Uint8List.fromList([0x42, 0xAA])),
        throwsA(isA<CborError>()),
      );
    });

    test('duplicate map key rejected', () {
      // map(2) { 0:0, 0:1 }
      expect(
        () => cborDecode(Uint8List.fromList([0xA2, 0x00, 0x00, 0x00, 0x01])),
        throwsA(isA<CborError>()),
      );
    });

    test('unsupported major type rejected', () {
      // 0xE0 = major type 7 (simple/float) — unsupported.
      expect(
        () => cborDecode(Uint8List.fromList([0xE0])),
        throwsA(isA<CborError>()),
      );
    });

    test('negative int encode rejected', () {
      expect(() => cborEncode(-1), throwsA(isA<CborError>()));
    });

    test('oversized collection header rejected before allocation', () {
      // array with declared length 0xFFFF but no elements.
      expect(
        () => cborDecode(Uint8List.fromList([0x99, 0xFF, 0xFF])),
        throwsA(isA<CborError>()),
      );
    });

    test('deeply nested arrays are rejected, not stack-overflowed', () {
      // 0x81 = array(1); a long run would recurse once per byte.
      final nested = Uint8List.fromList(List.filled(10000, 0x81));
      expect(() => cborDecode(nested), throwsA(isA<CborError>()));
    });

    test('nesting within the depth limit still decodes', () {
      // 3 levels: array(1) → array(1) → uint 0.
      expect(
        cborDecode(Uint8List.fromList([0x81, 0x81, 0x00])),
        [
          [0]
        ],
      );
    });

    test('8-byte byte-string length cannot overflow the bounds check', () {
      // 0x5B = byte string, 8-byte length 0x7FFF_FFFF_FFFF_FFFF.
      final attack = Uint8List.fromList(
          [0x5B, 0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]);
      expect(() => cborDecode(attack), throwsA(isA<CborError>()));
    });

    test('8-byte text length cannot overflow the bounds check', () {
      // 0x7B = text string, huge 8-byte length.
      final attack = Uint8List.fromList(
          [0x7B, 0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]);
      expect(() => cborDecode(attack), throwsA(isA<CborError>()));
    });
  });
}
