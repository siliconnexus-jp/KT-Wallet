import 'dart:typed_data';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:cold_signer/src/signing/sign_record_store.dart';
import 'package:cold_signer/src/signing/sign_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// End-to-end offline-signer safety: a scanned sign-request is validated
/// (walletId / expiry / replay / whitelist), driven through the sign session,
/// and its reqId is committed to the record store BEFORE the result is shown —
/// so the same request can never be signed twice (DD §3.4, §7.3, §13.5).

const _localWallet = 'WLT-LOCAL';

SignRequest _request({String walletId = _localWallet, int expiresAt = 2000}) =>
    SignRequest(
      reqId: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
      walletId: walletId,
      coin: 195,
      rawTx: Uint8List.fromList([0xde, 0xad]),
      createdAt: 1000,
      expiresAt: expiresAt,
    );

Future<CachedSignRecordStore> _store(SignRecordPersistence p) =>
    CachedSignRecordStore.load(p);

Future<void> _recordSigned(
  InMemorySignRecordPersistence persistence,
  SignRequest request,
) async {
  final reserved = SignatureRecord(
    reqId: request.reqIdHex,
    walletId: request.walletId,
    date: 1500,
    coin: 'tron',
    operation: 'tokenTransfer',
    toAddress: 'Tabc',
    amount: '120',
    status: RequestStatus.scanned,
  );
  expect(await persistence.reserve(reserved), isTrue);
  expect(
    await persistence.finalizeReservation(
      SignatureRecord(
        reqId: request.reqIdHex,
        walletId: request.walletId,
        date: 1500,
        coin: 'tron',
        operation: 'tokenTransfer',
        toAddress: 'Tabc',
        amount: '120',
        status: RequestStatus.signed,
      ),
    ),
    isTrue,
  );
}

SignRequestValidator _validator(
  SignRecordStore records, {
  bool allowed = true,
  int now = 1500,
}) => SignRequestValidator(
  localWalletId: _localWallet,
  records: records,
  transactionAllowed: (_) => allowed,
  clock: () => DateTime.fromMillisecondsSinceEpoch(now * 1000),
);

void main() {
  test(
    'first sign: validates, signs, records signed before result shown',
    () async {
      final persistence = InMemorySignRecordPersistence();
      final req = _request();

      final result = _validator(await _store(persistence)).validate(req);
      expect(result.isOk, isTrue);

      final session = SignSession();
      session.dispatch(SignEvent.framesComplete);
      session.dispatch(SignEvent.validationPassed);
      session.dispatch(SignEvent.userConfirm);
      session.dispatch(SignEvent.authOk);

      // Record BEFORE showing the result QR (crash-safety ordering).
      await _recordSigned(persistence, req);
      session.dispatch(SignEvent.signComplete);
      expect(session.state, SignState.resultDisplaying);
    },
  );

  test(
    're-scanning an already-signed request is rejected as duplicate',
    () async {
      final persistence = InMemorySignRecordPersistence();
      final req = _request();
      await _recordSigned(persistence, req);

      final result = _validator(await _store(persistence)).validate(req);
      expect(result.code, ValidationCode.duplicate);
      expect(result.detail, 'signed');
    },
  );

  test(
    'a previously-consumed request stays refused (no second chance)',
    () async {
      final persistence = InMemorySignRecordPersistence();
      final req = _request();
      expect(
        await persistence.reserve(
          SignatureRecord(
            reqId: req.reqIdHex,
            walletId: req.walletId,
            date: 1500,
            coin: 'tron',
            operation: 'unknown',
            toAddress: '',
            amount: '',
            status: RequestStatus.scanned,
          ),
        ),
        isTrue,
      );
      final result = _validator(await _store(persistence)).validate(req);
      expect(result.code, ValidationCode.duplicate);
    },
  );

  test('unsupported transaction never reaches the signed state', () async {
    final persistence = InMemorySignRecordPersistence();
    final req = _request();
    final result = _validator(
      await _store(persistence),
      allowed: false,
    ).validate(req);
    expect(result.code, ValidationCode.unsupportedTransaction);

    // Session mirrors the block. No key operation or anti-replay mutation is
    // necessary because validation failed before signing began.
    final session = SignSession();
    session.dispatch(SignEvent.framesComplete);
    session.dispatch(SignEvent.validationRejected);
    expect(session.state, SignState.riskBlocked);
    expect(await persistence.all(), isEmpty);
  });

  test('a foreign-wallet request is rejected', () async {
    final persistence = InMemorySignRecordPersistence();
    final result = _validator(
      await _store(persistence),
    ).validate(_request(walletId: 'OTHER'));
    expect(result.code, ValidationCode.badWallet);
  });

  test('an expired request is rejected', () async {
    final persistence = InMemorySignRecordPersistence();
    final result = _validator(
      await _store(persistence),
      now: 3000,
    ).validate(_request());
    expect(result.code, ValidationCode.expired);
  });
}
