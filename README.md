# KT Wallet

<p align="center">
  <img src="branding/kt-wallet-logo-256.png" width="160" alt="KT Wallet logo">
</p>

<p align="center">
  Open-source, air-gapped multi-chain wallet for iOS and Android.
</p>

<p align="center">
  Ethereum · Polygon · Base · Arbitrum · Avalanche · TRON · Solana
</p>

Source code, issues, and releases:
[siliconnexus-jp/KT-Wallet](https://github.com/siliconnexus-jp/KT-Wallet).
The project is licensed under [MPL-2.0](LICENSE).

## What is included

KT Wallet can be used in two complementary roles:

- **Online Wallet** — manages hot wallets and watch-only accounts, reads live
  balances and history, builds transactions, broadcasts them, and follows their
  confirmation state.
- **KT Wallet Cold Signer** — keeps recovery phrases and signing keys on an
  offline device. Transaction requests and signed responses move between
  devices through QR codes.

The main `apps/kt_wallet` installer includes both roles and asks which mode the
device should use on first launch. `apps/cold_signer` is also available as an
independent install for a dedicated offline phone.

The interface is localized in **简体中文**, **English**, and **日本語**.

## Air-gapped signing

```text
Online Wallet                         KT Wallet Cold Signer

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
| Polygon | ✅ | POL | ERC-20 | Blockscout |
| Base | ✅ | ETH | ERC-20 | Blockscout |
| Arbitrum | ✅ | ETH | ERC-20 | Blockscout |
| Avalanche C-Chain | ✅ | AVAX | ERC-20 | Routescan |
| TRON | ✅ | TRX | TRC-20 | TronGrid |
| Solana | ✅ | SOL | SPL Token | Solana RPC |

Hot wallets sign through the native Trust Wallet Core bridge. Watch-only
wallets have no private-key signing capability and use the QR workflow.

The table describes implemented transaction families. Public RPC availability,
faucet limits, and testnet token liquidity are external dependencies and are not
reported as successful when unavailable.

### Fees and preflight checks

- EVM transactions use the pending nonce, `eth_estimateGas`, and
  EIP-1559 fee history.
- TRON transactions query bandwidth, energy, and contract energy usage to
  derive `feeLimit`.
- Solana transactions use a fresh blockhash, `getFeeForMessage`, and node
  simulation.
- If a required fee or simulation call fails, sending is blocked instead of
  falling back to a demo fee.

SPL transfers currently require the recipient's associated token account to
already exist. Automatic ATA creation is not yet implemented.

## Transaction lifecycle

Transactions are stored locally as `submitted`, `pending`, `confirmed`,
`failed`, or `dropped`. KT Wallet resumes polling after restart and merges local
pending records with chain history so a newly submitted transaction does not
temporarily disappear.

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
- BIP-39 words and checksums are validated before import. Failed imports do not
  leave a partial wallet.
- Each Cold Signer signature requires PIN or biometric authentication. PIN
  retry limits and lockout state persist across restarts.
- Offline safety checks use `safe`, `unsafe`, and `unknown`; an unavailable
  probe is never displayed as a successful check.
- Signing is blocked when the signer detects an online connection, screen
  recording, or a failed device-integrity check.
- Android Cold Signer uses `FLAG_SECURE`. Android 14+ uses the official screen
  capture callback; iOS uses the system screenshot notification.
- Both apps replace their content with a branded privacy cover when entering
  the background or app switcher. Successful screenshots trigger a
  non-blocking security warning where the operating system supports detection.
- Production routes do not seed sample wallets, fake balances, or simulated
  successful transactions.

Security controls reduce risk but cannot make a compromised device safe. Read
[Security and Risk](SECURITY_AND_RISK.md) before using real assets.

## Reliability and data sources

RPC requests use bounded timeouts and per-network endpoint fallback. A custom
RPC selected by the user remains authoritative and is not silently replaced.
Balance failures remain visible as errors rather than being converted to zero.

History works directly through chain data providers and does not require the
optional KT Gateway. The gateway can still be configured as an infrastructure
override.

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
(cd packages/ui_kit && flutter test)
(cd packages/chains && flutter test)
(cd packages/wallet_data && flutter test)
(cd apps/kt_wallet && flutter test)
(cd apps/cold_signer && flutter test)
```

Build the applications:

```sh
(cd apps/kt_wallet && flutter build ios --no-codesign)
(cd apps/kt_wallet && flutter build apk)
(cd apps/cold_signer && flutter build ios --no-codesign)
(cd apps/cold_signer && flutter build apk)
```

Android builds without Wallet Core use a fail-closed crypto stub: signing and
key operations return `CRYPTO_UNAVAILABLE` rather than producing placeholder
cryptography. See [BUILDING.md](BUILDING.md) for Wallet Core setup, package
credentials, and release-signing requirements.

Recent device and simulator evidence is available in:

- [Security hardening report](reports/hardening-2026-07-26/index.html)
- [Pending replacement UI report](reports/pending-replacement-ui-2026-07-26/index.html)
- [Testnet cryptography report](reports/testnet-real-crypto-2026-07-26/index.html)
- [iOS transfer retest](reports/ios-transfer-retest-2026-07-26/index.html)

## Application identities

| Application | Android application ID | iOS bundle ID |
|---|---|---|
| KT Wallet | `cc.siliconnexus.ktwallet` | `cc.siliconnexus.ktwallet` |
| KT Wallet Cold Signer | `cc.siliconnexus.ktwallet.coldsigner` | `cc.siliconnexus.ktwallet.coldsigner` |

## Repository layout

| Path | Purpose |
|---|---|
| `apps/kt_wallet` | Online wallet and embedded Cold Signer |
| `apps/cold_signer` | Independently installable KT Wallet Cold Signer |
| `packages/core_crypto` | Native mnemonic, derivation, vault, and signing bridge |
| `packages/wallet_data` | Drift/SQLite wallets, transactions, and pending state |
| `packages/airgap_protocol` | Versioned QR request and response protocol |
| `packages/chains` | Address validation, RPC, parsing, and signature verification |
| `packages/ui_kit` | Shared KT design system and screen-security UI |
| `backend/gateway` | Optional infrastructure gateway |
| `reports` | HTML acceptance reports and screenshots |

## Current scope

The following are intentionally outside the current release scope:

- WalletConnect and DApp browser
- NFT gallery
- Swap
- Staking
- Production store signing and native CI

## Disclosures

- [Privacy Policy](PRIVACY_POLICY.md)
- [Security and Risk](SECURITY_AND_RISK.md)
- [Third-party Notices](THIRD_PARTY_NOTICES.md)
