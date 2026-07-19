# KT Wallet 详细设计（V1）

上游文档：`ui-m.md`（需求 V2）、`tech-plan.md`（选型与总体架构）。
配套执行文档：`todolist.md`（任务清单与 review 门禁）。

---

# 1. 模块总览

## 1.1 依赖图

```
apps/kt_wallet ──────┬── packages/core_crypto
                     ├── packages/airgap_protocol
                     ├── packages/chains        (tx + rpc)
                     └── packages/ui_kit

apps/cold_signer ────┬── packages/core_crypto
                     ├── packages/airgap_protocol
                     ├── packages/chains        (仅 tx/ 解析部分)
                     └── packages/ui_kit
```

硬性约束（CI 强制）：

* `cold_signer` 禁止依赖 `chains/rpc`、任何 HTTP 库；Android Manifest 不声明 INTERNET 权限。
* `core_crypto` 之外的任何 Dart 包不得 import wallet-core 相关符号。
* 助记词字符串类型只允许出现在 `core_crypto` API 边界与三个 onboarding 页面文件中（lint 自定义规则扫描）。

## 1.2 模块间数据流（转账为例）

```
普通钱包:  chains/tx 构建 SigningInput → core_crypto.signTransaction → chains/rpc 广播
观察钱包:  chains/tx 构建 SigningInput → airgap_protocol 打包 sign-request 二维码
           → (Cold Signer: airgap_protocol 解析 → chains/tx 反解展示 → core_crypto 签名 → sign-result 二维码)
           → kt_wallet: airgap_protocol 解析 → 校验 → chains/rpc 广播
```

---

# 2. packages/core_crypto（wallet-core 桥）

Flutter plugin。Dart 侧薄封装，iOS/Android 原生侧承载全部密钥操作。

## 2.1 Platform Channel 协议

Channel：`kt/core_crypto`（MethodChannel，JSON 编码）。

| 方法 | Request | Response | 备注 |
| --- | --- | --- | --- |
| `generateMnemonic` | `{strength: 128\|192\|256}` | `{mnemonic}` | 仅创建流程 |
| `validateMnemonic` | `{mnemonic}` | `{valid: bool}` | |
| `validateWord` | `{word}` | `{valid: bool}` | BIP-39 词表 |
| `suggestWords` | `{prefix, limit=3}` | `{words: []}` | |
| `storeWallet` | `{walletId, mnemonic, requireAuth: bool, kdfPassword?}` | `{ok}` | kdfPassword 仅 Cold Signer 传 |
| `deriveAddresses` | `{walletId}` | `{eth, polygon, tron, solana}` | eth==polygon |
| `signTransaction` | `{walletId, coin: "eth"\|"polygon"\|"tron"\|"solana", signingInput: base64}` | `{signedTx: base64, txHash: hex}` | 触发原生身份验证 |
| `exportMnemonic` | `{walletId}` | `{mnemonic}` | 强制身份验证，无免验证路径 |
| `deleteWallet` | `{walletId}` | `{ok}` | 强制身份验证 + 安全擦除 |
| `getAuthState` | `{}` | `{locked: bool, failCount, cooldownSec}` | 供 UI 展示锁定状态 |

错误码（PlatformException.code）：

| 错误码 | 含义 | UI 处理 |
| --- | --- | --- |
| `AUTH_FAILED` | 单次验证失败 | 提示重试，展示剩余次数 |
| `AUTH_LOCKED` | 连续失败进入冷却 | 展示倒计时，禁用操作 |
| `AUTH_CANCELLED` | 用户取消验证 | 静默返回 |
| `WALLET_NOT_FOUND` | walletId 不存在 | 引导刷新钱包列表 |
| `INVALID_MNEMONIC` | 助记词校验失败 | 表单错误态 |
| `INVALID_INPUT` | SigningInput 解析失败 | 上报 + 通用错误页 |
| `SIGN_FAILED` | wallet-core 签名异常 | 通用错误页 |
| `STORE_CORRUPTED` | 密文解密失败/完整性破坏 | 红色警告，引导重新导入 |
| `BIOMETRY_CHANGED` | 生物识别集变更导致密钥失效 | 要求密码重新绑定 |

## 2.2 原生侧结构

**iOS（Swift）**

* `KeychainStore`：entropy 密文读写。`kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` + `SecAccessControl(biometryCurrentSet)`。
* `WalletCoreBridge`：TrustWalletCore 调用（HDWallet、AnySigner）。
* `AuthGate`：LocalAuthentication 封装 + 失败计数/冷却（计数持久化在 Keychain，防重装绕过按产品决策：卸载即清）。
* `CryptoPlugin`：channel 分发，参数校验。

**Android（Kotlin）**

* `KeystoreManager`：AES-256-GCM 密钥（`setIsStrongBoxBacked(true)` 降级 TEE），`setUserAuthenticationRequired(true)`、`setInvalidatedByBiometricEnrollment(true)`。
* `EncryptedStore`：entropy 密文 → EncryptedFile。
* `WalletCoreBridge` / `AuthGate`（BiometricPrompt）/ `CryptoPlugin`：同 iOS 职责。

**Cold Signer 双层加密**：`storeWallet` 携带 `kdfPassword` 时，entropy 先经 Argon2id（m=64MB, t=3, p=4，盐随机 16B）派生密钥 XChaCha20-Poly1305 加密，再进 Keystore/Keychain 层。解密顺序相反，两层都必须通过。

## 2.3 密钥生命周期（五条路径）

1. **创建**：generateMnemonic（原生生成，返回 Dart 展示）→ 用户备份/校验（Dart UI）→ storeWallet → Dart 侧引用置空。
2. **导入**：Dart 收集单词 → storeWallet（原生内 validate + entropy 转换）→ 置空。
3. **签名**：signTransaction → AuthGate 验证 → 解密 entropy → HDWallet 派生 → AnySigner.sign → **entropy/私钥 buffer 立即 memset 清零** → 返回签名字节。
4. **查看助记词**：exportMnemonic → 强验证 → 返回 → UI 展示页关闭时置空。
5. **删除**：deleteWallet → 强验证 → Keychain/文件删除 + 密文覆写 → 相关 Keystore 别名删除。

内存清零点：原生侧所有 entropy/seed/privateKey 的字节缓冲在使用后立即清零；Swift 用 `withUnsafeMutableBytes` + `memset_s`，Kotlin 用 `ByteArray.fill(0)`（并避免 String 化 seed）。

## 2.4 锁定策略

* 连续验证失败 5 次 → 冷却 60s；再失败 5 次 → 300s；再 → 900s（上限）。
* 冷却期内所有需验证方法直接抛 `AUTH_LOCKED`。
* Cold Signer 侧密码输错计数独立于生物识别计数。

---

# 3. packages/airgap_protocol

## 3.1 Payload 定义（CBOR，definite-length）

公共头（所有 payload）：

| 字段 | key | 类型 | 约束 |
| --- | --- | --- | --- |
| version | 0 | uint | 恒为 1，≠1 拒绝 |
| type | 1 | uint | 1=account-export, 2=sign-request, 3=sign-result |

`account-export`（type=1）：

| 字段 | key | 类型 | 约束 |
| --- | --- | --- | --- |
| walletId | 2 | tstr | ≤32B |
| walletName | 3 | tstr | ≤64B |
| accounts | 4 | array | 1..8 项 |
| accounts[i] | | map | {coin: uint, address: tstr≤128, path: tstr≤64, index: uint} |

`sign-request`（type=2）：

| 字段 | key | 类型 | 约束 |
| --- | --- | --- | --- |
| reqId | 2 | bstr(8) | 随机 64bit |
| walletId | 3 | tstr | 必须匹配本机钱包 |
| coin | 4 | uint | 60/195/501 (SLIP-44) + polygon 用 60+chainId 字段 |
| chainId | 5 | uint? | EVM 专用 |
| rawTx | 6 | bstr | ≤32KB，未签名交易/SigningInput 字节 |
| summary | 7 | map | 展示对账用（to/amount/token），**不作为签名依据** |
| createdAt | 8 | uint | epoch 秒 |
| expiresAt | 9 | uint | ≤ createdAt+3600 |

`sign-result`（type=3）：reqId、walletId、coin、signedTx(bstr≤34KB)、signer(tstr)、txHash(tstr)。

## 3.2 分片格式（每帧二维码内容）

二进制布局，Base64URL 后进二维码（alphanumeric 模式不适用，用 byte 模式）：

```
magic   2B  "KT"
ver     1B  0x01
reqId   8B  （account-export 用 walletId 哈希前 8B）
seq     2B  从 0
total   2B  1..256
crc32   4B  整个 payload（重组后）的 CRC32
chunk   ≤400B
```

* 单片 chunk 默认 400B（实测中端机扫码成功率标定后可调 200-600）。
* total 上限 256 片；payload 重组上限 64KB；超限编码时报错、解码时拒绝。
* 播放速度：慢 600ms / 标准 350ms / 快 200ms 帧间隔，循环播放。

## 3.3 接收聚合器状态机

```
idle → receiving(收到首个合法帧, 锁定 reqId/total)
receiving: 帧 reqId 不匹配 → 忽略并计数“异常帧”
           seq 重复 → 去重, 上报 duplicateCount
           收齐 total → assembling
assembling: 拼接 → CRC 校验失败 → failed(CRC_MISMATCH)
            CBOR 解码失败 → failed(DECODE_ERROR)
            约束校验失败(字段超限/未知版本) → failed(SCHEMA_VIOLATION)
            成功 → done(payload)
任意态: reset() → idle
```

进度回调：`(received, total, duplicates)`。

## 3.4 防重放判定（Cold Signer 侧，收到 sign-request 后）

顺序执行，任一失败即拒绝并给出对应文案（ui-m.md §9.3）：

1. version/type 合法
2. walletId == 本机钱包
3. now < expiresAt 且 createdAt 合理（±10min 时钟容差）
4. reqId 不在本地记录（已扫描/已签名/已拒绝/已过期表）
5. rawTx 可被 chains/tx 完整解析，且解析结果与 summary 一致（不一致 → 高风险警告，以解析结果展示）
6. 交易类型在 V1 允许清单内（否则进"风险警告页"，禁止签名）

---

# 4. packages/chains

## 4.1 Amount 值类型

```dart
class Amount { final BigInt raw; final int decimals; final String symbol; }
```

* 全库禁止 double 参与金额运算（lint 自定义规则）。
* `parse("120.5", decimals)` / `format(maxFraction)` / 加减比较；溢出与负值抛异常。

## 4.2 TxBuilder → SigningInput 映射

每链一个 builder，输出 wallet-core SigningInput protobuf 字节 + 人类可读的 `TxPreview`（确认页数据源）。同一个包供 Cold Signer 反向解析（`parse(rawTx) → TxPreview`）。

**EVM（Ethereum chainId=1, Polygon chainId=137）**

| 输入 | SigningInput 字段 |
| --- | --- |
| 原生转账 | toAddress, transaction.transfer.amount |
| ERC-20 | toAddress=合约地址, transaction.erc20_transfer.{to, amount} |
| 手续费 | maxFeePerGas, maxInclusionFeePerGas (EIP-1559), gasLimit |
| nonce/chainId | nonce, chainId |

**TRON（coin=195）**

| 输入 | SigningInput 字段 |
| --- | --- |
| TRX | transfer_contract.{owner, to, amount(SUN)} |
| TRC-20 | trigger_smart_contract（transfer(address,uint256) calldata 由 builder 组装） + fee_limit |
| 时效 | ref_block_bytes/hash（取自 getnowblock）、expiration=now+10min、timestamp |

**Solana（coin=501）**

| 输入 | SigningInput 字段 |
| --- | --- |
| SOL | transfer.{recipient, value(lamports)} |
| SPL | token_transfer.{token_mint, to_token_address, amount, decimals}（TransferChecked）；收款 ATA 不存在时 create_and_transfer_token_transaction |
| 时效 | recent_blockhash；观察钱包流程改用 durable nonce（nonce_account + advance） |

V1 允许解析/签名的交易类型白名单 = 上表全集；其余（approve/permit/未知 calldata/未知 Program）→ 拒绝（ui-m.md §9.5-9.7）。

## 4.3 RPC 客户端（仅 kt_wallet）

接口 + 实现分离，测试用录制响应（fixture JSON）注入。

```dart
abstract class EvmRpc   { getBalance; erc20Balance; feeEstimate; getNonce; sendRaw; getReceipt; }
abstract class TronRpc  { getAccount; getResources; trc20Balance; getNowBlock; broadcast; getTxInfo; }
abstract class SolanaRpc{ getBalance; getTokenAccounts; getLatestBlockhash; sendTx; getSignatureStatuses; getNonceAccount; }
```

* 超时 10s；幂等查询重试 2 次（指数退避 500ms/1500ms）；**广播不自动重试**（防双花，失败交给用户显式重试，nonce/blockhash 复用）。
* 手续费三档：EVM 用 feeHistory p25/p50/p90；TRON 按资源估算 Energy×单价 三档 fee_limit；Solana base fee + priority fee 三档（0/中位/加急）。

---

# 5. 数据层（drift，仅 kt_wallet；cold_signer 仅 sign_records 一张表）

## 5.1 表结构

```
wallets        (id PK, name, type: hot|watch, avatarColor, sortOrder,
                backedUp bool, coldWalletId?, protocolVer?, createdAt)
accounts       (walletId FK, coin, address, derivationPath, accountIndex,
                PK(walletId, coin))
tokens         (walletId, coin, contract?, symbol, decimals, name,
                enabled bool, trusted bool, PK(walletId, coin, contract))
balances       (walletId, coin, contract?, raw TEXT/*BigInt*/, fiat REAL?,
                updatedAt, PK 同 tokens)
transactions   (id PK, walletId, reqId?, coin, contract?, direction,
                fromAddr, toAddr, amountRaw TEXT, feeRaw TEXT?, hash?,
                status: draft|awaiting_sig|signed|broadcast|confirmed|failed|expired,
                signMode: local|airgap, memo?, createdAt, broadcastAt?)
address_book   (id PK, walletId, name, address, coin, createdAt)
sign_requests  (reqId PK, walletId, coin, rawTx BLOB, expiresAt,
                status: pending|scanned|signed|broadcast|cancelled|expired)
settings       (key PK, value)          -- 全局项
wallet_settings(walletId, key, value, PK(walletId, key))
```

* 索引：transactions(walletId, createdAt DESC)、balances(walletId)。
* 隔离规则：所有查询必须经 Repository 层，Repository 构造时绑定 walletId；不存在跨钱包查询 API（仅 WalletRepository.listAll 例外）。
* 金额一律 TEXT 存 BigInt 十进制字符串。
* 迁移：schemaVersion 从 1 起，migration 测试覆盖每个版本跳变。

cold_signer 的 `sign_records`：reqId PK, date, coin, opType, toAddr, amountRaw, status(signed|rejected|expired)。无任何密钥相关字段（ui-m.md §14.1）。

---

# 6. apps/kt_wallet 应用层

## 6.1 Provider 图（Riverpod）

```
appDatabaseProvider
walletsProvider                     // 全部钱包（切换器/管理页）
currentWalletIdProvider (StateNotifier, 持久化到 settings)
currentWalletProvider = watch(wallets, currentWalletId)
-- 以下全部 family by walletId, UI 通过 currentWallet 间接消费 --
accountsProvider(walletId)
balancesProvider(walletId)          // 聚合刷新: 并发拉四链, 单链失败不阻塞
txHistoryProvider(walletId)
priceProvider                       // 全局, 15s 缓存
transferFlowProvider                // 每次转账新建, autoDispose
```

切换钱包 = 更新 currentWalletIdProvider，全部 family provider 自然切换（满足 ui-m.md §6.2 全局生效）。

## 6.2 路由表（go_router，对应 Pencil 屏幕）

| 路由 | 屏幕（设计稿编号） |
| --- | --- |
| /splash, /onboarding/* | W10, W11, W22, W23, W24, W25, W26, W12, W13 |
| /home | W1（观察）/ W20（普通）同一路由按 wallet.type 渲染 |
| /wallets (sheet), /wallets/manage, /wallets/:id | W21, W27, W28 |
| /assets, /token/:id, /receive | W2, W3, W14 |
| /transfer, /transfer/confirm, /transfer/auth (sheet) | W4, W5(观察)/W29(普通), W30 |
| /airgap/qr, /airgap/scan, /airgap/broadcast | W6, W7, W8 |
| /result/:txId, /tx/:id | W9, W15 |
| /settings/*（address-book, tokens, network, security） | W16-W19 |

## 6.3 转账双流程状态机

**LocalSignFlow（普通钱包）**

```
draft → confirming(费率/余额校验通过)
confirming --confirm--> authenticating
authenticating --ok--> signing --ok--> broadcasting --ok--> done(hash)
authenticating --AUTH_LOCKED/CANCELLED--> confirming(带错误)
signing/broadcasting --error--> failed(可重试: 复用 nonce/blockhash 重建)
```

**AirgapFlow（观察钱包）**

```
draft → confirming → qrDisplaying(生成 sign-request, 写 sign_requests 表)
qrDisplaying --扫描签名结果--> scanningResult
scanningResult --聚合完成--> verifying
verifying: reqId/walletId/coin/签名者==账户地址/未过期 全过 → broadcastConfirm
verifying --失败--> scanningResult(错误提示)
broadcastConfirm --广播--> broadcasting → done | failed
qrDisplaying/scanningResult --取消--> cancelled(sign_requests 置 cancelled)
过期定时器: 任意态 expiresAt 到 → expired
```

## 6.4 错误 → 文案映射

集中在 `lib/errors/error_mapper.dart`：RPC 超时/断网/余额不足/手续费不足/地址格式/错误网络地址（如 TRON 地址填进 ETH 转账）/Blockhash 过期/Energy 不足/AUTH_* 系列 → ui-m.md §8.10 风险清单与 §11 页面状态的对应文案。未映射错误统一"出错了"页 + 错误码。

---

# 7. apps/cold_signer 应用层

## 7.1 路由表

| 路由 | 屏幕 |
| --- | --- |
| /splash, /welcome | C11, C1 |
| /security-check | C2 |
| /onboarding/{warn,mnemonic,verify,import,pin,biometric,done} | C12, C3, C4, C13, C14, C15, C16 |
| /home | C5 |
| /scan, /parse, /risk, /auth, /result | C6, C7, C17, C8, C9 |
| /export, /records, /wallet, /settings, /delete | C10, C18, C19, C20, C21 |

## 7.2 安全检查引擎

```dart
enum CheckLevel { pass, warn, block }
class SecurityCheck { id; probe(); level(result); }
```

| 检查项 | 探测方式 | 异常等级 |
| --- | --- | --- |
| 网络可达（Wi-Fi/蜂窝） | NWPathMonitor / ConnectivityManager | block |
| 飞行模式 | 平台 API（Android 可读；iOS 由网络可达推断） | warn |
| 蓝牙开启 | CoreBluetooth state / BluetoothAdapter | warn |
| 设备密码未设置 | LAContext canEvaluate / KeyguardManager | block |
| 生物识别未启用 | 同上 | warn |
| 屏幕录制中 | UIScreen.isCaptured / MediaProjection 回调 | block |
| root/越狱迹象 | 常规探测集 | warn |

* 任一 block → 全局禁止进入 /scan 与签名路径（路由守卫）。
* 结果驱动 C2 页与 C5 首页安全状态条。

## 7.3 签名会话状态机

```
scanning(聚合器 receiving) → validating(§3.4 六步) 
validating --白名单外交易--> riskBlocked(C17, 记录 rejected)
validating --通过--> reviewing(C7, 展示 parse(rawTx) 的 TxPreview)
reviewing --拒绝--> rejected(记录)
reviewing --确认--> authenticating(C8) --ok--> signed
signed → resultDisplaying(C9, sign-result 分片播放, 记录 signed)
resultDisplaying --作废--> voided(记录保持 signed 但标记 voided, reqId 永久拒绝)
```

---

# 8. 安全不变量清单（Review 门禁 checklist）

每个模块 review 时逐条核对，任何一条不满足即 blocking finding：

**core_crypto**
1. 助记词/entropy/seed/私钥不出现在：日志、异常消息、持久化（除密文）、Dart 状态管理对象。
2. 每条含密钥内存的原生代码路径都有清零语句，且在 early-return/throw 路径同样覆盖。
3. signTransaction / exportMnemonic / deleteWallet 无任何绕过 AuthGate 的调用路径。
4. Android 密钥 `setUserAuthenticationRequired(true)`；iOS 访问控制含 biometryCurrentSet。
5. Cold Signer 存储路径两层加密均生效（单层通过即失败的测试存在）。

**airgap_protocol**
6. 所有解码路径对任意字节输入不崩溃（fuzz 测试在测试套内且通过）。
7. 所有上限（分片数/payload 尺寸/字段长度）有拒绝分支与测试。
8. 展示信息以 rawTx 解析结果为准，summary 仅对账（代码中无 summary 直出 UI 的路径）。

**chains**
9. 金额路径无 double；BigInt 字符串化往返无损。
10. 白名单外交易类型 parse 返回明确的 Unsupported 结果而非静默忽略。

**数据层**
11. Repository 之外无裸 SQL/DAO 访问；所有业务表查询绑定 walletId。

**cold_signer**
12. 包依赖不含网络能力；Android Manifest 无 INTERNET；无 WebView/统计/推送。
13. reqId 记录先落库后展示结果二维码（崩溃也不会导致重签窗口）。

**kt_wallet**
14. 观察钱包代码路径不可能调用 signTransaction（类型层面隔离：WatchWallet 无签名能力接口）。
15. 广播失败不自动重试。
16. 助记词相关页面路由退出时清理内存引用，Android 挂 FLAG_SECURE。

---

# 9. 测试基建约定

* `packages/*/test/fixtures/`：测试向量 JSON（BIP-39 Trezor 向量、各链已知地址、主网真实交易字节、录制 RPC 响应）。
* core_crypto 提供 `MockCoreCrypto`（内存实现，确定性密钥）供 app 层测试。
* 原生侧逻辑（锁定策略、加密封装）用 XCTest / Robolectric 单测；wallet-core 调用正确性主要通过 Dart 集成测试（真机/模拟器 instrumented）+ 固定向量验证。
* 状态机测试模式：枚举全部 (状态, 事件) 组合，非法迁移必须抛错（表驱动测试）。
