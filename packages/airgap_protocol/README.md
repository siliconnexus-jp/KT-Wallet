# airgap_protocol

Versioned binary protocol used between KT Wallet and KT Cold Signer. It
encodes account exports, unsigned signing requests, and signed results as
bounded CBOR payloads, then fragments them into CRC-protected animated-QR
frames.

## Public API

- `AccountExport`, `SignRequest`, and `SignResult` are the three protocol
  payloads.
- `Fragmenter` converts one payload into bounded `AirgapFrame` values.
- `FrameAggregator` rejects mixed sessions, duplicates, CRC failures, and
  oversized input while reporting deterministic progress.
- `SignRequestValidator` provides expiry, replay, wallet binding, and
  transaction-policy hooks.

The decoder rejects unknown CBOR fields, payloads larger than 64 KiB,
individual wire frames larger than the protocol maximum, and QR text that
cannot fit a legal frame. `Fragmenter` also validates its chunk size at runtime
so Release builds enforce the same limits as tests.

```dart
import 'dart:typed_data';
import 'package:airgap_protocol/airgap_protocol.dart';

final request = SignRequest(
  reqId: Uint8List(8),
  walletId: 'wallet-1',
  coin: 60,
  rawTx: Uint8List.fromList([1, 2, 3]),
  createdAt: 1_900_000_000,
  expiresAt: 1_900_000_060,
);
final frames = Fragmenter(chunkSize: 120).fragment(
  request.encode(),
  reqId: request.reqId,
);
final aggregator = FrameAggregator();
for (final frame in frames) {
  aggregator.addFrame(AirgapFrame.decode(frame.encode()));
}
final decoded = AirgapPayload.decode(aggregator.payload!) as SignRequest;
```

## Security boundary

This package authenticates framing and enforces protocol limits; it does not
make an unsigned transaction safe. Callers must parse `rawTx`, derive every
displayed field from those bytes, bind the sender to the paired public key,
and cryptographically verify the returned signed transaction before broadcast.
The optional human-readable `summary` is untrusted. Production replay
protection must atomically reserve a request ID in durable storage before the
native key operation; `InMemorySignRecordStore` is suitable only for tests.

Run `dart test` from this package directory. Protocol changes require backward
compatibility vectors and must not silently reinterpret an existing version.

Licensed under MPL-2.0; see `LICENSE`.
