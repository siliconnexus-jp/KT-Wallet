import 'dart:math';
import 'dart:typed_data';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:test/test.dart';

/// Fuzz decode paths against random and mutated-valid inputs. The invariant
/// (DD §8.6): every decode path throws a typed error or returns — it must never
/// crash the isolate with an unexpected exception type, hang, or OOM.
void main() {
  const rounds = 10000;

  Uint8List randomBytes(Random r, int maxLen) {
    final len = r.nextInt(maxLen);
    return Uint8List.fromList([for (var i = 0; i < len; i++) r.nextInt(256)]);
  }

  void expectSafe(void Function() decode) {
    try {
      decode();
    } on CborError {
      // expected
    } on PayloadError {
      // expected
    } on FragmentError {
      // expected
    } on FormatException {
      // utf8 decode of invalid text — acceptable typed failure
    } catch (e) {
      fail('unexpected exception type: ${e.runtimeType} ($e)');
    }
  }

  test('cborDecode never crashes on random bytes', () {
    final r = Random(1);
    for (var i = 0; i < rounds; i++) {
      final bytes = randomBytes(r, 64);
      expectSafe(() => cborDecode(bytes));
    }
  });

  test('AirgapPayload.decode never crashes on random bytes', () {
    final r = Random(2);
    for (var i = 0; i < rounds; i++) {
      expectSafe(() => AirgapPayload.decode(randomBytes(r, 128)));
    }
  });

  test('AirgapFrame.decode never crashes on random bytes', () {
    final r = Random(3);
    for (var i = 0; i < rounds; i++) {
      expectSafe(() => AirgapFrame.decode(randomBytes(r, 64)));
    }
  });

  test('mutated-valid payloads decode safely', () {
    final r = Random(4);
    final valid = SignRequest(
      reqId: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
      walletId: 'WLT-1',
      coin: 195,
      rawTx: Uint8List.fromList([0xde, 0xad, 0xbe, 0xef]),
      createdAt: 1000,
      expiresAt: 1600,
    ).encode();

    for (var i = 0; i < rounds; i++) {
      final mutated = Uint8List.fromList(valid);
      // Flip 1-3 random bytes.
      final flips = 1 + r.nextInt(3);
      for (var f = 0; f < flips; f++) {
        mutated[r.nextInt(mutated.length)] = r.nextInt(256);
      }
      expectSafe(() => AirgapPayload.decode(mutated));
    }
  });

  test('mutated-valid frames decode safely', () {
    final r = Random(5);
    final frame = Fragmenter(chunkSize: 16)
        .fragment(
          Uint8List.fromList([for (var i = 0; i < 40; i++) i]),
          reqId: Uint8List.fromList([9, 9, 9, 9, 9, 9, 9, 9]),
        )
        .first
        .encode();
    for (var i = 0; i < rounds; i++) {
      final mutated = Uint8List.fromList(frame);
      mutated[r.nextInt(mutated.length)] = r.nextInt(256);
      expectSafe(() => AirgapFrame.decode(mutated));
    }
  });
}
