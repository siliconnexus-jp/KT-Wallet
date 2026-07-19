# UI 实现任务清单（全部 52 屏）

目标：把 Pencil 设计稿(ui.pen, W1–W31 + C1–C21)全部实现成可运行的 Flutter 界面，
接已测试的业务逻辑(状态机/WalletManager/校验器/WalletStore)，每屏对照设计 1:1。

节奏：共享基础设施先行 → 按流程分批实现 → 每批 `flutter test` + 浏览器实跑对比。
已完成：W20 首页(样板)。

## U0 共享基础设施
- go_router 路由表(映射 W*/C* → 路由)。
- 应用外壳:两套主题(KT Wallet 浅色 / Cold Signer 深色)。
- 扩展 ui_kit 共享组件:StatusBar、NavBar(返回/标题/右操作)、ScreenScaffold、
  SectionCard、ListRow、QrCard(占位二维码)、SegmentedControl、Numpad、
  WordGrid(助记词栅格)、Avatar、BottomTabBar、BottomSheet 容器。

## U1 KT Wallet — 钱包接入与管理(12 屏)
W10 启动页, W11 连接离线钱包, W12 扫描账户二维码, W13 导入确认,
W22 添加钱包, W23 创建钱包安全提示, W24 助记词展示, W25 助记词校验,
W26 助记词输入, W21 钱包切换器(sheet), W27 钱包管理, W28 钱包详情编辑。

## U2 KT Wallet — 首页与资产(4 屏，首页已完成)
W1 观察钱包首页(首页变体), W2 资产列表, W3 Token 详情, W14 收款。

## U3 KT Wallet — 转账双流程(10 屏)
W4 转账输入, W31 手续费选择, W5 交易确认(观察), W29 交易确认(普通),
W30 转账身份验证(sheet), W6 待签名二维码, W7 扫描签名结果, W8 广播确认,
W9 广播结果, W15 交易详情。

## U4 KT Wallet — 设置(4 屏)
W16 地址管理, W17 Token 管理, W18 网络设置, W19 安全设置。

## U5 Cold Signer — Onboarding(9 屏)
C11 启动页, C1 欢迎, C12 助记词安全提示, C3 助记词展示, C4 助记词校验,
C13 助记词输入, C14 设置密码, C15 生物识别设置, C16 创建成功。

## U6 Cold Signer — 首页与签名(8 屏)
C5 离线首页, C2 离线安全检查, C6 扫描交易, C7 交易解析确认, C17 风险警告,
C8 身份验证, C9 签名结果二维码, C10 地址导出。

## U7 Cold Signer — 记录与设置(4 屏)
C18 签名记录, C19 钱包管理, C20 安全设置, C21 删除钱包。

## 每批完成定义
- 屏幕渲染无 overflow;widget 测试关键元素存在。
- 浏览器/设备实跑截图,对照设计图确认布局/颜色/文案一致。
- `dart analyze` 干净。
