import 'dart:typed_data';

import 'crc32.dart';
import 'fragmenter.dart';

/// Reassembles frames scanned from an animated QR (detailed-design.md §3.3).
///
/// State machine:
///   idle → receiving (first valid frame locks reqId/total)
///   receiving: reqId mismatch → ignored (anomaly counter)
///              duplicate seq → deduped (duplicate counter)
///              all seq present → assembling → done | failed
enum AggregatorState { idle, receiving, done, failed }

enum AggregatorFailure { crcMismatch, oversized }

/// Upper bound on the reassembled payload, mirroring the send-side limit
/// (fragmenter.dart maxPayload). Enforced on receive so a hostile frame set
/// can't force an unbounded allocation (DD §8.7).
const int aggregatorMaxPayload = 64 * 1024;

class AggregatorProgress {
  const AggregatorProgress({
    required this.received,
    required this.total,
    required this.duplicates,
    required this.anomalies,
  });
  final int received;
  final int total;
  final int duplicates;
  final int anomalies;
}

class FrameAggregator {
  AggregatorState _state = AggregatorState.idle;
  Uint8List? _reqId;
  int _total = 0;
  int _crc = 0;
  final Map<int, Uint8List> _chunks = {};
  int _accumulatedBytes = 0;
  int _duplicates = 0;
  int _anomalies = 0;
  Uint8List? _payload;
  AggregatorFailure? _failure;

  AggregatorState get state => _state;
  Uint8List? get payload => _payload;
  AggregatorFailure? get failure => _failure;
  Uint8List? get reqId => _reqId == null ? null : Uint8List.fromList(_reqId!);

  AggregatorProgress get progress => AggregatorProgress(
        received: _chunks.length,
        total: _total,
        duplicates: _duplicates,
        anomalies: _anomalies,
      );

  /// Feeds one parsed frame. Returns the current progress. Frames belonging to
  /// a different reqId than the locked session are ignored (anomaly counted),
  /// never fatal — a stray QR in view must not abort a scan.
  AggregatorProgress addFrame(AirgapFrame frame) {
    if (_state == AggregatorState.done || _state == AggregatorState.failed) {
      return progress;
    }
    if (_state == AggregatorState.idle) {
      _reqId = frame.reqId;
      _total = frame.total;
      _crc = frame.crc;
      _state = AggregatorState.receiving;
    } else {
      if (!_bytesEqual(frame.reqId, _reqId!) ||
          frame.total != _total ||
          frame.crc != _crc) {
        _anomalies++;
        return progress;
      }
    }
    if (_chunks.containsKey(frame.seq)) {
      _duplicates++;
      return progress;
    }
    _chunks[frame.seq] = frame.chunk;
    _accumulatedBytes += frame.chunk.length;
    // Fail closed as soon as the running total exceeds the cap, before the map
    // grows further.
    if (_accumulatedBytes > aggregatorMaxPayload) {
      _failure = AggregatorFailure.oversized;
      _state = AggregatorState.failed;
      return progress;
    }
    if (_chunks.length == _total) {
      _assemble();
    }
    return progress;
  }

  void _assemble() {
    final out = BytesBuilder();
    for (var i = 0; i < _total; i++) {
      final chunk = _chunks[i];
      if (chunk == null) {
        // Should not happen (count == total) but stay defensive.
        _anomalies++;
        return;
      }
      out.add(chunk);
    }
    final payload = out.toBytes();
    if (crc32(payload) != _crc) {
      _failure = AggregatorFailure.crcMismatch;
      _state = AggregatorState.failed;
      return;
    }
    _payload = payload;
    _state = AggregatorState.done;
  }

  /// Resets to idle so the same instance can scan a new request.
  void reset() {
    _state = AggregatorState.idle;
    _reqId = null;
    _total = 0;
    _crc = 0;
    _chunks.clear();
    _accumulatedBytes = 0;
    _duplicates = 0;
    _anomalies = 0;
    _payload = null;
    _failure = null;
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
