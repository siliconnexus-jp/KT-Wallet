import 'dart:typed_data';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:test/test.dart';

Uint8List _reqId() => Uint8List.fromList([9, 9, 9, 9, 9, 9, 9, 9]);
Uint8List _payload(int n) =>
    Uint8List.fromList([for (var i = 0; i < n; i++) i % 256]);

void main() {
  group('Fragmenter', () {
    test('chunk size is runtime-bounded in release builds', () {
      expect(() => Fragmenter(chunkSize: 0), throwsA(isA<FragmentError>()));
      expect(() => Fragmenter(chunkSize: -1), throwsA(isA<FragmentError>()));
      expect(
        () => Fragmenter(chunkSize: AirgapFrame.maxChunkLength + 1),
        throwsA(isA<FragmentError>()),
      );
    });

    test('total frame count is ceil(payload / chunkSize)', () {
      final f = Fragmenter(chunkSize: 100);
      expect(f.fragment(_payload(100), reqId: _reqId()), hasLength(1));
      expect(f.fragment(_payload(101), reqId: _reqId()), hasLength(2));
      expect(f.fragment(_payload(250), reqId: _reqId()), hasLength(3));
    });

    test('empty payload yields a single frame', () {
      final frames = Fragmenter().fragment(Uint8List(0), reqId: _reqId());
      expect(frames, hasLength(1));
      expect(frames.first.total, 1);
    });

    test('every frame carries reqId, total and identical crc', () {
      final frames = Fragmenter(
        chunkSize: 50,
      ).fragment(_payload(140), reqId: _reqId());
      final crc = frames.first.crc;
      for (var i = 0; i < frames.length; i++) {
        expect(frames[i].seq, i);
        expect(frames[i].total, frames.length);
        expect(frames[i].crc, crc);
        expect(frames[i].reqId, _reqId());
      }
    });

    test('frame header byte layout is exact', () {
      final frame = Fragmenter(
        chunkSize: 4,
      ).fragment(_payload(4), reqId: _reqId()).first;
      final bytes = frame.encode();
      expect(bytes[0], AirgapFrame.magic0);
      expect(bytes[1], AirgapFrame.magic1);
      expect(bytes[2], AirgapFrame.version);
      expect(bytes.sublist(3, 11), _reqId());
      expect(bytes.length, AirgapFrame.headerLength + 4);
    });

    test('reqId must be 8 bytes', () {
      expect(
        () => Fragmenter().fragment(_payload(1), reqId: Uint8List(4)),
        throwsA(isA<FragmentError>()),
      );
    });

    test('payload over 64KB rejected', () {
      expect(
        () => Fragmenter().fragment(_payload(64 * 1024 + 1), reqId: _reqId()),
        throwsA(isA<FragmentError>()),
      );
    });

    test('too many frames (>256) rejected', () {
      expect(
        () => Fragmenter(chunkSize: 1).fragment(_payload(300), reqId: _reqId()),
        throwsA(isA<FragmentError>()),
      );
    });
  });

  group('AirgapFrame.decode is total', () {
    test('roundtrips a valid frame', () {
      final frame = Fragmenter(
        chunkSize: 10,
      ).fragment(_payload(25), reqId: _reqId())[1];
      final decoded = AirgapFrame.decode(frame.encode());
      expect(decoded.seq, 1);
      expect(decoded.chunk, frame.chunk);
    });

    test('bad magic rejected', () {
      final bytes = Uint8List(AirgapFrame.headerLength + 1)..[0] = 0x00;
      expect(() => AirgapFrame.decode(bytes), throwsA(isA<FragmentError>()));
    });

    test('short frame rejected', () {
      expect(
        () => AirgapFrame.decode(Uint8List.fromList([0x4B, 0x54, 0x01])),
        throwsA(isA<FragmentError>()),
      );
    });

    test('oversized individual frame is rejected before chunk allocation', () {
      expect(
        () => AirgapFrame.decode(Uint8List(AirgapFrame.maxWireLength + 1)),
        throwsA(isA<FragmentError>()),
      );
    });

    test('seq >= total rejected', () {
      final frame = AirgapFrame(
        reqId: _reqId(),
        seq: 5,
        total: 3,
        crc: 0,
        chunk: Uint8List(1),
      );
      expect(
        () => AirgapFrame.decode(frame.encode()),
        throwsA(isA<FragmentError>()),
      );
    });
  });
}
