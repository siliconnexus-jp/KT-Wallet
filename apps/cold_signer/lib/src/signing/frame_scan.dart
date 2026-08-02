import 'dart:convert';
import 'dart:typed_data';

import 'package:airgap_protocol/airgap_protocol.dart';

/// Ingests raw QR strings from a camera (real or simulated feed): each string
/// is expected to be one base64url-encoded AIRGAP-V1 wire frame, exactly what
/// kt_wallet's animated sign-request QR emits per frame.
///
/// Pure Dart (no plugin, no widgets) so the scanned-string plumbing is
/// unit-testable without a camera. Strings that don't decode to a frame are
/// counted silently as anomalies — a stray QR in view must not abort a scan
/// (same policy as the aggregator's reqId-mismatch handling).
class QrFrameScanSession {
  final FrameAggregator aggregator = FrameAggregator();
  int _undecodable = 0;

  /// Rejected inputs so far: undecodable strings plus frames the aggregator
  /// itself ignored (foreign reqId / mismatched header).
  int get anomalies => _undecodable + aggregator.progress.anomalies;

  AggregatorProgress get progress => aggregator.progress;
  bool get isDone => aggregator.state == AggregatorState.done;
  bool get isFailed => aggregator.state == AggregatorState.failed;
  Uint8List? get payload => aggregator.payload;

  /// Feeds one scanned string; returns the aggregation progress afterwards.
  AggregatorProgress add(String raw) {
    if (isDone || isFailed) return aggregator.progress;
    if (raw.length > AirgapFrame.maxQrTextLength) {
      _undecodable++;
      return aggregator.progress;
    }
    final AirgapFrame frame;
    try {
      frame = AirgapFrame.decode(base64Url.decode(raw));
    } catch (_) {
      _undecodable++; // Not protocol traffic: count silently, keep scanning.
      return aggregator.progress;
    }
    return aggregator.addFrame(frame);
  }

  /// Starts a fresh session (e.g. after a payload that failed verification).
  void reset() {
    aggregator.reset();
    _undecodable = 0;
  }
}
