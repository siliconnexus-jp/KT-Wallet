export type Locale = 'en' | 'zh' | 'ja';

export const localePaths: Record<Locale, string> = { en: '/', zh: '/zh/', ja: '/ja/' };

export const translations = {
  "en": {
    "htmlLang": "en",
    "meta": {
      "title": "KT Wallet · Frontend & backend, 100% open source",
      "description": "Two independent apps. One transparent foundation. Multichain assets, offline QR signing and encrypted backups. KT Wallet’s frontend and backend are 100% open source.",
      "social": "An open-source multichain mobile wallet with air-gapped QR signing."
    },
    "skip": "Skip to main content",
    "nav": {
      "aria": "Primary navigation",
      "brandAria": "KT Wallet home",
      "roles": "The two apps",
      "features": "Features",
      "download": "Download",
      "language": "Language"
    },
    "hero": {
      "firstLine": "Your assets.",
      "secondLine": "Your peace of mind.",
      "lede": "An online wallet for everyday use. An independent offline wallet for signing. A clearer way to manage your assets, with code you can inspect from the interface to the gateway.",
      "get": "Explore the apps",
      "source": "Explore all the code",
      "devicesAria": "KT Wallet and KT Cold Signer, captured on Pixel 8 with wallet details replaced",
      "walletAlt": "KT Wallet multichain portfolio screen",
      "signerAlt": "Current offline wallet: QR signing and two-column actions",
      "badge": "Frontend & backend · 100% open source",
      "online": "Everyday, online",
      "offline": "Sign, offline",
      "proof": [
        "Two independent apps",
        "8 networks",
        "iOS & Android"
      ]
    },
    "chainsAria": "Supported blockchains",
    "roles": {
      "title": "Two apps. Each with a clear purpose.",
      "intro": "Use KT Wallet on its own, or connect it to KT Cold Signer on a separate offline device. In the paired setup, only public addresses, signing requests and signed results cross between devices.",
      "walletSubtitle": "Everyday online wallet",
      "walletItems": [
        "Switch between multiple wallets and networks",
        "View assets, receive, transfer and follow activity",
        "Use local signing or connect an offline wallet"
      ],
      "bridgeAria": "Exchange signing requests through QR codes",
      "signerSubtitle": "Fully offline signer",
      "signerItems": [
        "Manage multiple wallets on an offline device",
        "Review addresses, network and amounts before signing",
        "Recognize common tokens from a built-in contract catalog"
      ]
    },
    "features": {
      "title": "Less friction. More clarity.",
      "intro": "From your first backup to your next transfer, the important details stay in view.",
      "items": [
        {
          "title": "Your assets, across eight networks",
          "body": "Network icons, clear asset grouping and filtered activity. The same symbol never replaces a token’s network and contract identity."
        },
        {
          "title": "A backup you can encrypt",
          "body": "Export a wallet’s recovery phrase as a password-encrypted QR image. Import and decrypt it locally with the password. Keep both safe: a lost password cannot be recovered."
        },
        {
          "title": "A smoother way to unlock",
          "body": "With biometric authentication selected, the online wallet prompts automatically at startup. If it fails or you cancel, choose a retry or your wallet password."
        },
        {
          "title": "Review before you sign",
          "body": "Recipient, network, token contract, amount and fee have their own place. Sensitive key access and final transfer authorization remain protected by authentication."
        },
        {
          "title": "English · 中文 · 日本語",
          "body": "Both apps support three languages. Language and display currency are separate from security settings, and each wallet owns its own backup."
        }
      ]
    },
    "security": {
      "titleFirst": "100% open source.",
      "titleSecond": "Frontend. Backend. Both apps.",
      "body": "The online wallet, offline signer and backend gateway are all in the public repository. Read the code, build it yourself and examine how the pieces work together. Security starts with transparency—not a promise of zero risk.",
      "link": "Read the security model",
      "source": "Inspect the repository",
      "layers": [
        {
          "name": "Online wallet",
          "detail": "Assets, activity and transactions",
          "path": "apps/kt_wallet"
        },
        {
          "name": "Offline wallet",
          "detail": "Local keys, transaction review and QR signing",
          "path": "apps/cold_signer"
        },
        {
          "name": "Backend gateway",
          "detail": "Balances, RPC, history and risk checks",
          "path": "backend/gateway"
        }
      ],
      "note": "Open source does not mean independently audited or risk-free. External RPC and data providers are separate services."
    },
    "download": {
      "titleFirst": "Start with the source.",
      "titleSecond": "Follow official releases.",
      "body": "iOS and Android distribution links will be listed here when available. Only install packages from official channels. Keep the offline wallet on a separate device without a network connection.",
      "iosBody": "Public distribution link pending",
      "androidBody": "Public download link pending",
      "pending": "Not yet available",
      "sourceTitle": "Source & build guides",
      "sourceBody": "Both apps, the backend and build instructions",
      "repository": "Official repository:"
    },
    "footer": {
      "tagline": "Frontend & backend, 100% open source",
      "poweredBy": "Powered by Silicon Nexus LLC",
      "privacy": "Privacy",
      "security": "Security & risk",
      "notices": "Third-party notices"
    }
  },
  "zh": {
    "htmlLang": "zh-CN",
    "meta": {
      "title": "KT Wallet · 前后端 100% 开源",
      "description": "在线钱包与离线钱包独立运行。客户端与后端 100% 开源，支持 iOS、Android、多链资产、离线扫码签名和密码加密二维码备份。",
      "social": "开源、多链、支持隔空 QR 签名的移动钱包。"
    },
    "skip": "跳到主要内容",
    "nav": {
      "aria": "主导航",
      "brandAria": "KT Wallet 首页",
      "roles": "两款钱包",
      "features": "产品功能",
      "download": "下载",
      "language": "语言"
    },
    "hero": {
      "firstLine": "资产由你掌控。",
      "secondLine": "安心，从透明开始。",
      "lede": "日常使用的在线钱包，专注签名的独立离线钱包。从清晰的资产界面到后端网关，每一层代码都可以查看。让资产管理更简单，让安全有据可查。",
      "get": "了解两款钱包",
      "source": "查看完整源码",
      "devicesAria": "Pixel 8 真机上的在线与离线钱包，钱包信息已替换",
      "walletAlt": "KT Wallet 多链资产首页",
      "signerAlt": "当前离线钱包：扫码签名与双列功能布局",
      "badge": "前后端 · 完全 100% 开源",
      "online": "日常管理，在线完成",
      "offline": "核对签名，离线完成",
      "proof": [
        "两款独立应用",
        "8 条网络",
        "iOS 与 Android"
      ]
    },
    "chainsAria": "支持的区块链",
    "roles": {
      "title": "在线就是在线，离线就是离线。",
      "intro": "在线钱包可以独立使用，也可以连接另一台设备上的离线钱包。双设备配合时，只通过二维码交换公开地址、待签交易与签名结果。",
      "walletSubtitle": "日常在线钱包",
      "walletItems": [
        "多个钱包自由切换，多条网络统一管理",
        "查看资产、收款转账、跟踪交易活动",
        "选择本机签名，或连接独立离线钱包"
      ],
      "bridgeAria": "通过 QR 二维码交换签名请求",
      "signerSubtitle": "完全离线签名器",
      "signerItems": [
        "在离线设备中管理多个钱包",
        "核对地址、网络与金额后再确认签名",
        "内置常用代币合约目录，离线识别币种与精度"
      ]
    },
    "features": {
      "title": "操作少一点，信息清楚一点。",
      "intro": "从第一次备份到下一笔转账，让真正重要的信息始终看得见。",
      "items": [
        {
          "title": "多链资产，一个清晰的首页",
          "body": "网络图标、资产分组与活动筛选各就其位。同名代币仍按网络与合约区分，不混淆资产身份。"
        },
        {
          "title": "备份，也可以加密成二维码",
          "body": "为单个钱包的助记词设置强密码，导出加密二维码图片。导入时在本机输入密码解密。请妥善保管图片和密码；密码丢失无法找回。"
        },
        {
          "title": "打开钱包，自然完成验证",
          "body": "选择生物识别后，在线钱包启动时自动发起认证。失败或取消，再选择重试或使用钱包密码。"
        },
        {
          "title": "看清楚，再签名",
          "body": "收款地址、网络、代币合约、金额和手续费分层呈现。查看助记词、私钥与转账最终授权，依然需要身份验证。"
        },
        {
          "title": "中、英、日，都顺手",
          "body": "两款应用支持三种语言。语言、法定货币与安全设置分开管理；备份归属于具体钱包，不混淆范围。"
        }
      ]
    },
    "security": {
      "titleFirst": "前后端，100% 开源。",
      "titleSecond": "不是只公开一个界面。",
      "body": "在线钱包、离线钱包、后端网关，全部源码公开。你可以审查代码、自行构建，也可以看清每一部分如何协作。安全第一，从透明开始，而不是承诺绝对安全。",
      "link": "阅读安全与风险说明",
      "source": "查看完整仓库",
      "layers": [
        {
          "name": "在线钱包",
          "detail": "资产管理、交易活动与转账流程",
          "path": "apps/kt_wallet"
        },
        {
          "name": "离线钱包",
          "detail": "本地密钥、交易核对与二维码签名",
          "path": "apps/cold_signer"
        },
        {
          "name": "后端网关",
          "detail": "余额、RPC、交易历史与风险查询",
          "path": "backend/gateway"
        }
      ],
      "note": "开源不代表零风险，也不等同于已通过独立安全审计。外部 RPC 与数据提供商属于独立服务。"
    },
    "download": {
      "titleFirst": "源码，现在就能看。",
      "titleSecond": "安装，请认准官方。",
      "body": "iOS 与 Android 的公开分发链接就绪后会在此列出。请只从官方渠道获取安装包。离线钱包应安装在独立设备上，并保持断网使用。",
      "iosBody": "公开分发链接准备中",
      "androidBody": "公开下载链接准备中",
      "pending": "暂未开放",
      "sourceTitle": "源码与构建指南",
      "sourceBody": "两款应用、后端网关与完整构建说明",
      "repository": "官方仓库："
    },
    "footer": {
      "tagline": "前后端 100% 开源 · 安全第一",
      "poweredBy": "由 Silicon Nexus LLC 提供动力",
      "privacy": "隐私政策",
      "security": "安全与风险",
      "notices": "第三方许可"
    }
  },
  "ja": {
    "htmlLang": "ja",
    "meta": {
      "title": "KT Wallet · フロントエンドもバックエンドも、100% オープンソース",
      "description": "オンラインとオフライン、二つの独立したウォレット。iOS・Android に対応。フロントエンドもバックエンドも完全公開。QR 署名、暗号化バックアップ、マルチチェーン管理。",
      "social": "エアギャップ QR 署名に対応した、オープンソースのマルチチェーンウォレット。"
    },
    "skip": "メインコンテンツへ移動",
    "nav": {
      "aria": "メインナビゲーション",
      "brandAria": "KT Wallet ホーム",
      "roles": "二つのアプリ",
      "features": "機能",
      "download": "ダウンロード",
      "language": "言語"
    },
    "hero": {
      "firstLine": "資産を、自分の手に。",
      "secondLine": "安心を、透明性から。",
      "lede": "日常のためのオンラインウォレット。署名に集中する独立したオフラインウォレット。使いやすい画面からゲートウェイまで、すべてのコードを確認できます。",
      "get": "二つのアプリを見る",
      "source": "すべてのソースを見る",
      "devicesAria": "Pixel 8 で撮影したオンラインとオフラインのウォレット。ウォレット情報は差し替え済み",
      "walletAlt": "KT Wallet のマルチチェーン資産画面",
      "signerAlt": "現在のオフラインウォレット：QR 署名と2列のアクション",
      "badge": "フロントエンドもバックエンドも 100% 公開",
      "online": "日常の管理は、オンライン",
      "offline": "確認と署名は、オフライン",
      "proof": [
        "独立した二つのアプリ",
        "8 ネットワーク",
        "iOS & Android"
      ]
    },
    "chainsAria": "対応ブロックチェーン",
    "roles": {
      "title": "二つのアプリ。それぞれの役割。",
      "intro": "KT Wallet は単体でも、別のオフライン端末の KT Cold Signer と組み合わせても使えます。連携時に QR で交換するのは公開アドレス、署名リクエスト、署名結果だけです。",
      "walletSubtitle": "日常利用のオンラインウォレット",
      "walletItems": [
        "複数のウォレットとネットワークを切り替え",
        "資産の確認、送受信、取引履歴を管理",
        "端末内で署名、またはオフラインウォレットと連携"
      ],
      "bridgeAria": "QR コードで署名リクエストを交換",
      "signerSubtitle": "完全オフライン署名端末",
      "signerItems": [
        "オフライン端末で複数のウォレットを管理",
        "アドレス、ネットワーク、金額を確認して署名",
        "内蔵の主要トークン一覧で銘柄と桁数を識別"
      ]
    },
    "features": {
      "title": "操作は少なく。情報は明確に。",
      "intro": "最初のバックアップから次の送金まで、大切な情報を見失わないために。",
      "items": [
        {
          "title": "8 ネットワークの資産を、一つの画面に",
          "body": "ネットワークアイコン、資産のグループ表示、履歴の絞り込み。同じシンボルでも、ネットワークとコントラクトで区別します。"
        },
        {
          "title": "バックアップを、暗号化 QR に",
          "body": "ウォレットごとのフレーズを強いパスワードで暗号化し、QR 画像として保存。読み込み時は端末内で復号します。画像とパスワードを安全に保管してください。パスワードを紛失すると復元できません。"
        },
        {
          "title": "開くと、すぐに認証",
          "body": "生体認証を選択している場合、オンラインウォレットの起動時に自動で認証。失敗やキャンセルの後は、再試行かウォレットのパスワードを選べます。"
        },
        {
          "title": "確認してから、署名する",
          "body": "宛先、ネットワーク、コントラクト、金額、手数料を整理して表示。フレーズや秘密鍵の確認、送金の最終承認には認証が必要です。"
        },
        {
          "title": "English · 中文 · 日本語",
          "body": "両アプリが3言語に対応。言語・表示通貨とセキュリティ設定を分離し、バックアップは各ウォレットで管理します。"
        }
      ]
    },
    "security": {
      "titleFirst": "100% オープンソース。",
      "titleSecond": "画面も、バックエンドも。",
      "body": "オンラインウォレット、オフラインウォレット、バックエンドゲートウェイをすべて公開。コードの確認、自分でのビルド、仕組みの検証ができます。安全を最優先に、透明性から始めます。",
      "link": "セキュリティとリスクを読む",
      "source": "全ソースを確認",
      "layers": [
        {
          "name": "オンラインウォレット",
          "detail": "資産管理、履歴、送金フロー",
          "path": "apps/kt_wallet"
        },
        {
          "name": "オフラインウォレット",
          "detail": "端末内の鍵、取引確認、QR 署名",
          "path": "apps/cold_signer"
        },
        {
          "name": "バックエンド",
          "detail": "残高、RPC、取引履歴、リスク照会",
          "path": "backend/gateway"
        }
      ],
      "note": "オープンソースはリスクがないことや独立監査済みであることを意味しません。外部 RPC・データプロバイダーは別のサービスです。"
    },
    "download": {
      "titleFirst": "ソースは、今すぐ。",
      "titleSecond": "入手は、公式から。",
      "body": "iOS・Android の公開配布リンクは準備でき次第掲載します。必ず公式の配布元をご利用ください。オフラインウォレットは別の端末にインストールし、ネット接続を切って使用してください。",
      "iosBody": "公開配布リンクを準備中",
      "androidBody": "公開ダウンロードリンクを準備中",
      "pending": "未公開",
      "sourceTitle": "ソースとビルド手順",
      "sourceBody": "両アプリ、バックエンド、ビルドガイド",
      "repository": "公式リポジトリ："
    },
    "footer": {
      "tagline": "フロントエンドもバックエンドも 100% 公開",
      "poweredBy": "Silicon Nexus LLC が提供",
      "privacy": "プライバシー",
      "security": "セキュリティとリスク",
      "notices": "第三者ライセンス"
    }
  }
} as const;
