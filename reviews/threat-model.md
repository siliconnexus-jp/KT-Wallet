# P8 — Threat Model & Hardening

Cross-module consolidation of the security invariants (detailed-design.md §8),
their enforcement, residual risks, and the release-hardening checklist.

## Security invariant status (DD §8.1–8.16)

| # | Invariant | Enforced by | Status |
|---|-----------|-------------|--------|
| 1 | No key material in logs/exceptions/persistence/Dart state | code review; prod Dart never holds mnemonic | ✓ (mock is test-only) |
| 2 | Native key buffers zeroed on all paths | Swift `resetBytes`/`memset_s`, Kotlin `fill(0)` | ✓ entropy; managed key objects rely on lib dealloc (P1-4 device recheck) |
| 3 | No AuthGate bypass on sign/export/delete | plugin dispatch routes all three through AuthGate | ✓ |
| 4 | Android setUserAuthenticationRequired / iOS biometryCurrentSet | KeystoreManager / KeychainStore | ✓ when requireAuth=true; hot-wallet enforcement in creation flow |
| 5 | Cold Signer double-encryption both layers required | KDF blob header, fail-closed read | ✓ |
| 6 | All decode paths total (typed error, never crash) | CBOR depth guard + overflow fix + 10k fuzz | ✓ |
| 7 | All size/count limits rejected (send AND receive) | payload/fragmenter/aggregator caps | ✓ |
| 8 | summary is display-only, never authoritative | validator uses parse result only | ✓ |
| 9 | No doubles in money math; BigInt lossless | Amount type; lint intent | ✓ (web RPC-int caveat documented) |
| 10 | Unsupported tx = explicit reject | closed enums, exhaustive switch, uint256 overflow reject | ✓ |
| 11 | Every business query bound to walletId | Repository forces scope walletId (release-safe) | ✓ |
| 12 | Offline security gating blocks signing | SecurityChecks block-dominance (incl. rooted) | ✓ |
| 13 | Anti-replay; record-before-reveal; voided stays refused | sign session records at auth; reqId store | ✓ |
| 14 | Watch wallets cannot local-sign (type-level) | sealed Wallet; only HotWallet.sign() | ✓ |
| 15 | Broadcast never auto-retried | both flow machines; explicit retry only | ✓ |
| 16 | Mnemonic pages clear memory / FLAG_SECURE | UI layer | pending screen impl (below) |

## Residual risks & mitigations

1. **Native signing not yet device-verified (P1-4).** The wallet-core
   SigningInput injection + per-chain output is a fail-closed stub. MITIGATION:
   signing throws until wired; no wrong-but-plausible signature possible.
   Blocker for real-network signing, tracked in acceptance runbook.

2. **Pub-workspace shared package_config makes `http` resolvable from
   cold_signer at analysis time.** None of cold_signer's runtime deps declare
   http/dio (verified), so the built app doesn't link it. MITIGATION (defense in
   depth): (a) `tool/check_deps.dart` bans http/dio/chains-rpc imports in
   cold_signer/lib; (b) Android release/profile manifests declare NO INTERNET
   (OS-enforced, provable); (c) iOS has zero network code + NWPathMonitor
   warning. The Android no-INTERNET guarantee is the authoritative one.

3. **iOS cannot be provably offline.** MITIGATION: claims limited to "no network
   code + connectivity-detection warning"; the strong provable-offline claim is
   made only for the Android Cold Signer build.

4. **iOS KDF is PBKDF2 (210k), not Argon2id (Android).** MITIGATION: PBKDF2 is a
   real stretching KDF; Argon2id parity is a tracked follow-up (needs a vetted
   Swift Argon2). Not a regression vs. shipping wallets.

5. **CachedSignRecordStore snapshot (TOCTOU).** Single-session offline signer;
   documented reload rule if concurrency is ever added.

## Release hardening checklist

### Android
- [ ] Release + profile manifests contain NO INTERNET (CI: `check_deps.dart`
      asserts main+profile; add `aapt dump permissions` on the release APK as the
      authoritative artifact check).
- [ ] R8/ProGuard enabled (`minifyEnabled true`, `shrinkResources true`).
- [ ] Cold Signer: no analytics/crash/push/WebView SDKs (dependency whitelist +
      `check_deps.dart`).
- [ ] StrongBox path exercised on a StrongBox device; TEE fallback on others.

### iOS
- [ ] Privacy manifest (`PrivacyInfo.xcprivacy`) declares Keychain reason codes;
      no tracking domains.
- [ ] Cold Signer target links no networking frameworks beyond NWPathMonitor.
- [ ] Keychain access control asserted `biometryCurrentSet` in an instrumented test.

### Both
- [ ] FLAG_SECURE (Android) on mnemonic + QR routes; iOS screenshot-detection
      warning (INV-16 — implement with the screens).
- [ ] Dependency lockfiles pinned; `dart pub outdated` reviewed; licenses listed.
- [ ] Custom lint banning direct `WalletDatabase` table access outside
      `wallet_data` (P4 review follow-up).
- [ ] Reproducible build + signed artifacts; wallet-core version pinned (iOS pod
      4.7.0 / Android AAR 4.7.0) and checksum-verified.

## Dependency audit (cold_signer runtime)

Direct runtime deps: `core_crypto`, `airgap_protocol`, `chains` (core only),
`ui_kit`, `cupertino_icons`. NONE of these declares `http`/`dio`/analytics/
push/WebView. The `http`/`test`/`build_runner` entries in `dart pub deps` are
the shared workspace resolution (kt_wallet + dev tooling), not cold_signer
runtime deps. Firewall + no-INTERNET manifest are the shipping guarantees.
