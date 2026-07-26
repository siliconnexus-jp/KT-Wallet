# KT-Wallet

Open-source air-gapped multi-chain wallet for **Ethereum, Polygon, Base,
Arbitrum, Avalanche, TRON, and Solana**.

<p align="center">
  <img src="branding/kt-wallet-logo-256.png" width="160" alt="KT Wallet logo">
</p>

## Open source

Source code, issues, and releases:
[github.com/siliconnexus-jp/KT-Wallet](https://github.com/siliconnexus-jp/KT-Wallet)

## One installer, two roles

KT Wallet ships as a **single app** (`apps/kt_wallet`). On first launch you choose
what this phone is:

- **联网钱包 / Online Wallet** — everyday use: multi-wallet management, balances,
  transfers, broadcasting. Holds public addresses (watch wallets) and optional
  hot wallets for small amounts.
- **离线签名器 / Offline Signer** — install on a phone that never goes online.
  The recovery phrase is generated, stored, and used for signing only on this
  device; it communicates with the online phone exclusively by scanning QR codes.

The choice persists across restarts and can be changed later from Settings
(mode data is kept — switching back does not wipe wallets). Picking "Offline
Signer" is gated behind an air-gap warning, and the signer welcome screen keeps
an escape hatch back to the picker so a mis-tap never forces onboarding.

For maximum isolation, `apps/cold_signer` still builds as its **own standalone
app** — the combined installer embeds the same package.

### How a transfer works (air-gapped)

```
kt_wallet (online)                 cold_signer (offline)
    build tx → show QR   ── 📷 ──▶  parse & display tx
                                    verify password → sign with local key
    verify sig → broadcast ◀─ 📷 ── show signature QR
```

The only channel between the two devices is optical (QR), carried by the
`airgap_protocol` package. Watch wallets have no signing capability at the type
level — the online app cannot sign for them even in principle.

## Languages

Fully localized in **简体中文 (base), English, and 日本語** — follows the system
language with a persisted manual override in Settings (both roles).

## Chain capabilities

| Chain | Live balance | Native transfer | Token transfer | Direct history |
|---|---:|---:|---:|---:|
| Ethereum | ✅ | ✅ | ERC-20 | ✅ Blockscout |
| Polygon | ✅ | ✅ | ERC-20 | ✅ Blockscout |
| Base | ✅ | ✅ | ERC-20 | ✅ Blockscout |
| Arbitrum | ✅ | ✅ | ERC-20 | ✅ Blockscout |
| Avalanche C-Chain | ✅ | ✅ | ERC-20 | ✅ Routescan |
| TRON | ✅ | ✅ TRX | TRC-20 | ✅ TronGrid |
| Solana | ✅ | ✅ SOL | SPL | ✅ Solana RPC |

Hot wallets sign on-device through Trust Wallet Core on Android and iOS.
Watch-only wallets continue to use the QR air-gap flow. Production screens do
not seed sample wallets, balances, assets, or successful transactions. If all
configured RPC endpoints fail, the UI reports the network error instead of
substituting demo values.

The table describes implemented transaction families, not a guarantee that
every public testnet endpoint or faucet is currently available. EVM sends use
live nonce, fee history and gas estimation. TRC-20 sends estimate energy and
derive `feeLimit` from current resources. Solana sends use a fresh blockhash,
`getFeeForMessage` and node simulation. SPL transfers currently require the
recipient token account to already exist; automatic associated-token-account
creation is not yet implemented.

Public RPC calls use bounded timeouts and per-network fallbacks. A custom RPC
selected in Settings remains authoritative and is never silently replaced.
Transaction history no longer requires the optional KT Gateway; the gateway can
still be configured as an infrastructure override.

## Repository layout

| Path | What it is |
|---|---|
| `apps/kt_wallet` | The shipping app: mode picker + online wallet + embedded signer |
| `apps/cold_signer` | The signer, also independently buildable/installable |
| `packages/core_crypto` | Trust Wallet Core bridge (mnemonic / derivation / signing) |
| `packages/wallet_data` | drift (SQLite) persistence layer |
| `packages/airgap_protocol` | QR transport protocol between the two roles |
| `packages/chains` | Per-chain RPC / tx assembly |
| `packages/ui_kit` | Shared design system (1:1 with the Pencil design in `ui.pen`) |

## Building & testing

See [BUILDING.md](BUILDING.md) for build instructions (including the wallet-core
Android setup and release signing). Run the test suites from each package/app directory with
`flutter test`; golden tests replicate the Pencil design (including its mock
status bar — the real apps suppress it via `KtDeviceChrome`).

Privacy, security and dependency disclosures are in
[PRIVACY_POLICY.md](PRIVACY_POLICY.md),
[SECURITY_AND_RISK.md](SECURITY_AND_RISK.md), and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
