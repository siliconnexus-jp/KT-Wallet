import 'dart:math';
import 'dart:typed_data';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:test/test.dart';

Uint8List _reqId([int seed = 7]) =>
    Uint8List.fromList(List.filled(8, seed));
Uint8List _payload(int n) =>
    Uint8List.fromList([for (var i = 0; i < n; i++) (i * 7) % 256]);

void main() {
  final fragmenter = Fragmenter(chunkSize: 20);

  group('FrameAggregator happy path', () {
    test('reassembles frames received in order', () {
      final payload = _payload(85);
      final frames = fragmenter.fragment(payload, reqId: _reqId());
      final agg = FrameAggregator();
      for (final f in frames) {
        agg.addFrame(f);
      }
      expect(agg.state, AggregatorState.done);
      expect(agg.payload, payload);
    });

    test('reassembles frames received out of order', () {
      final payload = _payload(85);
      final frames = fragmenter.fragment(payload, reqId: _reqId())
        ..shuffle(Random(42)); // seeded → deterministic
      final agg = FrameAggregator();
      for (final f in frames) {
        agg.addFrame(f);
      }
      expect(agg.state, AggregatorState.done);
      expect(agg.payload, payload);
    });
  });

  group('FrameAggregator counters', () {
    test('duplicate frames are deduped and counted', () {
      final frames = fragmenter.fragment(_payload(45), reqId: _reqId());
      final agg = FrameAggregator();
      agg.addFrame(frames[0]);
      agg.addFrame(frames[0]); // duplicate
      final progress = agg.addFrame(frames[0]); // duplicate
      expect(progress.received, 1);
      expect(progress.duplicates, 2);
      expect(agg.state, AggregatorState.receiving);
    });

    test('frames from another reqId are ignored as anomalies', () {
      final frames = fragmenter.fragment(_payload(45), reqId: _reqId());
      final other = fragmenter.fragment(_payload(45), reqId: _reqId(3));
      final agg = FrameAggregator();
      agg.addFrame(frames[0]);
      final progress = agg.addFrame(other[1]); // stray QR in view
      expect(progress.anomalies, 1);
      expect(progress.received, 1);
      expect(agg.reqId, _reqId());
    });
  });

  group('FrameAggregator failure paths', () {
    test('crc mismatch on reassembly fails closed', () {
      final payload = _payload(45);
      final frames = fragmenter.fragment(payload, reqId: _reqId());
      // Corrupt one chunk while keeping seq/total/crc header intact.
      final tampered = AirgapFrame(
        reqId: frames[1].reqId,
        seq: frames[1].seq,
        total: frames[1].total,
        crc: frames[1].crc,
        chunk: Uint8List.fromList(
            frames[1].chunk.map((b) => (b + 1) & 0xFF).toList()),
      );
      final agg = FrameAggregator();
      agg.addFrame(frames[0]);
      agg.addFrame(tampered);
      agg.addFrame(frames[2]);
      expect(agg.state, AggregatorState.failed);
      expect(agg.failure, AggregatorFailure.crcMismatch);
      expect(agg.payload, isNull);
    });

    test('reset returns to idle and allows a fresh scan', () {
      final frames = fragmenter.fragment(_payload(45), reqId: _reqId());
      final agg = FrameAggregator();
      for (final f in frames) {
        agg.addFrame(f);
      }
      expect(agg.state, AggregatorState.done);
      agg.reset();
      expect(agg.state, AggregatorState.idle);
      expect(agg.progress.received, 0);

      final frames2 = fragmenter.fragment(_payload(30), reqId: _reqId(5));
      for (final f in frames2) {
        agg.addFrame(f);
      }
      expect(agg.state, AggregatorState.done);
    });

    test('reassembled payload over 64KB fails closed (oversized)', () {
      // 200 frames × ~400B chunk each header-claims total=200 but sums >64KB.
      // Build frames manually so we can push total chunk bytes past the cap
      // without the send-side guard rejecting first.
      final reqId = _reqId();
      const total = 200;
      final crc = 0; // irrelevant; oversize trips before CRC.
      final agg = FrameAggregator();
      AggregatorState? finalState;
      for (var seq = 0; seq < total; seq++) {
        final frame = AirgapFrame(
          reqId: reqId,
          seq: seq,
          total: total,
          crc: crc,
          chunk: Uint8List(400),
        );
        agg.addFrame(frame);
        finalState = agg.state;
        if (finalState == AggregatorState.failed) break;
      }
      expect(finalState, AggregatorState.failed);
      expect(agg.failure, AggregatorFailure.oversized);
    });

    test('frames after done are ignored', () {
      final frames = fragmenter.fragment(_payload(20), reqId: _reqId());
      final agg = FrameAggregator();
      for (final f in frames) {
        agg.addFrame(f);
      }
      final before = agg.progress.received;
      agg.addFrame(frames[0]);
      expect(agg.progress.received, before);
      expect(agg.state, AggregatorState.done);
    });
  });
}
