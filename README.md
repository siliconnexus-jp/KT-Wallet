# KT Wallet

<p align="center">
  <img src="branding/kt-wallet-logo-256.png" width="160" alt="KT Wallet logo">
</p>

<p align="center">
  Open-source, air-gapped multi-chain wallet for iOS and Android.
</p>

<p align="center">
  Ethereum · BNB Smart Chain · Polygon · Base · Arbitrum · Avalanche · TRON · Solana
</p>

Source code, issues, and releases:
[siliconnexus-jp/KT-Wallet](https://github.com/siliconnexus-jp/KT-Wallet).
The project is licensed under [MPL-2.0](LICENSE).

## Status and downloads

| Component | Current version | Availability |
|---|---:|---|
| KT Wallet | `1.0.0+1` | Controlled public-beta builds; App Store and Play Store listings are not yet public |
| KT Cold Signer | `1.0.0+1` | Controlled public-beta builds; source build is available for dedicated offline devices |
| KT Gateway | `1.16.9` | Production service at `https://gateway.kt-wallet.com` |

Until signed store releases are published, build both apps from this repository
and do not install APK or IPA files from unofficial mirrors. Start with
[Building KT Wallet](BUILDING.md), review the current
[P0/P1 release-readiness report](reports/p0-p1-wallet-audit-2026-07-31/index.html),
and read [Security and Risk](SECURITY_AND_RISK.md) before testing with assets.

The responsive English, Simplified Chinese, and Japanese product site is in
[`website`](website/README.md). Its download cards intentionally remain marked
as pending until official store artifacts are available.

## What is included

KT Wallet can be used in two complementary roles:

- **Online Wallet** — manages hot wallets and watch-only accounts, reads live
  balances and history, builds transactions, broadcasts them, and follows their
  confirmation state.
- **KT Cold Signer** — keeps recovery phrases and signing keys on an
  offline device. Transaction requests and signed responses move between
  devices through QR codes.

The main `apps/kt_wallet` installer includes both roles and asks which mode the
device should use on first launch. `apps/cold_signer` is also available as an
independent install for a dedicated offline phone.

The interface is localized in **简体中文**, **English**, and **日本語**.

### Which app should I install?

| Use case | Install | Network access | Private keys |
|---|---|---|---|
| Everyday balance, history, receive, and transfer | **KT Wallet** in Online Wallet mode | Required | Stored on this device for a hot wallet; absent for watch-only wallets |
| One-device offline signing trial | **KT Wallet** in Cold Signer mode | Must remain offline while signing | Stored only in the native vault on this device |
| Dedicated air-gapped signing phone | **KT Cold Signer** | Must remain offline while signing | Stored only in the native vault on the offline phone |

For the strongest separation, use KT Wallet as a watch-only wallet on the
connected phone and KT Cold Signer on a second phone that remains offline. The
Cold Signer does not fetch balances, prices, or history and does not broadcast
transactions. It only derives public accounts, verifies transaction details,
authenticates the user, and signs QR requests.

## Air-gapped signing

```text
Online Wallet                         KT Cold Signer

build unsigned transaction
show request QR          ── camera ──▶ parse raw transaction
                                      show recipient, amount, token,
                                      network and fee
                                      verify PIN / biometrics
                                      sign with the native key
verify signed response   ◀─ camera ── show signed-response QR
broadcast and track
```

The Cold Signer derives real accounts for every supported chain and exports
wallet ID, address, public key, derivation path, and protocol version. The
online wallet creates a watch-only account from this payload.

Before broadcasting, the online side validates that the signer, network, and
signed transaction match the original request. A modified payload, wrong
signer, wrong network, or mismatched transaction is rejected.

## Chain support

| Chain | Balance | Native transfer | Token transfer | History |
|---|:---:|:---:|:---:|:---:|
| Ethereum | ✅ | ETH | ERC-20 | Blockscout |
| BNB Smart Chain | ✅ | BNB | BEP-20 | Routescan |
| Polygon | ✅ | POL | ERC-20 | Blockscout |
| Base | ✅ | ETH | ERC-20 | Blockscout |
| Arbitrum | ✅ | ETH | ERC-20 | Blockscout |
| Avalanche C-Chain | ✅ | AVAX | ERC-20 | Routescan |
| TRON | ✅ | TRX | TRC-20 | TronGrid |
| Solana | ✅ | SOL | SPL Token | Solana RPC |

Hot wallets sign through the native Trust Wallet Core bridge. Watch-only
wallets have no private-key signing capability and use the QR workflow.

Built-in mainnet assets include:

- Ethereum: USDT, USDC, DAI, WETH, WBTC, LINK, UNI, SHIB, PEPE, BUSD, and
  PYUSD.
- BNB Smart Chain: BNB and BUSD.
- Solana: USDT, USDC, JUP, BONK, and Token-2022 PYUSD.
- Existing Polygon, Base, Arbitrum, Avalanche, and TRON stablecoin
  deployments remain supported.

The built-in registry uses canonical contract or mint identities rather than
trusting a token symbol. BUSD remains available for existing balances and
transfers, but it is a legacy asset whose issuer has ended new issuance.

The table describes implemented transaction families. Public RPC availability,
faucet limits, and testnet token liquidity are external dependencies and are not
reported as successful when unavailable.

### Fees and preflight checks

- EVM transactions use the pending nonce, `eth_estimateGas`, and
  EIP-1559 fee history.
- TRON transactions query bandwidth, energy, and contract energy usage to
  derive `feeLimit`.
- Solana transactions use a fresh blockhash, `getFeeForMessage`, node
  simulation, and automatically create a missing recipient associated token
  account in the same signed transaction.
- If a required fee or simulation call fails, sending is blocked instead of
  falling back to a demo fee.

Both the legacy SPL Token Program and Token-2022 transfers are supported for
built-in assets. The token program and mint are part of the parsed transaction
and are checked before an air-gapped signature is accepted.

## Transaction lifecycle

Transactions are stored locally as `submitted`, `pending`, `confirmed`,
`failed`, or `dropped`. KT Wallet resumes polling after restart and merges local
pending records with chain history so a newly submitted transaction does not
temporarily disappear.

Broadcasts are single-shot writes. An explicit node rejection is shown as a
failure, while a timeout, disconnected response, or malformed reply after the
request starts is kept as an unknown result. The locally derived transaction
hash and first-attempt time are persisted before submission, so KT Wallet can
continue reconciliation without automatically sending the transaction again.
The production Gateway also atomically claims a SHA-256 fingerprint of the
chain, network, and signed payload in shared Redis before contacting a node.
Repeated or concurrent POSTs across CDN, proxy, or Gateway instances reuse the
first outcome and never submit the same signed transaction twice; raw signed
bytes are not stored.

Pending EVM transactions support:

- **Speed up** — sends a replacement with the same nonce, recipient, value, and
  calldata, but a higher EIP-1559 fee.
- **Cancel** — sends a zero-value self-transfer with the same nonce and a higher
  fee.

A speed-up does not intentionally create a second transfer. Only one
same-nonce transaction can be accepted by the chain. Until one replacement is
confirmed, however, the original transaction may still win the race; the UI
therefore distinguishes signing, broadcasting, and chain confirmation.

## Security model

- Recovery phrases are committed to the native crypto vault under a random
  wallet ID; production flows do not persist the complete phrase in Dart
  secure storage.
- Dart security metadata uses platform secure storage without a production
  memory fallback. If that plugin is unavailable, KT Wallet stays locked and
  KT Cold Signer blocks onboarding and signing until secure storage recovers.
  The in-memory implementation is available only when a Flutter test marker is
  present in a non-Web Debug build. Profile and Release builds reject both the
  process marker and explicit test-storage overrides at the compile-mode
  boundary. Repository checks prevent production code from reading that marker
  outside the two canonical test-environment adapters.
- Developer galleries, seeded/test-bypass controllers, simulated scanner
  results, legacy demo account exports, and demo wallet IDs are available only
  in Debug builds. Profile is treated as production-equivalent here: both
  Profile and Release reject these fixtures and normalize production routes to
  real wallet state.
- A transient native-key or derivation failure never erases the Cold Signer's
  durable wallet identifier. Failed onboarding attempts independently clean
  native key material and every PIN/metadata key; a failure in one cleanup
  step cannot suppress the remaining compensation steps.
- KT Wallet hot-wallet creation and import commit the native key, derived
  addresses, and Drift rows as one compensated operation. A failure never
  publishes a wallet that disappears after restart, duplicate mnemonics are
  rejected, and startup verifies every persisted address against its native
  key before wallet content is shown. Transient creation failures keep the
  uncommitted phrase only in memory so the same verification flow can retry.
- Wallet deletion is crash-recoverable across native key storage and the Dart
  database. Both apps durably record deletion intent before erasing a key,
  hide any pending-deletion wallet on restart, and idempotently finish metadata,
  PIN, lockout, transaction, and signer-record cleanup.
- Wallet names, avatar colors, backup status, and ordering are published to
  the UI only after durable storage succeeds. Reordering writes every affected
  wallet in one Drift transaction, so a failure cannot persist a partial order.
- App Lock, authentication, auto-lock, privacy, approval consent, fiat/asset
  preferences, Gateway/RPC overrides, environment profiles, and custom
  networks are serialized and published only after durable storage succeeds.
  Network configuration uses one versioned snapshot, so a partial write cannot
  silently move signing or broadcasting to a different chain after restart;
  every affected screen keeps its prior value and reports a save failure.
- The combined installer's online-wallet/offline-signer device role follows
  the same commit-before-publish rule. Selection and exit requests are
  serialized; a storage failure keeps the current mode on screen, reports the
  error in the active language, and cannot silently change the role on restart.
- Manual language overrides in both apps accept only English, Simplified
  Chinese, or Japanese and are also published only after persistence succeeds;
  invalid stored values return to the system language instead of rendering an
  unsupported or inconsistent security UI.
- BIP-39 words and checksums are validated before import. Failed imports do not
  leave a partial wallet.
- Each Cold Signer signature requires PIN or biometric authentication. PIN
  retry limits and lockout state persist across restarts.
- A system-auth cancellation, timeout, lockout, or device error remains a
  failed authentication. Cold Signer offers the App PIN automatically only
  when the platform has no credential, enrollment, biometric hardware, or
  usable authentication plugin.
- Android system-auth prompts are coordinated with the Recents privacy cover:
  showing `BiometricPrompt` cannot launch a second privacy Activity and orphan
  the authentication result, while a real background transition still covers
  the wallet window before Android snapshots it.
- The signing boundary freezes the parsed request bytes, rechecks device state
  and expiry immediately before the native key call, and atomically reserves
  the request ID in durable storage. Concurrent callbacks, process restarts,
  storage failures, and failed native signing cannot replay the same request.
- KT Wallet does not publish an offline-signing request or render its QR bytes
  until the matching `awaitingSig` transaction row is durably committed. A
  database failure leaves the session empty and shows a localized blocking
  error, so the Cold Signer cannot sign a request the online wallet would lose
  after restart.
- Hot-wallet EVM, TRON, and Solana sends persist the exact user-authorized
  transaction intent before native signing, then persist the locally derived
  transaction hash before the first network broadcast. If the node accepts the
  bytes but its response is lost, the row remains `submitted` and restart
  polling resolves it from the chain; the UI does not label it failed or invite
  a second transfer. A failed intent write performs neither signing nor
  broadcasting.
- Offline safety checks use `safe`, `unsafe`, and `unknown`; an unavailable
  probe is never displayed as a successful check.
- Signing is blocked when the signer detects an online connection, screen
  recording, or a failed device-integrity check.
- Android Cold Signer enables `FLAG_SECURE` only while recovery-phrase show,
  verification, or import routes are visible; ordinary screens remain
  capturable and Android 14+ reports successful captures with the official
  callback. iOS warns after a one-shot screenshot and conceals phrase routes
  while screen recording or mirroring is actively detected.
- Reviewing an existing Cold Signer backup first invokes the native strong-auth
  gate, validates the exported BIP-39 phrase, and passes it only through an
  ephemeral in-memory route object. Authentication failure and direct deep
  links reveal no phrase; successful review returns to wallet management.
- Both Android apps disable cloud backup and device-to-device transfer for all
  local wallet state. The Cold Signer release artifact is additionally checked
  after manifest merging and must not contain the `INTERNET` permission;
  `ACCESS_NETWORK_STATE` is retained only to detect connectivity and block
  signing.
- On iOS, app files use Complete Data Protection while the device is locked,
  and the local Documents/Library state is excluded from system backups.
  Wallet entropy remains in a passcode-required, this-device-only Keychain
  item. Recovery is through the explicit encrypted backup or recovery phrase,
  not an implicit app-data restore.
- Both apps replace their content with a branded privacy cover when entering
  the background or app switcher. Successful screenshots trigger a
  non-blocking security warning where the operating system supports detection.
- Production routes do not seed sample wallets, fake balances, or simulated
  successful transactions.
- Online verification recovers the signer from canonical signed bytes and
  compares the complete EVM, TRON, or Solana transaction/message with the
  original request. EVM/TRON high-s malleable signatures are rejected.

Security controls reduce risk but cannot make a compromised device safe. Read
[Security and Risk](SECURITY_AND_RISK.md) before using real assets. Suspected
vulnerabilities must be reported privately using the process and response
targets in [Security Policy](SECURITY.md), never through a public issue.

## Reliability and data sources

Fresh installs use the production KT Gateway for supported balance, Token,
price, history, chain-parameter, simulation, risk, broadcast, and status
operations. Read paths have a controlled direct-provider fallback when the
Gateway is unavailable. Users can explicitly select direct mode or configure a
per-chain RPC override; a custom RPC remains authoritative and is never
silently replaced. Balance and history failures remain visible instead of
being converted to zero or an empty success.

Gateway `1.16.9` currently exposes 16 mainnet/testnet network profiles. It uses
bounded upstream failover and circuit breakers, plus short caches for prices
(30 seconds), display balances (10 seconds), and history (5 seconds). Pending
nonces, spendable balances, simulations, and transaction-status checks are not
read-cached. Broadcasts are never retried or failed over after submission
starts; a Redis-backed 24-hour payload fingerprint prevents duplicate
submission across instances without storing raw signed transaction bytes.

The Gateway receives the public address, network, and public contract/mint
needed for a requested lookup. Recovery phrases, private keys, signatures, raw
signed transactions, balances, addresses, and transaction hashes are excluded
from application logs. See the
[Gateway documentation](backend/gateway/README.md) for its protocol, cache,
privacy, rate-limit, observability, and deployment boundaries.

```text
KT Wallet ── public chain data / broadcast ──▶ KT Gateway ──▶ RPC and indexers
    │
    └── unsigned request QR ──▶ KT Cold Signer ── signed response QR ──┘
```

The Gateway is infrastructure, not a custody service: it never receives a
recovery phrase or private key and cannot sign a transaction. A custom RPC can
be selected explicitly, but the app never silently changes away from a user's
configured endpoint. The dedicated KT Cold Signer is expected to remain
offline and has no Android `INTERNET` permission in its release artifact.

## Build and test

Requirements:

- Flutter SDK compatible with the workspace lockfile
- Xcode and CocoaPods for iOS
- Android SDK for Android
- GitHub Packages `read:packages` access when enabling Trust Wallet Core on
  Android

Install workspace dependencies:

```sh
flutter pub get
```

Run the main test suites:

```sh
dart run tool/audit_public_beta.dart
```

That fail-fast command is the canonical local source gate: it runs repository
security/secret/cleanup checks, static analysis, all six shared packages, both
Flutter apps, and the Gateway audit in a fixed reviewable order. Add `--full`
to include pinned native/runtime dependency and OSV audits. It deliberately
does not replace signed-artifact checks, physical-device review, real-chain
broadcast evidence, or an independent security audit.

The underlying suites can also be run individually:

```sh
(cd packages/ui_kit && flutter test)
(cd packages/chains && flutter test)
(cd packages/wallet_data && flutter test)
(cd apps/kt_wallet && flutter test)
(cd apps/cold_signer && flutter test)
tool/audit_dependencies.sh
```

`tool/audit_dependencies.sh` requires Go 1.26.5 through toolchain
auto-selection, verifies all three official Gradle Wrapper JAR/distribution
checksums, resolves both locked Android Release runtime graphs, enforces both
CocoaPods lockfiles in deployment mode, runs the Gateway's call-aware
`govulncheck`, and scans Dart, npm, Go plus the two Android runtime lockfiles
with pinned OSV-Scanner 2.2.4. Only public package coordinates and versions are
queried; wallet data and source files are not uploaded. Because CocoaPods is
not a natively supported OSV lockfile ecosystem, the gate additionally resolves
each remote Pod tag to an exact upstream commit, verifies the pinned source
archive checksum, and queries those commits through OSV. The Dart native-assets
SQLite release tag, bundled source hashes, and final Apple/Android runtime
version are checked independently.

Build the applications:

```sh
(cd apps/kt_wallet && flutter build ios --no-codesign)
(cd apps/kt_wallet && flutter build apk)
(cd apps/cold_signer && flutter build ios --no-codesign)
(cd apps/cold_signer && flutter build apk)
tool/check_release_artifact.sh apps/kt_wallet/build/app/outputs/flutter-apk/app-release.apk
tool/check_release_artifact.sh apps/cold_signer/build/app/outputs/flutter-apk/app-release.apk
tool/check_apple_release_artifact.sh apps/kt_wallet/build/ios/iphoneos/Runner.app
tool/check_apple_release_artifact.sh apps/cold_signer/build/ios/iphoneos/Runner.app
```

Android Debug/test builds without Wallet Core use a fail-closed crypto stub:
signing and key operations return `CRYPTO_UNAVAILABLE` rather than producing
placeholder cryptography. Android Release builds refuse to configure unless
Wallet Core is enabled. See [BUILDING.md](BUILDING.md) for package credentials
and release-signing requirements.

Recent device and simulator evidence is available in:

- [P0/P1 trusted-wallet audit and release-readiness report](reports/p0-p1-wallet-audit-2026-07-31/index.html)
- [Security hardening report](reports/hardening-2026-07-26/index.html)
- [Pending replacement UI report](reports/pending-replacement-ui-2026-07-26/index.html)
- [Testnet cryptography report](reports/testnet-real-crypto-2026-07-26/index.html)
- [iOS transfer retest](reports/ios-transfer-retest-2026-07-26/index.html)

The latest source gate (2026-08-03) completed with zero static-analysis
issues: **1,461/1,461** KT Wallet tests, **570/570** KT Cold Signer tests, and
**400/400** shared-package tests passed. The Gateway audit, public-secret gate,
native dependency lock/checksum verification, and OSV scans also passed. These
numbers are reproducible source evidence, not a substitute for the outstanding
physical-device, real-chain, signed-artifact, or independent-audit work below.

## Application identities

| Application | Android application ID | iOS bundle ID |
|---|---|---|
| KT Wallet | `cc.siliconnexus.ktwallet` | `cc.siliconnexus.ktwallet` |
| KT Cold Signer | `cc.siliconnexus.ktwallet.coldsigner` | `cc.siliconnexus.ktwallet.coldsigner` |

Launcher names follow the device language: Chinese displays **KT钱包** and
**KT冷钱包**; English, Japanese, and other languages display **KT Wallet** and
**KT Cold Signer**.

## Repository layout

| Path | Purpose |
|---|---|
| `apps/kt_wallet` | Online wallet and embedded Cold Signer |
| `apps/cold_signer` | Independently installable KT Cold Signer |
| `packages/core_crypto` | Native mnemonic, derivation, vault, and signing bridge |
| `packages/wallet_data` | Drift/SQLite wallets, transactions, and pending state |
| `packages/airgap_protocol` | Versioned QR request and response protocol |
| `packages/chains` | Address validation, RPC, parsing, and signature verification |
| `packages/ui_kit` | Shared KT design system and screen-security UI |
| `backend/gateway` | Optional infrastructure gateway |
| `reports` | HTML acceptance reports and screenshots |

## Current scope

### Public beta status

The current build is suitable for continued TestFlight and controlled public
beta evaluation with testnet or small-value assets. It must not yet be
represented as having the assurance level of a mature international wallet or
as suitable for holding large mainnet balances.

There are currently no official App Store or Google Play download links.
Screenshots and HTML reports in this repository are engineering evidence from
specific builds and environments, not a security certification or a promise
that every public RPC, faucet, indexer, or token contract will remain
available. Always verify the network, contract or mint, recipient, amount, and
fee before authorizing a transfer.

The remaining release evidence includes:

- complete iOS and Android physical-device coverage for biometrics, lifecycle
  privacy, recovery-phrase protection, deletion, and accessibility;
- a current-batch Polygon Amoy native/token broadcast and replacement test,
  plus physical-camera QR round trips between the online wallet and the
  independent KT Cold Signer;
- small-value mainnet approval discovery and revoke validation;
- independent mobile and cryptography security audits;
- China-mainland multi-carrier, weak-network, and cross-region availability
  testing, plus an external Alertmanager/on-call receiver and SLA exercise;
- release-signed artifact inspection before store distribution.

The detailed, evidence-linked backlog is maintained in
[the P0/P1 trusted-wallet plan](docs/P0_P1_TRUSTED_WALLET_PLAN.md).

### Deliberately deferred features

The following are intentionally outside the current release scope:

- WalletConnect and DApp browser
- NFT gallery
- Swap
- Staking
- Production store signing and native CI

## Disclosures

- [Privacy Policy](PRIVACY_POLICY.md)
- [Security Policy and private reporting](SECURITY.md)
- [Security and Risk](SECURITY_AND_RISK.md)
- [Third-party Notices](THIRD_PARTY_NOTICES.md)
