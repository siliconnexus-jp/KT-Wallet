# Review: P5 cold_signer (offline signer logic)

Module: `apps/cold_signer` business logic (security check engine, sign session
state machine, onboarding flow, mnemonic quiz, sign-record store + anti-replay).
Reviewer: AI code review (Explore agent) + author reconciliation.
Design refs: detailed-design.md §7.2, §7.3, §3.4, §13.4, §13.5.

## Test status

- `flutter test` → 31 passing (security matrix, sign-session full transition
  table via the harness, onboarding create/import navigation, mnemonic quiz,
  end-to-end anti-replay integration).
- `dart analyze` → clean. Dependency firewall → OK (test_support is dev-only).
- Verifiable here (pure Dart logic; UI screens are the presentation layer, out
  of scope for this logic review).

## Findings & disposition

No blocking issues — all core invariants (INV-12 gating, INV-13 anti-replay)
held as specified. The minor robustness findings were addressed:

1. **Only `validationUnsupported` routed to block** — FIXED. Renamed to a
   general `validationRejected` event, so ANY non-ok validation result
   (duplicate / expired / foreign-wallet / clock-skew / unsupported) routes to
   `riskBlocked`. The caller must fire `validationPassed` only for
   `ValidationCode.ok`. Removes the mapping-coupling risk.

2. **`signed` was not recorded → crash-after-auth left the reqId re-signable** —
   FIXED. Split the state metadata into `signRecordStatus` (what to persist at
   each state) and `signTerminalStates` (no outgoing transition). `signed` now
   carries a `'signed'` record status, so the reqId is persisted the instant
   authentication succeeds — a crash before the result QR is shown cannot leave
   the request re-signable (DD §13.5). New test pins it.

3. **rooted/jailbroken was WARN** — FIXED (security hardening). A rooted/
   jailbroken device is a full compromise of the key holder; it is now a
   `block` that makes `canSign` false (ui-m.md §9.2 "禁止签名"). New test pins it.

4. **Quiz distractors not validated** — FIXED. `MnemonicQuiz.build` now rejects
   a `distractorsFor` that returns the wrong count or duplicates (in addition to
   the existing correct-word-in-distractors and duplicate-position guards).

5. **Onboarding step-completion not enforced by the controller** — DOCUMENTED
   (by design). The controller governs navigation only; the UI gates step
   completion (quiz passed, valid password) before dispatching `next`. Clarified
   in a doc comment. The controller already forbids skipping ahead.

6. **CachedSignRecordStore snapshot staleness (TOCTOU)** — DOCUMENTED. The Cold
   Signer is single-user/single-session, so no concurrent session can record a
   reqId mid-scan; a doc comment states the assumption and the reload rule if it
   ever changes.

## Confirmed correct (agent, no violation)

- INV-12: network / missing passcode / screen capture → block; block-dominance
  in `overall`/`canSign` correct.
- INV-13: no path from `scanning` to `signed`/`resultDisplaying` skips
  `validating`+`reviewing`; terminal→record mapping correct; every unlisted
  (state,event) pair throws `IllegalSignTransition`.
- `SignatureRecord` holds only non-sensitive fields (no key/mnemonic/seed).
- `skipBiometric` cannot bypass `setPassword` (password step precedes biometric
  in both modes).

## Invariant checklist

| # | Invariant | Status |
|---|-----------|--------|
| 12 | Offline security gating blocks signing on network/no-passcode/capture (+rooted now) | PASS |
| 13 | Anti-replay: no bypass of validation; record-before-reveal; voided reqId stays refused | PASS — signed now recorded at auth, all non-ok validations block |

## Gate decision

Auto-continue gate. All findings fixed or documented, 31 tests green, analyze +
firewall clean. Proceeding to P6 (KT Wallet app). Note: the Cold Signer UI
screens (C1–C21) and the drift-backed SignRecordPersistence implementation are
presentation/wiring work layered on this reviewed logic; the security-critical
decision logic is complete and tested.
