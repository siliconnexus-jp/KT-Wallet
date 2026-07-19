# KT Wallet 实施任务清单（V1）

上游：`ui-m.md`（需求）、`tech-plan.md`（架构）、`detailed-design.md`（详细设计，下称 DD）。

## Review 门禁统一定义

每个模块组（P1-P6）末尾有一个门禁任务，流程固定：

1. 该模块全部单测通过（`melos run test` 绿）。
2. 运行 AI 代码审查：正确性 + DD §8 安全不变量逐条核对。
3. 修复全部 confirmed 发现，回归单测。
4. 审查报告留存 `reviews/<模块>.md`（发现清单、修复情况、不变量核对表）。
5. **P1、P2 门禁：停下等用户确认后才进入下一阶段；其余门禁自动继续。**

任务格式：每个任务含【内容】【产出】【单测】【完成定义 DoD】。

---

## P0 工程基建（4 任务）

### P0-1 Monorepo 骨架
- 内容：melos workspace；`apps/kt_wallet`、`apps/cold_signer`、`packages/{core_crypto,airgap_protocol,chains,ui_kit}` 空包；统一 analysis_options（strict）。
- 产出：可 `melos bootstrap && melos run analyze` 的空工程。
- 单测：每包一个 placeholder 测试保证测试链路通。
- DoD：两 App 均可空跑到占位首页（iOS 模拟器 + Android 模拟器）。

### P0-2 CI 与依赖门禁
- 内容：GitHub Actions（或本地脚本）：analyze / test / 依赖白名单检查（cold_signer pubspec.lock 比对白名单，见 tech-plan §4）/ cold_signer Manifest 无 INTERNET 断言。
- 产出：`tool/check_deps.dart`、CI 配置。
- 单测：check_deps 对"混入违禁依赖的 lock 文件"fixture 报错、对合法 lock 通过。
- DoD：CI 全绿；人为加入 `http` 到 cold_signer 时 CI 失败。

### P0-3 ui_kit 设计 tokens 与基础组件
- 内容：从 Pencil 变量翻译 tokens（w-*/c-* 两套色板、字体、间距、圆角）；基础组件：主按钮、明细行、网络徽章、钱包类型徽章、分片进度条。
- 产出：`packages/ui_kit/lib/{tokens,components}/`。
- 单测：golden 测试（按钮/徽章/明细行 × 浅色深色两主题）；token 值与 Pencil 变量对照表测试。
- DoD：golden 基线入库；两 App 引用 tokens 渲染示例页与设计稿目测一致。

### P0-4 测试基建
- 内容：fixtures 目录规范（DD §9）；`MockCoreCrypto`；录制 RPC 响应加载器；表驱动状态机测试工具。
- 产出：`packages/core_crypto/lib/testing.dart`、`test_support` 共享包。
- 单测：MockCoreCrypto 确定性（同一助记词恒定地址）；fixture 加载器容错。
- DoD：后续任务可直接 import 使用。

---

## P1 core_crypto（6 任务）【模块完成后停等用户确认】

### P1-1 Dart API 层 + Mock
- 内容：DD §2.1 十方法的 Dart 封装、错误码映射为类型化异常、`MockCoreCrypto` 补全。
- 产出：`packages/core_crypto/lib/src/{api,errors,mock}.dart`。
- 单测：每个错误码 → 异常类型映射；参数校验（空 walletId、非法 strength 等拒绝）；mock 全方法行为。
- DoD：app 层可仅依赖接口开发。

### P1-2 iOS 原生实现
- 内容：DD §2.2 iOS 四组件；TrustWalletCore SPM 集成。
- 产出：`packages/core_crypto/ios/`。
- 单测（XCTest）：KeychainStore 读写/删除/访问控制属性断言；错误码传播；【向量】generateMnemonic 熵长度、validateMnemonic 对 Trezor BIP-39 官方向量全过。
- DoD：iOS 模拟器 instrumented 测试：`abandon…about` 助记词派生四链地址与已知向量一致（ETH `0x9858EfFD232B4033E47d90003D41EC34EcaEda94`、TRON/SOL 用 wallet-core 官方测试向量）。

### P1-3 Android 原生实现
- 内容：DD §2.2 Android 四组件；wallet-core Maven 集成。
- 产出：`packages/core_crypto/android/`。
- 单测（Robolectric/instrumented）：KeystoreManager StrongBox 降级路径；EncryptedStore 密文不可明文读出；派生向量测试同 P1-2；`setUserAuthenticationRequired` 属性断言。
- DoD：Android 模拟器四链地址向量一致；双端派生结果互相一致。

### P1-4 签名路径与 SigningInput 通道
- 内容：signTransaction 全链路（auth → 解密 → AnySigner → 清零 → 返回）；四链 coin 分发。
- 产出：双端 WalletCoreBridge.sign。
- 单测：【向量】四链各一组固定 SigningInput → 期望签名字节（取 wallet-core 仓库测试向量）；未知 coin 拒绝；INVALID_INPUT 路径。
- DoD：Dart 集成测试双端签名输出逐字节等于向量。

### P1-5 锁定策略 + Cold Signer 双层加密
- 内容：DD §2.4 失败计数/冷却；Argon2id + XChaCha20 双层封装（kdfPassword 路径）。
- 产出：AuthGate 完整实现、KDF 封装。
- 单测：5/10/15 次失败的冷却阶梯（注入时钟）；冷却期方法抛 AUTH_LOCKED；双层加密单层通过必失败；Argon2 参数断言；KDF 盐随机性。
- DoD：getAuthState 驱动 UI 倒计时演示通过。

### P1-6 【Review 门禁】core_crypto
- 内容：统一流程 + DD §8 不变量 1-5 逐条核对（重点人工检查内存清零的 early-return 路径）。
- 产出：`reviews/core_crypto.md`。
- DoD：单测全绿、confirmed 发现清零、**用户确认后**进入 P2。

---

## P2 airgap_protocol（5 任务）【模块完成后停等用户确认】

### P2-1 CBOR payload 编解码
- 内容：DD §3.1 三种 payload 的 encode/decode + 约束校验。
- 产出：`packages/airgap_protocol/lib/src/payload/`。
- 单测：三 payload 往返；每个字段超限单独拒绝用例；未知 version/type 拒绝；缺字段拒绝；边界值（accounts=1/8、rawTx=32KB）。
- DoD：与 DD 字段表逐项对齐的测试注释。

### P2-2 分片编码器
- 内容：DD §3.2 帧布局；chunk 尺寸参数化；帧序列生成器（循环播放数据源）。
- 产出：`fragmenter.dart`。
- 单测：不同 payload 尺寸 → total 计算正确；单片 payload；恰好整除/余数分片；>64KB 编码报错；>256 片报错；帧字节布局逐字段断言。
- DoD：给定 payload 可输出稳定帧序列。

### P2-3 接收聚合器
- 内容：DD §3.3 状态机 + 进度回调。
- 产出：`aggregator.dart`。
- 单测（表驱动）：乱序收齐、重复帧计数、混入其他 reqId 帧忽略、CRC 损坏 → failed、CBOR 损坏 → failed、reset 后可复用；进度回调序列断言。
- DoD：全部 (状态,事件) 组合有测试，非法迁移抛错。

### P2-4 防重放校验器 + Fuzz
- 内容：DD §3.4 六步校验器（记录存储抽象注入）；fuzz 测试（随机字节/变异合法帧 ×10k 不崩溃）。
- 产出：`validator.dart`、`test/fuzz_test.dart`。
- 单测：六步每步单独失败用例；时钟容差边界（±10min）；重复 reqId 各状态（scanned/signed/rejected/expired）都拒绝；fuzz 套件。
- DoD：fuzz 10k 轮零崩溃零 hang。

### P2-5 【Review 门禁】airgap_protocol
- 内容：统一流程 + 不变量 6-8。
- 产出：`reviews/airgap_protocol.md`。
- DoD：**用户确认后**进入 P3。

---

## P3 chains（6 任务）

### P3-1 Amount 值类型
- 单测：parse/format 往返；精度 6/9/18；超精度输入拒绝；负数/溢出；"0.1+0.2"类十进制精确性；千分位格式化。
- DoD：lint 规则（no-double-in-amount）生效并有违例测试。

### P3-2 EVM TxBuilder（含 Polygon）
- 内容：DD §4.2 EVM 映射 + parse 反解 + TxPreview。
- 单测：【向量】原生转账与 ERC-20 各一组：SigningInput 字节与 wallet-core 向量一致；【主网对照】选主网真实成功交易（1 笔 ETH 转账、1 笔 USDT transfer），本地重建序列化逐字节一致；chainId 1/137 区分；approve calldata → Unsupported；parse(rawTx) 与 build 往返。
- DoD：向量与主网对照全过。

### P3-3 TRON TxBuilder
- 单测：TRX 与 TRC-20 各一组向量；refBlock 注入正确性；expiration=+10min 断言；fee_limit 设置；未知合约调用 → Unsupported；主网真实 TRC-20 交易对照。
- DoD：同上。

### P3-4 Solana TxBuilder
- 单测：SOL/SPL TransferChecked/ATA 创建三组向量；durable nonce 模式（nonce advance 指令在首位断言）；decimals 不符拒绝；未知 Program → Unsupported；主网对照一笔 SPL 转账。
- DoD：同上。

### P3-5 RPC 客户端三件套
- 内容：DD §4.3 接口 + 实现 + 手续费三档估算。
- 单测：全部方法用录制响应 fixture；超时/重试策略（注入 fake client 计数）；广播不重试断言；feeHistory 三档计算对固定 fixture 的期望值；错误响应（限流/节点错误）映射。
- DoD：mock server 集成测试通过。

### P3-6 【Review 门禁】chains → `reviews/chains.md`（不变量 9-10），自动继续。

---

## P4 数据层（3 任务）

### P4-1 drift schema + DAO
- 单测：全表 CRUD；金额 BigInt 字符串往返；索引存在性；schema 迁移 v1→v2 演练（加列脚本 + 数据保留断言）。

### P4-2 Repository 层
- 内容：walletId 绑定仓储；cold_signer 侧 sign_records 仓储。
- 单测：钱包 A 写入后钱包 B 仓储查询为空（隔离）；删除钱包级联清理；并发写（两个 isolate/事务）无损坏；sign_records 无敏感字段（schema 断言）。

### P4-3 【Review 门禁】数据层 → `reviews/data.md`（不变量 11），自动继续。

---

## P5 cold_signer 应用（8 任务）

### P5-1 Onboarding：创建流程（C1,C11,C12,C3,C4,C14,C15,C16）
- 单测：流程状态机（跳步禁止、返回重入）；助记词校验题生成（抽 3 词不重复、选项含正确词）；PIN 一致性校验；widget 测试关键页。
- DoD：模拟器全流程可走通，storeWallet 带 kdfPassword。

### P5-2 Onboarding：导入流程（C13）
- 单测：12/18/24 切换清空处理；逐词校验与候选词（mock 词表）；完整性校验失败提示；粘贴禁用断言（离线端无粘贴入口）。

### P5-3 安全检查引擎（C2 + 首页状态条）
- 单测：DD §7.2 判定矩阵全组合（探测结果注入 → 等级/是否阻断）；路由守卫：block 状态下 /scan 跳转被拦截。

### P5-4 地址导出（C10）
- 单测：account-export payload 组装与 deriveAddresses 一致；单链/全部导出两种 payload；分片播放数据源正确。

### P5-5 扫码接收 + 解析展示（C6,C7,C17）
- 单测：聚合器接入（相机帧 mock）；§3.4 校验失败各分支 → 对应页面/文案；TxPreview 展示字段与 parse 结果一致性（summary 不一致时高风险标记）；白名单外 → 风险警告页并记录 rejected。

### P5-6 签名会话 + 结果页 + 记录（C8,C9,C18）
- 单测：DD §7.3 状态机全路径（表驱动）；先落库后展示顺序断言（注入崩溃点测试）；作废后同 reqId 再扫拒绝；记录列表过滤（全部/已签名/已拒绝/已过期）。

### P5-7 设置与删除钱包（C19,C20,C21）
- 单测：删除五步顺序强制（跳步失败）；确认文字精确匹配；删除后 getAuthState/钱包查询行为。

### P5-8 【Review 门禁】cold_signer → `reviews/cold_signer.md`（不变量 12-13 + 依赖白名单复查），自动继续。

---

## P6 kt_wallet 应用（9 任务）

### P6-1 多钱包管理（W21,W22,W27,W28 + wallets 仓储接线）
- 单测：创建/导入/连接三入口状态机；上限 20 拒绝；切换后 currentWallet 派生 provider 全部刷新（provider 测试）；排序持久化；删除普通钱包的备份确认分支。

### P6-2 普通钱包 Onboarding（W22-W26）
- 单测：备份流程与"稍后备份"分支（backedUp 标记）；校验题；导入粘贴解析后剪贴板清空断言（mock 剪贴板）。

### P6-3 观察钱包连接（W12,W13）
- 单测：account-export 解析 → 钱包创建映射；含私钥类字段的恶意 payload 拒绝并警告（schema 层已拒，再加集成断言）；协议版本不符提示。

### P6-4 资产首页 + 余额聚合（W1/W20,W2,W3）
- 单测：四链并发拉取单链失败不阻塞（部分数据渲染 + 异常态标记）；价格缓存 15s；隐藏余额模式；未备份横幅显隐逻辑；钱包类型 → 动作区渲染分支。

### P6-5 转账输入与校验（W4 + 手续费）
- 单测：各链地址格式校验；跨链地址误填检测（TRON 地址在 EVM 表单）；最大金额（原生币扣手续费）；粉尘/零值/超余额；三档手续费展示与自定义边界。

### P6-6 LocalSignFlow（W29,W30,W9）
- 单测：DD §6.3 状态机全路径；AUTH_LOCKED 冷却 UI；广播失败重试复用 nonce 断言；未备份钱包转账前警告分支；成功后 transactions 状态迁移 draft→confirmed。

### P6-7 AirgapFlow（W5,W6,W7,W8,W9）
- 单测：状态机全路径含过期定时器；sign-result 校验失败各分支（reqId 不符/签名者不符/过期）；取消后 sign_requests 状态；广播确认页数据与 sign-result 一致。

### P6-8 收款 + 记录 + 设置（W14,W15,W16-W19）
- 单测：收款地址与 accounts 一致 + 网络警告文案；交易记录按钱包隔离渲染；地址簿 CRUD 与转账页联动；Token 显隐过滤资产列表；RPC 节点切换生效。

### P6-9 【Review 门禁】kt_wallet → `reviews/kt_wallet.md`（不变量 14-16），自动继续。

---

## P7 集成联调（3 任务）

### P7-1 Testnet 四链端到端
- 内容：Sepolia/Amoy/Nile/Devnet 配置档；普通钱包四链真实转账各 ≥1 笔。
- DoD：四链均拿到 confirmed 回执；记录到 `reviews/e2e-testnet.md`。

### P7-2 双机传签联调
- 内容：两台真机（联网 iOS/Android × 离线另一台）完整三段式；分片尺寸/速度标定（三档实测成功率）。
- DoD：观察钱包四链 testnet 转账走通；标定参数回写 airgap_protocol 默认值。

### P7-3 验收对照
- 内容：对 ui-m.md §18 的 25 条验收标准逐条实测打勾，未过项转 issue。
- 产出：`reviews/acceptance.md`。

---

## P8 加固（3 任务）

### P8-1 依赖审计与锁定复查：白名单最终化、pub audit、许可证清单。
### P8-2 威胁建模复查：对 DD §8 全部不变量做一次跨模块复查 + 渗透式自查（重放/降级/剪贴板/截屏路径），产出 `reviews/threat-model.md`。
### P8-3 发布配置：Android R8 混淆 + 无 INTERNET 验证（aapt dump 断言进 CI）、iOS 隐私清单、版本号与更新说明。

---

## 汇总

| 阶段 | 任务数 | 门禁 |
| --- | --- | --- |
| P0 基建 | 4 | — |
| P1 core_crypto | 6 | AI review + **用户确认** |
| P2 airgap_protocol | 5 | AI review + **用户确认** |
| P3 chains | 6 | AI review 自动继续 |
| P4 数据层 | 3 | AI review 自动继续 |
| P5 cold_signer | 8 | AI review 自动继续 |
| P6 kt_wallet | 9 | AI review 自动继续 |
| P7 联调 | 3 | 验收报告 |
| P8 加固 | 3 | 威胁建模报告 |
| 合计 | 47 | |
