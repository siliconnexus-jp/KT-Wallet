import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/transfer/airgap_codec.dart';
import 'package:kt_wallet/src/transfer/frame_scan.dart';

/// The scanned-string plumbing behind the live camera screens, unit-level (no
/// plugin): every QR string a camera would hand over is one base64url
/// AIRGAP-V1 frame, and feeding them advances the real aggregator.
void main() {
  SignRequest request() =>
      buildSignRequest(walletId: demoWalletId, fromAddress: demoFromAddress);

  test('feeding valid frame strings advances the aggregator to done', () {
    final req = request();
    final frames = encodeQrFrames(req, reqId: req.reqId);
    expect(
      frames.length,
      greaterThan(1),
      reason: 'demo payload must span frames',
    );

    final session = QrFrameScanSession();
    for (final (i, frame) in frames.indexed) {
      final progress = session.add(frame);
      expect(progress.received, i + 1);
      expect(progress.total, frames.length);
    }
    expect(session.isDone, isTrue);
    expect(session.anomalies, 0);

    // The assembled payload is the request, byte-for-byte.
    final decoded = AirgapPayload.decode(session.payload!);
    expect(decoded, isA<SignRequest>());
    expect((decoded as SignRequest).reqIdHex, req.reqIdHex);
  });

  test('invalid strings count silently as anomalies and never abort', () {
    final req = request();
    final frames = encodeQrFrames(req, reqId: req.reqId);
    final session = QrFrameScanSession();

    session.add('definitely not base64url protocol traffic 🙂');
    session.add(''); // empty read
    expect(session.anomalies, 2);
    expect(session.progress.received, 0);

    for (final frame in frames) {
      session.add(frame);
      session.add('more garbage between frames');
    }
    expect(session.isDone, isTrue);
    expect(session.anomalies, greaterThanOrEqualTo(2));
  });

  test('duplicate consecutive frames do not double-count progress', () {
    final req = request();
    final frames = encodeQrFrames(req, reqId: req.reqId);
    final session = QrFrameScanSession();
    session.add(frames.first);
    session.add(frames.first); // camera re-read of the same displayed frame
    expect(session.progress.received, 1);
    expect(session.progress.duplicates, 1);
  });

  test('scanned sign-result frames verify against the outstanding request', () {
    final req = request();
    final result = buildDemoSignResult(req, signer: demoFromAddress);
    final session = QrFrameScanSession();
    for (final frame in encodeQrFrames(result, reqId: req.reqId)) {
      session.add(frame);
    }
    expect(session.isDone, isTrue);

    final verified = verifySignResultPayload(session.payload!, expected: req);
    expect(verified.reqIdHex, req.reqIdHex);
    expect(verified.walletId, req.walletId);

    // A result answering a different request is rejected.
    final other = buildSignRequest(
      walletId: demoWalletId,
      fromAddress: demoFromAddress,
      reqId: randomReqId(),
    );
    expect(
      () => verifySignResultPayload(session.payload!, expected: other),
      throwsStateError,
    );
  });

  test('reset starts a fresh session', () {
    final req = request();
    final frames = encodeQrFrames(req, reqId: req.reqId);
    final session = QrFrameScanSession()
      ..add('junk')
      ..add(frames.first)
      ..reset();
    expect(session.progress.received, 0);
    expect(session.anomalies, 0);
  });
}
