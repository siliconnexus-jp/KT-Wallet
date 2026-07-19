# Review: P2 airgap_protocol

Module: `packages/airgap_protocol` (AIRGAP-V1 animated-QR transport).
Reviewer: AI code review (Explore agent) + author reconciliation.
Design refs: detailed-design.md §3, §8.6–8.8.

## Test status

- `dart test` → 59 passing (CBOR roundtrip + strictness, payload schema bounds,
  fragmenter chunk math + frame layout, aggregator state machine, six-step
  validator, 10k-round fuzz + targeted adversarial vectors).
- `dart analyze` → clean.
- Runs fully in this environment (pure Dart, no native/device dependency).

## Findings & disposition

All five review findings are FIXED with regression tests. (The agent reviewed a
snapshot before the depth-guard commit, so it re-reported #1 as open; it was
already fixed and is confirmed below.)

### Blocking

1. **CBOR decoder had no recursion depth guard (stack overflow / untyped
   Error)** — FIXED. `_Decoder` now enforces `_maxDepth = 16` via a `_nested`
   wrapper around array/map decoding; a run of nested-array bytes throws
   `CborError('nesting too deep')` instead of `StackOverflowError`. Tests:
   `cbor_test.dart` "deeply nested arrays are rejected" (10k frames) and
   "nesting within the depth limit still decodes".

2. **8-byte length header overflowed the byte-string bounds check** — FIXED.
   `_readBytes` now compares `len > bytes.length - offset` (never the
   overflow-prone `offset + len`), so a header like `0x5B 0x7FFF…FF` throws
   `CborError` instead of an untyped `RangeError`. Tests added for both byte
   (`0x5B`) and text (`0x7B`) 8-byte-length attacks.

### Minor

3. **Payload ≤64KB not enforced on the receive path** — FIXED. `FrameAggregator`
   tracks a running `_accumulatedBytes` and fails closed
   (`AggregatorFailure.oversized`) the moment chunks exceed
   `aggregatorMaxPayload = 64KB`, independent of the send-side guard. Test:
   "reassembled payload over 64KB fails closed".

4. **Text field limits were counted in UTF-16 code units, not on-wire bytes** —
   FIXED. `_text` now checks `utf8.encode(v).length` against the cap, so
   multibyte characters can't slip a field past its limit. Test: "length limits
   are UTF-8 bytes, not code units".

5. **Validator read the record store twice for the duplicate branch** — FIXED.
   `validate` now caches the single `statusFor` result (safe for a future
   async/mutable store).

## Confirmed correct (agent, no violation)

- **INV-8 — summary is display-only**: `summary` is round-tripped but never read
  as a signing input; the validator explicitly documents that display uses the
  parse result, not `summary`.
- **Validator six-step order (DD §3.4)**: wallet → expiry/clock-skew → duplicate
  → transaction-allowed, each failing closed with early return; no fail-open.
- **crc32**: correct reflected IEEE-802.3 (init/poly/final-XOR/mask), big-endian
  byte order consistent between frame encode and decode.
- **Fragmenter chunk math**: correct for empty payload, exact multiples, and
  general case; >256 frames, bad reqId length, >64KB all rejected on send.
- **Aggregator state machine**: duplicate dedup, reqId/total/crc mismatch as
  non-fatal anomaly, CRC mismatch → failed, terminal states frozen, reset clears
  all fields.
- **AirgapFrame.decode**: total and bounded (magic, version, total range,
  seq<total), fixed-offset reads.

## Invariant checklist (DD §8.6–8.8)

| # | Invariant | Status |
|---|-----------|--------|
| 6 | All decode paths total (typed error / return, never crash/hang/OOM) | PASS — depth guard + overflow fix + 10k fuzz |
| 7 | All size/count limits have a rejecting branch (send AND receive) | PASS — receive-side 64KB + UTF-8 byte limits added |
| 8 | summary is display-only, never authoritative | PASS |

## Gate decision

All findings fixed, regression tests added, suite green (59), analyze clean.
No deferred items — this module is pure Dart and fully verifiable here. **P2
stops here for user confirmation** (per plan) before P3. Recommended: proceed to
P3 (chains). Field calibration of the chunk size / animation speed is a P7
task and does not block P3.
