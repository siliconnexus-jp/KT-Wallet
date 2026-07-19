# Review: P6 kt_wallet (online app logic)

Module: `apps/kt_wallet` business logic (wallet model + manager, LocalSignFlow,
AirgapFlow, transfer validation).
Reviewer: AI code review (Explore agent) + author reconciliation.
Design refs: detailed-design.md §6.3, §8.14–8.16.

## Test status

- `flutter test` → 37 passing (wallet manager + cap + switching, type-level
  sign isolation, both transfer flow full transition tables via the harness,
  transfer validation incl. wrong-network detection, dust boundary, decimals
  guards, maxNative).
- `dart analyze` → clean. Firewall → OK.
- Verifiable here (pure Dart; UI screens are presentation, out of scope).

## Invariant verdicts (agent)

- **INV-14 (watch wallets cannot sign) — PASS.** Sealed `Wallet` base exposes
  no signing method; only `HotWallet.sign()` reaches `crypto.signTransaction`;
  `WatchWallet` has no method/getter/field that could reach it — signing on a
  watch wallet is a compile-time impossibility. `canSignLocally` matches.
- **INV-15 (broadcast never auto-retried) — PASS (both flows).** `broadcasting`
  only goes to `done`/`failed`; local retry is an explicit `failed→confirming`
  (rebuild), airgap `failed` is terminal (restart). No auto-loop; cancel/expire
  cannot fire during an in-flight broadcast.
- Both transition tables total; every illegal (state,event) pair throws; full
  cross-product covered by the harness tests.

## Findings & disposition (all minor)

- **Dust check convoluted + no decimals guard** — FIXED. Replaced
  `amount <= threshold && amount.raw != threshold.raw` with a `_requireSameScale`
  guard + `amount.raw < threshold.raw`. Boundary confirmed by test (below = dust,
  exactly-at = allowed); mismatched decimals now throw instead of misclassifying.
- **Token branch missing decimals guard** — FIXED. `amount` vs `tokenBalance`
  now guarded by `_requireSameScale`.
- **`maxNative` no decimals/symbol guard** — FIXED. `_requireSameScale(balance,
  maxFee)` added; still never returns negative.
- **`reorder` accepted a subset / mutated partially on a bad id** — FIXED. Now
  requires an exact permutation of the current wallet ids, validated up front;
  a subset or unknown id is rejected before any mutation (all-or-nothing). Test
  asserts order is unchanged after a rejected reorder.
- **Airgap `failed` has no retry (asymmetry with local)** — kept BY DESIGN. A
  failed air-gap broadcast restarts the flow rather than re-broadcasting; this
  is the conservative choice and still satisfies INV-15. Documented, not changed.

## Confirmed clean (agent)

- Native transfer requires both `amount ≤ balance` AND `amount + maxFee ≤
  balance`; token transfer checks token balance and native fee separately.
- wrong-network vs invalid-address distinction correct.
- 20-wallet cap, duplicate-id rejection, current-wallet fallback on remove (no
  dangling currentId), markBackedUp-on-watch throws — all correct.
- No `double` in money math anywhere; all `Amount`/`BigInt`.

## Invariant checklist (DD §8.14–8.16)

| # | Invariant | Status |
|---|-----------|--------|
| 14 | Watch wallets cannot local-sign (type-level) | PASS |
| 15 | Broadcast never auto-retried | PASS |
| 16 | Mnemonic pages clear memory / FLAG_SECURE | UI-layer, deferred to screen impl + P8 |

## Gate decision

Auto-continue gate. No blocking findings; all minor items fixed or documented.
37 tests green, analyze + firewall clean. Proceeding to P7 (integration).
The KT Wallet UI screens (W1–W30) and Riverpod/go_router wiring are presentation
work layered on this reviewed logic; the multi-wallet + transfer decision logic
is complete and tested.
