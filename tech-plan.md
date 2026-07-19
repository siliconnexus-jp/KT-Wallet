# KT Wallet 技术实现方案（V1）

对应需求文档：`ui-m.md`（V2）。

交付目标：iOS + Android 双端，两个 App：

* KT Wallet（联网多钱包 App：普通钱包 + 观察钱包）
* Cold Signer（离线签名 App）

支持链：Ethereum、Polygon、TRON、Solana。

---

# 1. 选型决策

## 1.1 结论

**两个 App 都使用 Flutter 开发；链上密码学（助记词、派生、交易构建与签名）全部交给 Trust Wallet Core（经审计的 C++ 库）；密钥存储、生物识别、防截屏等安全敏感面用原生平台代码实现。**

一句话版本：

* Flutter 负责 UI 和业务流程。
* wallet-core 负责一切碰到私钥的计算。
* iOS/Android 原生层负责一切碰到系统安全能力的部分。

若未来改为只做 iOS：直接用 SwiftUI 原生 + wallet-core（SPM 集成），其余架构不变。

## 1.2 方案对比

| 维度 | 双原生 Swift+Kotlin | Flutter（选定） | React Native | KMP + Compose MP |
| --- | --- | --- | --- | --- |
| 代码库数量（2 App × 2 端） | 4 套 | 2 套 | 2 套 | 2.5 套（共享逻辑 + 双 UI） |
| 开发与维护成本 | 最高，翻倍 | 低 | 低 | 中 |
| 密钥安全 | 最好 | 好（密钥不进 Dart 长期持有） | 差：密钥材料进 JS 堆，无法主动清零 | 好 |
| 依赖供应链风险 | 低 | 低（pub 依赖可控制在个位数） | 高：npm 供应链攻击近年集中打击加密钱包 | 低 |
| 离线可证明性（Cold Signer） | 好 | 好（Android 可不声明 INTERNET 权限） | 差：JS 运行时 + 庞大依赖树进入签名器 | 好 |
| UI 还原度（对齐 Pencil 设计稿） | 好但要做两遍 | 最好，双端像素一致 | 好 | iOS 侧欠成熟 |
| 链上生态 | Swift/Kotlin 链库较弱 | Dart 链库弱，但被 wallet-core 补齐 | 最强（viem/solana-web3/tronweb） | 弱 |
| AI 开发友好度 | 中（两套语言语料） | 高 | 高 | 低（语料薄） |

排除理由小结：

* 双原生：4 个交付目标，成本与安全审查面都翻倍；二维码协议、业务逻辑要实现两遍并保持一致，风险大于收益。
* React Native：JS 生态优势在本方案中用不上（签名都在 wallet-core），而它的两个缺点——密钥进 JS 堆、npm 供应链风险——恰好打在钱包产品最痛的地方。离线签名器里放一个 JS 运行时不符合"最小攻击面"原则。
* KMP：方向不错但 iOS 侧成熟度、AI 语料、wallet-core cinterop 的坑都偏多，不适合 AI 主导的开发方式。

## 1.3 为什么是 Trust Wallet Core

* 开源、经安全审计、Trust Wallet 亿级用户在用。
* 原生覆盖本项目全部四条链，且不只是密钥派生——**交易构建 + 签名**（protobuf SigningInput）都在库内完成：
  * Ethereum / Polygon：EIP-1559、Legacy、ERC-20 transfer calldata
  * TRON：TransferContract、TRC-20 TriggerSmartContract、refBlock/expiration
  * Solana：System Transfer、SPL Token Transfer/TransferChecked、ATA 创建
* 官方提供 iOS（SPM/CocoaPods）与 Android（Maven）绑定。
* 结果：Dart 层不需要任何重型链库，只做 HTTP RPC 查询与广播。这直接消解了"Flutter 链上生态弱"的短板。

---

# 2. 总体架构

## 2.1 Monorepo 布局

```
KT-Wallet/
├── apps/
│   ├── kt_wallet/          # 联网 App（Flutter）
│   └── cold_signer/        # 离线 App（Flutter）
├── packages/
│   ├── core_crypto/        # wallet-core 桥（Flutter plugin：iOS Swift + Android Kotlin）
│   ├── airgap_protocol/    # 二维码分片协议（纯 Dart，双 App 共享）
│   ├── chains/             # 链参数构建 + RPC 客户端（纯 Dart）
│   └── ui_kit/             # 设计 tokens 与共享组件
├── ui-m.md
└── tech-plan.md
```

* 用 melos（或 pub workspace）管理 monorepo。
* `cold_signer` 只允许依赖 `core_crypto`、`airgap_protocol`、`ui_kit`，**禁止依赖 `chains` 的 RPC 部分**（CI 用依赖检查强制）。

## 2.2 packages/core_crypto（wallet-core 桥）

Flutter plugin，通过 platform channel 调用官方原生绑定（起步不用 FFI，见 §9 风险）。

Dart 侧 API（全部无状态，密钥不出原生层）：

```
generateMnemonic(strength) -> mnemonic          // 仅创建流程调用
validateMnemonic(mnemonic) -> bool
validateWord(word) -> bool                      // BIP-39 单词逐词校验
suggestWords(prefix) -> [word]                  // 导入时的候选词
storeWallet(walletId, mnemonic, auth)           // 写入原生安全存储，此后 Dart 不再接触
deriveAddresses(walletId) -> {chain: address}   // ETH/Polygon 共用地址
signTransaction(walletId, chain, signingInput) -> signedBytes
exportMnemonic(walletId, auth) -> mnemonic      // 仅"查看助记词"流程，需强验证
deleteWallet(walletId, auth)
```

约定：

* `signingInput` 是 wallet-core 的 SigningInput protobuf 字节，由 `chains` 包在 Dart 侧组装参数、原生层填入并执行。
* 助记词字符串只在两类 UI 流程短暂经过 Dart 层：创建/备份展示、导入输入、查看助记词。其余全部生命周期只存在于原生层与安全存储。

## 2.3 packages/chains

纯 Dart，两部分：

* `tx/`：把用户输入转成各链 SigningInput 参数（金额精度、ERC-20 calldata 参数、TRON feeLimit、Solana blockhash 等）。双 App 共享（离线端解析展示交易也用它）。
* `rpc/`：仅 kt_wallet 引用。见 §6。

## 2.4 packages/airgap_protocol

纯 Dart。二维码分片协议编解码 + 解析校验。见 §5。

## 2.5 packages/ui_kit

* 设计 tokens 从 Pencil 设计稿变量直接翻译：`w-*`（联网端浅色）与 `c-*`（离线端深色）两套色板、Inter + JetBrains Mono 字体、间距与圆角。
* 共享组件：按钮、明细行、网络徽章、钱包类型徽章、二维码卡片、分片进度条等（与设计稿组件一一对应）。

---

# 3. 密钥安全设计

## 3.1 存储模型（两个 App 相同的底座）

存储的是助记词 entropy（不是明文助记词字符串），加密后落盘：

**iOS**

* Keychain item：`kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`
* Access Control：`biometryCurrentSet`（换脸/换指纹后失效，强制重新验证身份）
* 说明：Secure Enclave 只支持 P-256，无法直接保管 secp256k1/ed25519 种子。SE 在本方案中的角色是**门禁**（Keychain 访问控制由 SE 背书），不是保险箱本体。文档与宣传措辞需准确，避免夸大。

**Android**

* Android Keystore 生成 AES-256-GCM 密钥（StrongBox 可用则优先，否则 TEE）
* `setUserAuthenticationRequired(true)` + 生物识别/凭据绑定
* entropy 用该密钥加密后存 EncryptedFile / DataStore
* Keystore 密钥不可导出，设备锁屏凭据变更策略与 iOS 对齐

## 3.2 签名路径（关键不变量）

```
Dart（业务层）
  └─ signTransaction(walletId, chain, signingInput)
       └─ 原生层：身份验证 → 从安全存储解密 seed
            └─ wallet-core：派生 + 签名（内存中，用后清零）
                 └─ 返回已签名字节 → Dart 只拿到可公开数据
```

* Dart 层永远拿不到 seed / 私钥。
* 每次签名必须先通过系统级身份验证（ui-m.md §8.11 / §9.8）。
* 验证失败计数与锁定冷却在原生层实现，Dart 只收状态。

## 3.3 Cold Signer 附加要求

* App 密码经 Argon2id KDF 派生密钥，与 Keystore/Keychain 密钥**双层加密** entropy（防设备锁被绕过的纵深防御）。
* 每次签名：生物识别或 App 密码，V1 强制不可关闭。
* 删除钱包按 ui-m.md §15.2 五步流程，最后调用原生层安全擦除。

## 3.4 普通钱包附加要求（ui-m.md §13.3 落地）

* 助记词展示/备份页：Android 加 `FLAG_SECURE`；iOS 无法阻止截屏，用 `userDidTakeScreenshotNotification` 检测并弹警告。
* 剪贴板：全局禁止写入助记词；导入粘贴为唯一例外，解析成功后立即 `Clipboard.setData('')` 清空。
* 未备份状态持久化在钱包元数据中，驱动全链路提醒（首页横幅 → 列表红点 → 转账前警告）。

---

# 4. 离线保障（Cold Signer）

* **Android：Manifest 不声明 INTERNET 权限。** 系统层面保证进程无法发起网络请求，这是可向用户证明的离线承诺，作为核心卖点写入产品说明。
* iOS 无法移除网络能力，对策：
  * 代码零网络调用（依赖清单可审计）
  * `NWPathMonitor` 监测网络状态，驱动"离线安全检查页"（ui-m.md §9.2）的飞行模式/Wi-Fi/蜂窝检查项，联网时按等级警告或禁止签名
* 依赖白名单（cold_signer 的全部第三方依赖）：

| 依赖 | 用途 |
| --- | --- |
| TrustWalletCore（原生） | 密码学 |
| mobile_scanner | 扫码（MLKit / AVFoundation） |
| qr_flutter | 二维码渲染 |
| drift 或 sqflite | 签名记录（非敏感） |
| local_auth | 生物识别入口 |
| flutter_riverpod | 状态管理 |

* 无广告/统计/推送/WebView SDK（ui-m.md §13.1 逐条对应）。CI 检查 pubspec.lock 白名单外依赖直接失败。

---

# 5. 二维码分片协议（AIRGAP-V1）

## 5.1 选型

优先评估 BlockchainCommons BC-UR 标准（`ur:` URI + fountain code）在 Dart 的可用实现；若无维护良好的实现，按下述自研简化协议（保留将来迁移 BC-UR 的字段兼容性）。

## 5.2 Payload 类型（CBOR 编码）

1. `account-export`：协议版本、walletId、账户名、[{chain, address, derivationPath, accountIndex}]
2. `sign-request`：协议版本、reqId、walletId、chain、原始未签名交易字节、构建参数摘要、createdAt、expiresAt
3. `sign-result`：协议版本、reqId、walletId、chain、已签名交易字节、签名者地址、txHash

## 5.3 分片与播放

* 分片头：`{reqId, seq, total, crc32}`，单片数据量以中端手机扫码成功率标定（初始 ~400 bytes/片，实测调整）。
* 循环播放，三档速度（慢/标准/快）对应帧间隔（如 600/350/200ms），可暂停。
* 接收端：按 seq 去重聚合，实时上报进度（已收/总数/重复提示），全部收齐后 CRC 校验再解码。

## 5.4 安全校验（离线端强制，对应 ui-m.md §9.3/§13.4/§13.5）

* 只接受 AIRGAP-V1 协议与已知 payload 类型；未知版本拒绝。
* 总数据量、分片数上限；过期（expiresAt）拒绝。
* reqId 查本地记录：已签名/已拒绝的重复请求拒绝并提示。
* 交易内容以**离线端独立解析原始交易字节**为准展示（不信任请求中的摘要字段，摘要仅用于对账提示不一致时告警）。

---

# 6. KT Wallet 联网层

纯 Dart HTTP（`dart:io` + 少量封装），不引入重型链 SDK。

## 6.1 各链 RPC

**EVM（Ethereum / Polygon，JSON-RPC）**

* 余额：`eth_getBalance`；ERC-20：`eth_call` balanceOf
* 手续费：`eth_feeHistory` + `eth_maxPriorityFeePerGas` 三档估算；`eth_estimateGas`
* nonce：`eth_getTransactionCount(pending)`
* 广播：`eth_sendRawTransaction`；确认：`eth_getTransactionReceipt` 轮询

**TRON（TronGrid REST）**

* 账户与资源：`/v1/accounts/{addr}`、`getaccountresource`（Energy/带宽，驱动确认页资源提示）
* TRC-20 余额：`triggerconstantcontract` balanceOf
* 交易本地构建（wallet-core 需要 refBlock：取 `getnowblock`）
* 广播：`broadcasttransaction`（hex）

**Solana（JSON-RPC）**

* 余额：`getBalance`；SPL：`getTokenAccountsByOwner`
* `getLatestBlockhash`（构建时取，注意有效期 ~60-90s，对应确认页"Blockhash 即将过期"风险项）
* 广播：`sendTransaction`；确认：`getSignatureStatuses`

## 6.2 行情与元数据

* 币价：CoinGecko simple/price（免费档），15s 缓存，失败降级为隐藏法币估值（不阻塞主流程）。
* Token 可信列表：内置四链主流 Token（symbol/decimals/合约地址/图标），自定义 Token 走用户确认 + 高风险标记（与离线端可信列表同源，随 App 版本更新）。

## 6.3 数据存储

* drift（sqlite）：`wallets`、`accounts`、`tokens`、`transactions`、`address_book`、`sign_requests`
* 多钱包隔离：业务表主键/索引全部含 `walletId`（ui-m.md §6.5、§14.2）
* 设置：全局项在 SharedPreferences；按钱包项落库

---

# 7. 应用层

* 状态管理：Riverpod（provider 按 walletId 作用域划分，切换钱包 = 切换作用域，天然满足全局切换语义）
* 路由：go_router
* 转账流程分叉（ui-m.md §8.10）：确认页之后按 `wallet.type` 走 `LocalSignFlow`（验证→签名→广播→结果）或 `AirgapFlow`（生成二维码→扫签名结果→广播确认→结果），两条流复用同一个结果页
* 防截屏：Android 在助记词/二维码相关 route 挂 FLAG_SECURE；iOS 检测 + 提示
* 生物识别：UI 层 local_auth 触发，真正的门禁在原生 Keychain/Keystore 访问控制（双层，UI 层被绕过也拿不到密钥）
* 国际化：V1 中文为主，文案集中管理（intl），预留英文

---

# 8. 工程与质量

## 8.1 依赖原则

* 两个 App 各自维护 pubspec 依赖白名单，CI 校验 lock 文件；新增依赖需说明理由。
* 版本全部锁定（不用 caret 浮动），升级走独立 PR。

## 8.2 测试重点（按风险排序）

1. **派生正确性**：BIP-39/44 官方测试向量 + 与 OKX/imToken/Phantom 对同一助记词的地址一致性（四条链）。
2. **交易序列化**：wallet-core 输出与链上真实成功交易逐字节对比（每链原生币 + Token 各一组）。
3. **分片协议**：编解码往返、乱序/重复/缺片/损坏分片、过期与重放拒绝。
4. **金额精度**：decimals 边界（USDT 6 位、SOL 9 位、ETH 18 位）、最大金额、粉尘。
5. 集成：testnet（Sepolia / Amoy / Nile / Devnet）端到端转账，双机实拍扫码联调。

## 8.3 里程碑

| 阶段 | 内容 | 验收 |
| --- | --- | --- |
| M1 基建 | monorepo、core_crypto 桥、安全存储、ui_kit tokens | 单测：派生四链地址过测试向量 |
| M2 Cold Signer | 创建/导入/备份/安全检查/地址导出/扫码签名/签名记录 | 离线机全流程可用，Android 包无 INTERNET 权限 |
| M3 观察钱包 | 连接导入、资产查询、构建交易、二维码传签、广播 | 双机 testnet 完成 ui-m.md §7.7 三段式 |
| M4 普通钱包 + 多钱包 | 本机签名转账、钱包切换器/管理、备份提醒链路 | ui-m.md §18 验收 1-11 条 |
| M5 加固 | 依赖审计、威胁建模复查、混淆/反调试、审计准备 | 安全 checklist 全绿 |

---

# 9. 风险与对策

| 风险 | 对策 |
| --- | --- |
| wallet-core 无官方 Flutter 绑定，桥是自研点 | 起步用 platform channel 调官方 iOS/Android 绑定（代码量小、可靠）；性能或复用需要时再演进为 Dart FFI 直调 C 接口。桥接层 API 面积刻意收窄（§2.2 十个方法） |
| Solana 派生路径兼容性 | 默认 m/44'/501'/0'（Phantom 主流路径），导入时校验首地址与用户预期不符的场景给出路径提示；V1 不开放多路径选择（与 ui-m.md 一致） |
| TRON refBlock/expiration 时效 | 构建后立即展示二维码倒计时（观察钱包）；expiration 设置需覆盖"扫码-签名-回传"的真实耗时（默认 10 分钟，与 ui-m.md 一致），真机联调标定 |
| Solana blockhash 60-90s 过期 vs 传签耗时 | 观察钱包的 Solana 转账默认走 Durable Nonce（wallet-core 支持 nonce advance，ui-m.md §9.7 已允许）；普通钱包本机签名用普通 blockhash 即可 |
| platform channel 传输助记词（创建/导入流程） | 仅进程内内存传输，可接受；Dart 侧用后置空引用并尽快触发 GC，不写日志、不进状态管理 |
| CoinGecko 免费档限流 | 客户端缓存 + 失败降级隐藏估值；行情不属于核心安全路径 |
| iOS 无法禁网络/禁截屏的宣传风险 | 文案只承诺"无网络代码 + 联网检测告警 / 截屏检测告警"，可证明的强承诺只给 Android 版 Cold Signer |

---

# 10. 与需求文档的对应关系

* ui-m.md §13.1 离线设备红线 → 本文 §4（无 INTERNET 权限 + 依赖白名单）
* §13.2 分层安全模型 → §3.1/§3.2（观察钱包本机根本不存在密钥记录；普通钱包按存储模型加密）
* §13.3 普通钱包密钥安全 → §3.4
* §13.4 离线端签名校验 → §5.4
* §13.5 防重放 → §5.4（reqId 记录）
* §6 多钱包管理 → §6.3 数据隔离 + §7 Riverpod 作用域
* §8.10/§8.11 流程分叉 → §7 转账双流
* §18 验收标准 → §8.3 里程碑逐条覆盖
