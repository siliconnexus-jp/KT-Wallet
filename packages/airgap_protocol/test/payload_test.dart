import 'dart:typed_data';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:test/test.dart';

Uint8List _reqId() => Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);

void main() {
  group('AccountExport', () {
    test('roundtrips', () {
      final payload = AccountExport(
        walletId: 'WLT-3E8A91',
        walletName: '主钱包',
        accounts: [
          AccountRecord(
              coin: 60, address: '0xabc', path: "m/44'/60'/0'/0/0", index: 0),
          AccountRecord(
              coin: 195, address: 'Tabc', path: "m/44'/195'/0'/0/0", index: 0),
        ],
      );
      final decoded = AirgapPayload.decode(payload.encode()) as AccountExport;
      expect(decoded.walletId, 'WLT-3E8A91');
      expect(decoded.accounts, hasLength(2));
      expect(decoded.accounts[1].coin, 195);
    });

    test('accounts count bounds enforced (1..8)', () {
      AccountRecord rec(int i) =>
          AccountRecord(coin: i, address: 'a', path: 'p', index: i);
      expect(
        () => AccountExport(walletId: 'w', walletName: 'n', accounts: []),
        throwsA(isA<PayloadError>()),
      );
      expect(
        () => AccountExport(
            walletId: 'w',
            walletName: 'n',
            accounts: [for (var i = 0; i < 9; i++) rec(i)]),
        throwsA(isA<PayloadError>()),
      );
    });

    test('length limits are UTF-8 bytes, not code units', () {
      // 22 × 'é' = 22 code units but 44 UTF-8 bytes → exceeds a 32-byte cap.
      final bytes = cborEncode({
        0: 1,
        1: 1,
        2: 'é' * 22,
        3: 'n',
        4: [
          {0: 60, 1: 'a', 2: 'p', 3: 0}
        ],
      });
      expect(() => AirgapPayload.decode(bytes), throwsA(isA<PayloadError>()));
    });

    test('oversized walletId rejected on decode', () {
      final bytes = cborEncode({
        0: 1,
        1: 1,
        2: 'x' * 33,
        3: 'n',
        4: [
          {0: 60, 1: 'a', 2: 'p', 3: 0}
        ],
      });
      expect(() => AirgapPayload.decode(bytes), throwsA(isA<PayloadError>()));
    });
  });

  group('SignRequest', () {
    SignRequest build({int created = 1000, int expires = 1600}) => SignRequest(
          reqId: _reqId(),
          walletId: 'WLT-3E8A91',
          coin: 195,
          rawTx: Uint8List.fromList([0xde, 0xad]),
          summary: {0: 'to', 1: '120'},
          createdAt: created,
          expiresAt: expires,
        );

    test('roundtrips and exposes reqIdHex', () {
      final decoded = AirgapPayload.decode(build().encode()) as SignRequest;
      expect(decoded.reqIdHex, '0102030405060708');
      expect(decoded.coin, 195);
      expect(decoded.summary, isNotNull);
    });

    test('reqId must be 8 bytes', () {
      expect(
        () => SignRequest(
          reqId: Uint8List.fromList([1, 2, 3]),
          walletId: 'w',
          coin: 60,
          rawTx: Uint8List(1),
          createdAt: 0,
          expiresAt: 10,
        ),
        throwsA(isA<PayloadError>()),
      );
    });

    test('expiry window over one hour rejected', () {
      expect(
        () => build(created: 0, expires: 3601),
        throwsA(isA<PayloadError>()),
      );
    });

    test('expiresAt before createdAt rejected', () {
      expect(() => build(created: 100, expires: 50),
          throwsA(isA<PayloadError>()));
    });

    test('rawTx over 32KB rejected', () {
      expect(
        () => SignRequest(
          reqId: _reqId(),
          walletId: 'w',
          coin: 60,
          rawTx: Uint8List(32 * 1024 + 1),
          createdAt: 0,
          expiresAt: 10,
        ),
        throwsA(isA<PayloadError>()),
      );
    });
  });

  group('SignResult', () {
    test('roundtrips', () {
      final payload = SignResult(
        reqId: _reqId(),
        walletId: 'w',
        coin: 501,
        signedTx: Uint8List.fromList([1, 2, 3]),
        signer: '0xsigner',
        txHash: '0xhash',
      );
      final decoded = AirgapPayload.decode(payload.encode()) as SignResult;
      expect(decoded.txHash, '0xhash');
      expect(decoded.signedTx, [1, 2, 3]);
    });
  });

  group('version and type gating', () {
    test('unknown version rejected', () {
      final bytes = cborEncode({0: 2, 1: 1});
      expect(() => AirgapPayload.decode(bytes), throwsA(isA<PayloadError>()));
    });

    test('unknown type rejected', () {
      final bytes = cborEncode({0: 1, 1: 99});
      expect(() => AirgapPayload.decode(bytes), throwsA(isA<PayloadError>()));
    });

    test('non-map root rejected', () {
      expect(() => AirgapPayload.decode(cborEncode(42)),
          throwsA(isA<PayloadError>()));
    });

    test('malformed CBOR surfaces as PayloadError', () {
      expect(
        () => AirgapPayload.decode(Uint8List.fromList([0x42, 0x00])),
        throwsA(isA<PayloadError>()),
      );
    });
  });
}
