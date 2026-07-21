// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTagline => '双机离线钱包 · 联网观察端';

  @override
  String get actionConfirm => '确认';

  @override
  String get actionCancel => '取消';

  @override
  String get actionDelete => '删除';

  @override
  String get actionNext => '下一步';

  @override
  String get actionImport => '导入';

  @override
  String get manage => '管理';

  @override
  String get viewAll => '全部';

  @override
  String get max => '最大';

  @override
  String get tabHome => '首页';

  @override
  String get tabAssets => '资产';

  @override
  String get tabRecords => '记录';

  @override
  String get tabSettings => '设置';

  @override
  String get walletKindHot => '普通';

  @override
  String get walletKindWatch => '观察';

  @override
  String get walletStateBackedUp => '已备份';

  @override
  String get walletStateNotBackedUp => '未备份';

  @override
  String get walletSeedDaily => '日常钱包';

  @override
  String get walletSeedMain => '主钱包';

  @override
  String walletDefaultName(int index) {
    return '钱包 $index';
  }

  @override
  String walletImportedName(int index) {
    return '导入钱包 $index';
  }

  @override
  String get backupBannerText => '尚未备份助记词，存在丢失风险';

  @override
  String get backupNow => '立即备份';

  @override
  String get balanceTitle => '总资产估值 (USD)';

  @override
  String get balanceChangePeriod => '过去24小时';

  @override
  String get actionReceive => '收款';

  @override
  String get actionSend => '转账';

  @override
  String get actionMore => '更多';

  @override
  String get actionScanSign => '扫签名';

  @override
  String get assetsSortByValue => '按持仓价值排序';

  @override
  String get recordsTitle => '交易记录';

  @override
  String get txSent => '转出';

  @override
  String get txReceived => '收款';

  @override
  String get dateToday => '今天';

  @override
  String get dateYesterday => '昨天';

  @override
  String monthDay(int month, int day) {
    return '$month月$day日';
  }

  @override
  String get settingsWalletManage => '钱包管理';

  @override
  String get settingsSecurity => '安全设置';

  @override
  String get settingsAddressBook => '地址簿';

  @override
  String get settingsNetwork => '网络';

  @override
  String get settingsTokenManage => '代币管理';

  @override
  String get addWalletTitle => '添加钱包';

  @override
  String get addWalletStandardSection => '普通钱包 · 便捷';

  @override
  String get createNewWallet => '创建新钱包';

  @override
  String get createNewWalletDesc => '在本机生成新的助记词，立即可用';

  @override
  String get importMnemonic => '导入助记词';

  @override
  String get importMnemonicDesc => '已有 12 / 18 / 24 个单词的助记词';

  @override
  String get coldWalletSection => '离线钱包组合 · 高安全';

  @override
  String get connectColdWallet => '连接离线钱包';

  @override
  String get connectColdWalletDesc => '扫码配对 Cold Signer，私钥永不进入本机';

  @override
  String get createWalletTitle => '创建普通钱包';

  @override
  String get showMnemonic => '显示助记词';

  @override
  String get mnemonicWillGenerate => '接下来将生成助记词';

  @override
  String get hotWalletNotice => '这是一个热钱包：助记词保存在本机安全区。适合小额日常使用，大额资产建议使用离线钱包组合。';

  @override
  String get ruleFullControlTitle => '助记词等于资产的完全控制权';

  @override
  String get ruleFullControlDesc => '任何人拿到这 12 个单词，即可转走你的全部资产';

  @override
  String get ruleHandwriteTitle => '只用纸笔手写备份';

  @override
  String get ruleHandwriteDesc => '不要保存到相册、云盘、备忘录或聊天软件';

  @override
  String get backupMnemonicTitle => '备份助记词';

  @override
  String get mnemonicShowConfirmBtn => '我已手写备份，开始校验';

  @override
  String get mnemonicShowWarning => '请按顺序手写抄录，请勿截图或拍照。任何人获得助记词即可控制资产。';

  @override
  String get verifyBackupTitle => '校验备份';

  @override
  String mnemonicWordChallenge(int position) {
    return '第 $position 个单词是？';
  }

  @override
  String get mnemonicChallengeHint => '从下列单词中选择正确的一项';

  @override
  String get verifyWrong => '选择有误，请对照您手写的备份重试';

  @override
  String get walletCreatedBackedUp => '钱包已创建并完成备份';

  @override
  String get backupVerified => '备份已验证，助记词记录正确';

  @override
  String get mnemonicInvalid => '助记词无效，请检查每个单词后重试';

  @override
  String get mnemonicImported => '助记词已导入';

  @override
  String wordsCount(int count) {
    return '$count 个单词';
  }

  @override
  String get pasteMnemonic => '粘贴助记词（解析后自动清空剪贴板）';

  @override
  String get scanAccountQr => '扫描账户二维码';

  @override
  String get connectColdSubtitle => '从离线手机导入公开地址，创建观察钱包';

  @override
  String get connectColdSafety => '本机永远不会接收或保存助记词、私钥或 Seed。';

  @override
  String get scanAccountHint => '对准 Cold Signer 的地址二维码';

  @override
  String get importConfirmTitle => '确认导入';

  @override
  String get createWatchWallet => '创建观察钱包';

  @override
  String walletIdProtocol(String id, int version) {
    return 'Wallet ID: $id · 协议 v$version';
  }

  @override
  String get walletsTitle => '钱包';

  @override
  String get deleteWalletTitle => '删除钱包';

  @override
  String deleteWalletConfirm(String name) {
    return '确定删除「$name」？此操作仅移除本机记录，不影响链上资产。';
  }

  @override
  String deletedWallet(String name) {
    return '已删除「$name」';
  }

  @override
  String get sortAction => '排序';

  @override
  String walletCountLimit(int count, int max) {
    return '共 $count 个钱包 · 上限 $max 个';
  }

  @override
  String get walletDetailTitle => '钱包详情';

  @override
  String get walletTypeLabel => '钱包类型';

  @override
  String get standardWallet => '普通钱包';

  @override
  String get backupNotYet => '尚未备份助记词';

  @override
  String get viewMnemonic => '查看助记词';

  @override
  String get viewMnemonicDesc => '需要 Face ID 或密码验证';

  @override
  String get deleteWalletDesc => '需身份验证，删除前将再次确认备份状态';

  @override
  String get amountMustBePositive => '金额需大于 0';

  @override
  String get insufficientBalance => '余额不足';

  @override
  String get amountFormatInvalid => '金额格式不正确';

  @override
  String get recipientAddress => '收款地址';

  @override
  String get pasteOrEnterAddress => '粘贴或输入地址';

  @override
  String enterChainAddress(String network) {
    return '请输入 $network 网络收款地址';
  }

  @override
  String addressValidOn(String network) {
    return '地址格式正确 · $network 网络';
  }

  @override
  String get addressInvalid => '地址无效';

  @override
  String get amountLabel => '金额';

  @override
  String availableBalance(String amount, String symbol) {
    return '可用 $amount $symbol';
  }

  @override
  String get selectAsset => '选择资产';

  @override
  String get scanAddressTitle => '扫描地址二维码';

  @override
  String get scanAddressHint => '对准收款地址二维码';

  @override
  String get networkFee => '网络手续费';

  @override
  String get feeCustom => '自定义';

  @override
  String get feeSlow => '慢';

  @override
  String get feeStandard => '标准';

  @override
  String get feeFast => '快';

  @override
  String get confirmFee => '确认手续费';

  @override
  String get feeExplainer => '手续费越高，交易确认越快。费用支付给网络，不进入本 App。';

  @override
  String get feeEtaSlow => '≈ 3-5 分钟';

  @override
  String get feeEtaStandard => '≈ 1 分钟';

  @override
  String get feeEtaFast => '≈ 15 秒';

  @override
  String get feeLowWarning =>
      '手续费过低可能导致交易长时间未确认甚至失败。TRON Energy 不足时将燃烧 TRX 抵扣。';

  @override
  String get confirmTransactionTitle => '确认交易';

  @override
  String get confirmTransfer => '确认转账';

  @override
  String get generateSignQr => '生成待签名二维码';

  @override
  String get hotConfirmHint => '验证身份后本机签名并自动广播';

  @override
  String get watchConfirmHint => '二维码中不包含助记词或私钥';

  @override
  String get fromAddress => '转出地址';

  @override
  String get totalSpend => '总支出';

  @override
  String get unbackedTransferWarning => '该钱包尚未备份助记词。建议先完成备份，再进行转账。';

  @override
  String get pendingSignTitle => '待签名交易';

  @override
  String dynamicShard(int received, int total) {
    return '动态分片 $received / $total';
  }

  @override
  String get networkRow => '网络';

  @override
  String get requestId => '请求 ID';

  @override
  String get scanWithOfflinePhone => '请使用离线签名手机扫描此二维码';

  @override
  String get scanSignResultTitle => '扫描签名结果';

  @override
  String recognizedShard(int received, int total) {
    return '已识别分片 $received / $total';
  }

  @override
  String get broadcastTitle => '广播交易';

  @override
  String get dontBroadcastYet => '暂不广播';

  @override
  String get signatureVerified => '签名已验证 · 签名者与钱包地址一致，交易内容未被篡改';

  @override
  String get signerAddress => '签名地址';

  @override
  String get txHashPreview => '交易 Hash 预览';

  @override
  String get backToHome => '返回首页';

  @override
  String get txSubmitted => '交易已提交';

  @override
  String get txHash => '交易 Hash';

  @override
  String get statusLabel => '状态';

  @override
  String confirming(int received, int total) {
    return '确认中 ($received/$total)';
  }

  @override
  String get txDetailTitle => '交易详情';

  @override
  String get confirmedPrefix => '已确认';

  @override
  String get confirmations => '确认数';

  @override
  String get authToConfirmTransfer => '验证以确认转账';

  @override
  String get authEveryTransfer => '每次转账都需要 Face ID 或密码验证';

  @override
  String get useFaceId => '使用 Face ID 验证';

  @override
  String get usePasscode => '改用密码';

  @override
  String get searchAssetHint => '搜索名称 / Symbol / 合约地址';

  @override
  String get price => '价格';

  @override
  String get change24h => '24h 涨跌';

  @override
  String get contractAddress => '合约地址';

  @override
  String get receiveWarning => '仅支持接收 TRON 网络（TRC-20）资产。从其他网络转入将导致资产丢失。';

  @override
  String get explorerLinkCopied => '区块浏览器链接已复制';

  @override
  String get addressCopied => '地址已复制';

  @override
  String get addressBookTitle => '地址管理';

  @override
  String get searchNameOrAddress => '搜索名称或地址';

  @override
  String get noMatchingContacts => '没有匹配的联系人';

  @override
  String get contactBobExchange => 'Bob 交易所';

  @override
  String get contactColdBackup => '冷钱包备份';

  @override
  String get addContactTitle => '添加联系人';

  @override
  String get nameLabel => '名称';

  @override
  String get addressLabel => '地址';

  @override
  String get invalidChainAddress => '不是有效的链地址';

  @override
  String get actionSave => '保存';

  @override
  String get tokenManageTitle => 'Token 管理';

  @override
  String get addTokenTitle => '添加代币';

  @override
  String get tokenSymbolLabel => '代币符号';

  @override
  String get networkSettingsTitle => '网络设置';

  @override
  String get rpcTimeout => '超时';

  @override
  String get rpcNode => 'RPC 节点';

  @override
  String get accessControl => '访问控制';

  @override
  String get appLock => 'App 锁';

  @override
  String get appLockDesc => '打开 App 时需要 Face ID';

  @override
  String get autoLock => '自动锁定';

  @override
  String get autoLockDesc => '后台超过时限后重新锁定';

  @override
  String get autoLockValue => '1 分钟';

  @override
  String get privacyMode => '隐私模式';

  @override
  String get privacyModeDesc => '首页默认隐藏余额';

  @override
  String get dataSection => '数据';

  @override
  String get fiatUnit => '法币单位';

  @override
  String get displayLanguage => '显示语言';

  @override
  String get deleteWatchWallet => '删除观察钱包';

  @override
  String get deleteWatchWalletDesc => '仅移除公开地址与本地记录，不影响资产';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get modeSelectTitle => '选择设备模式';

  @override
  String get modeSelectSubtitle => '首次使用前，请先确定这台手机的角色';

  @override
  String get modeWalletTitle => '联网钱包';

  @override
  String get modeWalletDesc => '日常使用、查看余额、发起转账';

  @override
  String get modeSignerTitle => '离线签名器';

  @override
  String get modeSignerDesc => '安装在永不联网的手机上，离线保管私钥并签名';

  @override
  String get modeSignerConfirmTitle => '启用离线签名器';

  @override
  String get modeSignerConfirmBody => '此模式供离线设备使用，请开启飞行模式并保持设备永不联网。';

  @override
  String get deviceMode => '设备模式';

  @override
  String get deviceModeSwitchTitle => '切换设备模式';

  @override
  String get deviceModeSwitchDesc => '切换后将返回模式选择页。';

  @override
  String get walletLoadErrorTitle => '钱包加载失败';

  @override
  String get walletLoadErrorDesc => '无法读取本机的钱包数据。请重试;若问题持续,请重新安装应用。';

  @override
  String get actionRetry => '重试';

  @override
  String get renameWallet => '重命名钱包';

  @override
  String get backupTranscribed => '我已抄写';

  @override
  String receiveWarningFor(String network) {
    return '仅支持接收 $network 网络资产。从其他网络转入将导致资产丢失。';
  }

  @override
  String get autoLockImmediate => '立即';

  @override
  String autoLockMinutesLabel(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String get copyAddress => '复制地址';

  @override
  String get noMatchingAssets => '没有匹配的资产';

  @override
  String get noWatchWallet => '当前没有观察钱包';

  @override
  String get watchWalletCreated => '观察钱包已创建';

  @override
  String get marketOfflineDemo => '离线，显示演示数据';
}
