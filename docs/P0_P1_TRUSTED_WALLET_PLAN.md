# KT Wallet P0/P1 可信基础钱包实施方案

更新日期：2026-08-03

## 目标与边界

本方案将 KT Wallet 提升到可以公开测试、且核心资产链路能够被独立复核的
“可靠基础钱包”。范围继续排除 WalletConnect/DApp、NFT、Swap、质押、
正式发布签名和原生构建 CI；这些能力不会被暗中计入完成度。

完成状态只能由以下证据证明：

1. 自动化测试覆盖明确的失败闭合条件并全部通过。
2. iOS/Android UI 流程在目标构建上逐步执行并截图。
3. 涉及链上结果的项目必须提供当轮测试网 txHash 和浏览器链接。
4. 涉及真机系统行为的项目必须保留真机证据，模拟器不能替代。
5. RPC、索引器或系统状态无法确认时，产品必须显示 `unknown`，不得推测成功。

## 设计原则

### 1. 链状态是唯一结算依据

账户历史索引器仅用于发现和展示记录。交易最终状态由按 hash/signature 查询的
链节点结果决定。历史缺失、请求超时、限流和索引延迟不能生成 `failed` 或
`dropped`。

统一状态为：

- `submitted`：App 已接受提交，节点尚未回答。
- `pending`：节点知道交易，但尚未达到链的确认标准。
- `confirmed`：链执行成功且达到当前产品确认标准。
- `failed`：链返回明确执行失败。
- `unknown`：当前证据不足，不覆盖最后可信状态。
- `replaced`：EVM 同 nonce 替换交易已经确认。
- `dropped`：只有链族专用规则取得充分证据时才允许产生。

### 2. 数据快照按 wallet × network × generation 原子发布

余额、Token 余额、nonce、手续费、价格和最后成功时间必须来自同一刷新代次。
一条慢链或失败链不得清空其他链的最后可信数据。网络或钱包切换后旧代次结果
必须丢弃。

### 3. 认证错误必须区分用户失败和设备不可用

错误凭据可以进入退避锁定；缺少生物识别、未设置设备密码、硬件不可用、
系统取消、超时和系统自身锁定不能累计 KT Wallet 的攻击计数。

### 4. 交易发送必须 fail-closed

手续费估算、预执行、网络一致性、签名验证或广播结果任一不可确认时禁止显示
成功。广播成功、链上确认成功和历史索引成功是三个独立阶段。

### 5. 报告不扩大结论

自动化测试通过、模拟器 UI 通过、测试网通过、真机通过和外部审计通过必须使用
不同标签。没有证据的项目保留为待办。

## P0：达到可公开测试的可信钱包

### P0-01 交易最终状态真实性

- [x] `ChainTxRecord` 使用 `pending/confirmed/failed/unknown`，不再压成布尔值。
- [x] 删除“历史超过 24 小时查不到就 dropped”的推断。
- [x] 只有显式 `failed` 才将本地记录更新为失败。
- [x] 旧版历史快照可迁移，新快照保存完整状态。
- [x] 交易详情对 `unknown` 显示“状态暂不可用”，不显示失败。
- [x] EVM：receipt 明确成功/失败；hash 缺失时只有 confirmed nonce 已越过
  持久化 nonce 才判定 `replaced`，其余保持 `unknown`。
- [x] EVM：节点仍能返回旧 Pending 交易时，逐字段核对 hash/from/nonce 后一次性
  回填缺失 nonce；Gateway 返回 pending 也不会跳过该证据采集。
- [x] EVM：节点已永久遗忘、且本地从未保存 nonce 的历史交易保持非终态
  `unknown`，不能无证据推断 replacement/dropped。数据库 v7 额外持久化最近一次
  hash 专项查询的 `pending/unknown` 证据：unknown 时首页、详情和导出凭证明确显示
  “状态暂不可用”并继续轮询；节点重新证明 Pending 后自动恢复“确认中”。
- [x] 交易状态查询不再跟随用户此刻选择的网络：Gateway 和直连 RPC 都按交易行持久化
  的 `networkId` 解析原端点；已删除、未知或跨链家族 ID 保持 `unknown` 且不发请求，
  不会在另一网络根据同 hash/nonce 制造确认、失败或 replacement。
- [x] 当前网络只过滤可见历史，不再暂停其他网络的 Pending 对账。钱包级专用查询持续
  读取全部带 hash 的 `submitted/broadcast/pending` 行，每行仍使用自身网络；异步 nonce、
  状态与 EVM replacement 终态写入显式绑定行内 `walletId`，用户在请求期间切换钱包也
  不能让结果丢失或落到当前钱包。旧实现在 Sepolia Pending + 主网显示条件下红测保持
  pending；修复后链状态更新为 confirmed 而主网列表仍为空。钱包数据 20/20、相关
  Wallet 定向 73/73、静态分析与 `check_deps` 通过。
- [x] 历史最终合并增加远端事件级去重与交易级状态冲突闭合：EVM 交易哈希及事件 ID
  按大小写不敏感身份合并，TRON 只规范化十六进制交易哈希而保留 Base58 后缀，Solana
  签名与事件 ID 保持大小写敏感；同一交易的原生币、Token、internal/SPL event 仍按
  稳定事件 ID 分开展示。Gateway、直连结果或旧快照重复返回同一事件时只显示一次；
  同一 coin + networkId + hash 若同时出现 confirmed 与 failed，无论顺序或重复次数，
  所有事件统一降为 unknown、本地 Pending 不结算并继续 hash 专项查询。三项新增负例与
  既有跨链、Solana 大小写、刷新故障回归合计 33/33 通过；KT Wallet 全量
  1484/1484、静态分析 0、`check_deps` 与公开测试源码审计 12/12 通过。该不变量直接
  证明列表与数据库行为，不使用无关截图冒充远端冲突证据。
- [x] 直连与 Gateway 历史解析不再把 Provider 缺失字段的语言零值当作成功：EVM
  只有 `isError=0` 或 `txreceipt_status=1` 的一致证据才确认，二者冲突时保持
  `unknown`；Solana 只有显式 `err:null` 才确认；TRON native/internal 分别要求
  `contractRet` 或 `rejected`，三条 TronGrid feed 都显式请求 `only_confirmed=true`。
  同时修复 hash 专项查询中 TRON 有交易 ID 但无 receipt result、Solana 已 finalized
  但缺少 `err` 时的假确认。App 3 项与 Gateway 5 项负例均先红后绿；缺证据只展示
  unknown 并继续按 hash 对账，明确成功/失败回归仍保持终态。该项是解析与协议不变量，
  不以无关截图代替畸形 Provider 回包证据。
- [x] 对照 Etherscan 官方 tokentx schema 与真实 Blockscout 响应继续复审后，修复
  “安全但不可用”的第二层回归：ERC-20 事件本来不返回 normal transaction 的执行字段，
  现在只有区块号、32-byte block hash、交易索引与非负确认数字段完整时，才把已索引
  receipt event 认定为 confirmed；若 Provider 额外返回执行字段则仍以其为准，矛盾或
  畸形保持 unknown。App 与 Gateway 同时兼容 Blockscout internal 的
  `transactionHash/index`，避免空投、合约退款等内部转入在直连 fallback 消失。两项旧
  行为均以红测复现后转绿；App history 18/18、Gateway upstream/handlers、完整公开源码
  审计 12/12 通过。生产 1.16.15 的公开 Ethereum 历史只读 smoke 返回 5 条且 5/5 ok。
- [x] EVM hash 专项终态查询不再只信任 receipt 的 `status`：App 直连与 Gateway
  同时要求返回的 `transactionHash` 精确匹配请求 hash，并要求 32-byte `blockHash`、
  canonical `blockNumber` 与 `transactionIndex` 完整；无 receipt 但节点声称仍在 mempool
  时，Gateway 也会核对 `eth_getTransactionByHash.hash`。错交易、缺字段、非 canonical
  quantity、超过 256-bit 的数量或非 0/1 hex status 在 App 保持 `unknown`，Gateway 返回固定 upstream error，均不会
  伪造 confirmed/failed/pending。三项 App、三项共享 parser 与三项 Gateway 负例先红后绿；
  KT Wallet 1495/1495、chains 181/181、Gateway 普通/race/vet/govulncheck 与静态分析通过。
  生产 1.16.15 已按 secondary → primary 滚动，公网与双实例均返回 16 网络、ready；
  全 `f` 的有效形状假 hash 三处均为 unknown，公开 Ethereum 历史 5/5 status=ok。
  这只能证明 RPC 回包内部身份与包含字段一致，不能把单一 RPC 的区块视为密码学最终性，
  因此不使用无关 UI 截图扩大结论。
- [x] TRON hash 专项查询绑定完整链上证据：App 直连与 Gateway 都要求
  `TransactionInfo.id` 与请求的 64-hex txID 精确一致，并要求非负 `blockNumber`。
  智能合约/TRC-20 必须给出协议已知的 `receipt.result`；普通 TRX 系统转账因 protobuf
  默认值可能省略该字段时，必须继续读取 `gettransactionbyid`，再次核对同一 `txID`，
  并要求非空且全部已知的 `ret.contractRet`。顶层 `FAILED` 明确映射为失败；错误 txID、
  缺区块、缺结果、未知枚举或错误 fallback 交易在 App 保持 unknown/抛出固定解析错误，
  Gateway 返回固定 upstream error，均不能生成 confirmed。生产 1.16.15 已按
  secondary → primary 滚动；双实例与公网对有效形状假 txID 均为 unknown，发布后
  warning+ 为 0，Prometheus 3/3、规则 17/17、0 firing，Alertmanager 0 active。
  KT Wallet 1501/1501、chains 183/183、共享 packages 409/409、Gateway 普通/race/
  vet/govulncheck、静态分析 0 与完整公开测试审计 13/13 通过。
  该证据证明交易身份、包含位置与执行结果相互绑定，但 FullNode receipt 仍不等同于
  SolidityNode 固化或密码学最终性。
- [x] JSON-RPC 响应身份在移动端与 Gateway 双边闭合：响应必须声明
  `jsonrpc=2.0`、精确回显请求的 String/整数 `id`，并且 `result` 与 `error` 必须恰好
  存在一个；error 必须包含整数 code 与字符串 message。错 ID、缺 ID、
  null/浮点/string 类型偷换、错版本、同时携带 result/error 或两者都缺失均作为畸形响应，
  不得归属到余额、价格、手续费、模拟、交易状态、历史、自定义网络探测、Solana 水龙头、
  匿名诊断或广播请求。只读请求可以换到已验证
  同链备用节点；写请求即使收到错 ID 也保持 outcome unknown 且不尝试第二节点。该规则
  依据 [JSON-RPC 2.0 Response Object](https://www.jsonrpc.org/specification#response_object)
  的 request/response correlation 要求。移动端负例先证明错 ID 广播被当成功，Gateway
  负例先证明错 ID result 被接受；第一轮修复后再次枚举生产 JSON-RPC 所有者，又发现
  Gateway 主客户端、匿名诊断、Solana 水龙头、Solana 直连历史与自定义 RPC 探测仍绕过
  统一校验。五条路径负例全部先红后绿，现由共享闭合函数与生产所有权门禁防止新增旁路；
  最终并发复审又发现 Solana 钱包地址与多个 ATA 历史调用共用固定 id，现改为每次调用
  递增且不重复，并由 ATA 并发测试锁定全部请求 id 唯一；
  错 Gateway 广播确认保持 outcome unknown，Gateway 1 次、直连 0 次。matching string
  id、null result、合法 error 与 single-shot 写入正负例全部通过，KT Wallet 1510/1510、静态分析 0，
  Gateway 普通/race/vet/govulncheck 通过。生产 1.16.15 静态制品 8,708,222 bytes、
  SHA-256 `b9427d2b5639feec1cdb2eeda9a93333bd59b9d3f52ac6334a279f05302a6a88`
  已按 secondary → primary 滚动；双实例与公网版本/ready/16 网络一致，公开 Ethereum
  历史 5/5 ok，3/3 targets、17/17 rules、0 firing、0 active alert、warning+ 为 0。
- [x] TRON：从同一 `getnowblock` 构造并保存 TAPOS reference block 与
  canonical-time expiration；transaction info 缺失且链时间越界后才标记
  `expired`，边界内保持 `unknown`。
- [x] Solana：保存与 recent blockhash 配对的 `lastValidBlockHeight`；
  signature status 缺失且 finalized block height 明确越界后才标记
  `expired`。
- [x] 广播结果严格区分 `accepted / rejected / unknown`：只有节点返回可解析的明确拒绝
  才进入失败；请求开始后的超时、断连、畸形回包或 Gateway 不确定错误均保持 unknown。
  EVM/Solana JSON-RPC 与 TRON REST 广播只向一个端点提交一次，不做 endpoint failover
  或自动重试；Gateway 仅在能够证明请求尚未转发的 unsupported/rate-limit 前置拒绝时
  才允许直连。热钱包、AIRGAP、replacement 与授权撤销都在首次提交前持久化本地
  txHash 和广播尝试时间；结果未知页明确禁止再次发送，并以该 hash 持续对账。
  Gateway 1.16.2 又在访问链节点前，以 `chain + network + canonical signed payload`
  的 SHA-256 指纹取得 Redis `SET NX` 原子 claim；24 小时内的并发、客户端/CDN/代理
  重放和跨 Gateway 实例重复请求只复用首次 accepted/rejected/unknown 结果。Redis
  无法确认 claim 时在链请求前失败闭合；Redis 只保存指纹和结果元数据，不保存签名交易。
  1.16.3 又对共享记录执行字段不变量校验，空 txHash 的 accepted、错误码与状态不匹配
  等损坏记录一律按 unknown 失败闭合且不访问链节点。
- [x] EVM replacement 广播被节点接收时，原交易与替换交易都保持 Pending；只有
  receipt 证明某个 nonce 候选获胜后，才原子地将同 nonce 竞争者标为 `replaced`。
  本地签名、认证或广播失败不会错误终结原交易。
- [x] 加速/取消构造同时核验 `latest` 完整获胜交易负债与 `pending` 增量负债；余额
  不足或 RPC 无法确认时在签名前失败闭合。
- [x] Ethereum Sepolia 使用真实 iOS Wallet Core + Face ID 分别完成 speed-up 与
  cancel：nonce gap Pending、同 nonce 12.5% 以上提费候选、补齐前序 nonce 与链上
  确认。两个原始候选均无 receipt；speed-up 保持原 `value=1 wei`，cancel 为发送者
  本人、`value=0`；获胜候选与 filler 均为 `status=0x1`。
- [x] Base Sepolia、Avalanche Fuji、BNB Smart Chain Testnet 分别完成真实
  speed-up/cancel，保存 original/winner/filler txHash 并独立 RPC 复核。Avalanche
  pending block 不可用时，replacement 只允许 confirmed nonce 使用 latest 回退；普通发送
  还必须证明 confirmed/pending/本次 nonce 三者相同。未知前序负债仍失败闭合。
- [x] Arbitrum sequencer 的 first-come-first-served、快速确认模型无法形成可靠的
  replacement 窗口；真实竞态只会确认一个候选并拒绝另一个 nonce。App 已按链隐藏
  加速/取消，避免用 L1 交互误导用户。
- [ ] Polygon Amoy 补足测试燃料后执行真实 speed-up/cancel 并保存证据。2026-08-02
  只读复核仍为 `0.000585315121694324 POL` 与 `16 USDC`；实时约 30 gwei 时完整六笔
  预算约 0.01728 POL（另加测试 value），不再沿用旧的 0.00378 POL 静态估算。

验收：索引器空结果、429、超时、畸形状态均不制造终态；UI 显示 unknown 并继续
轮询，明确 revert 才失败。

### P0-02 认证与密钥操作闭合

- [x] KT Cold Signer 创建/导入流程改为显式的易失状态机：助记词展示、逐词校验、
  PIN 设置、生物识别选择和完成页必须按顺序推进；生产深链不能跳过助记词精确核对或
  PIN。已有钱包禁止再次进入创建/导入，完成页还必须携带与当前 walletId 一致的真实
  `WalletMetadata`。并发点击创建或完成提交只执行一次原生密钥/metadata 操作，失败时
  保持补偿清理和失败闭合；Gallery 的密码页改用显式 preview 注入，不借用生产状态。
  路由、竞态、错误阶段、伪造完成页和已有钱包负例通过，Cold Signer 全量 568/568。
- [x] EVM 加速/取消不再只依赖确认弹窗：用户确认交易语义后，还必须通过当前配置的
  钱包密码或系统生物识别，才能报价、签名和广播；认证拒绝时上述调用均为 0，同一
  Pending 记录的 nonce 保护仍阻止并发重复 replacement。
- [x] 两款 App 的 Dart 安全元数据存储不再在生产环境捕获
  `MissingPluginException` 后静默退回进程内 `Map`。进程内实现只允许显式 Flutter
  测试环境使用；设备端插件缺失、初始化或读写失败会向上失败。KT Wallet 启动、PIN
  校验和 PIN 写入均保持锁定并显示中英日阻断页；KT Cold Signer 启动时阻止创建、导入
  与签名入口。iPhone 17 Pro Simulator 已分别截图验证无敏感页面或误导入口，重试仍会
  重新检查真实存储。
- [x] 2026-08-03 继续复核测试/生产边界时发现，两款 App 原先只凭进程环境中的
  `FLUTTER_TEST` 标记启用测试路径；若分发进程被注入同名变量，PIN/vault 内存实现、
  相机禁用和 Profile 转账测试参数存在被误启用的可能。现在唯一入口要求
  `kDebugMode && !kIsWeb && markerPresent`，PIN 与 vault 的显式测试 override 还在最终
  存储决策处再次受 `kDebugMode` 限制；相机和转账页只能依赖该统一入口。仓库门禁递归
  拒绝两份规范适配器之外的直接环境变量读取。两项边界测试先红后绿，KT Wallet
  1460/1460、KT Cold Signer 570/570、共享 packages 397/397、Gateway audit、
  `check_deps` 与完整静态分析通过。该项证明 Release/Profile 不能由进程标记进入测试
  存储或测试交易路径，不替代物理设备 Keychain/Keystore、相机和正式签名制品验收。
- [x] 2026-08-03 进一步发现 Gallery、seed/test-bypass controller、模拟地址/账户/签名
  扫码、legacy AccountExport 和 demo walletId 原先使用 `!kReleaseMode`，因此 Profile
  构建仍可能进入开发夹具。两款 App 现在只通过统一的 `kDebugMode` 适配器开放这些
  能力；Profile 与 Release 均按生产路由处理，仓库门禁禁止生产 Dart 再以
  `kReleaseMode` 放宽夹具（仅诊断构建类型分类保留）。两项边界测试先红后绿，Wallet
  定向 43/43、Signer 定向 19/19，两个 Android arm64 Profile AOT bundle 构建通过；
  完整门禁 12/12、KT Wallet 1460/1460、KT Cold Signer 570/570、共享 packages
  397/397、Gateway audit 与静态分析 0 问题。该项仍不替代正式签名制品检查或真机验收。
- [x] Cold Signer 启动时的原生派生失败不再被当成“钱包不存在”并擦除 metadata/PIN；
  临时性 Wallet Core、Keychain 或 Keystore 故障只会进入阻断页并保留同一 walletId 供
  重试。Onboarding 在原生密钥已写入但 metadata 提交失败时，先补偿删除原生密钥，再
  独立尝试清理 legacy mnemonic、metadata、PIN 与 lockout；任一删除失败不会短路其余
  清理。无活动助记词不能进入创建成功页，名称/生物识别偏好也只在持久化成功后更新
  内存状态。5 项故障注入负例与完整 Cold Signer 226/226 通过。
- [x] KT Wallet 热钱包创建/导入改为补偿式原子提交：原生密钥写入、全链地址派生和
  Drift wallet/account 事务全部成功后才发布到 WalletManager 与成功页面；派生或数据库
  失败会独立删除新原生密钥和数据库半成品，观察钱包持久化失败会回滚内存发布与当前
  选择。重复助记词按全链派生地址拒绝；启动时逐个用原生密钥重新派生并核对持久化地址，
  缺失或错配会进入阻断页而不删除旧数据。临时认证/存储失败保留仅驻内存的未提交词表
  供当前验证页重试，持久提交成功后才清空。8 项故障/UI 负例与完整 KT Wallet
  850/850 通过。
- [x] 热钱包不再把原生 Wallet Core 桥返回的 signed bytes 与 txHash 直接当作可信
  广播凭据：EVM、TRON、Solana 三个签名入口在跨越持久化/广播边界前，都会复制并冻结
  用户确认的 unsigned transaction/message，调用共享密码学验签器从 signed bytes 独立
  恢复 signer，核对声明发送者、原始交易内容及派生 txHash，并要求派生 hash 与原生桥
  返回值精确一致。EVM 分支同时覆盖 Ethereum、Polygon、Base、Arbitrum、Avalanche 与
  BNB。畸形 EVM/TRON 签名和伪造 Solana native txHash 均在广播前失败，广播调用为 0；
  合法 ed25519 正例只广播 1 次。iPhone 17 Pro Simulator 又用真实原生 Wallet Core
  分别完成 EVM、TRON、Solana 签名与同一共享验签器复核，临时 `kt-e2e-*` wallet 经
  系统认证 teardown 删除，集成测试 1/1 通过。KT Wallet 1514/1514、chains 183/183、
  共享 packages 409/409 与静态分析 0 通过。
- [x] 热钱包广播成功回包不再以节点/Gateway 返回的任意非空 hash 覆盖本地密码学结果。
  EVM、TRON 与 Solana 的所有热钱包发送、加速/取消和授权撤销入口现在必须把广播前已
  持久化的本地 txHash 传入不可逆网络边界；节点返回值只有与它逐链一致时才算 accepted。
  EVM/TRON 仅忽略十六进制大小写，Solana 签名保持大小写敏感。空本地 hash 在发网前
  失败；不一致回包因签名字节可能已经送达节点而保持 outcome unknown，继续查询本地
  hash，禁止自动重发。旧实现“签名 A、节点回 B、UI 跟踪 B”的负例先红后绿；匹配时
  始终返回本地 canonical 形式。KT Wallet 1517/1517、远程安全边界审计与静态分析通过。
- [x] 观察钱包 + KT Cold Signer 的 QR 广播页也使用同一逐链 hash 绑定。在线端扫码后
  已独立验签并持久化本地 txHash；节点/Gateway accepted 回包必须与该值一致，匹配时
  仍保留离线签名器派生的 canonical 形式。不一致回包不能把交易 A 替换成交易 B，也不
  写入 pending；因首次提交可能已到达节点，页面进入“结果未知”、继续查询本地 hash 且
  不提供第二次广播。W8 旧实现红测先稳定复现跳到 B，修复后转绿；共享比较器保持
  EVM/TRON 大小写不敏感、Solana base58 大小写敏感，并由远程安全边界审计锁定。
  KT Wallet 1519/1519、KT Cold Signer 570/570、共享 packages 409/409、默认公开测试
  门禁 12/12 与静态分析 0 通过。
- [x] KT Wallet 新建/导入热钱包和扫码配对观察钱包的本地 walletId 已从可预测的
  微秒时间戳改为 `Random.secure()` 生成的 144-bit URL-safe 随机值。旧 walletId 继续
  兼容读取；新 ID 在内存已有钱包中连续碰撞 8 次会失败闭合，数据库主键冲突仍由原子
  保存失败并触发密钥补偿清理，不会覆盖旧钱包。格式、128 次唯一性、固定 RNG 连续碰撞
  负例与真实配对路径均已覆盖。原生 MethodChannel 同时作为独立信任边界，在任何认证、
  Keychain/Keystore 读取或 Android blob 路径拼接前强制校验 ASCII
  `[A-Za-z0-9_-]{1,64}`；空值、非字符串、路径穿越、分隔符、空白、Unicode 与超长 ID
  均固定返回 `INVALID_INPUT`。Android JVM 24/24、Core Crypto Dart 41/41、iOS 定向
  XCTest、KT Wallet 与 KT Cold Signer Simulator 原生构建均通过。
- [x] 原生 wallet slot 改为 create-only，重复 walletId 不能替换已有密钥或改变认证
  策略。iOS 不再先删除旧 Keychain item，而由 `SecItemAdd` 原子返回
  `errSecDuplicateItem`；Android 在同一临界区同时检查 blob 与 Keystore alias，密文先
  写私有临时文件、flush + fsync 后在同目录 rename，文件提交失败会补偿删除刚创建的
  Keystore key。Dart、Mock 与双原生层统一返回 `WALLET_EXISTS`，调用方必须重新分配
  随机 ID。覆盖尝试后旧助记词/密文保持不变；Core Crypto 41/41、Android JVM 24/24、
  真实 Wallet Core Kotlin 编译、唯一 iPhone 17 Pro Keychain XCTest 与两款 App iOS
  构建均通过。
- [x] 设备本地密钥 envelope 采用闭合 schema：header 只允许 0（直接熵）或 1（设备
  KDF），解密结果只允许 BIP-39 的 16/24/32-byte entropy。Android 私有 blob 在读取前
  只接受 Keystore AES-GCM 与可选 KDF 对应的 45/53/61/89/97/105 bytes，避免损坏文件
  无上限读入；iOS Keychain payload 只接受 17/25/33/61/69/77 bytes。未知 header、
  截断/超长文件、GCM tag 失败和错误熵长度统一为 `STORE_CORRUPTED`，不进入 Wallet
  Core。Android JVM 24/24、真实 Wallet Core 编译、iPhone 17 Pro 原生负例与双 App iOS
  构建通过。
- [x] Core Crypto 的整个原生 MethodChannel 输入边界不再依赖 Dart 类型正确：iOS 已
  移除助记词、签名输入、备份 blob/密码等所有 `as!` 强制转换及 HDWallet 构造强制
  解包；Android 同步使用精确类型解码。128/192/256 之外的助记词强度、缺失字段、错误
  类型和畸形 typed data 均在系统认证、KDF、Keychain/Keystore 与 Wallet Core 前返回
  `INVALID_INPUT`，不会让用户为无效请求认证，也不会触发原生进程崩溃。仓库门禁禁止
  Swift force-cast/HDWallet force-unwrap 回归并固定关键解码点。助记词自动补全的
  `limit` 也在 Dart、Mock 与双原生层统一限制为 1–20，Dart 对原生返回再执行上限裁剪，
  不再出现测试实现与真实设备行为漂移。双原生层还在认证前限制助记词 512 UTF-8 bytes、
  单词/前缀 64 bytes、设备 KDF 密码 1024 bytes、备份密码 4096 bytes、签名输入 1 MiB，
  并只接受真实 backup-v1/v2 的 60/68/76-byte payload 与八链 coin allowlist。空、超限、
  错误尺寸和未知 coin 均不触发系统认证、KDF 或 Wallet Core。Core Crypto Dart 41/41、
  Android JVM 24/24、真实 Wallet Core Kotlin 编译、iOS 原生负例与两款 App Simulator
  构建通过。
- [x] 钱包名称、头像颜色与备份状态改为持久化成功后才发布到内存/UI；全部 metadata
  写入按调用顺序串行，失败不会显示假成功。拖拽排序把完整 permutation 放在同一 Drift
  事务中，任一钱包写入失败会回滚全部 sortOrder，当前 UI 与重启后的顺序均保持原值。
  metadata 故障与 SQLite 中途触发器负例 2/2、完整 KT Wallet 850/850 通过。
- [x] App Lock、认证方式、自动锁定、隐私模式、授权扫描同意、法币/资产偏好及
  Gateway/RPC 覆盖全部改为串行的“持久化成功后发布”；写入失败保持旧值并显示中英日
  重试提示。网络环境、逐链覆盖和自定义网络改为单一版本化快照，避免三把独立键只写入
  一部分后在重启时改变签名域或广播网络；快速连续操作按用户意图顺序提交。控制器关闭
  前还会排空钱包 metadata 队列。新增 11 项存储失败、并发、非法旧值、隐私同意与关库
  竞态负例；偏好/授权定向 30/30、网络定向 44/44、完整 KT Wallet 850/850 通过。
- [x] 组合安装器的设备模式不再先切 UI、后 best-effort 写入：选择联网钱包/离线签名器、
  钱包设置退出、空钱包返回和签名器退出均等待 SharedPreferences 成功后才发布；失败保留
  当前模式并显示中英日提示。加载会清除非法旧值，所有选择/清除按意图串行执行，失败
  不会毒化后续队列。新增 9 项持久化、重启、损坏值、并发与四入口 UI 负例，定向
  19/19、完整 KT Wallet 850/850 通过。
- [x] 两款 App 的手动语言设置改为串行、落盘后发布，只接受 en/zh/ja；非法旧值会
  清理并回到系统语言。语言页写入失败保持当前语言和 Bottom Sheet，并显示当前语言的
  重试提示。新增双端 round-trip、系统语言、非法值、失败恢复、快速意图与 UI 负例
  12 项；定向 KT Wallet 7/7、Cold Signer 6/6，完整套件分别 850/850、226/226。
- [x] 待签名二维码改为提交后发布：在线端先把对应 `awaitingSig` 交易写入 Drift，提交
  成功后才把 SignRequest 放入会话并编码/展示 QR。写入期间页面不含任何可扫描字节，
  写入失败时会话请求和本地交易 ID 均保持为空，并以中英日阻断提示留在当前页；失败的
  首次写入也不会把临时 ID 泄漏给下一份 reqId。新增“未提交不发布”和“数据库失败无
  QR”2 项故障注入负例，AIRGAP 定向 17/17、完整 KT Wallet 850/850 通过。
- [x] Android 生物识别错误分类为取消、设备不可用、系统锁定。
- [x] 设备未登记认证方式不再累计持久化失败次数。
- [x] Dart 暴露 `AuthUnavailableException`。
- [x] Android JVM 与 MethodChannel 映射测试。
- [x] iOS 对设备不可用、未录入、未设置密码、系统取消和系统锁定做相同语义
  分类；只有明确 `authenticationFailed` 累计 KT Wallet 失败次数。
- [x] 两款 App 的删除流程跨原生密钥与 Dart 数据库使用持久化墓碑恢复：先记录用户已
  确认的删除意图，再删除 Keychain/Keystore 密钥，最后级联清理 metadata、PIN、
  lockout、交易与签名记录。进程在任一步终止后，启动会隐藏墓碑钱包并幂等续做；不会
  重新展示“有地址但无密钥”的损坏钱包。删除意图无法持久化时不触碰密钥；原生删除失败
  时当前钱包保持可见并显示三语重试提示。观察钱包先提交 Drift 删除再改变内存状态。
- [x] Wallet Data 删除事务覆盖账户、Token、余额、Pending/历史、地址簿、
  SignRequest 与 wallet settings；Cold Signer 控制器测试覆盖密钥、PIN、
  lockout、metadata 与防重放记录清理。
- [x] 删除最后一个钱包会同步清空余额、Token、价格关联、历史、本地 Pending 和状态通知
  的控制器内存，并递增 generation 作废删除前已经发出的余额、Indexer 与 RPC 请求；晚到
  响应不能重新填回已删除账户。钱包 A 切换到 B 时也会在任何 await 前同步隐藏 A 的本地
  历史和排队通知，再加载 B 的快照/数据库；余额控制器销毁时递增同一 generation，所有
  晚到 provider callback 直接丢弃，不能向已 dispose 的 notifier 发布。四个竞态回归均在
  旧实现先红、修复后转绿；相关 Market/History 34/34、静态分析、`check_deps` 与完整
  源码审计 12/12 通过。
- [x] Cold Signer 删除页不再是仅展示的危险操作说明：生产钱包必须先输入当前语言下的
  完整确认文字，再验证当前 App PIN；启用系统认证时还必须通过系统生物识别/设备凭据，
  才能进入最终不可恢复确认。错误 PIN、系统认证失败和未输入确认文字都不会删除钱包；
  Widget 测试和 iOS Simulator / Android API 35 原生 UI 流程均已覆盖。
- [x] Cold Signer 最终签名边界冻结 `reqId/rawTx`，在原生密钥调用前再次检查请求过期、
  未来时钟偏差与设备状态，并先把 `reqId` 原子预留为 `scanned`。16 个并发回调只有
  1 个能进入签名；预留跨 Store 重建保持有效。原生签名失败、设备状态变化、数据库
  打开/最终写入失败都不会释放请求或回退内存存储，因此同一请求不能在崩溃、重启或
  双击回调后重放。旧的直接写入 `signed` 控制器入口已删除。
- [x] AIRGAP-V1 输入边界在 Release 与测试一致：单帧 chunk 最大 4 KiB、完整 payload
  最大 64 KiB，相机文本先按最大合法 frame 长度拒绝；AccountExport、嵌套账户、
  SignRequest 与 SignResult 的未知 CBOR 字段失败闭合，避免编码歧义与内存放大。
- [x] App 层 PIN/生物识别切换、旧 PIN 验证后修改、重启偏好恢复、密码优先
  转账认证与生产敏感路由防绕过已在 iOS Simulator 和 Android API 35 独立
  执行并截图；无 PIN 且生物识别不可用的旧状态保持 fail-closed。
- [x] Android 系统认证与后台任务保护不再互相抢占：`local_auth` 与原生 Wallet Core
  的 `BiometricPrompt` 都向宿主报告认证生命周期，认证期间及弹窗关闭后 1.5 秒内不把
  `onUserLeaveHint` 当成真实离开；若用户确实在认证期间切到后台，后续 `onStop` 仍会
  进入保护状态。实现不再启动第二个 Activity。API 35 模拟器已使用真实已登记系统指纹
  分别跑通 KT Wallet、KT Cold Signer 的 `local_auth`，以及 EVM/TRON 原生 Wallet Core
  签名；普通 Home → Recents 只显示深色安全任务卡，恢复后 MainActivity 正常可用。
- [x] Android 两款 App 显式设置 `allowBackup=false`，并用 Android 11 及以下
  `fullBackupContent` 与 Android 12+ `dataExtractionRules` 同时排除云备份和设备间迁移；
  最终合并 APK 门禁验证该属性，而不只检查源码 Manifest。Cold Signer 的 ML Kit
  传递依赖曾向 Release 注入 `INTERNET`，现由 Manifest merger removal 规则移除，
  新 APK 权限表已证明无 `INTERNET`；Debug 单独保留 Flutter 调试所需权限。
- [x] iOS 两款 App 将默认文件保护提升为 `NSFileProtectionComplete`，覆盖数据库、
  偏好、联系人、Pending 与防重放元数据；助记词熵仍由更强的
  `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` Keychain 保存。App 启动时同时将
  Documents 与 Library 标记为 `isExcludedFromBackup`，避免设备绑定密钥无法迁移、
  数据库却被单独恢复的不一致状态；iPhone 17 Pro Simulator 中两款 App 的四个目录
  均实测出现 `com.apple.metadata:com_apple_backup_excludeItem`。Simulator 与
  `iphoneos --release --no-codesign` 均构建通过。
- [x] KT Wallet 加密备份导入在原生文档选择器边界限制为 256 KiB：Android 以 8 KiB
  分块并在上限 + 1 字节停止，iOS 使用 `FileHandle` 有界读取；Dart 再次校验大小并对
  v1/v2 envelope 执行闭合 schema、KDF rounds、cipher、UTC 时间、payload format 与
  payload 校验。v2 固定为跨平台 PBKDF2-HMAC-SHA256 210000 rounds + AES-256-GCM，
  Android v1 先尝试该可移植格式、认证失败后才兼容旧 Android Argon2id；v2 绝不降级。
  设备本地助记词 Argon2id 存储与可移植备份密码学继续隔离。超限使用三语固定错误，
  不读取完整文件、不回显 Provider 路径。备份专项 33/33、Android 独立向量/格式选择
  JVM 7/7、API 35 Unicode 跨平台向量与真实旧 Argon2 v1 恢复 2/2、生产 Swift
  密码学源码直接编译执行同一向量通过，以及 iOS `build-for-testing` 通过。2026-08-03
  在唯一 iPhone 17 Pro Simulator / iOS 26.2 复跑 KT Wallet 原生 XCTest 11/11，
  其中跨平台固定向量、错误密码和 256 KiB + 1 有界读取负例均通过；物理跨平台恢复与
  Files/iCloud Drive/Android Provider 仍纳入真机验收，Simulator 结果不替代 Provider。
- [x] iOS Xcode 构建不再被上一次 Flutter 集成测试的临时入口污染：真实复验发现被
  Git 忽略的 `Generated.xcconfig` 会残留已经删除的 `flutter_test_listener.dart` 及
  测试期 Dart defines，令后续 Debug XCTest 在 Flutter Run Script 阶段失败，Release/
  Profile 虽已覆盖 `FLUTTER_TARGET`，仍可能继承测试期 defines。两款 App 的 Run Script
  现先读取 generated target：listener 已不存在，或正在 Release/Profile/Archive 时，
  只在当前构建环境恢复 `lib/main.dart` 并清除全部测试期 defines；仍存在的 Debug
  listener 保持不变，不破坏正在运行的集成测试。4 个缺失/live/Archive/普通构建向量、
  `check_deps` 双 App 项目门禁及修复后的 KT Wallet 原生 XCTest 11/11 通过；独立
  KT Cold Signer 随后以真实残留且已删除的 listener 触发修复警告，生产入口重新打包后
  原生 XCTest 8/8 通过，证明不是只修复测试脚本中的合成 fixture。
- [x] 备份恢复不再把 Provider 故障伪装成用户取消：只有原生显式
  `cancelled=true` 返回空结果；插件不可用、读取失败、空响应与畸形 payload 分别进入
  固定失败类型，页面显示中英日可重试提示且不回显 URI、路径或原生异常。Provider
  异常/取消/畸形响应、不可用状态、三语 UI 与手机尺寸 Golden 已纳入备份专项 33/33。
- [x] 新建加密备份不再只检查 8 位长度：按 Unicode scalar 要求 14–128 个字符，并拒绝
  低多样性、1–4 字符周期重复、单调连续及明确常见模式；中英日 UI 分别解释过短、过长
  和可预测密码。规则只应用于创建，旧 v1/v2 恢复仍允许历史短密码，避免安全升级反而
  锁死用户。长英文短语、中日韩短语、重复/连续/超长负例和 W32 Golden 均通过；完整
  KT Wallet 1424/1424、Core Crypto 39/39。
- [x] Android 可移植备份 KDF 不再依赖只保证 API 26+ 的
  `PBKDF2WithHmacSHA256` `SecretKeyFactory` 别名；在声明的 minSdk 24 上改由 API 23+
  `HmacSHA256` 按 RFC 8018 直接计算同一 PBKDF2-HMAC-SHA256 字节，显式使用 UTF-8，
  不改变 backup-v2 格式。Unicode 固定向量在 JVM 3/3 和 Android API 35 设备 2/2
  通过；依赖门禁禁止回退到 API 26-only 别名。API 24/25 零售真机仍归真机兼容矩阵。
- [x] Provider 文件名不再直接进入可信 UI：只显示净化后的 basename，移除控制符、
  Bidi/零宽字符，归一空格并限制 80 code points；空名称使用三语匿名回退。文件错误与
  密码错误分离为各自语义区域，无有效文件时密码框禁用，换文件失败清除旧密码，重新
  编辑密码清除旧错误。恶意名称、MethodChannel 映射、状态错配与 Golden 均已覆盖。
- [x] Apple 制品门禁新增显式 `--require-signed` 分发模式：在既有 bundle ID、
  WalletCore、SQLite、Privacy Manifest、Export Compliance 与秘密扫描之外，执行
  `codesign --verify --deep --strict`，要求 Apple/iPhone Distribution identity、Apple
  信任的 `embedded.mobileprovision` CMS 且最终 App signer 必须存在于 profile 的
  DeveloperCertificates，并逐个要求内嵌 Framework、Extension 与动态库使用同一 profile
  signer；同时核对精确 team + bundle application identifier、iOS 平台、
  未过期 App Store profile、`get-task-allow=false`，并同时从 profile 与最终签名
  entitlements 读取 `NSFileProtectionComplete`。Development、Ad Hoc、Enterprise、
  wildcard、错 bundle、过期、可调试或未签名制品均失败闭合；静态门禁防止这些检查
  被后续删除。两个现有 unsigned iphoneos App 仍通过内容审阅，但在严格模式下都按预期
  被“无有效分发签名 + 无 embedded profile”拒绝。
- [ ] 使用两款 App 各自正式签名 Archive/IPA 实际执行上述严格门禁。2026-08-03 本机
  `flutter build ipa --release` 对两个 bundle ID 分别尝试归档，均明确失败：Xcode 当前
  没有可用账号会话，现有 wildcard profile 不含 Data Protection capability 及
  `com.apple.developer.default-data-protection`。不能删除安全 entitlement 换取构建成功；
  需为团队 `6SFGHFY924` / `29K73YAJ7J` 配置匹配的 App ID、App Store profile 与
  Distribution 证书后重跑。Simulator ad-hoc 或无签名 device build 不能替代该证据。
- [ ] iOS/Android 真机验证系统生物识别/设备密码原生提示，以及每次真实
  Wallet Core 签名都不可通过返回、深链或路由绕过。模拟器中的可注入认证
  不能替代这项证据。
- [ ] 删除钱包后在 iOS/Android 真机验证原生 Keychain/Keystore 密钥、PIN、
  认证设置、Pending 与签名记录全部清理。

验收：设备条件错误不能制造攻击锁定；错误 PIN 的退避锁定重启后仍有效。

### P0-03 余额、法币与交易页面一致性

- [x] 首页和转账页读取同一 `MarketController` 的
  per-wallet/per-network generation 快照；未加载时统一显示 `--`。
- [x] USD/CNY/JPY 使用 Gateway/CoinGecko 返回的实时币种报价；无汇率时显示
  `--`，快照保存报价代次。
- [x] EVM 热钱包与观察钱包确认页生成 30 秒有效的不可变交易报价，绑定
  network id、chainId、
  from、to、amount、Token、nonce、gas 与费用；认证层只允许签名这份已确认报价，
  Cold Signer 请求二维码也只编码这份报价。过期、网络切换或字段漂移都会返回确认页
  重新估算。
- [x] EVM 可发送额在报价时使用未缓存的 `pending` 原生币/Token 余额，并与
  精确 `eth_call`、`estimateGas` 和最终签名共用同一份交易参数；Gateway 失败时
  只回退到当前已验证网络的直连 RPC，全部失败则禁止继续。
- [x] TRON 确认页生成 30 秒不可变报价：使用实时 TRX/TRC-20 余额、链参数、
  Energy、Bandwidth 与未激活收款账户费用构造同一份 TAPOS raw_data；热钱包签名
  和 Cold Signer QR 只消费这份已确认字节。
- [x] Solana 确认页生成 30 秒不可变报价：使用最新 blockhash、精确
  `getFeeForMessage` 和相同 message 的 `simulateTransaction` 后置付款账户余额，
  分离网络费与可回收 ATA rent；热钱包签名和 Cold Signer QR 只消费同一 message。
- [x] 三条链报价都绑定钱包 sender、网络、收款地址、金额、Token/Program，构造和
  getter 均防御性复制原始字节；过期、字段漂移或错误钱包签名均失败闭合。
- [x] 金额和手续费从用户十进制输入到链上 base unit 全程使用 `BigInt`，不经过浮点数；
  超出 Token decimals 不截断，逗号小数/分组歧义直接拒绝。EVM 的 chainId、nonce、
  priority/max fee、gas limit 与 value 在生成签名哈希前统一限制为 `uint256`；Gateway
  返回的原生币 decimals/symbol 必须与具体链的协议常量完全一致，否则整条余额响应失败
  闭合并进入直连回退。运营方 Token 目录的 decimals 超出 0–36 时不会获得官方身份或
  进入资产列表。2026-08-03 的先红后绿边界、chains 178/178、35/35 内置部署精度审计、
  KT Wallet 1455/1455、静态分析 0 与 `check_deps` 均通过。
- [x] 展示用市场数据也执行真实性闭合：Gateway、CoinGecko 与本地 last-good 快照只接受
  正且有限的币价/FX 汇率，24h 涨跌只接受有限数；没有有效价格的资产不会单独保留涨跌。
  `BigInt` 链上数量转成法币时检查 `double` 溢出，单资产、Token、跨部署合计、总资产、
  确认页和币种换算任何一步产生非有限值都显示 `--`，不会展示负资产或
  `Infinity/NaN`。负价格与 4096-bit 极端余额先红后绿；定向 86/86、KT Wallet
  1460/1460、静态分析 0、`check_deps`、秘密扫描和差异格式门禁均通过。
- [x] 测试网禁止展示主网法币估值：原生币与 Token 的价格、24h 涨跌和总资产
  在 `MarketController` 数据边界按链环境隔离；全测试网环境不会发布或持久化
  主网 last-good 报价，混合环境只保留主网链估值。首页、Token 详情和确认页已在
  iOS Simulator 与 Android API 35 独立验证。

验收：切换钱包、网络、弱网和刷新并发下，首页与转账页不会给出矛盾余额。

### P0-04 发布回归门槛

- [x] Dart 静态分析必须零错误。
- [x] Gateway Go 测试必须包含 race。
- [x] Android Core Crypto 原生单测必须执行。
- [x] KT Wallet、KT Cold Signer、packages 全量测试全部绿色。
- [x] Golden 基线只在人工复核新截图后更新。
- [x] 生产状态路由与设计 Gallery 隔离：缺少真实 `AccountExport` 时不能创建观察钱包；
  缺少 draft/request/verified result 时不能进入确认、签名或广播确认；广播结果页必须
  同时拥有持久化本地交易 ID 与节点返回的 broadcast txHash。签名成功不再被当作
  广播成功，设计专用费率页不能从生产路由进入。交易详情、地址簿和 Token 管理组件
  即使绕过路由或缺失持久化 Store，也只在显式 `allowTestBypass` 的 Gallery/Golden
  环境加载 fixture；生产控制器保持未找到或真实空状态。iOS/Android 模拟器已验证
  路由失败闭合，Widget 回归覆盖组件级隔离。
- [x] 生产签名结果扫码页在收到真实 AIRGAP-V1 帧前不显示任何固定分片进度；旧的
  Gallery `5 / 12` 只存在于显式测试 fixture。相机不可用也不会制造“已识别”状态，
  生产作用域回归测试锁定该边界。
- [x] 热钱包发送遵守单向不可逆边界：EVM、TRON、Solana 均先持久化完整用户意图，
  再调用原生签名；本地派生 txHash 提交成功后才允许首次广播。节点可能已接收但响应
  丢失时保留 `submitted + txHash` 供重启续查，不标记失败、不自动重发；初始数据库
  写入失败时签名与广播调用均为 0。EVM replacement 与授权撤销使用相同顺序。
- [x] KT Wallet 与 KT Cold Signer 的 Android Release 均强制启用真实
  Wallet Core；关闭 Wallet Core 时 APK 与 AAB Release 均在 Gradle 配置阶段失败。
  两份 APK 和两份 AAB 的三个 ABI 均包含 `libTrustWalletCore.so`。产物门禁扫描完整
  解压 APK/AAB 和全部 ABI，并同时检查七类 Demo/Mock/模拟签名/stub 标记、本地
  E2E 助记词 canary、GitHub/Alchemy 凭证形式、精确包名、备份规则、明文流量、
  权限白名单、导出组件白名单和签名状态。旧门禁中 `strings | grep -q`
  在 `pipefail` 下可被 SIGPIPE 141 误判为“未命中”，现已修正；负例向 APK
  注入禁止标记会立即失败，错误包名也会拒绝。进一步构造 `walletCore=false` Debug
  APK，确认 stub 的精确诊断文本真实存在于最终 DEX；门禁现显式拒绝该文本，避免未来
  构建脚本错误地同时打包 `libTrustWalletCore.so` 与 Kotlin stub 时只看 native library
  而误放行。两款 `assembleRelease` 与 `bundleRelease -PwalletCore=false` 负例均在
  配置阶段拒绝。AAB 额外在解压前拒绝路径穿越/符号链接，要求 `BundleConfig.pb`、
  base manifest、DEX 和全部 ABI；严格解析 `BundleConfig.pb` 的 producer version，要求
  与独立 release-toolchain lock 一致，并让 bundletool JAR 同时匹配 lock SHA-256 和各 App
  Gradle verification metadata。执行 bundletool 的 16 个 runtime JAR 也逐个核对 metadata，
  不再选择缓存最高版本。随后校验容器并读取最终 protobuf Manifest；权限、导出组件、
  凭证与签名规则与 APK 共用。最新 APK 产物：
  KT Wallet 136,870,401 bytes（SHA-256
  `c7ffdc3d4560987c8ec75f460f76033b9a122f309844f2846bec841d927c23d5`）；
  KT Cold Signer 127,021,401 bytes（SHA-256
  `e1ae4b3b5b04f2af753d2970f3f4b41680688caa20da872515b377bb0c0d2908`）。最终合并
  Manifest 同时证明两款 App 禁止备份，Cold Signer Release 不含
  `INTERNET`。两款 iOS Simulator App 与
  `iphoneos --release --no-codesign` device App 同时构建通过，bundle ID、英文显示名、
  标准加密声明、App 自有 Privacy Manifest、Data Protection 配置与
  WalletCore.framework 均已核对。
  两份 AAB 分别为 KT Wallet 100,272,294 bytes（SHA-256
  `dd554dfdef9cc98c7f0190b9888026fb63dbddd3dc64912fea3497e009a35651`）与
  KT Cold Signer 91,536,306 bytes（SHA-256
  `d315eeeeeb91feb47c3d5f34ece9bf1752efbfe2bae1af3cee0e12cf423de937`），bundletool、
  最终 base Manifest、权限、导出组件、原生库与完整敏感标记门禁均通过；两者刻意未签名，
  只能用于制品审阅，不能上传商店。
- [x] 生产根节点不再暗中提供固定演示钱包：`WalletScope.of` 缺失时直接失败，
  Gallery、Golden 和 Widget 测试必须显式注入测试钱包。Release 中 Wallet App
  不能以 seed controller 启动，Cold Signer 不能以 `/`、`/parse`、`/auth`、
  `/result-qr` 深链获取演示请求或签名结果。定向回归 86/86、KT Wallet
  全量 860/860、KT Cold Signer 226/226、共享 packages 377/377、Android
  Core Crypto 原生认证 12/12 全部通过；Golden 未重录。
- [x] App 与 Core Crypto 的生产错误边界不再透传原生异常、Provider body 或含凭证
  endpoint：Dart MethodChannel 只接受固定错误码及 `AUTH_LOCKED.cooldownSec`，iOS/
  Android 原生层不返回 `localizedDescription`、`Throwable.message` 或认证供应商文字；
  Gateway/直连 HTTP transport 将 URI、解析异常和未知 RPC 文本归一化为固定错误，常见
  交易拒绝只映射到有限可操作词汇。Solana Devnet 水龙头也只暴露有限错误分类，
  HTTP/JSON-RPC/传输异常中的完整 URL、Provider key 与节点文案均不会进入界面或日志。
  助记词、私钥、Provider key 与完整 URL canary 负例先失败、修复后通过；
  `tool/audit_runtime_privacy.sh` 已纳入依赖审计。
- [x] Cold Signer 已有钱包的“助记词备份验证”不再进入演示词或 onboarding 密码设置：
  原生 `exportMnemonic` 先执行强认证，Dart 只接收一次性不可修改词表并再次校验 BIP-39
  词数/有效性；短语仅通过不可序列化的内存路由对象传递，认证/校验失败不导航且不展示
  任何词。`/mnemonic-show`、`/mnemonic-verify` 缺少真实内存状态会按钱包状态退回
  `/home` 或 `/welcome`，验证成功回到钱包管理并移除短语路由。钱包管理页同时改用真实
  walletId、创建时间和持久化名称，固定 `WLT-3E8A91 / 2026-06-07` 只保留于显式 Gallery。
- [x] Core Crypto 对其实际使用的 app-scoped UserDefaults 独立声明 CA92.1，并通过
  CocoaPods `resource_bundles` 与 SwiftPM `.process` 两条消费路径打包；pod 源码 glob
  只包含 Swift，不再把 `.xcprivacy` 当编译源码。两款 Simulator `Runner.app` 的最终
  `core_crypto.framework/core_crypto_privacy.bundle` 均已读取复核；两份 Podfile 同时
  固定 iOS 13 并将更旧传递依赖 target 抬到 13，Core Crypto manifest 与旧 iOS 11
  target 构建警告均已清零。仓库门禁覆盖声明、包管理元数据与 Pod 版本下限。
- [x] Gateway 供应链基线不再使用模糊的 `go 1.26` / `golang:1.26`：首次
  `govulncheck` 证明 Go 1.26.1 有 9 个代码可达标准库漏洞后，模块最低版本提升到
  Go 1.26.5，构建与 Distroless 运行镜像均固定内容摘要。Go 1.26.5 的 call-aware
  扫描为 0，vet、普通/race 测试、Linux amd64 静态构建和最终容器 build info 通过；
  OSV-Scanner 2.2.4 同时扫描 147 个 Dart、293 个 npm、4 个 Go 依赖及最终镜像，
  当前已知问题为 0。`make audit`、`make docker-audit` 与
  `tool/audit_dependencies.sh` 固化复查命令；结果不替代外部安全审计。
- [x] Android Release runtime 版本和制品字节均可复核：三个 Android 工程纳入
  官方 Gradle 9.1.0 Wrapper（JAR 与发行 ZIP 双 SHA-256、URL 校验），两款 App
  保存 Release runtime lock 与全构建图 verification metadata。首次 OSV 扫描完整
  metadata 报告 210 条构建/测试工具告警；逐项归因后唯一进入 APK 的已知命中为
  Wallet Core 传递的 `protobuf-javalite 3.22.3`，已在官方 Java 3.x 兼容窗口内提升
  到 3.25.8。实际 Release runtime 的 KT Wallet 135 个、Cold Signer 134 个坐标
  当前 OSV 为 0；篡改哈希负例被 Gradle 拒绝，两款标准 Flutter Release 与 artifact
  guard 重新通过。旧 SQLite 3.52.0 精确 commit 扫描命中 4 个 CVE 后，两款 App
  已从 EOL CocoaPod 迁移至 `sqlite3 3.5.0` native assets / SQLite 3.53.3；Apple
  门禁固定两个远程 Pod 与 SQLite 的 tag commit、spec/archive/source SHA-256，查询
  exact commit OSV，并检查最终 iphoneos framework 的实际版本。构建工具告警、初始
  基线 provenance、CocoaPods 非原生 OSV 生态和正式签名仍是未闭合边界，不能扩大为
  “供应链已审计”。
- [x] 两款 iOS Runner 不再让 Profile 配置复用 `Release.xcconfig`：独立
  `Flutter/Profile.xcconfig` 包含对应的 `Pods-Runner.profile.xcconfig`、Flutter
  生成配置和生产 `lib/main.dart`，Xcode Runner Profile target 显式引用。两款
  unsigned iphoneos Profile device build 通过；故意改回 Release Pod include 的负例
  被 Apple 依赖门禁拒绝，恢复后双 Release build 与 artifact guard 通过。
- [ ] Android 正式签名按用户既定范围暂缓；`apksigner` 与 AAB JAR 签名检查已明确
  证明本轮两份 APK 和两份 AAB 未签名，因此只能作为代码/原生库/Release guard
  验收产物，不能称为可直接分发、可升级安装或可上传商店的正式包。
- [ ] Android AGP 9 内建 Kotlin 迁移仍受当前最新 `mobile_scanner 7.4.0` 阻塞。
  2026-08-02 已从两个 App 临时移除 `android.builtInKotlin=false` 并分别执行 Debug
  构建；Flutter 3.44.2 均因该插件仍应用 KGP 而自动写回兼容开关，同时明确提示未来
  Flutter 将拒绝此配置。两个 App 本身没有应用 Kotlin 插件，本轮没有修改 pub cache
  或引入未审计私有分叉。待上游真正迁移后升级，再用双 App Debug/Release、原生测试
  和 Release guard 关闭此项。

验收：报告中保存完整命令、退出码和失败清单；任何失败都会阻止 P0 完成。

### P0-05 八链真实闭环

以下勾选记录的是 2026-08-01 旧批次留下的可复核链上能力证据，不等同于
2026-08-02 新短期批次已经广播通过。新批次当前只完成 16 条确定性离线签名/验签，
全部链的广播、receipt 与 Gateway 历史必须在补充测试资产后重新验收。

- [x] Ethereum：原生币 + USDC/USDT。
- [ ] Polygon：POL + USDC。
- [x] Base：ETH + USDC。
- [x] Arbitrum：ETH + USDC。
- [x] Avalanche：AVAX + USDC。
- [x] BNB Smart Chain：BNB + BUSD。
- [x] TRON：TRX + TRC-20。
- [x] Solana：SOL + SPL Token，包含幂等 ATA 绑定。

每项步骤：真实地址导出 → 在线配对 → 构造原始交易 → 离线解析 → 认证 →
Wallet Core 签名 → 在线密码学验签 → 广播 → 链上确认 → 双端历史出现。

2026-07-31 热钱包签名/广播子链路证据（不等同于上述完整离线闭环）：

- Ethereum Sepolia：原生 ETH + Test USDT 已确认。
- Polygon Amoy：原生 POL 已确认；USDC 因测试账户剩余 POL 不足，在广播前置
  条件整改前出现半完成，本轮不标为完整通过。现在已增加双交易总预算校验。
- Base Sepolia、Arbitrum Sepolia、Avalanche Fuji：原生币 + Circle USDC
  已确认。
- BNB Smart Chain Testnet：BNB + BUSD 已确认。
- TRON Nile：TRX + 测试 TRC-20 已确认。
- Solana Devnet：SOL + Circle USDC 的节点签名为 `finalized / err: null`；
  PYUSD Token-2022 首次收款已实际创建 ATA 并确认。
- 上述链路尚未同时覆盖“离线配对、二维码解析、在线密码学验签、双端历史出现”，
  因此它们不能单独证明 P0-05。

2026-08-01 Ethereum Sepolia 首条双端完整闭环：

- [x] iOS Simulator 26.2 与隔离的 Android API 35 分别使用真实 Wallet
  Core 和系统 Face ID/设备凭据，执行同一生产协议路径：八链公钥
  `AccountExport` 分片/聚合 → 公钥、地址、派生路径严格校验 → 观察钱包 →
  实时 nonce/费率/预执行 → 请求 QR 分片/聚合 → 原始交易解析 → 原生签名 →
  结果 QR 分片/聚合 → 在线密码学验签 → 广播 → receipt → Gateway 历史。
- [x] iOS：ETH
  `0x660dfe10729e0e647259a16ce5a51a93617272734f302c4644a468ec0e2ac0f5`；
  Test USDT
  `0xdcd773ab53ca7f4b1d1991b7311e7e6447bd4880ca94e4c91717aee6e67f3761`。
- [x] Android：ETH
  `0x88119a83fb3b5dc69508e0dfad1807ecb3dcae8240c1f56b21fa40974a239b68`；
  Test USDT
  `0x44c485baa13f4b3abb1e9b4e8584b0a6736bd7805e0c0cc6771ee8830243295d`。
- [x] 四笔 receipt 经独立 Sepolia RPC 复核均为 `status=0x1`；Gateway
  返回 ETH `1000000000000 wei` 与 USDT `1000000` 基础单位的已确认转出记录。
- 边界：自动化使用真实 AIRGAP-V1 帧传输与生产解码/验证函数，但不代替
  两台物理手机实际摄像头扫描验收；后者继续归入 P0-06 真机矩阵。

2026-08-01 EVM 扩展链双端完整闭环：

- [x] Base Sepolia、Arbitrum Sepolia、Avalanche Fuji、BNB Smart Chain
  Testnet 均在 iOS Simulator 26.2 与隔离 Android API 35 执行与 Ethereum
  相同的完整生产协议路径；每链原生币与官方测试 Token 各一笔，共 16 笔新交易。
- [x] iOS：Base ETH/USDC
  `0x1732a034240d48aad89c906ed662d8fffd3dae08312f3ebc50a85b3a4533a17d` /
  `0x027971584a1f8e3926acec22910ad05fa60c0419701322b98bb6c2304013e94f`；
  Arbitrum ETH/USDC
  `0x57117423d263d15eb18ab42f2791724f94e76b21cef8ff2e4476a300cec99afc` /
  `0x068894631e3801b74093cee34c6be6e7723a217e018bc2b0e82de56375adadf6`；
  Avalanche AVAX/USDC
  `0xf118d6cccff2285616308de10ce09181ec068ae9d34ddf27d329f93937e73125` /
  `0x97189ce7eb0371f3d8f516f5bcf782207f4bf24701a3f290eaf44888648a3708`；
  BNB/BUSD
  `0x4ca4e028eb05c83be640cef8dc280b3a88d898faf8ff58a3b3438113fde016cf` /
  `0x2f914c853eeff838ebf79c1cf927be3f5e65625d1afb7120d1f55fc49af8f45e`。
- [x] Android 最终整组绿灯：Base ETH/USDC
  `0xf15886adb4e244eb36c61b34fde29116edd4081f5fd37a685189b2aba5ae2d4d` /
  `0x1943e1e56cb87853782107fb88bdb8f7afadd72e538fb03df9d75cc3b60de859`；
  Arbitrum ETH/USDC
  `0x8c3590d3cc127b784488c247dbfedf6c6a96795ff20bade7b2765eeec2dd5d60` /
  `0x1056d14636a722d107ce652239706c9a155ede56e0e212c970396a50ebc191c8`；
  Avalanche AVAX/USDC
  `0xc286876fa9bae42640ee512a7afb53cafb2038a3536db65900984a905314e827` /
  `0xf71cbb62dee0f25aaf6c012ec0797d1e840aad926c4b2e2d3290cfe5cf427c61`；
  BNB/BUSD
  `0x60c889030c38e0a0158aa30bed9f6e04ef13066b85cd04b8566425a0d2595b29` /
  `0x0b5ebb7724d159b00acf535bcc70f6f021d4fbfa6119e233935329b7af8b245c`。
- [x] 16 笔均由独立 RPC 返回成功 receipt，且生产 Gateway 历史精确出现并标为
  confirmed。Avalanche 明确缺少 pending block state 时，仅在同一节点证明
  confirmed/pending/本次 nonce 三者相同后才回退 latest，不降低排队交易安全边界。
- 当时边界：Polygon Amoy 缺测试燃料；TRON/Solana 的缺口已由下述 2026-08-01
  双端完整闭环补齐。

2026-08-01 TRON / Solana 双端完整闭环：

- [x] TRON Nile 在 iOS / Android 均执行实时网络身份、账户余额、TAPOS 区块引用、
  Bandwidth/Energy 与 feeLimit 估算，再完成请求/结果 QR、原生 Wallet Core 签名、
  在线验签、广播、receipt 与 Gateway 历史。iOS TRX/Test USDT：
  `b17e14cd08ba0bf4ca7f64c36da3030e3608e84ee91e19bbd640645451bfa0e0` /
  `e9634e6792aab57d1281a7d34160e1d5960fb109e687c81416c71287f8e1ed92`；
  Android：
  `374c69f47effa2ba506e647865a2d46c806fa73ad44d682fb99f4c1dccb4e525` /
  `7b321ae5e54f95d3c617fe77140cc05ff9f911a297c544abd6f78f784afab3d6`。
- [x] Solana Devnet 在 iOS / Android 均执行 genesis hash、latest blockhash、
  `getFeeForMessage`、交易模拟、系统认证、原生 ed25519 签名、在线验签、广播、
  finalized/confirmed 与 Gateway 历史。iOS SOL/USDC：
  `5ZhthgGfm9kir6hWJt9dz6tt8eq2EmeqLDVUGEH5Rg9AfYoFsWpLM9KbY2DD6vNfiVck9SmQt1dtyFMzpD7mCHzn` /
  `4Ms239u1RvLEjdaWDwYafx99vumU5h5j1GJzkCkbJdDB94kFipGnHrKGLNH5v8QUqyJhUD2NUexX6ZtQ64SZzFUp`；
  Android：
  `eQ5CjHNiMhb3xXMKywZ49U57DZjNLCgjC2erxXAi5EbMK2EeHqyRb8TYXPag1pCsags64QmwpwSmUSBSgVrM3Ht` /
  `4JAcVNsK1SXvk3tfKWwV3ypLqRMqtGpD8cCPRZCdfqLZ9KuD5bAfKG21WcMHQzxm6YEZZ9h8hgBBpwJy4QNqZfwL`。
- [x] 修复 Solana 已存在 ATA 的离线收款人绑定：生产构造现在始终加入 Associated
  Token Program 的 CreateIdempotent 指令。ATA 不存在时创建，已存在时无副作用；
  两种情况下原始交易均携带 owner、mint 与 token program，离线端可以重算 ATA 并
  展示用户输入的主地址，不信任 QR summary。
- 边界：自动帧聚合不代替两台物理设备的真实摄像头扫描；八链中只剩 Polygon Amoy
  因 POL 测试燃料不足尚未完成同等级双端链上闭环。
- 2026-08-03 18:31 JST 使用仍有效的当前短期批次在唯一 iPhone 17 Pro Simulator
  重新启动 Polygon Amoy 原生币 + Circle USDC 用例。官方 chainId/余额读取阶段返回
  POL 精确为 0，用例在费用预算、签名和广播之前失败，原生签名调用与链上广播均为 0；
  没有把“测试启动成功”写成链路通过。

2026-07-31 Cold Signer 原生签名/验签子链路证据（仍不等同于广播闭环）：

- [x] iOS Simulator 26.2 使用真实原生 Wallet Core，逐笔触发系统 Face ID，完成
  Ethereum、Polygon、Base、Arbitrum、Avalanche、BNB、TRON、Solana 共 16 条
  “请求 QR 分片/聚合 → 原始交易解析 → 原生签名 → 结果 QR 分片/聚合 → 在线密码学
  验签”矩阵；原生币与 Token 各一条，Solana Token 包含创建 ATA。
- [x] Android API 35 使用 GitHub Packages 的真实 Wallet Core 构建，逐笔触发系统设备
  凭据，完成与 iOS 相同的 16 条矩阵；未设置系统凭据时首先返回
  `AUTH_UNAVAILABLE`，设置测试模拟器凭据后才允许继续，证明失败闭合。
- [x] 在线验签按链比较签名者：EVM 地址忽略校验和展示大小写，TRON/Solana Base58
  保持大小写敏感；同时从原始交易重新解析 sender/owner/fee payer，并与签名者绑定。
- [x] 在线验签不再只信任摘要或 signer 字符串：EVM 对最终 canonical signed wire
  恢复发送地址，并逐字段核对 type/chainId/nonce/费用/gas/to/value/data；TRON 核对
  完整 canonical protobuf raw_data 与交易哈希；Solana 核对 compact-u16 message、
  fee payer 与 ed25519 签名。EVM/TRON 额外拒绝高-s malleable 签名。Android API 35
  已用真实 Wallet Core 临时钱包生成 EVM 与 TRON 签名并通过强化验签，测试结束后
  通过第三次系统认证删除临时钱包。
- [x] Cold Signer 在调用原生密钥前校验 TRON owner 和 Solana fee payer 属于当前钱包；
  两个外来发送者负例均证明原生签名调用次数为 0。
- [x] 真实 `AccountExport` 固定导出八链地址、公钥、派生路径和随机 walletId；在线
  相机在 Debug/Release 都执行严格校验，导入确认页再次校验。缺链、重复 coin、错误
  path、篡改地址/公钥、secp256k1 非曲线点和 EVM key 不一致均被拒绝。
- [x] 两端使用 `chains` 共享派生路径契约。已按 Wallet Core 4.7.0 官方 registry 与
  `TWDerivationDefault` 核实 Solana 当前原生桥使用 `m/44'/501'/0'`；修复 Cold Signer
  曾错误宣称命名路径 `m/44'/501'/0'/0'` 的协议漂移，并增加反向回归测试。
- [x] 2026-08-02 新短期批次已在 iOS Simulator 26.2 再次完成相同 16 条矩阵；
  EVM/TRON/Solana 派生地址与批次公开地址一致，每笔通过原生 Face ID、Wallet Core
  签名、AIRGAP-V1 往返和在线验签，结束后原生临时钱包已删除。该矩阵未访问 RPC、
  未广播且不需要测试资产。
- [x] 2026-08-03 轮换后的当前批次 `batch_20260802_3eb2631a3683a40c` 已在 Android
  API 35 使用真实系统指纹逐次授权，重新完成六条 EVM 原生币/Token、TRON/TRC-20、
  Solana/SPL-ATA 共 16 条 Wallet Core 签名、AIRGAP-V1 往返与在线密码学验签；输出
  signer 与当前批次公开地址一致，测试 teardown 再次通过系统指纹删除 Android 临时
  原生钱包。该证据只覆盖 Android 组合 App 的确定性未广播矩阵。
- [x] 同一轮换批次已在唯一 iPhone 17 Pro Simulator / iOS 26.2 重新完成相同 16 条
  矩阵：每笔通过系统 Face ID、原生 Wallet Core、AIRGAP-V1 多帧往返、原始交易解析和
  在线密码学验签，EVM/TRON/Solana signer 均与当前批次公开地址一致；第 17 次系统
  Face ID 成功删除矩阵临时钱包，集成测试 1/1 通过。该证据只覆盖 KT Wallet iOS bundle
  的确定性未广播矩阵；物理相机 QR 往返及链上广播仍需分别验收。
- [x] 2026-08-03 同一当前批次又在独立 `KT Cold Signer` iOS bundle 内完成相同
  16 条矩阵。测试直接链接该 App 自己的原生 `core_crypto` 插件，每笔分别触发系统
  Face ID，经 Wallet Core 生成真实 signed transaction，再执行 AIRGAP-V1 多帧请求/
  结果往返、原始交易解析、chainId/owner/fee payer 与密码学 signer/txHash 核对；
  EVM、TRON、Solana signer 均与当前批次公开地址一致。第 17 次系统 Face ID 成功删除
  独立 App Keychain 域内的矩阵钱包，集成测试 1/1、Cold Signer 全量 570/570、原生
  建钥清理审计 31 处/0 债务通过。该证据不访问 RPC、不广播，也不替代物理相机或真机。
- [x] 同一测试又在独立 `KT Cold Signer` Android API 35 bundle 内通过：APK manifest
  精确核对为 `cc.siliconnexus.ktwallet.coldsigner`，16 次系统指纹分别授权八链原生币/
  Token Wallet Core 签名，第 17 次系统指纹认证删除独立 App Keystore 钱包；AIRGAP-V1
  请求/结果往返、原始交易解析及 signer/txHash 与当前批次公开地址全部一致，集成测试
  1/1。清空 Gradle 缓存后的首次构建先失败闭合，暴露 Cold Signer 依赖验证缺少 6 个
  Kotlin/coroutines/Guava/JUnit BOM metadata；每个构件均从 Maven Central 独立下载计算
  SHA-256，并与另一 App 已审阅的同版本值交叉核对后精确加入 allowlist，未关闭验证或
  批量扩展信任。随后冷缓存 Debug APK 与矩阵均通过。
- [ ] 本矩阵的确定性、未广播交易仍只证明八链离线签名和验签；新批次全部八链仍需
  补充测试资产并保存 explorer txHash、链上确认与双端历史证据。旧批次的 Ethereum、
  Base、Arbitrum、Avalanche、BNB、TRON、Solana 广播闭环保留为历史回归证据；
  Polygon 在旧批次中也未完成完整闭环。

### P0-06 真机屏幕与系统安全

- [x] 设备检查使用 `safe / unsafe / unknown`，探测失败保持 unknown；Cold Signer
  首页启动与恢复时执行真实 probe，不再固定显示“安全检查通过”或伪造“离线 42 天”。
  Dart 与原生 probe 均有 2 秒上限，网络在线、录屏或完整性明确失败仍禁止签名；
  超时、原生错误或无法可靠检测的状态显示“无法确认”，不会悬挂或误报绿色。
- [ ] iOS 普通钱包、内嵌签名器、KT Cold Signer 的 App Switcher/锁屏/控制中心。
  - 2026-08-03 严格运行复测发现，Scene 状态机虽然会在
    `sceneDidEnterBackground` 请求保护，但旧的 `activeWindow()` 只选择
    `isKeyWindow`；Scene 真正进入后台后窗口已经失去 key 状态，保护页因此可能静默
    无宿主，任务卡继续保留内部页面。单元测试当时只覆盖事件顺序，没有覆盖窗口选择，
    不能作为系统快照闭合证据。
  - 两款 App 现在把触发回调的精确 `UIWindowScene` 传入保护层，并按 key window →
    可见普通 window → Scene 首个 window → AppDelegate fallback 的顺序选择宿主。
    `sceneWillEnterForeground` 不移除封面，只有同一 Scene 的
    `sceneDidBecomeActive` 才恢复原 UI；临时 inactive 仍不安装封面。
  - 唯一保留的 iPhone 17 Pro（iOS 26.2）已分别验证 KT Wallet 与
    KT Cold Signer：普通前台 → 首次 App Switcher → 选择另一 App → 再次 App
    Switcher 显示品牌保护页 → 点击任务卡恢复，共保留 6 张系统截图。首次 App
    Switcher 时当前 App 仍为 foreground-inactive，不提前遮挡；选择另一 App 后才进入
    background 并替换快照，符合此前确定的交互。原生 XCTest 现为 Wallet 11/11、
    Signer 8/8，新增非 key 后台 window 与 fallback 选择负例。
  - 该项仍保持未完成：控制中心/系统弹窗目前有状态机单测但没有本轮系统截图；锁屏、
    电话遮挡、真机 App Switcher、恢复闪帧、独立 Signer 与组合 App 内嵌签名模式仍需
    iOS 零售真机逐项验收。
- [ ] Android 截图策略、后台保护和系统任务卡。
  - 2026-08-03 严格重测发现，旧实现虽然在 `onUserLeaveHint` 启动了第二个
    `PrivacyActivity`，Android 的任务快照仍可能复用启动前的 Flutter 页面；旧报告中的
    品牌页截图不能证明每次任务卡都安全。现在两款 App 已删除该第二 Activity，并把
    `onPause` 与真正离开任务分开：通知栏、权限层等临时系统覆盖不隐藏当前画面；
    `onUserLeaveHint/onStop` 才进入保护状态。
  - Android 13+ 在保护状态使用官方 `setRecentsScreenshotEnabled(false)`，任务描述背景
    固定为 KT 深色并显示 App 图标；Android 12 及以下使用仅后台生效的
    `FLAG_SECURE` 回退。助记词路由的独立 `FLAG_SECURE` 与后台状态取并集，恢复前台
    不能误清除敏感路由保护。普通前台截图仍允许，API 34+ 成功截屏后继续提示。
  - API 35 单一模拟器已分别验证 KT Wallet 与 KT Cold Signer：前台、完整通知栏、
    Home → Recents 深色安全任务卡、点击任务卡恢复共 8 张系统截图；`dumpsys` 证明通知栏
    展开时原 MainActivity 仍是 `topResumedActivity`，Recents 中没有任何 App 内部像素，
    恢复后没有封面残留。每个 App 的 6 项纯状态单测覆盖 API 33+ 与 API 32 回退、
    临时 pause、stop、resume 和敏感路由保持；双端原生聚合测试及源码门禁 12/12 通过。
  - 该项仍保持未完成：API 24–32 当前只有策略单测、没有对应系统运行截图；还需零售
    Android 真机覆盖普通页与助记词页的 Home、Recents、锁屏、截图、录屏和认证弹窗
    期间切后台。
- [ ] iOS 截图提醒真机通知。
- [x] 自动化已证明 root/jailbreak、录屏、网络状态无法确认时显示 `unknown`；各厂商
  ROM / 越狱工具的真机检测覆盖仍归上方真机矩阵，不能据此宣称完整检测率。

### P0-07 外部保证与公开测试准备

- [ ] 独立移动端安全审计。
- [ ] 密钥存储、QR 协议和在线验签密码学审计。
- [ ] 安全披露与响应渠道：
  - [x] 新增 `SECURITY.md`，定义范围、安全研究规则，以及 3 个工作日确认、
    7 个工作日初步分级、每 14 天状态更新的公开测试期响应目标。
  - [x] Privacy Policy 不再引导用户把漏洞细节发到公开 Issue；App About 页
    提供安全政策与“永不索要助记词/私钥”的明确提醒。
  - [ ] 仓库当前 GitHub Private Vulnerability Reporting API 返回
    `enabled=false`；需由仓库管理员启用，或配置并验证专用安全邮箱后，才能把
    App 入口指向真正可用的私密提交渠道。2026-08-03 重新通过 GitHub 官方
    `GET /repos/siliconnexus-jp/KT-Wallet/private-vulnerability-reporting` 回读，仍为
    `enabled=false`；应用内浏览器未登录，Chrome 账号 `Dollarkillerx` 的仓库设置页
    无 repository options 权限，本机现有 HTTPS Git 凭证调用官方 `PUT` 启用接口也
    返回 404。未越权修改；需由具有 Administration(write) 的仓库管理员执行。
- [x] 测试版风险提示、隐私说明、开源许可证清单已存在；KT Wallet About 页提供
  隐私政策、安全风险、Security Policy、第三方许可证和安全报告流程入口，
  iOS/Android 模拟器已独立执行并截图。独立 KT Cold Signer 保持断网原则，不从
  App 内发起网页请求；分发页/README 必须同时提供这些文件。
- [x] 六个共享 package 与 Core Crypto iOS podspec/example 已补齐 API、示例、测试、
  许可证和威胁边界文档；递归文档门禁禁止默认 TODO、示例公司/域名及 Flutter
  模板描述重新进入公开测试代码。
- [x] 已增加版本化测试凭证批次门禁：批次 ID、UTC 创建/过期时间、最长 14 天、
  `0600`、非符号链接、公开 BIP-39 vector 拒绝和交互式隐藏输入；报告发布前使用
  本地助记词作为 canary，扫描助记词、私钥赋值与常见 provider token，错误日志不
  回显秘密。24 个读取真实助记词的 E2E 入口全部内置相同的批次有效性检查，直接
  执行测试也无法绕过；仓库级门禁同时防止新 E2E 漏接并扫描公开报告。
- [x] 2026-08-03 公开发布秘密门禁扩展到项目实际使用的 Etherscan、Helius、GoPlus、
  Prometheus bearer，以及常见 GitHub、Alchemy、Slack、Stripe、Google 和私钥格式。
  `check_deps` 不再只检查 Markdown/HTML，还扫描两款 App 的生产 Dart/原生资源、Gateway、
  网站与 CI 配置；Android APK/AAB 和 iOS `.app` 的最终制品门禁使用同一类 Provider/
  repository token 规则。`TESTING_LOCAL`、`SIMULATOR_RECOVERY_LOCAL` 与
  `BACKEND_DEPLOY_LOCAL` 必须存在于共享 `.gitignore`，不能只依赖某台机器的
  `.git/info/exclude`。Provider 负例先红后绿，28 份本地文档/报告使用当前短期助记词
  canary 扫描通过；`check_deps`、脚本语法、test_support 49/49、共享 packages
  389/389 与相关静态分析通过。模式扫描不能识别所有无前缀高熵字符串，正式公开发布
  仍应叠加专用 secret scanner 与 GitHub push protection。
- [x] 2026-08-03 Push Protection 类覆盖缺口已闭合：旧仓库门禁只遍历生产目录，且
  `e2e_credential_guard scan` 只识别报告扩展名，因此完整的 provider 测试 fixture
  可能留在公开 Dart 测试源码中，直到远端 push 才被拦截。新门禁通过
  `git ls-files --cached --others --exclude-standard -z` 枚举全部已跟踪及可提交的未跟踪
  文件，并共享一份文本类型 allowlist，覆盖 App、测试、工具、配置、CI、Gateway 与
  文档，同时依赖共享 `.gitignore` 排除本地凭证、私密 runbook 和构建目录。测试中需要
  验证的令牌形状改为运行时拼接，不降低检测正例强度；第一次全仓扫描实际发现并修正
  3 个测试文件中的 8 类 provider canary。文件选择负例先红后绿，定向 12/12、Faucet
  10/10、test_support 57/57、共享 packages 397/397、KT Wallet 1460/1460、Cold Signer
  570/570、`check_deps` 与完整静态分析 0 问题。该门禁覆盖当前工作树；Git 历史与无前缀
  opaque key 仍必须继续依赖 GitHub Push Protection/专用扫描器。
- [x] 2026-08-03 在 Provider 前缀和私钥格式之外增加通用高熵凭证赋值检测：只检查
  `apiKey/accessToken/authToken/bearerToken/clientSecret/credential/password/secret/token`
  等明确凭证字段中的 20–256 字符 opaque 值，使用字符类别与 Shannon entropy 阈值，
  同时放行占位符、环境变量和明确的公开 EVM 地址/交易哈希，避免把链上公开标识误报为
  私钥。先红后绿的正负例 2 项证明无前缀值会被拒绝且占位符/公开标识通过；第一次全仓
  扫描又实际发现 Gateway 两个测试文件中的 3 个完整 opaque fixture，已改为运行时拼接。
  Android APK/AAB 与 iOS `.app` 制品门禁同步扩展到通用凭证字段。定向 14/14、
  test_support 57/57、共享 packages 397/397、Gateway upstream 与 `check_deps` 通过。
  该启发式仍不声称识别无上下文、无字段名的任意随机字符串，Git 历史与此类值继续依赖
  GitHub Push Protection/专用 scanner。
- [x] 2026-08-03 建立可重复的本地公开测试源码验收入口：
  `dart run tool/audit_public_beta.dart` 固定、逐步、失败即停地执行差异完整性、仓库安全/
  秘密/原生清理门禁、完整静态分析、四个纯 Dart package、两个 Flutter package、
  KT Wallet、KT Cold Signer 和 Gateway audit，共 12 步；`--list` 可在执行前审阅精确
  命令与工作目录，未知参数固定失败。`--full` 只在 12 步之后追加已固定版本的 Android/
  Apple runtime、Gradle/CocoaPods、Gateway govulncheck 与五份 lockfile OSV 审计，不修改
  CI，也不把源码门禁冒充为正式签名、真机、真实广播或外部审计。计划/停止首错/全成功
  四项测试先红后绿；真实默认执行 12/12 通过，追加依赖脚本又验证 Apple 2 个远程 Pod +
  SQLite 3.53.3、portable backup Swift vector、Gateway 全套和 Dart 147/npm 293/Go 4/
  Android 135+134 个 package，已知问题 0。README 与 BUILDING 已指向同一 canonical 命令。
- [x] 2026-08-02 已由 iOS 原生 Wallet Core 生成并安装新的 14 天短期批次
  `batch_20260802_e56bbf695db00dab`，默认凭证与旧凭证归档均为本地忽略文件且权限
  为 `0600`；模拟器临时凭证文件、新批次原生密钥及首次失败遗留密钥均已删除。
  新公开地址为 EVM `0xDc989afaBb7142e607cF275E8C86F46b36A96B2C`、TRON
  `TLosVtHkawwuWffoTxr1CRZcrXQLb2Gm6j`、Solana
  `7Gn3q9giKazyNrazByThiYQudQmvpKvDSXEsj4PaY3DC`；助记词未进入日志、文档或报告。
- [x] 2026-08-03 发现上述批次的敏感 JSON 字段名未被一次临时终端脱敏命令匹配，
  因而立即视为泄露并作废；旧 host 文件已删除且不得再注资或执行测试。唯一 iPhone
  17 Pro Simulator 无损恢复后，原生 Wallet Core 已轮换生成 14 天批次
  `batch_20260802_3eb2631a3683a40c`，host 文件为 `0600` 且 credential guard 通过，
  公开地址为 EVM `0xfa1B78714280c3DCF70Af6Dc6b4F5D56fB52aD11`、TRON
  `TRn5vEZomUM4MHbvyoRCuxngTWGaFCWJqj`、Solana
  `4Frj8584f3yv5ZAAVRs6yNXV5bXkVJR91EFPuA3p5q3S`。设备侧私密 JSON 已消费删除；
  临时 native walletId 的删除因生产策略要求 Face ID 而第一次超时；保持生产认证策略
  不变，通过唯一 iPhone 17 Pro Simulator 的系统 Face ID 菜单立即复跑 cleanup-only，
  原生桥明确返回 `E2E-STALE-NATIVE-KEY-DELETED`，随后集成测试 1/1 退出成功。没有重置
  Simulator Keychain，也没有读取或打印助记词；当前已知 provisioning 临时密钥已清理。
- [ ] 原生 E2E 钱包生命周期必须闭合。仓库级
  `tool/audit_e2e_wallet_cleanup.dart` 已建立“零新增技术债”门禁：任何新的
  `storeWallet` 测试若没有显式 `deleteWallet` 或
  `registerE2eWalletCleanup` 会直接失败；已先修复基础真实派生与 Sepolia 签名测试，
  teardown 使用生产系统认证并把超时视为失败，不提供测试后门。初始 24 个原始命中
  中的 23 个真实原生测试已逐文件接入同一清理，原生技术债为 0；剩余 1 个仅使用
  `MockCoreCrypto` 且没有 `MethodChannelCoreCrypto` 的内存 UI 测试被明确排除，未知
  实现不会被自动豁免。
- [x] 2026-08-03 严审发现上述清理门禁仍是文件级字符串判断：注释中的 cleanup、错误
  walletId/`CoreCrypto` 实例、普通成功路径删除、第二个未清理钱包，甚至吞掉删除超时，
  都可能让文件被误判为安全。门禁现使用 Analyzer AST 对每个原生 `storeWallet` 逐站点
  核对同实例、同 walletId，并只接受紧邻注册的生产认证 teardown，或确实覆盖该创建点且
  不吞异常的 `finally` 删除；纯 `MockCoreCrypto` 通过实际变量初始化识别，不再靠原始文本
  豁免。六类绕过先红后绿，真实扫描发现并修复 Sepolia replacement 生命周期，同时把
  EVM replacement 的静默 TimeoutException 路径改为统一认证 teardown。当前 31 个原生
  store 分支、0 源码清理债务。门禁同时解析统一 helper 本身，要求真实注册 `addTearDown`、
  执行同实例 `deleteWallet(walletId).timeout(timeout)`，并只允许忽略
  `WalletNotFoundException`；空 helper 或吞 TimeoutException 的负例均失败。
  `check_deps`、完整静态分析、KT Wallet 1495/1495 与完整公开测试审计 13/13 通过。
  - [x] Polygon 用例新增只接受 `kt-e2e-*` 的中断自愈 helper：同名 slot 只能经生产
    `deleteWallet` 认证删除后重建；认证失败保留旧密钥并终止，不能覆盖。新建、认证替换、
    非测试命名空间和认证失败保持旧地址 4/4 通过；Analyzer 门禁另以缺命名空间、吞认证
    失败和错 walletId 三类绕过自测固定该控制流。
  - [x] 原生 canonicality 集成测试已迁移到统一 `kt-e2e-*` 命名与认证 teardown；本轮
    EVM/TRON/Solana 三次真实签名复核后，临时钱包通过系统密码认证删除，测试 1/1 退出
    成功。该证据只覆盖本轮新建的临时 slot，不代表下述两个既有 Polygon slot 已删除。
  - [ ] 本次复跑暴露的旧 `polygon-amoy-e2e-v2` 与新
    `kt-e2e-polygon-amoy-v3` 两个已知 Simulator 测试 slot 尚需通过系统 Face ID 的
    cleanup-only 路径精确删除。没有重置 Keychain，也没有未经用户确认触发不可恢复删除；
    因此总项暂时恢复为未完成。
- [ ] 新批次尚未补充最小测试网 gas/Token，因此八链真实广播矩阵仍需在注资后重跑；
  旧 EVM 地址关联主网 BNB，只保留在本地安全归档中，不得用于自动化或未授权交易。
  18:31 JST 的 Polygon Amoy 真实预检仍返回 POL=0，签名/广播均未执行。

## P1：达到国际“可靠基础钱包”水平

### P1-01 RPC 与 Gateway 可靠性

- [x] Endpoint 健康评分：每个网络与匿名 endpoint 位置记录成功/失败、熔断状态、
  最近延迟及最近 256 次尝试的 P50/P95；429、超时、畸形响应、传输、5xx、
  provider 路由和其他错误独立分桶。统计不保存 URL、API key、地址或 payload。
- [x] 每链 endpoint 熔断与半开探测。
- [x] App 内同 URL/JSON-RPC 读请求合并；只有显式只读/模拟 allowlist 允许 endpoint
  failover。未知 JSON-RPC 方法与未知 TRON POST 路径默认单端点、单次提交，避免未来
  新增写方法在未分类时被重复发送；广播方法明确不合并、不自动重试。
- [x] EVM `eth_chainId`、Solana genesis hash、TRON block-0 identity 在 RPC
  配置探测和交易构造前双重校验，错误网络在读取 nonce/费用及签名前失败闭合。
- [x] App 直连备用节点在发送钱包地址、交易标识或其他原请求 metadata 前先执行链身份
  探针：EVM 校验 `eth_chainId`，Solana 校验 genesis hash，TRON 校验 block 0 ID；
  错链或错误路由的备用节点直接跳过。2026-08-03 在东京当前网络只读验证 Amoy dRPC、
  BNB 主网 PublicNode、BNB Testnet dRPC/官方备用、Solana 主网 PublicNode 与 TRON
  主网/Nile TronStack 身份正确；DNS 失败、503 或路径 404 的候选已从默认列表移除。
  这不等于中国大陆多运营商可达性验收；Solana Devnet 当前无合格直连备用，仍以
  Gateway 为默认可靠性层。
- [x] App 的 Gateway / RPC 覆盖与自定义网络统一经过端点安全策略：生产只接受
  HTTPS，仅 loopback 开发节点允许 HTTP；禁止内嵌账号凭证、fragment、非法 URL
  和跨链 network override。旧版污染配置在加载时丢弃并恢复安全默认，错误输入停留
  在编辑页展示中英日提示，且不会发出探测请求或写入本地。
- [x] 自定义网络只有显式配置安全的区块浏览器地址时才显示交易/地址/Token 浏览器入口
  与交易凭证二维码；未配置时不再按协议回退到 Ethereum、Solana 或 TRON 主网浏览器，
  避免生成外观正常但指向错误链的链接。交易哈希、地址与 Token 标识在拼入路径前按
  单一路径段编码，不能用 query/fragment 改写目标 URL。两条先红后绿单元测试、无浏览器
  自定义网络 Widget 负例、相关交易/资产回归 53/53、KT Wallet 全量 1448/1448 与静态
  分析 0 通过。
- [x] 链上历史记录贯穿保留产生该记录的具体 `networkId`：Gateway/直连结果由当次活动
  网络标记，本地 Pending 使用数据库中的原始网络，显示缓存升级为 v3 并持久化该字段。
  详情页只允许 `networkId` 能被当前网络注册表解析且链家族一致时显示网络名称、浏览器
  外链与交易凭证二维码；旧 v1/v2 缓存或已删除/跨链网络不再猜测当前活动网络。三组模型/
  服务/快照红测、跨环境 Widget 与失败闭合负例、相关 44/44、KT Wallet 全量 1451/1451、
  静态分析与 `check_deps` 通过。
- [x] 历史记录合并、终态同步和本地详情定位统一使用
  `coin + networkId + normalized txHash` 复合身份，不再假设交易哈希跨链全局唯一。
  EVM/TRON 哈希按大小写不敏感归一化，Solana 签名保持大小写敏感；数据库中的未知 coin
  失败闭合并跳过。旧实现上先复现 Ethereum 远端记录错误确认并隐藏 Polygon 本地 Pending，
  修复后两条记录独立保留且详情选择正确；Solana 大小写负例同步通过。相关 46/46、KT Wallet
  全量 1453/1453、静态分析与 `check_deps` 通过。
- [x] 当前钱包全部网络的 Pending 对账使用固定 4 个 worker，不再按本地行数无界并发请求
  Gateway/RPC。单条 status provider/resolver 若抛出未分类异常，只把该 hash 本轮证据记为
  `unknown` 并继续其他行，不会制造失败/确认或中止整轮刷新。12 条 Pending 压力红测把旧
  峰值稳定复现为 12，修复后峰值精确为 4 且全部完成；单条异常隔离红测同步转绿。钱包/
  网络 generation 改变或页面销毁时，排队 worker 会在出网前停止；前 4 条阻塞时销毁页面
  的红测证明后 8 条不再查询。定向 11/11、静态分析、`check_deps` 与完整源码审计 12/12
  通过。
- [x] 市场/历史刷新异常不再把页面永久锁在 skeleton 或 load-more：展示快照实现即使因
  损坏或本地存储异常直接抛错，控制器也只把它当作 cache miss 并继续实时余额/历史；余额
  Provider、Indexer 或 Drift 的未预期异常会把尚未解析的 loading 行转为明确 error，复位
  `isRefreshing/isLoadingMore`，保留已有 last-good 行且不伪造新更新时间，下一次显式刷新
  可立即重试。无人 await 的 Pending 定时轮询也捕获数据库/插件异常并按 1×/2×/4×/8×
  上限退避，成功或钱包 context 改变后清零，不再因一次本地错误永久停止 finality。
  7 项快照/Provider/Indexer/数据库/结构化并发/轮询故障注入先红后绿，Market + History
  定向 41/41、KT Wallet 1,481/1,481、静态分析 0、`check_deps` 与公开测试源码审计
  12/12 通过。这是
  非视觉状态机与故障恢复证据，不用模拟器截图代替。
- [x] Gateway 多实例无状态部署、共享缓存或一致缓存键。
  - [x] 源码已支持可选 Redis local-first 共享缓存：价格、展示余额和历史保持
    5–30 秒原 TTL；第二 Gateway 实例可命中第一实例写入的数据。共享 key 使用固定
    namespace + SHA-256 指纹，不暴露地址、网络或 Token 集；状态确认、预执行和
    spendable balance 永不进入读缓存。广播只进入独立的 24 小时幂等层：保存签名
    payload 指纹与结果三态，不保存原始交易。严审后进一步移除了旧有 5 秒链参数缓存，包含
    pending nonce 的 `kt_getChainParams` 每次报价都重新访问链节点。
  - [x] 远程 Redis 强制 `rediss://`，明文 `redis://` 只允许 loopback；显式配置但
    启动时不可用会拒绝启动，运行期错误回退本地 miss，并暴露匿名 hit/miss/error
    Prometheus 指标。
  - [x] 1.14.1 修复反向代理后所有用户共用同一 TCP 对端限流桶的生产缺陷：
    只有 `TRUSTED_PROXY_CIDRS` 明确允许的代理才可使用 XFF/X-Real-IP，转发链从右向左
    剥离可信 hop，客户伪造的左侧地址不能获取新配额，非法/过长链回退对端。
    限流表有 65,536 桶硬上限，高基数 IP 攻击进入保守 overflow 桶，不再无界增长。
  - [x] Redis 可选层禁止默认多次命令/连接重试，单次 I/O 上限 750 ms，一次故障后
    打开 5 秒熔断且只允许一个半开恢复探测。本机两实例 + 真 Redis 已证明跨实例
    balance hit；停止 Redis 后真实 Polygon Amoy 余额仍成功，耗时从修复前约 3.47 s
    降至约 0.256 s，并累计匿名 error 指标。并发严审进一步证明：故障打开熔断后，
    更早开始但稍晚完成的成功请求不能错误关闭熔断。
  - [x] 2026-08-02 生产已在同一主机启用两个 systemd Gateway 实例
    `127.0.0.1:8119/8120`、专用 Redis `127.0.0.1:6388` 与 HAProxy
    `127.0.0.1:8118`；Cloudflare/FluxGate 只指向 HAProxy。跨实例首次 miss 后另一实例
    命中共享缓存；停止 Redis 时两实例分别约 198 ms / 142 ms 回退本地 miss，公网仍可用；
    分别停止 primary、secondary 时公网低频健康检查均为 10/10，恢复后 10/10。
    并发 XFF 限流测试为 90 成功 / 110 限流，新的独立客户端仍成功，证明回环代理后
    未把所有用户合并为一个桶。1.16.1 严审后 HAProxy 移除 redispatch/retry-on 并设为
    `retries 0`，避免不可逆 POST 被代理转投另一实例；实例健康传播窗口内的当前读请求
    可能失败，下一请求会选择健康实例。1.16.2 再加入 Redis 原子广播 claim，使 CDN、
    FluxGate、HAProxy、客户端或两个 Gateway 实例即使重复送达相同 POST，也不会产生第二次
    链 RPC write。这里只证明单物理主机冗余，不等同于多地域容灾。
  - [x] 2026-08-03 对独立 FluxGate 仓库完成数据面边界复核：生产基线源码只有一次
    Hyper upstream request、无应用层 retry；最终版本进一步删除上游失败日志中的完整
    URL/query 与 connector error，只保留 bounded upstream name，并加入禁止重复转发和
    动态错误泄漏的结构回归。继续严审发现旧 HTTPS upstream 使用 accept-all verifier；
    现已改为编译内置 Mozilla WebPKI 根并强制证书链与请求主机名校验，运行时正例接受
    可信链，错误主机名和未受信链均拒绝。PEM 解析迁移出已停维的 `rustls-pemfile`，
    畸形链和证书/密钥错配失败闭合；JWT 升级并固定 malformed exp 负例，MaxMind API 同步
    升级。只读生产核对又发现进程常驻约 5.27 GB、6.0 GB access JSONL 的小时级保留任务
    会整文件读取、建立行引用并再次拼接，已造成 writer stall 与日志丢弃。候选现以
    `BufReader`/固定容量 `VecDeque` 流式恢复尾部。大型稳定前缀由独立线程流式整理到
    同目录临时文件，实时 writer 同期继续追加；整理完成后 writer 只短暂停顿合并快照后的
    尾部、`fsync` 并原子替换，再重开 `O_APPEND` 句柄。畸形记录和崩溃留下的不完整尾行
    继续保留。结构回归禁止整文件 `read_to_string`/`join`，并覆盖最新有效尾部、裁剪、
    原子替换、整理期间 200 条实时追加、替换后追加和不完整尾行。
    OSV Scanner 2.3.8 对 300 个 Rust 包结果为 0，CI action 固定到已复核 commit；
    最终格式、全 target/feature 严格 Clippy、Release 构建与工作区 209 项实际执行测试
    通过，9 项基准/长耗时/doc 测试明确 ignored。第一次把同步恢复候选部署到生产时，
    systemd 虽 active，但 6.55 GB access JSONL 使 80/443 延迟约 53 秒才绑定，公网探针
    返回 521，发布门禁随即恢复旧 SHA-256。源码随后改为在 writer/retention 启动前固定
    完整 JSONL 前缀的只读 inode，并将恢复完全放入后台；启动后的实时记录始终位于历史
    尾部之前，原子替换路径也不能使恢复线程重开新 inode 并重复计数。最终修复已记录为
    FluxGate commit `7e68008`，Linux amd64 musl static-pie 为 16,467,488 bytes，SHA-256
    `3436f9b2ea062e5d31085b0b2cc0b370863a272e397c9be3661f8229d57adb86`。
    2026-08-03 08:27:18 UTC 使用时间戳备份和 15 秒监听失败回滚门禁发布；80/443 在
    890 ms 内绑定。24,852,234 条 access 历史在 114 秒后台恢复，完成后进程 RSS 约
    64–69 MiB、warning 为 0；后台保留任务随后原子裁剪 27,227 条记录，writer 未停顿。
    公网 health/ready、Gateway 1.16.13 `kt_health`、Sepolia `kt_getChainParams` 与
    `im-api.nyxnet.jp/.cc` 两条真实 WebSocket 101 握手均通过。旧生产制品及两次候选
    均保留时间戳备份，当前生产精确 SHA 与上述最终制品一致。
- [x] Gateway 当前公开版本新增单一来源门禁：生产 Go 配置中的唯一 SemVer 必须与
  backend README health 示例、根 README 状态表及可靠性段落、P0/P1 生产证据和 HTML
  报告的发布徽标/上线标题逐项一致。门禁只匹配这些“当前状态”标记，允许历史发布记录
  保留旧版本。六个公开面同时改旧的负例先红后绿，缺失和重复源码版本也失败闭合；
  `dep_check` 35/35、test_support 61/61、共享 packages 409/409、默认源码门禁 12/12、
  完整依赖门禁 13/13 和静态分析 0 均通过。该检查防止仓库公开证据漂移，不替代公网
  `kt_health`、制品 SHA 或部署目录的运行时核验。
- [x] `/healthz`、`/readyz`、`kt_health` 匿名 endpoint 汇总、Prometheus
  `/metrics` 与结构化 RPC 日志完成；指标只含 network、匿名位置、结果、错误类型
  和延迟，不含钱包数据或 provider 凭证。1.14.1 默认关闭 `/metrics`；只有配置至少
  32-byte Bearer Token 且请求通过常量时间认证才能读取，公网无凭证返回 404。
  1.14.x 进一步从 RPC 日志删除完整地址与
  曾经保留的首 6/尾 4 截断片段，日志捕获回归证明两种形式均不出现。`/readyz`
  报告单链降级但不会因一条链故障下线仍可服务其他网络的实例；只有全部 JSON-RPC
  网络不可用才返回 503。1.16.5 进一步发现并关闭路由字段注入：未经认证的调用方曾可
  把任意文字放进 `method / chain / network` 后进入日志；现在 method 只接受服务端实际
  注册值，chain/network 只接受固定内置白名单，其余统一记录为 `unknown / invalid`。
  单测与公网 canary 均证明原始输入未进入生产 journal。1.16.7 又关闭错误响应凭证泄漏：
  所有上游客户端丢弃可能携带完整 URL/API key 的 `net/http` 错误，REST/RPC provider
  文本与畸形值不再透传；JSON-RPC read/broadcast 边界独立收敛为固定 upstream 与固定
  文案，常见交易拒绝映射为有限的可操作词汇。跨八类客户端、未知节点错误和边界注入
  测试，以及本地真实进程 credential-bearing URL 故障注入均为 0 泄漏。
- [x] Gateway 1.16.8 关闭 HTTP 请求/响应体截断歧义。旧实现对 4 MiB 入站
  JSON-RPC 和多个 1/8 MiB 上游响应仅使用精确 `LimitReader`，无法区分“刚好到上限”
  与“更大但被截断”；合法 JSON 后追加超大空白仍会执行 handler 或被当作有效上游
  回包。现在所有边界统一读取上限 + 1 字节，超限时在 JSON 解析、缓存和业务处理前
  整体拒绝；Alchemy、Etherscan、Helius、TronGrid、CoinGecko、GoPlus 及通用 EVM/
  Solana RPC 全部覆盖。先红后绿的 3 项边界测试、Gateway 329/329、race、vet、
  govulncheck 与真实本地 4 MiB 请求均通过。Linux amd64 制品为 8,695,970 bytes，
  SHA-256 `c6d14f32de5042e6865cce0cac7a5f4df9a724a2268a3838dc92d3cf386e41d2`。
- [x] 1.16.8 已使用上述精确制品、原子软链接和自动回滚门禁按 secondary → primary
  滚动部署；release 为
  `/opt/workspace/kt-wallet/releases/20260802T094843Z-worktree-v1.16.8-body-integrity`。
  8119/8120 与公网均返回 1.16.8、16 个网络和 ready。公网及两个直连实例分别以
  4 MiB+ 的合法 `kt_health` JSON 前缀验证为 `-32600/id=null`，未执行 handler；价格、
  USDT 搜索、pending/latest 可发送余额、Ethereum USDC GoPlus 风险和无授权隐私同意
  拒绝均通过。当时 Prometheus 2/2 target UP、14/14 rules healthy、0 firing，两个 service
  发布后 warning 为 0；公网未认证 metrics 为 404。
- [x] 2026-08-03 源码补强并生产发布 Gateway 1.16.9 入站资源限流边界：限流器现在在读取请求体和
  JSON 解析之前执行，因此已耗尽配额的客户端不能继续消耗最多 4 MiB 的读取与解析
  资源，畸形 JSON 同样会消耗入站令牌；已知 `Content-Length` 超过上限时在零读取下
  返回固定 `-32600/id=null`。早期拒绝无法安全解析调用方提供的 JSON-RPC id，因此
  统一使用 `id=null`，日志也只记录固定的 `unknown`/空路由标签。3 项先红后绿回归、
  Gateway 336/336、`go test -race ./...` 与 `go vet ./...` 通过。2026-08-03 补跑完整
  `make audit`：`govulncheck` 可达漏洞 0，HAProxy、Alertmanager 与 Token 风险矩阵
  门禁全部通过。Linux amd64 静态制品为 8,700,066 bytes，SHA-256
  `48a05ed2df9de886957e48383a13515860ac54b6593459db72ea20a609cd5283`；第一次滚动因
  primary 刚重启尚未监听而触发自动回滚，确认双实例恢复 1.16.8 后改为有界 ready
  轮询再次发布。最终 release 为
  `/opt/workspace/kt-wallet/releases/20260803T010057Z-worktree-v1.16.9-inbound-limit`，
  8120 → 8119 与公网均返回 1.16.9、16 个网络和 ready。两个直连实例分别用隔离测试
  IP 耗尽配额：后续声明 4 MiB+ 的请求在读取 body 前返回 `-32001/id=null`；新测试 IP
  的同请求返回 `-32600/id=null`。公网 4 MiB+、ETH/USDC 价格、3/3 Prometheus target、
  17/17 rules 与 Alertmanager 均通过，发布后真实 WARN/ERROR/panic/fatal 为 0。
- [x] Gateway 1.16.7 发布版已部署到生产并验证 `kt_getEvmSpendableBalances`。
  2026-08-02 以 SHA 校验、原子软链接、secondary → primary 滚动和自动回滚门禁发布
  `1.16.7`；当时 `kt_health.version=1.16.7`，16 个网络、14 个 JSON-RPC upstream
  组及 `/readyz=200`。Linux amd64 静态制品 SHA-256 为
  `f6f76f83dacc2dbdde9d7715d1f1a66bd47921750aba1174dbfda4d0173fcc67`，
  Go 1.26.5，没有冒充干净 commit。FluxGate commit
  `13e42f64ade4d1f364cae713d612d7f64cfc3841` 源码确认只发出一次 Hyper request，错误/
  超时直接返回 502/504；Cloudflare 官方仍可能在配置多个健康源站且出现特定 52x 时做
  一次 [Zero-Downtime Failover](https://developers.cloudflare.com/fundamentals/security/protect-your-origin-server/#zero-downtime-failover)，
  因此不能只依赖代理。公网连续两次相同安全无效 Sepolia
  payload 已证明响应相同、两个实例合计 endpoint attempt 增量仅 1。
  - [x] 生产只读 smoke 覆盖实时价格与 24h、官方 Token 搜索、EVM pending/latest
    可发送余额、ETH + Solana Portfolio、Alchemy 历史、GoPlus Token 风险及授权；
    无隐私同意的授权查询返回 `-32602`，显式同意的公开零地址查询返回 provider 结果。
  - [x] FluxGate + Cloudflare 实测会丢弃伪造 XFF/X-Real-IP，并向 loopback Gateway
    传递与 WAF 日志一致的清洗后 XFF；生产只信任 `127.0.0.1/32,::1/128`，没有信任
    公网代理段。公网 `/metrics` 无凭证为 404，服务器本地带随机 256-bit Token 为 200。
  - [x] 2026-08-03 使用修正后的真实 FluxGate 工作区
    `/Users/github/Documents/workspace/FluxGate` 复核源码，发现数据平面虽会追加可信
    `X-Forwarded-For`，但旧实现仍可能把客户端原始的 `Forwarded`、XFF、X-Real-IP、
    CF-Connecting-IP 等身份头一并发给上游，且没有删除 `Connection` 动态声明的
    hop-by-hop 字段。源码已改为 HTTP/WebSocket 均先删除六类客户端身份头，只保留代理
    计算出的单一 XFF；同时解析全部 `Connection` token，删除动态 hop-by-hop、
    Proxy-Connection 与 TE。2026-08-03 第二轮严格审阅又发现 WebSocket 识别只读取
    第一条 `Connection` 并以子串匹配 `upgrade`，且上游响应方向没有删除动态 hop 字段；
    现改为遍历全部 field-line、按逗号精确匹配 token，并在请求/101 响应两跳都丢弃原始
    Connection/Upgrade 后只生成规范的 `Connection: Upgrade` 与 `Upgrade: websocket`。
    WebSocket 分类还必须同时满足 GET、唯一且格式有效的 Sec-WebSocket-Key 及 version 13；
    上游 101 缺少合法 Upgrade 语义时固定失败为 502，不能被代理规范化成成功握手。
    4 项单元边界及 4 项真实 HTTP/WebSocket 数据面回读通过。2026-08-03 在用户确认的
    `/Users/github/Documents/workspace/FluxGate` 重新执行完整门禁：FluxGate admin
    121/121、workspace 合计 209 项实际测试通过（9 项 benchmark/doc 用例按设计 ignored），
    fmt、全 target/feature Clippy `-D warnings`、本机 Release 构建及 OSV Scanner 2.3.8
    对 Cargo.lock 300 个包的扫描均通过，已知问题为 0。HAProxy 官方文档确认
    `option forwardfor` 会把自身
    XFF 追加到现有 header list 末尾，因此 Gateway 会按线序展开逗号值和重复 XFF field，
    完整校验后从右向左跳过可信代理；空、畸形、超长 XFF 与重复 X-Real-IP 仍退回可信
    socket peer，且无效 XFF 不会降级读取第二身份头。新增 6 项身份边界用例，Gateway
    `go vet` 与完整 race suite 通过。最终 FluxGate commit `7e68008` / static-pie
    `3436f9b2…adb86` 已使用时间戳备份、15 秒监听和失败回滚门禁部署；80/443 在 890 ms
    内绑定。公网 Gateway health/ready、16-network `kt_health`、真实 Sepolia fee/nonce
    读取以及 `im-api.nyxnet.jp`、`im-api.nyxnet.cc` 两条 101 WebSocket 握手均通过。
    6.55 GB access log 的 24,852,234 条历史在后台恢复期间公网持续可用，完成后 RSS
    约 64–69 MiB、warning 为 0；保留线程再原子裁剪 27,227 条记录。本项已有生产证据，
    不再用源码测试替代线上验证。
  - [ ] 中国大陆多运营商真机网络、持续弱网和跨地域可达性仍需单独验收；生产上线
    证明不等同于大陆网络质量已经达标。
- [ ] 告警规则、监控采集部署及多实例/多地域演练：
  - [x] 仓库已提供 17 条 Prometheus 告警，覆盖实例下线、全部网络不可用、单链降级、
    上游失败率/P95、Redis、Token 风险、授权供应商，以及匿名客户端 fatal/ANR 与广播
    失败趋势；另覆盖广播原子 guard 未配置、不可用/结果持久化失败和损坏共享记录，
    安全供应商熔断持续打开，以及 Alertmanager 未发现、通知错误与通知队列超过 80%。
    客户端规则明确标为
    `untrusted-client-report`，只触发调查，不用于分页或计算人群崩溃率。抓取配置、
    规则文件和真实 `/metrics` 输出均通过 Prometheus 3.12.0 `promtool`；新增三条监控
    管线规则还通过先红后绿的确定性 rule unit tests。
  - [x] 生产 Prometheus 3.12.0 已只监听 `127.0.0.1:9099`，以 30 秒周期直接抓取
    两个 Gateway 和自身 loopback metrics；3/3 target 为 UP，17/17 规则 health=ok，
    保留 7 天且上限
    512 MB。认证 metrics 对 6 个敏感环境值、已知测试地址的扫描命中均为 0，最近
    1000 条双实例日志凭据命中为 0；1.16.5 公网路由字段 canary 原文命中为 0，日志只
    保留 `unknown/invalid` 固定分类；公网未认证 `/metrics` 仍为 404。
  - [x] 生产 Alertmanager 0.32.1 使用官方 digest 固定镜像，只监听
    `127.0.0.1:9098`，禁用集群端口，启用 UTF-8 strict matcher、5 天保留与 silence
    数量/大小上限。Prometheus 实际发现 1 个 Alertmanager；临时 critical canary 经
    Prometheus notification queue 送达 Alertmanager API，正式 17 条规则随后按 SHA
    恢复。四条 destination-free route 分离 critical/warning/default/untrusted，且较高
    严重度按同 environment/service 抑制较低严重度。这里证明本地收件箱、分组、静默与
    投递链路，不冒充外部值班人员已经收到通知。
  - [x] 单主机进程故障、Redis 故障、实例恢复及公网切换演练已通过。
  - [ ] 外部 Alertmanager 邮件/Webhook/值班接收方、生产阈值长期校准，以及跨主机/
    跨地域演练仍未完成；仓库配置刻意不含任何通知目标或凭证。

验收：故障注入单节点 429/超时/错误链/错误 JSON，页面保留最后可信快照并显示
数据时间；不会跨网络返回缓存。

### P1-02 交易预执行与风险解释

- [x] EVM 在热钱包确认及 Cold Signer 请求 QR 生成前，对完全一致的
  `from/to/value/data` 执行 pending-state `eth_call` 与 `eth_estimateGas`；
  revert、畸形返回或 ERC-20 明确返回 false 时禁止签名。Gateway 按活动 network
  代理预执行与估算，失败时才回退用户当前 RPC，且状态相关结果不缓存。
- [x] EVM 确认页从最终待签名 EIP-1559 `unsignedTx` 反解并展示原生币或
  ERC-20 转出量，以及独立的原生币最大网络手续费；反解结果逐字段核对 chainId、
  nonce、recipient、Token contract、amount、gas 与不可变报价，任何漂移都会
  阻止签名。iOS/Android 已分别验证原生币和 ERC-20 页面。
- [x] Solana `simulateTransaction` 解析 program error 和付款账户后置余额；缺失
  ATA 时从同一 message 的实际余额变化计算可回收 rent，响应缺失/畸形时禁止签名。
- [x] TRON constant call/energy、Bandwidth、账户激活与动态链参数统一进入最大费用；
  constant call 失败、资源响应畸形或动态价格缺失时禁止签名。
- [x] 收款地址投毒提示：与联系人、本地钱包或历史地址近似但不完全相同时
  强制二次确认。
- [ ] 恶意/垃圾 Token 和可疑合约风险数据源：
  - [x] Gateway 提供按 `network + 完整合约地址` 精确匹配的运营方风险注册表，
    严格区分 `safe / unsafe / unknown`；畸形配置会阻止 Gateway 启动，风险记录
    优先于官方 Token 身份目录。
  - [x] Token 转账确认页接入三态检测：明确 `unsafe` 时阻止签名；`unknown`
    或服务不可用时显示黄色“无法确认安全”，绝不显示绿色安全；官方蓝勾只表示
    合约身份已验证，不代表投资或合约行为安全。iOS/Android 模拟器已独立执行并截图。
  - [x] Gateway 1.12.0 源码接入独立 GoPlus Token Security API，六条 EVM 主网与
    TRON 主网只发送公开 `chain id + 完整 Token 合约`，不发送钱包地址、余额或交易。
    运营方紧急风险表优先，随后外部明确 honeypot / fake-token / malicious-address /
    gas-abuse 证据可覆盖官方身份目录；无证据保持 `unknown`，429、超时、部分或畸形
    响应返回“无法检查”。5 分钟本地缓存保护 30 次/分钟公共配额；远程地址强制 HTTPS、
    禁止内嵌凭证/fragment/query 和自动重定向，Bearer Token 不会被转发；匿名
    lookup/unsafe/unknown/error/cache-hit 指标已通过自动化和实时 API 验证。
  - [x] Gateway 1.14.1 接入独立 Solana Token Security API；只发送公开完整 mint，
    不发送 owner、余额或交易。解析覆盖 creator、metadata/mint/freeze/close、transfer fee、
    default account state、balance authority 与 transfer hook/upgradable hook；只有这些
    对象内明确 `malicious_address` 才阻止签名。USDC 合法 mint/freeze/metadata 权限不会
    被误判，未知/无数据仍为 unknown，429、畸形 flag、超大响应和重定向失败闭合。
    Devnet 不复用主网情报，运营方紧急风险表仍优先。Gateway handler、App Solana mint
    精确传递/阻止签名、race/vet/vulncheck 与实时 USDC API 查询均已通过。
  - [x] 生产 `gateway.kt-wallet.com` 已部署外部风险 provider；2026-08-02 使用新增
    失败闭合 smoke 工具，对 Ethereum、Polygon、Base、Arbitrum、Avalanche、BNB、
    TRON 与 Solana 各一个官方热门 Token 做只读验收，8/8 返回 `safe` 且来源包含
    `official_catalog+goplus`。工具拒绝不安全端点、缺链目录、transport/RPC 错误、
    unsafe、unknown、畸形和超大响应，正负例已进入默认 Gateway audit。
  - [x] Gateway 1.16.0 为 EVM Token、Solana Token 与 EVM Approval 三个 endpoint
    建立相互隔离的熔断：连续 3 次失败后快速失败闭合 30 秒，恢复时只允许一个半开
    探针；调用方取消不计供应商故障，旧请求成功也不能关闭更新的故障代次。固定标签
    Prometheus 指标、独立熔断告警和版本化运维 runbook 已通过并发测试、race、
    `promtool` 与生产双实例抓取。发布过程中三次门禁真实触发并成功回滚到 1.15.0，
    修正规则权限、jq 作用域与只读单文件 bind-mount 重建流程后才放行 1.16.0。
  - [ ] Alertmanager 通知接收方、供应商长期 SLA/版本监测和用户误报申诉渠道仍未完成；
    一次生产 smoke 与自动熔断不能证明所有链、所有风险类型或供应商长期质量，因此本
    总项保持未完成。
- [ ] ERC-20 授权清单、无限授权提示与撤销交易。
  - [x] Gateway 1.14.1 包含 GoPlus Token Approval Security，当前覆盖
    Ethereum、Polygon、Base、Arbitrum 与 BNB 主网；请求只在用户明确同意隐私披露后
    发出，页面区分高风险、无限授权、有限授权和风险未知，不把无数据误报为安全。
  - [x] 热钱包撤销使用原 Token 合约、原 spender 与精确
    `approve(spender, 0)` calldata；确认后强制钱包认证、执行 EVM 预执行、保存
    `approvalRevoke` 操作类型，并在 Pending、历史、详情、加速与取消中保持正确语义，
    不显示成 `0 Token` 转账，也不会把 spender 误记为本地收款人。
  - [x] 观察钱包可通过 KT Cold Signer QR 往返撤销：在线端生成真实原始交易，离线端
    从原始 calldata 重新解析 Token 与 spender、认证后原生签名，在线端逐字段验签后
    广播；重复请求、错误 operation 和用零金额转账替换撤销报价均失败闭合。
  - [x] 未决撤销在 App 重启/重进页面后恢复并禁止重复提交；speed-up 保留同一
    `approve(spender, 0)`，cancel 明确变为同 nonce 的 0 原生币自转。
  - [x] 生产授权 API 已上线：无 `privacyConsent:true` 的查询明确拒绝；显式同意后对
    公开零地址的只读查询返回 `source=goplus`，证明隐私门禁和 provider 路径同时生效。
  - [ ] 仍需用小额主网钱包完成真实授权发现、热钱包撤销、Cold Signer 撤销、链上
    确认与历史回填，并建立第三方限流、告警、回滚和隐私运营流程，因此本总项保持未完成。

验收：模拟失败禁止签名；风险服务不可用显示“无法检查”，不能显示绿色安全。

### P1-03 体验与可访问性

- [x] 首屏先展示最后可信缓存再后台刷新；离线时保留缓存时间，无整页白屏。
- [x] 前台恢复立即续查 Pending；同一轮多个状态变化排队展示，并按
  `txHash + status` 去重，单次 App 会话只通知一次。
- [x] 首页 → 转账确认 → 认证基础链路具备自动化语义树证据：首页动作、导航返回、
  页面标题、确认明细和主/备用认证操作均可被辅助技术识别；确认明细按“标签 + 值”
  作为一个读取单元。
- [x] 关键链路在 200% 动态字体下自动将明细改为纵向布局，底部操作避让系统安全区；
  主要触控目标不小于 44/48 logical px，系统减少动态效果时取消按压缩放和加载装饰动效。
- [x] `screenRegistry` 34 个生产页面在 320×568 小屏、390×844 标准手机、844×390 横屏
  的 en/zh/ja 三语言环境逐页通过 Flutter
  `labeledTapTargetGuideline`、Android/iOS 触控尺寸和 WCAG 文字对比度门禁；同时把该
  审计纳入默认 Widget 套件。默认字号共 306 个屏幕场景通过。除既有扫描区/遮罩语义、
  搜索框、小图标、窄屏文案和对比度修复外，三语言矩阵还发现并修复了 CJK 短文案使
  首页备份提示、钱包管理、钱包详情、转账 MAX/自定义费率、安全设置及关于页触控区
  缩到 48 px 以下的问题。
- [x] 同一 34 页面在三种视口、200% 动态字体及 en/zh/ja 下逐页通过布局异常、语义
  标签和 Android/iOS 触控尺寸门禁，共 306 个屏幕场景；日文首页余额标题的横向溢出
  已改为可收缩/换行布局，并进一步修复扫码取景器固定高度、窄屏详情行、快捷操作、
  联系人卡片、助记词输入、钱包类型标记、备份提示与手续费卡片。保留 7 个英文大字
  Golden 作为可复核证据，并人工复核、更新本轮布局变化影响的基线。
- [x] 独立 KT Cold Signer 的 21 个注册页面也按 en/zh/ja × 默认/200% 字体执行同一
  三视口门禁，共 378 个屏幕场景。三语言矩阵额外发现并修复首页安全状态和安全设置
  两类 CJK 短文案触控区不足 48 px；三视口又修复扫码页、签名记录、钱包卡片、创建结果
  和删除步骤布局。6 个英文大字 Golden 与受影响默认基线均已复核。两款 App 合计
  55 个页面、990 个语言/视口/字号场景；最终全量 KT Wallet 1424/1424、KT Cold Signer
  562/562 通过。
- [ ] VoiceOver/TalkBack 完成首页 → 转账确认 → 认证基本链路。
  - [x] Android API 35 模拟器启用系统 TalkBack 服务（含触摸探索），使用真实
    Wallet Core 钱包完成首页 → Solana Devnet 转账输入 → 确认 → App 认证选择 →
    系统指纹认证 → 广播 → 链上确认；转账
    [`23J1Vn…XvzzbX`](https://explorer.solana.com/tx/23J1Vn2WniBbsdmGYVgoViGhZmrgErjUKbaQ1eikWEhiW4KjTAVjNL6ZwmuYtWro8L1oXxyPBGAJwAUCEgXvzzbX?cluster=devnet)
    已由官方 RPC 独立验证为 `finalized`、`err=null`、slot `480534314`。焦点截图、
    UIAutomator 语义树与链上结果分别保存，系统认证保护导致的黑屏不作为普通页面
    `FLAG_SECURE` 证据。
  - [ ] iOS VoiceOver 尚未完成同等真实链路；Android 零售真机 TalkBack 仍待验收。
- [ ] 物理设备完成 200% 动态字体和真实读屏逐页人工验收；自动化 55/55 只证明
  渲染、语义标签和触控尺寸，不把规则门禁扩大宣称为 VoiceOver/TalkBack 真机通过。
- [ ] 中英日错误文本不混排，链与 Token 名称不错误翻译。
  - [x] KT Cold Signer 的设备安全检查使用结构化状态并在 UI 层按中英日翻译；助记词
    校验、生物识别、密钥存储、交易解析、签名和删除认证等关键错误已移除生产路径中的
    硬编码中文。英文、中文、日文 Widget 测试及双端原生 UI 测试已覆盖安全检查和删除门槛。
  - [x] 新增生产 Dart 文案静态门禁：扫描 KT Wallet 与 KT Cold Signer 的生产
    `lib/**/*.dart`，禁止直接写入用户可见的中日韩文字与未批准的固定英文 Widget 文案；
    屏幕库、协议示例和语言自称使用逐文件精确白名单，不能用宽泛目录豁免绕过检查。
  - [x] 修复离线导出无效、重复配对、Wallet ID / KT Cold Signer Wallet ID、Cold
    Signer 相机不可用提示及新钱包默认名称的中英日一致性；默认名称由当前语言生成并随
    `AccountExport` 传递，不再把中文“主钱包”永久写入英文或日文钱包。Widget、持久化、
    AccountExport 和 iOS Simulator / Android API 35 UI 测试均已覆盖。
  - [x] 新增三层发布门禁：两款 App 的 Flutter ARB 必须保持中英日用户键与 ICU
    placeholder 完全一致，英文 fallback 禁止混入 CJK；Android 原生 strings 必须保持
    default / zh-rCN / ja 同键；iOS `InfoPlist.strings` 必须完整覆盖显示名、相机、
    Face ID，以及 KT Wallet 的照片写入权限。6 项正负例、`check_deps`、两款 iOS
    Simulator 构建和两份 Android Debug APK 资源表读取均通过；最终 iOS App bundle
    已逐语言读取到权限文案，不只检查源码。
  - [x] 节点广播拒绝从安全英文字符串升级为 16 类结构化原因；在线签名广播、热钱包
    转账、EVM replacement 与授权撤销均只在 UI 层映射中英日文案。任意 Provider、
    数据库或 Dart 异常不再通过 `'$error'` / `error.message` 进入 Snackbar。先用中文
    混排与异常 canary 证明旧路径，再以三语 16/16 映射、定向 19/19、chains 176/176、
    Wallet 全量 860/860 和静态隐私门禁闭合；英文拒绝页 Golden 已人工检查，无方块字
    或 Debug 水印。
  - [x] 2026-08-03 严格复查发现热钱包在签名前缺少活动网络或 EVM Chain ID 时，
    `_showTransferError` 仍直接接收固定英文。生产文案门禁已扩展到 Snackbar/error helper，
    且带插值的错误字符串不再因包含 `$` 被豁免。初次红测捕获固定英文路径；随后新增
    插值 helper 夹具，证明动态路径同样会被拒绝；两条生产英文路径均已移除。新增中英日
    ARB 文案和精确三语回归，定向 4/4、静态分析 0、`check_deps: OK`、KT Wallet 全量
    1446/1446 通过。
  - [x] 2026-08-03 继续审阅无障碍语义时发现 KT Wallet PIN 键盘删除键在三元表达式中
    固定为英文 `Delete`；中文和日文视觉页面正常，但读屏会混入英文。生产文案门禁新增
    named UI 属性三元表达式扫描，先红测精确捕获真实路径；删除键现使用中英日
    `Delete last digit / 删除最后一位 / 最後の桁を削除`，三语 Semantics 回归与门禁
    6/6、静态分析 0、`check_deps: OK`、KT Wallet 全量 1446/1446 通过。
  - [x] ARB 发布门禁进一步拒绝中文/日文值无审阅地与英文 fallback 完全相同；合理保持
    原文的品牌、Nonce、Chain ID、Bluetooth 与占位破折号必须按 App、语言、key 显式
    allowlist，未知语言或 key 也会失败。先红后绿单测和真实双 App 目录通过；六个共享
    package 全量为 65 + 176 + 41 + 26 + 49 + 32 = 389/389。
  - [x] 中文/日文 ARB 新增排版门禁：CJK 文案相邻的半角逗号、冒号和分号默认失败，
    只有 `approve(spender, 0)` 等必须逐字呈现的代码调用可以按 App、语言、key 精确
    放行，未知 allowlist 同样失败。先红后绿回归覆盖门禁本身；同时修正 KT Wallet
    13 条中文与 2 条日文生产文案，网络探测、水龙头和 About Golden 随真实文案同步。
    KT Wallet 1446/1446、test_support 49/49、共享 packages 389/389、两组静态分析及
    `check_deps: OK` 通过。
  - [x] 2026-08-03 品牌一致性复审发现配对说明、账户扫码提示、观察钱包状态和中文
    签名拦截提示仍使用已停用的 `KT Wallet Cold Signer` 或中文界面中的英文名称。
    现统一为英文/日文 `KT Cold Signer`、中文 `KT冷钱包`；新增通用 ARB 禁用词门禁，
    可按语言拒绝退役品牌和语言不匹配名称。门禁单测先红后绿，三语 Widget 回归及受影响
    Golden 已人工复核；最新公开测试源码审计 12/12、完整依赖审计 13/13、KT Wallet
    1514/1514、KT Cold Signer 570/570、共享 packages 409/409、静态分析 0、Gateway
    audit 全部通过。
  - [ ] 真机系统权限弹窗、生命周期保护页及全部生产路由仍需逐页三语语义人工复核，
    因此本总项保持未完成，不能扩大宣称为“全 App 本地化验收完成”。

### P1-04 生产可观测性与支持

- [ ] 隐私友好的 Crash/ANR、启动耗时、RPC 延迟与交易阶段指标。
  - [x] App 已采集首帧启动、Flutter/Platform 错误计数、市场/历史刷新，及 prepare /
    sign / broadcast / finality 交易阶段的耗时与成功状态；队列最多 100 条，诊断导出
    只输出聚合计数和 P50/P95。
  - [x] 上述固定 allowlist 样本已使用版本化 SharedPreferences 在本机跨重启保存；只
    持久化指标名、受限毫秒值和布尔结果，不保存准确事件时间、错误文字或 stack。畸形、
    未知字段和未来 schema 整包拒绝，读写失败不阻止 App 启动或钱包操作。
  - [x] Android 两款 App 均安装进程级 uncaught-exception 观察器和仅前台运行的主线程
    ANR 看门狗；连续阻塞 10 秒才记录一次，后台、调试器和同一轮卡死不会制造重复告警。
    iOS 两款 App 使用 MetricKit 接收系统的 crash / hang 汇总。两端原生队列最多 32 条，
    跨桥只允许单调 ID 与固定 `fatal / anr`，不传输时间、错误名、文字、线程或 stack。
  - [x] App 将原生事件和高水位一起持久化成功后才确认原生队列；写入失败不确认，确认前
    退出后按高水位去重重放。旧 schema 可迁移，未知字段与非单调 ID 失败闭合。
  - [x] About 页新增与本地导出分离的“发送匿名性能报告”：每次都先展示中英日包含/
    排除项并要求用户主动同意；只发送 App 版本、平台、大致语言、构建模式，以及固定
    12 项指标的 count/success/failure/P50/P95。没有后台上传、没有自动重试、没有
    device/session ID、准确时间、地址、交易、错误文字或 stack；重复内容用本地 digest
    抑制。直接连接模式不上传，Gateway URL 必须通过 HTTPS/loopback 安全策略。
  - [x] Gateway 1.15.0 使用严格 closed schema，完整验证后才写入固定标签内存计数，
    不保存请求体或原始事件。生产 Prometheus 只监听 loopback，保留 7 天/512 MB；新增
    两条 info 级、`untrusted-client-report` 告警。公网合成 debug 样本已验证
    `accepted=true/rawEventsStored=false`，下一次 scrape 后匿名上传计数为 1。
  - [x] 匿名上传确认与余额、价格、历史、广播等生产 JSON-RPC 共用响应身份闭合：错
    `jsonrpc`、错 ID/类型、双 result/error 或畸形 error 均不写本地已发送 digest；上传
    仍为单次提交且不自动重试。旧实现会把错 ID 确认当成功的负例先红后绿，并进入生产
    JSON-RPC 所有权门禁。
  - [ ] iOS MetricKit 真正的系统 payload 投递及 Android 真实 ANR/fatal 仍需物理设备
    故障注入验收；匿名未认证样本也不能替代 App Store/Play Console 的可信安装基数或
    外部崩溃平台。因此本总项仍保持未完成，不能宣称已有完整生产崩溃率监控。
- [x] 指标不得包含地址、余额、助记词、签名、完整 tx payload。App 端采用固定 12 项
  名称 allowlist，只记录时长与成功状态，不采集异常文字、stack、参数或返回值；未知
  指标名静默丢弃，观测失败不能打断钱包操作。Gateway 指标只使用 network、匿名
  endpoint 位置、错误分类和延迟。诊断导出层再次以精确 schema allowlist 拒绝未知
  字段与任意字符串，恶意指标名不会进入文件。
- [ ] 远程配置只能调整 endpoint/阈值，不能降低签名与验签规则。
  - [x] 当前版本没有远程配置下载或控制面；签名、验签、认证、风险阻断和交易一致性
    规则均为本地编译代码，Gateway/RPC 用户覆盖又受上述端点策略约束，因此运营端目前
    无法远程开启“跳过验签/允许未知网络”等降级开关。新增的结构审计同时禁止常见远程
    配置/Feature Flag SDK，冻结 Gateway Client 当前 61 个响应字段为逐项复核的闭集，
    并要求 AIRGAP codec、交易认证、PIN、Cold Signer controller 与共享签名验签器五个
    安全模块保持无 HTTP/Gateway import。EVM/TRON/Solana 热钱包签名入口必须使用各自
    精确 unsigned bytes 与 sender 调用独立验签器；Gateway Token 风险只能把状态提升为
    `unsafe/unknown`，不能远程制造 `safe`。审计自带 extractor 负例并已纳入
    `check_deps`，当前输出为 61 fields / 5 network-free modules / 3 signing families。
  - [ ] 若未来引入远程配置，仍需版本化 allowlist schema、配置签名、防回滚、过期和
    kill-switch 边界测试；未完成前不得添加可影响签名/验签的远程字段。
- [x] 支持导出脱敏诊断包。About 页先展示“包含/永不包含”并要求显式确认，再导出
  版本化 JSON；只含 App/构建、平台/语言、内置网络 ID 或 `custom` 标记、服务状态与
  P50/P95 汇总。钱包地址、余额、金额、交易、txHash、密钥、签名、助记词、RPC/
  Gateway URL 永不进入文件；分享返回后清理临时文件。中英日与 iOS/Android UI 已验证。
- [x] 交易问题页面明确提供 hash、网络、广播时间、持久化的最后链状态查询时间、
  完整 hash 复制和按原交易网络打开的浏览器入口；数据库 v7 同时保留最近查询的
  `pending/unknown` 证据，unknown 不会被显示为失败或确认中，且仍参与后台续查。
  iOS/Android 模拟器已独立执行并截图。
- [x] 移动端所有生产 HTTP 响应在缓冲和 JSON 解析前执行统一 8 MiB 硬上限：Gateway、
  EVM/Solana JSON-RPC、TRON REST、区块浏览器历史、CoinGecko、Solana Faucet、
  自定义 RPC 探测及匿名诊断回执均使用同一个 `BoundedHttpClient`。声明
  `Content-Length` 超限会在订阅正文前取消；未知长度、chunked 或解压后正文在跨越上限
  的首个 chunk 立即取消，不保留 URL 或响应内容。静态门禁扫描全部生产 `http.Client()`
  所有权点，防止新增直连绕过；三项流式边界正负例、120 项联网定向回归、静态分析及
  KT Wallet 全量 1446/1446 通过。KT Cold Signer 生产 Dart 仍无 HTTP 依赖。

## 严格测试循环

每轮按以下顺序执行，失败即修复并从相关层重新开始：

1. `dart analyze apps packages tool`
2. `tool/audit_dependencies.sh`（Go call-aware + Dart/npm/Go OSV）
3. packages 的 Dart/Flutter tests
4. KT Cold Signer 全量 tests
5. KT Wallet 全量 tests（含 Golden）
6. Gateway `go test -race ./...`
7. Android Core Crypto JVM tests
8. iOS Simulator 核心 UI 路径和截图
9. Android Emulator 核心 UI 路径和截图
10. 测试网交易与浏览器结果复核
11. Release guard 和敏感信息扫描

2026-08-02 最新循环：`dart analyze apps packages tool` 为 0 问题；依赖审计覆盖
Dart/npm/Go/Android lock 与 Apple 原生依赖，已知漏洞为 0；共享 packages 377/377、
KT Cold Signer 220/220。KT Wallet 首轮发现 1 个陈旧断言仍期待模糊的 `≈ --`，
实际 UI 已明确显示“测试网资产无市场价格”；在保留“不得使用主网报价”负断言的前提
下修正测试后，定向与全量 791/791 通过。随后新增安全存储失败闭合负例并在唯一保留的
iPhone 17 Pro Simulator 运行两款 App 的原生宿主截图测试；KT Wallet 与 Cold Signer
全量分别保持 791/791、217/217，静态分析均为 0。随后修复 Cold Signer 启动派生失败
误擦 metadata/PIN 与 onboarding 补偿清理短路问题；新增 5 项原子性负例后再次全量
217/217；继续修复 KT Wallet 热钱包创建/导入/启动恢复的补偿原子性与重复助记词拒绝，
新增 8 项负例后完整回归提升为 799/799；随后为两款 App 增加跨原生密钥/数据库的
删除墓碑恢复与三语失败反馈，7 项新增故障/UI 负例通过，最终全量为 KT Wallet
803/803、KT Cold Signer 220/220；随后将名称/颜色/备份标记改为持久化后发布，并将
完整钱包排序纳入单一 Drift 事务，2 项故障负例通过，KT Wallet 当时为 805/805。
Gateway race tests、Core Crypto 12/12、
`check_deps`、Android/iOS 匿名诊断系统级模拟器截图及四份已有 Release artifact guard
均通过。随后 Gateway 1.16.0 的安全供应商熔断定向/全量/race/vet/govulncheck 均通过，
Prometheus 14 条规则经 3.12.0 `promtool` 与生产 2/2 target、14/14 health 复核；该轮
没有重新运行全部 Flutter 套件，也没有重新广播测试网交易，不能替代上文链上证据。
随后将所有 App 安全/隐私偏好、Gateway/RPC 与网络环境写入改为串行的提交后发布，
网络配置合并为单一版本化快照，并在 WalletController 关闭前排空 metadata 写队列；
新增 11 项失败/竞态负例。随后将组合安装器设备模式改为提交后发布，新增 9 项失败、
重启、损坏值、并发与 UI 负例；随后双 App 语言设置也改为提交后发布，新增 12 项
控制器与 UI 负例。随后将待签名交易改为先持久化再发布 SignRequest/QR，新增 2 项
故障注入负例；继续把 EVM、TRON、Solana 热钱包发送改为“意图落盘 → 原生签名 →
本地 txHash 落盘 → 首次广播”，新增 6 项数据库不可写和广播响应丢失负例。当前
继续把传输结果拆为 accepted/rejected/unknown，禁止三类链写请求 endpoint failover，
并将 AIRGAP、replacement、授权撤销和热钱包的 unknown 恢复统一到本地 hash 对账；
Gateway 内部 EVM/Solana 广播也改为单端点 `CallOnce`，丢失权威回答时通过
`-32003 submission_unknown` 端到端保留不确定语义；EVM 加速/取消补上钱包认证门禁。
广播/恢复/认证相关 Flutter 定向测试 64/64，Gateway 新增 7 项单次提交故障注入及
12 项跨实例幂等/并发/精度/损坏记录负例并
通过全量、race、vet 与固定版本 govulncheck；`make audit` 新增 HAProxy 模板门禁，
会拒绝非零 retries、redispatch 与 retry-on。Gateway 1.16.1 与 HAProxy
`retries 0` 已滚动上线；随后 Gateway 1.16.2 的 Redis 原子广播 claim 与 1.16.3 的
损坏记录失败闭合校验均完成双实例滚动发布。公网对同一安全无效 Sepolia payload 连续请求两次，响应完全一致，两个实例
合计 endpoint attempt 只增加 1。
最终重新执行结果
为 KT Wallet 860/860、KT Cold Signer 226/226、共享 packages 377/377、
`dart analyze apps packages tool` 0 问题、`check_deps: OK` 与 `git diff --check` 通过；
本轮没有重新广播测试网交易，unknown UI 截图只证明确定性故障注入下的展示与禁止重发，
不替代真实节点接收或链上确认证据。
随后新增 Core Crypto、Gateway Client、直连 RPC 与三链 Provider 错误隐私 canary，修复
原生异常文字、含凭证 URL 和未知节点错误反射；定向 Core Crypto 20/20、HTTP/Gateway/
广播 46/46、chains RPC 34/34、水龙头定向 10/10、KT Wallet 全量 860/860 通过。两款 Android 自有 JVM 测试与
Release runtime 依赖门禁通过，最终 APK 重新构建并通过全 ABI 制品检查；两款 iOS
`iphoneos --release --no-codesign` 与 App Bundle 门禁通过，唯一 iPhone 17 Pro
Simulator 上 KT Wallet XCTest 1/1、KT Cold Signer XCTest 3/3 通过。Gradle 根任务
`testDebugUnitTest` 会进入 `mobile_scanner 7.4.0` 自带测试；2026-08-03 已对其 JUnit
6.1.2 测试 classpath 的 7 个 `.module` 与 6 个 JAR 逐项完成 Maven Central 官方
SHA-256、全新下载与本机缓存三方比对，并以精确集合门禁防止缺失、重复、哈希漂移或
信任扩张。未使用自动生成命令批量接受构件。两款 App 根任务现分别通过 298 与 252 个
actionable tasks；JUnit Vintage、built-in Kotlin 与 Mockito agent 仍保留为上游迁移
warning，JUnit 6 不进入 Release runtime，本次 provenance 核验也不替代安全审计。
旧 Polygon Amoy 公开测试地址虽有 0.000585315121694324 POL 与 16 USDC，但按当前
standard max fee，仅原生币 + USDC 两笔测试的最坏总预算约为 0.002977 POL，且旧
凭证已经作废。轮换批次 `batch_20260802_3eb2631a3683a40c` 的 EVM 地址通过 Gateway
1.16.8 与独立 Amoy RPC 交叉读取均为 0 POL / 0 USDC，因此 Polygon 仍保持未完成。

2026-08-03 对用户指出的测试网确认价格、认证层黑底与双状态栏再次做实现级回归：
Sepolia 确认页必须显示明确的“测试网资产无市场价格”且不得回退为 `≈ --`；认证路由
必须为 `opaque=false` 并保留已确认页面；生产 `KtDeviceChrome` 必须移除设计稿的
`9:41` 状态栏。三项定向 Widget 回归 40/40 通过，六个共享 package 全量为
65 + 176 + 26 + 49 + 32 + 41 = 389/389；双端现有系统截图逐张复核通过。新增的
2 项 test_support 回归固定 Android JUnit 6.1.2 精确审阅集合并拒绝信任扩张；两款
Android 根级 `testDebugUnitTest --offline` 同期通过。

最终 HTML 报告必须包含：环境、commit、任务矩阵、命令结果、截图、链上链接、
失败项目、外部限制和“不可宣称能力”。

2026-08-03 生产夹具隔离复审继续从 Release 可达性而不是字符串存在性出发：Router
显式绑定持久化 `WalletController`，设计 Splash、无钱包的收款/发送/资产/历史/备份、
缺少 pending mnemonic 的创建流程和不存在的 walletId 均在构建页面前拒绝。首页未备份
横幅不再进入新钱包创建流程，改为打开当前 walletId 的详情并沿用强认证助记词导出。
Release 根 App 会拒绝 test-bypass controller，账户/签名扫码的模拟点击回调被物理拆除，
配对 fixture 不在 Release 进程实例化；仓库门禁固定这些边界。先更新两条陈旧断言后，
定向 37/37、KT Wallet 全量 1446/1446、分析 0 与 `check_deps` 全部通过。随后使用真实
Wallet Core 重新构建并门禁 Android APK 137,034,241 bytes、AAB 100,313,693 bytes 和
iOS iphoneos Release Runner.app 72.6 MB；当前仅保留一个关机状态 iPhone 17 Pro
Simulator。制品未签名边界保持不变，本轮未把构建成功冒充商店发布验收。

同日继续复核独立 KT Cold Signer：创建/导入不再只依赖页面是否可见，而由
`idle → mnemonicReview → pinSetup → biometricSetup → completed` 状态机控制。
已有钱包无法重新创建/导入；助记词校验必须与本次原生生成结果逐词一致；PIN 与完成页
不能通过深链跳过；完成页还核对当前 walletId 的真实 metadata。创建和最终提交均有
in-flight 去重，避免双击产生两次原生操作。Gallery 的设置密码页使用显式 preview，
不再污染生产状态。路由、竞态和伪造完成页负例、静态分析与 `check_deps` 通过，
KT Cold Signer 全量 568/568。真实 Wallet Core Android Release APK 重新构建为
127,037,785 bytes，SHA-256
`259cbf56fab2adaea638816a2ebbf1ba31a58f45db8200409f004538fe47ba1b`；制品门禁核对
三 ABI、包名、权限、SQLite 3.53.3、无演示/Mock/本地 E2E 助记词及 provider 凭证。
APK 仍未签名，不能描述为可分发制品。
