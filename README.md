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
| KT Gateway | `1.16.25` | Production service at `https://gateway.kt-wallet.com` |

Gateway source version: `1.16.26`. Production currently remains on `1.16.25`
until the commitment-semantics candidate passes rollout validation on both
production instances behind `https://gateway.kt-wallet.com`.

Until signed store releases are published, build both apps from this repository
and do not install APK or IPA files from unofficial mirrors. Start with
[Building KT Wallet](BUILDING.md), review the current
[P0/P1 release-readiness report](reports/p0-p1-wallet-audit-2026-07-31/index.html),
and read [Security and Risk](SECURITY_AND_RISK.md) before testing with assets.

The responsive English, Simplified Chinese, and Japanese product site is in
[`website`](website/README.md). Its download cards intentionally remain marked
as pending until official store artifacts are available.

### Release readiness at a glance

| Evidence area | Current state | What it means |
|---|---|---|
| Reproducible source gate | Passed on 2026-08-05 | Static analysis, Flutter/package tests, Gateway tests, secret checks, dependency locks, checksums, and OSV scans passed for the revision described below |
| iOS native lifecycle tests | Passed on one retained simulator | Scene privacy and native bridge regressions are covered, but simulator evidence does not replace physical-device testing |
| Android and iOS physical devices | In progress | Biometrics, camera QR, lifecycle privacy, accessibility, recovery, and deletion still need the complete device matrix |
| Current-batch chain evidence | Partial | Implemented chains and transaction families are listed below; remaining live-network evidence is tracked explicitly and is never inferred from mocks |
| Store artifacts | Not published | No official App Store or Google Play download is available yet |
| Independent security audit | Not completed | The project is appropriate for controlled beta evaluation, not large-balance assurance |

“Passed” in this README refers to the stated source revision and environment,
not a permanent certification of an RPC, indexer, token contract, mobile OS, or
future build. The detailed evidence and remaining work are linked under
[Current scope](#current-scope).

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

Status reconciliation is pinned to the network ID persisted with each
transaction, not the network currently selected in the UI. Gateway lookups and
direct RPC fallbacks therefore query the original chain endpoint. If that
network was deleted, is unknown, or belongs to another chain family, the status
remains unknown and no request is sent instead of risking a false confirmation,
failure, or nonce replacement on a different network.

Changing the visible network only filters the history being displayed. Every
hashed `submitted`, `broadcast`, or `pending` row for the current wallet keeps
polling on its own persisted network, and asynchronous nonce/finality writes
remain bound to that row's original wallet even if the user switches wallets
while a provider request is in flight. Reconciliation runs with four bounded
workers instead of issuing every restored Pending lookup at once. An unexpected
error in one hash lookup is persisted as unknown evidence for that row and does
not abort status updates for its peers. If the wallet/network context changes
or the route is disposed, queued workers stop before sending another old hash.

Broadcasts are single-shot writes. A definitive rejection from the directly
selected node is shown as a failure, while a timeout, disconnected response,
or malformed reply after the request starts is kept as an unknown result.
Network-seen responses are deliberately non-terminal: EVM `nonce too low` or
`already known`, Solana `already processed`, and TRON
`DUP_TRANSACTION_ERROR` retain the locally derived hash/signature and continue
reconciliation. They may mean the exact transaction was already accepted or
that its nonce was consumed, so treating them as a retryable failure could
induce a duplicate payment. The local transaction identity and first-attempt
time are persisted before submission, allowing KT Wallet to reconcile without
automatically sending the transaction again.
No error returned by a posted Gateway broadcast—including one claiming an
upstream rejection, `unsupported`, or `rate_limited`—authorizes a terminal
failure or direct-node retry. The App keeps the locally verified hash in
reconciliation instead. Only a local network-manifest decision made before the
signed payload leaves the App may select the direct route; this prevents a
stale or malformed intermediary answer from hiding a forwarded transaction or
causing the same signed bytes to be submitted twice.
The production Gateway also atomically claims a SHA-256 fingerprint of the
chain, network, and signed payload in shared Redis before contacting a node.
Repeated or concurrent POSTs across CDN, proxy, or Gateway instances reuse the
first outcome and never submit the same signed transaction twice; raw signed
bytes are not stored.

Solana direct reconciliation and the post-send confirmation view share one
strict `getSignatureStatuses` parser. It accepts exactly one result for the
requested canonical 64-byte Base58 signature, binds the entry slot to the RPC
context, validates confirmations and the official confirmation-state vocabulary,
requires rooted/finalized and counted/non-finalized evidence to agree, and
requires the legacy `status` result to agree with `err`. Only an explicit
single `null` entry means “not found”; incomplete, contradictory, oversized, or
ambiguous responses stay unknown instead of inventing confirmation, failure, or
expiry.

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
  PIN, lockout, transaction, and signer-record cleanup. When the final wallet
  is removed, KT Wallet also invalidates every in-flight balance/history request
  and clears wallet-derived controller state before a late response can restore
  deleted account data in memory. Switching wallets synchronously hides the
  previous wallet's local history and queued transaction notices before any
  snapshot or database read for the new wallet can yield. Disposing the market
  route also invalidates provider callbacks, so a late balance cannot publish
  through a destroyed controller.
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
  a second transfer. A successful node response must return the same hash as
  the locally verified signed transaction (case-insensitive only for EVM/TRON);
  a mismatch remains outcome-unknown, retains the local hash, and is never
  retried automatically. A failed intent write performs neither signing nor
  broadcasting. The same response binding applies when the online wallet
  submits a cryptographically verified QR result from KT Cold Signer: the node
  cannot replace the transaction identity chosen by the offline signer.
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
- Both apps install an in-window privacy cover when the task leaves the
  foreground. On iOS, the cover is installed only after the scene actually
  enters the background, remains in place throughout foreground restoration,
  and is removed only when that scene becomes active again. On Android 13+,
  Recents capture is disabled and the system shows a dark KT task placeholder;
  older Android versions use a background-only secure-window fallback. Pulling
  Control Center, the notification shade, or another temporary system overlay
  does not replace the live UI. Successful screenshots trigger a non-blocking
  security warning where the operating system supports detection.
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

Wallet-scoped market and history state is cleared synchronously when a wallet
is switched or deleted, before cached data or a late provider response can be
rendered for the next wallet. Pending finality reconciliation is separately
bounded to four concurrent lookups, isolates a failing hash from its peers, and
stops queued requests when the owning wallet/network context is no longer
current. A corrupt display snapshot is treated as a cache miss rather than a
live-data failure. Unexpected provider or database exceptions close the loading
state into an explicit error and leave refresh immediately retryable; an
unattended Pending poll retries with a bounded 1×/2×/4×/8× delay instead of
silently stopping. These controls improve responsiveness without treating stale
cache or unknown chain evidence as a successful result.

Gateway `1.16.25` currently exposes 16 mainnet/testnet network profiles. It uses
bounded upstream failover and circuit breakers, plus short caches for prices
(30 seconds), display balances (10 seconds), and history (5 seconds). Pending
nonces, spendable balances, simulations, and transaction-status checks are not
read-cached. Broadcasts are never retried or failed over after submission
starts; a Redis-backed 24-hour payload fingerprint prevents duplicate
submission across instances without storing raw signed transaction bytes.

EVM and TRON status lookups bind every returned receipt to the requested
transaction identity and canonical inclusion fields. TRON smart-contract
receipts require a known execution result; native transfers whose protobuf
receipt omits the default result are cross-checked against the same
transaction's `ret.contractRet`. Missing, mismatched, or unknown evidence never
becomes a successful transaction.

Every direct JSON-RPC response and every Gateway upstream response must echo
the exact request id and scalar type, declare JSON-RPC 2.0, and contain exactly
one of `result` or a standard integer-code/string-message `error`. The same
rule covers balances, prices, fees, status, simulation, history, custom-network
probes, Solana airdrops, optional diagnostics, and broadcasts. A stale,
reordered, malformed, or mismatched response is never attributed to a request.
Concurrent Solana wallet and associated-token-account history calls also use a
distinct request id per call, so an out-of-order response cannot satisfy a
different in-flight lookup.
Broadcasts remain single-shot when this check fails, so an unknown outcome
cannot trigger an automatic duplicate submission.

Successful broadcast responses repeat and bind the requested chain, resolved
network, and a canonical transaction identity. EVM and TRON require a 32-byte
hex hash; Solana requires a canonical Base58-encoded 64-byte signature. The App
rejects another chain/network, unknown response members, or a malformed node
identity and keeps the durable local transaction in the honest `unknown` state
without posting the signed bytes again.

Balance results repeat and bind the exact chain, resolved network, and account
before any amount reaches the UI. Portfolio rows preserve request order and
repeat the same identity in both the outer account row and nested balance
result; missing, duplicated, reordered, additive, or cross-wallet rows are
rejected. The versioned shared-cache namespace prevents a rolling deployment
from interpreting a pre-binding Redis entry as a current trusted response.

History results apply the same request binding to chain, resolved network, and
owner. Each row must use the exact reviewed schema, carry a canonical
transaction identity and amount, and prove that its direction touches the
queried owner. A malformed, duplicated, additive, cross-wallet, or oversized
page is rejected in full and falls back to the chain source; it is never
partially displayed. The `history-v2` cache namespace isolates older unbound
entries during a rolling release.

The public production path remains FluxGate → HAProxy on loopback port 8118 →
the two Gateway instances on 8119/8120. The Gateway systemd units do not wait
for Docker or Redis to start: if Redis is unavailable, the documented bounded
local cache remains available and both Gateway instances can still start.
HAProxy, Prometheus, Alertmanager, and Redis remain containerized and are
monitored separately.

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

The iOS Scene lifecycle and native security bridges have separate XCTest
targets. Run them on one explicitly selected simulator so local testing does
not create or retain unnecessary simulator devices:

```sh
(cd apps/kt_wallet/ios && xcodebuild \
  -workspace Runner.xcworkspace -scheme Runner -configuration Debug \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -only-testing:RunnerTests test)
(cd apps/cold_signer/ios && xcodebuild \
  -workspace Runner.xcworkspace -scheme Runner -configuration Debug \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -only-testing:RunnerTests test)
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
(cd apps/kt_wallet && flutter build appbundle)
(cd apps/cold_signer && flutter build ios --no-codesign)
(cd apps/cold_signer && flutter build apk)
(cd apps/cold_signer && flutter build appbundle)
tool/bootstrap_android_release_toolchain.sh
tool/check_release_artifact.sh apps/kt_wallet/build/app/outputs/flutter-apk/app-release.apk
tool/check_release_artifact.sh apps/kt_wallet/build/app/outputs/bundle/release/app-release.aab
tool/check_release_artifact.sh apps/cold_signer/build/app/outputs/flutter-apk/app-release.apk
tool/check_release_artifact.sh apps/cold_signer/build/app/outputs/bundle/release/app-release.aab
tool/check_apple_release_artifact.sh apps/kt_wallet/build/ios/iphoneos/Runner.app
tool/check_apple_release_artifact.sh apps/cold_signer/build/ios/iphoneos/Runner.app
```

The two commands above intentionally allow unsigned device bundles for local
source/artifact review. Before TestFlight or App Store distribution, export the
signed `.app` from each archive and rerun the guard in strict mode:

```sh
tool/check_apple_release_artifact.sh --require-signed \
  /path/to/KT-Wallet.xcarchive/Products/Applications/Runner.app \
  cc.siliconnexus.ktwallet
tool/check_apple_release_artifact.sh --require-signed \
  /path/to/KT-Cold-Signer.xcarchive/Products/Applications/Runner.app \
  cc.siliconnexus.ktwallet.coldsigner
```

Strict mode requires a valid distribution signature, binds every embedded
framework, extension, and dynamic library to the same profile signer, and requires an Apple-trusted profile
CMS whose certificate list contains the actual app signer, an unexpired App
Store profile that exactly matches the bundle ID, debugger attachment disabled,
and `NSFileProtectionComplete` in both profile and final signed entitlements.
Passing the unsigned guard must never be reported as signed-release evidence.

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

The latest source gate (2026-08-05) completed with zero static-analysis
issues: **1,633/1,633** KT Wallet tests, **570/570** KT Cold Signer tests, and
**438/438** shared-package tests passed. The default gate passed **12/12** and
the native/runtime/OSV `--full` gate passed **13/13**. The Gateway audit,
public-secret gate, Gateway public-release version gate, native dependency
lock/checksum verification, and OSV scans also passed. These numbers are
reproducible source evidence. Broadcast acceptance is measured as successful
only after the node acknowledgement matches the locally verified transaction
hash; a missing or inconsistent hash is fail-closed/unknown and records a
failed broadcast metric. Market and history refresh metrics also require a
complete live result: one healthy chain cannot hide another chain's explicit
failure, and missing/invalid native quotes cannot be counted as a successful
portfolio refresh. Gateway market responses are bound to the exact requested
symbols, closed schemas, bounded financial values, and a 15-minute freshness
window. The direct CoinGecko fallback additionally requires the complete
requested quote set and mutually consistent CNY/JPY rates before it replaces
the last-known-good cache; malformed, additive, partial, stale, or polluted
answers are discarded as one unit. A legacy wallet whose actually enabled chains are all on
testnets now skips the price request entirely, regardless of disabled network
profiles. Gateway health is also a closed routing-authority boundary: only an
exact, versioned response with a non-empty, unique subset of the 16 built-in
network IDs may route public wallet reads through the Gateway. Legacy,
additive, malformed, duplicate, or operator-invented network advertisements
fail closed; custom networks remain bound to the user's direct RPC. Transaction
finality is committed in the same Drift transaction as
its terminal state: confirmed is successful; failed, replaced, and expired are
failed; pending and unknown evidence never manufacture a terminal sample. The
bounded SQLite ring stores only duration and outcome—no wallet, address, hash,
amount, network, error text, event timestamp, or payload—and is the single
persistent source for finality. SharedPreferences schema 3 explicitly excludes
those samples. Finality and ordinary experience samples use independent
100-entry in-memory pools, and diagnostic read failures are swallowed so they
cannot break startup, confirmation, or UI refresh. A process exit after
confirmed/failed commits therefore cannot lose or duplicate the corresponding
success-rate/P95 evidence on restart.

EVM mempool reconciliation also treats the node transaction object as bound
evidence, not a loose status hint. The request hash and sender must be
canonical; the returned hash and sender must match them exactly (hex case
aside), and nonce must be a canonical, non-negative uint256 quantity before
the app may show Pending or persist replacement evidence. Missing, mismatched,
negative, leading-zero, oversized, or otherwise malformed values remain
unknown. An opt-in read-only BNB Smart Chain Testnet smoke verifies this parser
against a previously confirmed public test transaction without loading a key
or broadcasting.

Direct public-RPC confirmation depth is display-only enrichment. Once a
hash-bound EVM receipt or TRON execution result proves confirmed/failed, an
unavailable, malformed, or lagging latest-height response cannot delay or undo
that terminal state; the UI keeps the terminal result and honestly leaves the
numeric confirmation depth unavailable.
The opt-in BNB Smart Chain Testnet smoke also reads that public transaction's
real receipt and latest height through this production confirmation service;
it never loads a key or broadcasts.

EVM nonce competitors are settled in one Drift transaction guarded by a live-
status compare-and-set. A late pending/unknown response cannot overwrite a
confirmed, failed, replaced, or expired row; the same settlement commits an
anonymous failed-finality row for every competitor it replaces together with
the winner's outcome. Account-history reconciliation, hash polling, the
broadcast-result page, and transaction detail all use that database boundary.
Detail pollers reload when their stale write loses this guard instead of publishing
the stale response; a direct receipt confirmation is also terminal even when
the fallback status service is not consulted. On
2026-08-03, the iOS native
Runner test targets passed **11/11** for KT Wallet and **8/8** for KT Cold Signer
on the single retained iPhone 17 Pro simulator, including the Scene privacy
state and non-key background-window selection tests. Both apps were also
verified by switching to another app, reopening App Switcher, and restoring
the protected task card. This is not a substitute for the outstanding
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
