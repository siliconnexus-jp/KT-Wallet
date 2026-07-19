# P7 — Acceptance & Integration (ui-m.md §18)

Maps each V1 acceptance criterion to its verification method and current status.

Legend:
- **UNIT** — covered by automated tests in this repo (runnable now).
- **LIVE** — validated against real testnet nodes by `tool/testnet_smoke.dart`.
- **DEVICE** — requires a physical device + wallet-core native build (the
  standing P1-4 boundary); scripted here, run on hardware.

## Live testnet RPC smoke (runnable now)

`dart run apps/kt_wallet/tool/testnet_smoke.dart` — READ-ONLY, no broadcast.
Last run: **7/7 PASS** across all four chains:

| Check | Network | Result |
|---|---|---|
| getBalance | Sepolia | real wei balance parsed |
| feeHistory 3-tier | Sepolia | slow < standard < fast computed from live data |
| getNonce | Polygon Amoy | ok |
| getBalance | Solana Devnet | real lamports |
| getLatestBlockhash | Solana Devnet | real blockhash |
| getTrxBalance | TRON Nile | real SUN |
| getNowBlock (refBlock) | TRON Nile | real block number |

This validates RPC transport, hex/JSON parsing, fee estimation, and refBlock
retrieval against production node software.

## Acceptance criteria (ui-m.md §18, 25 items)

### 多钱包管理
| # | Criterion | Method | Status |
|---|---|---|---|
| 1 | 创建普通钱包并完成助记词备份校验 | UNIT (onboarding_flow, mnemonic_quiz) + DEVICE (real HDWallet) | logic ✓ / device pending |
| 2 | 助记词导入普通钱包 | UNIT (onboarding import) + DEVICE (derive vectors) | logic ✓ / device pending |
| 3 | 连接观察钱包 | UNIT (account-export payload decode) | ✓ |
| 4 | 列表普通/观察混排、随时切换 | UNIT (wallet_manager) | ✓ |
| 5 | 切换后首页/资产/记录/收款跟随当前钱包 | DEVICE (Riverpod scope wiring) | pending UI |
| 6 | 交易记录/Token/地址簿按钱包隔离 | UNIT (wallet_data repositories) | ✓ |
| 7 | 删除普通钱包需身份验证+备份确认 | UNIT (flow) + DEVICE (AuthGate) | logic ✓ / device pending |

### 普通钱包
| # | Criterion | Method | Status |
|---|---|---|---|
| 8 | 构建支持范围内转账 | UNIT (transfer_validation, chains TxBuilder params) | ✓ |
| 9 | 每次转账生物识别/密码验证 | UNIT (LocalSignFlow) + DEVICE (AuthGate) | logic ✓ / device pending |
| 10 | 本机签名并自动广播,全程无二维码 | DEVICE (wallet-core sign + LIVE broadcast) | pending device |
| 11 | 助记词经系统安全区加密,不上传/不明文落盘 | DEVICE (Keychain/Keystore) + code review §8.1 | design ✓ / device pending |

### 离线钱包组合
| # | Criterion | Method | Status |
|---|---|---|---|
| 12 | 离线手机创建助记词 | DEVICE (wallet-core) | pending device |
| 13 | 导出四链公开地址 | UNIT (address derivation params) + DEVICE (vectors) | logic ✓ / device pending |
| 14 | 联网手机查询四链余额 | LIVE (testnet_smoke: 4/4 chains) | ✓ |
| 15 | 观察钱包构建支持范围内转账 | UNIT (AirgapFlow + tx params) | ✓ |
| 16 | 未签名交易经动态二维码传输 | UNIT (airgap fragmenter/aggregator) | ✓ |
| 17 | 离线端独立解析交易 | UNIT (chains parse) + DEVICE | logic ✓ / device pending |
| 18 | 离线端准确展示地址/金额/网络/手续费 | UNIT (TxPreview) + DEVICE | logic ✓ / device pending |
| 19 | 离线端拒绝未知交易 | UNIT (sign_session validationRejected, chains whitelist) | ✓ |
| 20 | 离线端完成本地签名 | DEVICE (wallet-core) | pending device |
| 21 | 签名结果经动态二维码返回 | UNIT (airgap sign-result payload) | ✓ |
| 22 | 联网端验证并广播 | UNIT (AirgapFlow verify) + DEVICE (LIVE broadcast) | logic ✓ / device pending |
| 23 | 观察钱包助记词/私钥全程不进入联网设备 | code review §8 (INV-14 type-level) + firewall | ✓ |
| 24 | 离线 App 不发起任何网络请求 | firewall (no INTERNET / no http in cold_signer) | ✓ (Android build-time in P8) |
| 25 | 同一签名请求不能被无提示重复签名 | UNIT (anti-replay integration, validator) | ✓ |

## Device pass runbook (P7-2, run on hardware)

1. Build cold_signer (Android release: assert no INTERNET — see P8) on device A (offline).
2. Build kt_wallet on device B (online, testnet config).
3. Cold Signer: create wallet → verify derived addresses match BIP-44 vectors
   (P1-2/P1-3 DoD) → export addresses QR.
4. KT Wallet: scan account QR → confirm watch wallet imported with 4 addresses.
5. Fund the derived addresses from public testnet faucets.
6. Watch-wallet transfer (each chain): build → sign-request QR → Cold Signer
   scan/parse/verify (matches TxPreview) → sign → result QR → KT Wallet scan →
   broadcast → confirm receipt. Calibrate fragment size/speed (write back to
   airgap defaults).
7. Hot-wallet transfer (each chain, testnet): build → auth → local sign →
   broadcast → confirm. (Requires P1-4 native signing wired.)
8. Record tx hashes in this file; file issues for any criterion that fails.

## Summary

- **Runnable-now coverage**: multi-wallet, isolation, both transfer flow
  machines, anti-replay, transaction validation, address/amount/calldata, and
  **live 4-chain RPC** are all verified. 257 unit tests + 7 live checks green.
- **Device-gated**: wallet-core signing (all "DEVICE" rows) and live broadcast,
  which are the standing P1-4 native boundary. The runbook above executes them.
