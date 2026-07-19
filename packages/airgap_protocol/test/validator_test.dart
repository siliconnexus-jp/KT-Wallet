import 'dart:typed_data';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:test/test.dart';

Uint8List _reqId() => Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);

SignRequest _request({
  String walletId = 'WLT-1',
  int created = 1000,
  int expires = 1600,
}) =>
    SignRequest(
      reqId: _reqId(),
      walletId: walletId,
      coin: 195,
      rawTx: Uint8List.fromList([0xde, 0xad]),
      createdAt: created,
      expiresAt: expires,
    );

SignRequestValidator _validator({
  SignRecordStore? records,
  bool allowed = true,
  int nowSec = 1200,
}) =>
    SignRequestValidator(
      localWalletId: 'WLT-1',
      records: records ?? InMemorySignRecordStore(),
      transactionAllowed: (_) => allowed,
      clock: () => DateTime.fromMillisecondsSinceEpoch(nowSec * 1000),
    );

void main() {
  group('six-step acceptance (DD §3.4)', () {
    test('accepts a well-formed, in-window, novel, allowed request', () {
      expect(_validator().validate(_request()).code, ValidationCode.ok);
    });

    test('step 2: wrong wallet id rejected', () {
      final result = _validator().validate(_request(walletId: 'OTHER'));
      expect(result.code, ValidationCode.badWallet);
    });

    test('step 3: expired request rejected', () {
      final result = _validator(nowSec: 1600).validate(_request());
      expect(result.code, ValidationCode.expired);
    });

    test('step 3: createdAt beyond clock skew rejected', () {
      // now=1200, created=2000 → 2000 - 600 > 1200.
      final result =
          _validator(nowSec: 1200).validate(_request(created: 2000, expires: 2100));
      expect(result.code, ValidationCode.clockSkew);
    });

    test('step 3: createdAt within skew accepted', () {
      // now=1200, created=1700 → 1700 - 600 == 1100 <= 1200.
      final result =
          _validator(nowSec: 1200).validate(_request(created: 1700, expires: 2000));
      expect(result.code, ValidationCode.ok);
    });

    test('step 4: duplicate reqId rejected for every prior status', () {
      for (final status in RequestStatus.values) {
        final store = InMemorySignRecordStore()
          ..put('0102030405060708', status);
        final result = _validator(records: store).validate(_request());
        expect(result.code, ValidationCode.duplicate, reason: status.name);
        expect(result.detail, status.name);
      }
    });

    test('step 6: unsupported transaction type rejected', () {
      final result = _validator(allowed: false).validate(_request());
      expect(result.code, ValidationCode.unsupportedTransaction);
    });
  });
}
