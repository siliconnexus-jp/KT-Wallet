# Review: P3 chains

Module: `packages/chains` (money type, crypto primitives, address validation,
tx preview/ABI, RPC clients).
Reviewer: AI code review (Explore agent) + author reconciliation.
Design refs: detailed-design.md §4, §8.9–8.10.

## Test status

- `dart test` → 62 passing. Crypto primitives validated against authoritative
  references:
  - keccak256 vs pycryptodome (empty / "abc" / 200×'a' multi-block / ERC-20
    selector `a9059cbb`).
  - sha256 vs FIPS 180-4 vectors (empty / "abc" / multi-block / double-sha256).
  - EIP-55 vs the four spec addresses; TRON base58check vs the real USDT-TRON
    address; cross-chain mispaste rejection.
  - ERC-20 transfer calldata byte-exact.
  - RPC parsing/fee logic via recorded-response fixtures.
- `dart analyze` → clean. Firewall (`check_deps`) → OK.
- Fully verifiable in this environment (pure Dart).

## Scope note (native boundary)

The per-chain wallet-core **SigningInput protobuf serialization** is consumed by
the native signer and lands with the P1-4 device signing pass. P3 delivered the
pure, verifiable chain logic that feeds it: address validation, unit/amount
handling, ERC-20 calldata, TxPreview, and the RPC query/broadcast layer.

## Findings & disposition

No blocking issues on the mobile (64-bit AOT) target. Minor findings fixed:

- **EVM `estimateFees` untyped-cast gaps** — FIXED. Malformed `eth_feeHistory`
  (missing/short `baseFeePerGas`/`reward`, short reward row) now throws
  `RpcException` instead of `CastError`/`StateError`/`RangeError`. Regression
  tests added.
- **`_uint256` silently truncated amounts ≥ 2²⁵⁶** — FIXED. Now throws
  `ArgumentError`. Test added.
- **TRON balance masked a malformed field as zero** — FIXED. Absent balance
  still returns 0 (valid fresh account); a present-but-non-int value now throws
  `RpcException`. Test added.
- **Solana `confirmationStatus` unguarded cast** — FIXED. Non-string status
  throws `RpcException`; null returns null.

### Deferred / documented (not fixed)

- **Web-target shift precision in keccak/sha256** — the 32-bit-split shifts
  produce intermediates >2⁵³ before masking, which is exact on the 64-bit VM/AOT
  but would corrupt low bits on the JS/web target. **Flutter web is not a target
  (mobile only, tech-plan.md §1)**, so this is a documented limitation, not a
  fix. If web is ever added, the shift/rotate helpers must be reworked and
  re-vectored before use.
- **Solana/TRON large numeric JSON fields** — parsed as `int` (exact on the
  64-bit VM for all realistic lamport/SUN magnitudes < 2⁶³). Same web caveat.

## Confirmed correct (agent, no violation)

- **Amount**: fully BigInt/string; parse/format/add/sub lossless with explicit
  rejects for over-precision, underflow, scale mismatch. INV-9 satisfied.
- **keccak rotation & padding**: hi/lo split rotations (n<32, ==32, 32<n<64),
  theta/rho-pi/chi/iota indexing, multi-block absorb, 0x01…0x80 padding — all
  correct by static reasoning and vectors.
- **sha256**: no remaining signed-truncation path after the Int32List→List<int>
  fix; all writes masked to [0, 2³²).
- **base58**: total on hostile input (typed `Base58Error`), lossless leading-zero
  roundtrip.
- **address**: EIP-55 nibble selection correct; TRON 25-byte/0x41/double-sha256;
  Solana 32-byte; cross-chain mispaste structurally rejected.
- **broadcast never auto-retried** (double-spend safety): EVM/TRON/Solana each
  POST exactly once and surface failure as `RpcException`.
- **Dependency firewall**: `chains.dart` core does NOT re-export `rpc`; `rpc.dart`
  is a separate entrypoint; no core `src/*` file imports `rpc/`. Offline signer
  can import `chains.dart` without pulling RPC/transport.

## Invariant checklist (DD §8.9–8.10)

| # | Invariant | Status |
|---|-----------|--------|
| 9 | No doubles in money math; BigInt lossless | PASS (core); web caveat documented for RPC int fields |
| 10 | Unsupported = explicit reject | PASS — closed enums, exhaustive switch, uint256 overflow now rejected |

## Gate decision

Auto-continue gate (no user stop per plan). All findings fixed or documented,
62 tests green, analyze + firewall clean. Proceeding to P4 (data layer). The
native SigningInput serialization is tracked with the P1-4 device pass.
