# Review: P1 core_crypto

Module: `packages/core_crypto` (wallet-core bridge + native key security).
Reviewer: AI code review (Explore agent) + author reconciliation.
Design refs: detailed-design.md §2, §3, §8.1–8.5.

## Test status

- Dart layer: `flutter test` → 32 passing (API validation, error mapping, mock
  determinism, lockout ladder 60→300→900, KDF-header fail-closed indirectly via
  mock).
- Android AuthGate: pure-JVM tests written (ladder + persistence). **Not run in
  this environment** (needs Gradle + Android SDK).
- iOS/Android native vector tests (BIP-39/44 addresses, signing): **not run**
  — require the wallet-core framework and a device/simulator (see Deferred).

## Environment constraint (why some items are deferred, not fixed)

wallet-core is a native binary (iOS pod / Android AAR) and the signing path
needs per-chain SigningInput/Output protobufs. It cannot be compiled or run in
this sandbox. Native correctness is therefore verified on a device in P1-4 /
P7. Items below are marked **FIXED** (logic verifiable now), or
**DEFERRED-TO-DEVICE** (structural fix applied + must be verified on device).

## Findings & disposition

### Blocking

1. **iOS Cold-Signer KDF was HKDF (non-stretching), no DEBUG guard** — FIXED.
   `EntropyCipher.swift` now uses PBKDF2-HMAC-SHA256 @ 210k iterations via
   CommonCrypto (a real password-stretching KDF, no extra dependency), RNG
   status checked, derived key zeroed. Target remains Argon2id to match Android;
   swap noted in code when a vetted Swift Argon2 is vendored.

2. **Android lockout ladder in-memory → reset on process restart** — FIXED.
   `AuthGate` now takes an injected `AuthGateStore`; production uses
   `PrefsAuthGateStore` (SharedPreferences). Added JVM test simulating restart
   (fresh gate over same store still locked). iOS AuthGate now also persists the
   active `lockedUntil` deadline (was in-memory), comment corrected to match
   UserDefaults usage.

3. **Derived private key never injected into SigningInput; signing depended on
   key being inside the Dart-supplied input** — DEFERRED-TO-DEVICE (fail-closed
   now). Both bridges' `sign()` are now explicit structural stubs that throw
   `SIGN_FAILED` until P1-4 wires per-chain key injection, so they can never emit
   a wrong-but-plausible signature or force a key across the Dart boundary. The
   integration signing test is `skip: true` with a P1-4 reference; a guard
   asserts signing stays fail-closed.

### Minor — FIXED

- iOS no-op "zero the private key" defer removed (was misleading); signing stub
  no longer derives an unmanaged key.
- Empty-output → mapping and error contract: signing is now fail-closed; the
  test that expected `INVALID_INPUT` was replaced by the P1-4 skip guard.
- Android `KeyPermanentlyInvalidatedException` → `BIOMETRY_CHANGED` added to
  `mapError`.
- Raw exception text no longer forwarded to Dart (Android passes `null`
  message); avoids leaking any future library-internal strings.
- iOS salt RNG `OSStatus` now checked (throws `rngFailed` instead of silently
  using an all-zero salt).
- **deriveAddresses broken for KDF wallets + no persisted KDF marker** — FIXED.
  A 1-byte blob header records whether the KDF layer is present; read paths
  (both platforms) fail closed when a KDF wallet is read without its password,
  enforcing invariant 5 at the native layer instead of trusting the caller.

### Minor — DEFERRED-TO-DEVICE (needs framework/device to implement+verify)

- **Per-chain txHash**: keccak256-for-all-chains placeholder removed with the
  signing stub; correct per-chain SigningOutput hash extraction lands in P1-4.
- **Android BiometricPrompt not CryptoObject-bound**: current prompt is UI-only.
  Auth-bound Keystore keys need a `CryptoObject` (or a validity window) to
  actually gate decryption; wiring + on-device verification in P1-4. Tracked.
- **`requireAuth=false` drops invariant-4 protections**: by design for
  watch-only/derivation ergonomics, but hot wallets must always store with
  `requireAuth=true`. Enforcement (reject `requireAuth=false` for hot wallets)
  to be asserted where wallets are created (P4/P6) + native test on device.
- **Argon2 on iOS** (vs PBKDF2 interim): swap when a vetted Swift Argon2 is
  vendored; parity test with Android in P1-4.

### Notes (no violation)

- Invariant 3 holds: `signTransaction` / `exportMnemonic` / `deleteWallet` all
  route through the AuthGate on both platforms; no bypass path.
- Production Dart (`method_channel.dart`) never stores or logs a mnemonic.
- KeychainStore / BlobStore persist only ciphertext; delete best-effort scrubs.
- `MockCoreCrypto` holds a plaintext mnemonic in memory — test-only, not
  exported from `core_crypto.dart`; acceptable so long as it never ships in a
  production path.

## Invariant checklist (DD §8.1–8.5)

| # | Invariant | Status |
|---|-----------|--------|
| 1 | No mnemonic/key in logs/exceptions/persistence/Dart state | PASS (prod); mock is test-only |
| 2 | Key-material zeroed on all native paths incl. early return | PARTIAL — entropy buffers zeroed; managed key objects rely on lib dealloc; revisit in P1-4 |
| 3 | No AuthGate bypass on sign/export/delete | PASS |
| 4 | Android setUserAuthenticationRequired / iOS biometryCurrentSet | PASS when requireAuth=true; enforcement of that for hot wallets deferred |
| 5 | Cold Signer double-encryption both layers required | PASS — enforced via KDF blob header, fail-closed |

## Gate decision

Signing correctness (finding 3 + per-chain hash + CryptoObject) is genuinely a
device-build task (P1-4) and is now fail-closed rather than silently wrong. All
other blocking/minor items are fixed and the Dart layer is green. **P1 stops
here for user confirmation** (per plan) before P2. Recommended: proceed to P2
(airgap_protocol — independent of native signing) and schedule the P1-4 device
pass (signing + native vectors) before any real-network signing.
