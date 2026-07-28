export type Locale = 'en' | 'zh' | 'ja';

export const localePaths: Record<Locale, string> = {
  en: '/',
  zh: '/zh/',
  ja: '/ja/',
};

export const translations = {
  en: {
    htmlLang: 'en',
    meta: {
      title: 'KT Wallet · Assets online. Keys offline.',
      description:
        'KT Wallet is an open-source multichain wallet for iOS and Android, paired with the fully offline KT Cold Signer.',
      social: 'An open-source multichain mobile wallet with air-gapped QR signing.',
    },
    skip: 'Skip to main content',
    nav: {
      aria: 'Primary navigation',
      brandAria: 'KT Wallet home',
      roles: 'Two devices',
      features: 'Capabilities',
      download: 'Download',
      language: 'Language',
    },
    hero: {
      firstLine: 'Assets online.',
      secondLine: 'Keys offline.',
      lede:
        'KT Wallet separates everyday multichain asset management from offline signing. Review balances, build a transaction, scan a QR code, then sign on a device that never goes online.',
      get: 'Get KT Wallet',
      source: 'View source',
      devicesAria: 'KT Wallet and KT Cold Signer app interfaces',
      walletAlt: 'KT Wallet multichain portfolio screen',
      signerAlt: 'KT Cold Signer offline signing welcome screen',
    },
    chainsAria: 'Supported blockchains',
    roles: {
      title: 'One system, two trust boundaries.',
      intro:
        'The online device sees the network. The offline device protects the keys. Clear responsibilities make security decisions easier.',
      walletSubtitle: 'Everyday online wallet',
      walletItems: [
        'View multichain balances and history',
        'Build, broadcast, and track transactions',
        'Use a hot wallet or watch-only wallet',
      ],
      bridgeAria: 'Exchange signing requests through QR codes',
      signerSubtitle: 'Fully offline signer',
      signerItems: [
        'Seed phrases and private keys stay offline',
        'Review the parsed raw transaction before signing',
        'PIN, biometrics, and device security checks',
      ],
    },
    features: {
      title: 'Every step rejects “looks successful.”',
      intro:
        'Balance failures never become a fake zero. A transaction is blocked when fees cannot be estimated. Signed results must match the original request field by field.',
      items: [
        {
          title: 'One entry point, eight networks',
          body: 'Balances, prices, tokens, and history in one place. Assets remain strictly separated by network and contract.',
        },
        {
          title: 'Real signing, no demo path',
          body: 'Native Wallet Core handles derivation and signing. If an operation cannot be performed safely, it stops.',
        },
        {
          title: 'Full transaction lifecycle',
          body: 'Track submitted, pending, and confirmed states across restarts, with EVM speed-up and cancellation.',
        },
        {
          title: 'Private in the app switcher',
          body: 'Wallet content is hidden as soon as the app enters the background, with screenshot alerts where supported.',
        },
        {
          title: 'English · 中文 · 日本語',
          body: 'Interface copy and app names follow the selected language for a consistent experience across regions.',
        },
      ],
    },
    security: {
      titleFirst: 'Security is not one switch.',
      titleSecond: 'It is a closed set of conditions.',
      body:
        'KT Cold Signer checks network, screen recording, and device state. Signing stops whenever a critical condition is unsafe or cannot be verified.',
      link: 'Read the security model',
    },
    download: {
      titleFirst: 'Public builds are in progress.',
      titleSecond: 'The source is available now.',
      body:
        'The project is open source. The first public iOS and Android builds have not been released yet. Only install builds linked from this page or the official GitHub repository.',
      iosBody: 'First public build in progress',
      androidBody: 'Signed release package in progress',
      pending: 'Coming soon',
      sourceTitle: 'GitHub source',
      sourceBody: 'Build guides, test reports, and complete code',
      repository: 'Official repository:',
    },
    footer: {
      tagline: 'Open-source air-gapped wallet',
      privacy: 'Privacy',
      security: 'Security & risk',
      notices: 'Third-party notices',
    },
  },
  zh: {
    htmlLang: 'zh-CN',
    meta: {
      title: 'KT Wallet · 资产在线，密钥离线',
      description:
        'KT Wallet 是面向 iOS 与 Android 的开源多链钱包，支持在线钱包与完全离线的 KT Cold Signer。',
      social: '开源、多链、支持隔空 QR 签名的移动钱包。',
    },
    skip: '跳到主要内容',
    nav: {
      aria: '主导航',
      brandAria: 'KT Wallet 首页',
      roles: '双设备',
      features: '能力',
      download: '下载',
      language: '语言',
    },
    hero: {
      firstLine: '资产在线。',
      secondLine: '密钥离线。',
      lede:
        'KT Wallet 把日常多链资产管理与离线签名拆成清晰的信任边界。看余额、构建交易、扫描 QR，然后在不联网的设备上完成签名。',
      get: '获取 KT Wallet',
      source: '查看源码',
      devicesAria: 'KT Wallet 与 KT Cold Signer 应用界面',
      walletAlt: 'KT Wallet 多链资产首页',
      signerAlt: 'KT Cold Signer 离线签名器欢迎界面',
    },
    chainsAria: '支持的区块链',
    roles: {
      title: '一套系统，两个信任边界。',
      intro:
        '在线设备负责看见世界，离线设备只负责守住密钥。职责越清晰，安全判断越简单。',
      walletSubtitle: '日常在线钱包',
      walletItems: [
        '查看多链余额与交易记录',
        '构建、广播并跟踪交易',
        '热钱包或观察钱包两种方式',
      ],
      bridgeAria: '通过 QR 二维码交换签名请求',
      signerSubtitle: '完全离线签名器',
      signerItems: [
        '助记词与私钥留在离线设备',
        '解析原始交易后再授权签名',
        'PIN、生物识别与设备安全检查',
      ],
    },
    features: {
      title: '每一步，都拒绝“看起来成功”。',
      intro:
        '余额失败不会伪装成 0；手续费无法估算就不发送；签名结果必须与原始请求逐项一致。',
      items: [
        {
          title: '一个入口，八条网络',
          body: '统一查看余额、价格、Token 与交易记录。相同资产按网络和合约严格区分。',
        },
        {
          title: '真实签名，不走演示路径',
          body: '原生 Wallet Core 完成派生和签名；无法安全执行时，交易会被阻止。',
        },
        {
          title: '交易全生命周期',
          body: '从 submitted、pending 到 confirmed，重启后继续跟踪；EVM 支持加速与取消。',
        },
        {
          title: '保护任务切换画面',
          body: '进入后台立即隐藏钱包内容；系统支持时，截屏会触发安全提醒。',
        },
        {
          title: '中 · 英 · 日',
          body: '界面与应用名称跟随所选语言，为不同地区的日常使用保持一致体验。',
        },
      ],
    },
    security: {
      titleFirst: '安全不是一个开关，',
      titleSecond: '而是一串闭合条件。',
      body:
        'KT Cold Signer 会检查网络、录屏与设备状态。任何关键条件不安全或无法确认时，签名都会停止。',
      link: '阅读安全模型',
    },
    download: {
      titleFirst: '公开构建正在准备。',
      titleSecond: '源码现在就能查看。',
      body:
        '项目已经开源。首个公开 iOS / Android 安装版本尚未发布；请只从本页或官方 GitHub 获取，避免安装来源不明的钱包应用。',
      iosBody: '首个公开版本准备中',
      androidBody: '签名发布包准备中',
      pending: '即将上线',
      sourceTitle: 'GitHub 源码',
      sourceBody: '构建文档、测试报告与完整代码',
      repository: '官方仓库：',
    },
    footer: {
      tagline: '开源隔空签名钱包',
      privacy: '隐私政策',
      security: '安全与风险',
      notices: '第三方许可',
    },
  },
  ja: {
    htmlLang: 'ja',
    meta: {
      title: 'KT Wallet · 資産はオンライン、鍵はオフライン',
      description:
        'KT Wallet は iOS・Android 向けのオープンソースマルチチェーンウォレットです。完全オフラインの KT Cold Signer に対応します。',
      social: 'エアギャップ QR 署名に対応した、オープンソースのマルチチェーンウォレット。',
    },
    skip: 'メインコンテンツへ移動',
    nav: {
      aria: 'メインナビゲーション',
      brandAria: 'KT Wallet ホーム',
      roles: '2台構成',
      features: '機能',
      download: 'ダウンロード',
      language: '言語',
    },
    hero: {
      firstLine: '資産はオンライン。',
      secondLine: '鍵はオフライン。',
      lede:
        'KT Wallet は、日常のマルチチェーン資産管理とオフライン署名を明確に分離します。残高確認、取引作成、QR スキャンを行い、ネット接続のない端末で署名します。',
      get: 'KT Wallet を入手',
      source: 'ソースを見る',
      devicesAria: 'KT Wallet と KT Cold Signer のアプリ画面',
      walletAlt: 'KT Wallet のマルチチェーン資産画面',
      signerAlt: 'KT Cold Signer のオフライン署名画面',
    },
    chainsAria: '対応ブロックチェーン',
    roles: {
      title: '一つのシステム、二つの信頼境界。',
      intro:
        'オンライン端末はネットワークを見て、オフライン端末は鍵を守ります。役割が明確であるほど、安全性を判断しやすくなります。',
      walletSubtitle: '日常利用のオンラインウォレット',
      walletItems: [
        'マルチチェーンの残高と履歴を確認',
        '取引を作成・送信・追跡',
        'ホットウォレットまたは監視専用で利用',
      ],
      bridgeAria: 'QR コードで署名リクエストを交換',
      signerSubtitle: '完全オフライン署名端末',
      signerItems: [
        'シードフレーズと秘密鍵をオフラインで保持',
        '生の取引内容を解析してから署名',
        'PIN、生体認証、端末セキュリティチェック',
      ],
    },
    features: {
      title: '「成功したように見える」を許さない。',
      intro:
        '残高取得の失敗を 0 と表示せず、手数料を見積もれなければ送信しません。署名結果は元のリクエストと項目ごとに照合します。',
      items: [
        {
          title: '一つの入口、八つのネットワーク',
          body: '残高、価格、トークン、履歴を一元表示。同じ資産でもネットワークとコントラクトを厳密に区別します。',
        },
        {
          title: 'デモではない実署名',
          body: 'ネイティブ Wallet Core が派生と署名を実行。安全に処理できない場合は停止します。',
        },
        {
          title: '取引の全ライフサイクル',
          body: 'submitted、pending、confirmed を再起動後も追跡し、EVM の高速化とキャンセルに対応します。',
        },
        {
          title: 'アプリ切替画面も保護',
          body: 'バックグラウンド移行時に内容を即座に隠し、対応環境ではスクリーンショットを通知します。',
        },
        {
          title: 'English · 中文 · 日本語',
          body: '選択した言語に合わせて UI とアプリ名を表示し、地域を問わず一貫した体験を提供します。',
        },
      ],
    },
    security: {
      titleFirst: '安全は一つのスイッチではなく、',
      titleSecond: '閉じた条件の積み重ねです。',
      body:
        'KT Cold Signer はネットワーク、画面収録、端末状態を確認します。重要な条件が危険または確認不能なら、署名を停止します。',
      link: 'セキュリティモデルを読む',
    },
    download: {
      titleFirst: '公開ビルドを準備中。',
      titleSecond: 'ソースは今すぐ確認できます。',
      body:
        'プロジェクトはオープンソースです。iOS・Android の初回公開ビルドはまだ未公開です。このページまたは公式 GitHub から案内されるビルドのみをご利用ください。',
      iosBody: '初回公開ビルドを準備中',
      androidBody: '署名済みリリースを準備中',
      pending: '近日公開',
      sourceTitle: 'GitHub ソース',
      sourceBody: 'ビルド手順、テストレポート、完全なコード',
      repository: '公式リポジトリ：',
    },
    footer: {
      tagline: 'オープンソース・エアギャップウォレット',
      privacy: 'プライバシー',
      security: 'セキュリティとリスク',
      notices: '第三者ライセンス',
    },
  },
} as const;
