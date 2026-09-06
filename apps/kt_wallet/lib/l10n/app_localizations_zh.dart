// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get signResultSaveFailed => '无法安全保存签名结果。尚未广播，请重新扫描后重试。';

  @override
  String get settingsGeneral => '通用';

  @override
  String get generalSettingsDescription => '语言和计价货币适用于整个 App，不影响钱包或链上资产。';

  @override
  String get backupThisWallet => '备份此钱包';

  @override
  String get backupScopeDescription => '仅备份此钱包的恢复信息，不包含其他钱包、联系人或 App 设置。';

  @override
  String get backupEncryptedOptions => '加密文件或二维码';

  @override
  String get backupTargetLabel => '正在备份的钱包';

  @override
  String get backupWalletUnavailable => '此钱包不可备份，请返回钱包管理重新选择。';

  @override
  String get backupQrTitle => '加密二维码';

  @override
  String get backupFileFormat => '备份文件';

  @override
  String get backupQrIntro =>
      '使用独立强密码在本机加密助记词，生成带 KT Wallet 品牌的二维码图片。图片不包含明文助记词或密码。';

  @override
  String get backupQrWarning =>
      '我已了解：持有图片的人可以离线尝试猜测密码；忘记密码无法恢复。请将密码与图片分开保管，并保留手抄助记词。所选文件夹可能会同步到云端。';

  @override
  String get backupQrImageInstruction =>
      '需要密码 · 不是收款码\n在 KT Wallet 中选择「从备份恢复」→「扫描加密二维码」或「选择二维码图片」。请勿公开此图片，密码须分开保管。';

  @override
  String get backupQrGenerate => '生成加密二维码';

  @override
  String get backupQrSave => '保存二维码图片到本地';

  @override
  String get backupQrScan => '扫描加密二维码';

  @override
  String get backupQrPickImage => '选择二维码图片';

  @override
  String get backupQrScanHint => '扫描 KT Wallet 加密备份二维码，下一步输入备份密码。';

  @override
  String get backupQrInvalid => '未找到有效的加密备份二维码，请选择只包含一个二维码的原始 PNG/JPEG 图片。';

  @override
  String get backupQrRestoreIntro =>
      '支持加密备份文件、扫描二维码或选择已保存的二维码图片。解密在本机完成，需要输入备份密码。';

  @override
  String get secretAccessRiskTitle => '查看前请注意';

  @override
  String get secretAccessContinue => '我已了解，继续';

  @override
  String get mnemonicAccessRisk =>
      '助记词可以恢复整个钱包。任何人获取它，都可能转走你的资产。\n\n请在无人旁观时查看，不要截图、录屏或分享。';

  @override
  String get privateKeyAccessRisk =>
      '私钥可以控制对应账户。任何人获取它，都可能转走该账户的资产。\n\n请在无人旁观时查看，不要截图、录屏或分享。';

  @override
  String get tabWallet => '钱包';

  @override
  String get tabActivity => '活动';

  @override
  String get scanSignedResultNext => '离线设备已签名，扫描结果';

  @override
  String backupCheckProgress(int current, int total) {
    return '备份抽查 $current / $total';
  }

  @override
  String get introOpenTitle => '前后端 100% 开源';

  @override
  String get introOpenDescription => '从钱包界面、离线签名到后端网关，代码全部公开。让信任建立在可审查的代码上。';

  @override
  String get introOpenNote => '查看完整源码，了解资产如何被保护。公开可审查，也欢迎持续改进。';

  @override
  String get introSecurityTitle => '安全第一。\n掌控始终在你。';

  @override
  String get introFrontend => '客户端';

  @override
  String get introBackend => '后端网关';

  @override
  String get introOnline => '在线钱包';

  @override
  String get introOffline => '离线签名端';

  @override
  String get introNext => '继续';

  @override
  String get introSkip => '跳过引导';

  @override
  String get introBack => '上一步';

  @override
  String get introSource => '查看开源代码';

  @override
  String get introSourceHint => '使用联网设备扫描二维码查看完整源码。此页面不会发起网络请求。';

  @override
  String get introCopyLink => '复制源码地址';

  @override
  String get introCopied => '源码地址已复制';

  @override
  String get introSaveFailed => '未能保存引导状态，请重试。';

  @override
  String get introRole => '独立在线钱包';

  @override
  String get introSecurityDescription =>
      '只有一台手机？可创建本机签名钱包，由这台手机保管私钥并签名。转账前，始终核对网络、收款地址与金额。';

  @override
  String get introSecurityNote => '妥善离线备份助记词，不截图、不分享。任何人索要助记词，都不要提供。';

  @override
  String get introPairTitle => '联网管理。\n离线守护。';

  @override
  String get introPairDescription =>
      '有两台手机？在离线手机安装 KT冷钱包，再在这里连接其公开账户。本机查询和广播，离线设备核对并签名。';

  @override
  String get introPairNote => '两个独立 App，通过二维码协作。离线钱包的私钥不导入在线设备。';

  @override
  String get introStart => '开始使用在线钱包';

  @override
  String get appName => 'KT钱包';

  @override
  String get appTagline => '双机离线钱包 · 联网观察端';

  @override
  String get actionConfirm => '确认';

  @override
  String get actionCancel => '取消';

  @override
  String get actionClose => '关闭';

  @override
  String get actionDelete => '删除';

  @override
  String get pinKeyDelete => '删除最后一位';

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
  String get homeSearchHint => '搜索币种、地址或网络';

  @override
  String get homeCategoryCoins => '币种';

  @override
  String get homeCategoryNetworks => '网络';

  @override
  String get homeCategoryCustom => '自定义';

  @override
  String get homeNoMatchingAssets => '没有匹配的资产';

  @override
  String get homeNoMatchingNetworks => '没有匹配的网络';

  @override
  String get walletKindHot => '本机签名';

  @override
  String get walletKindWatch => '离线签名';

  @override
  String get walletStateBackedUp => '已备份';

  @override
  String get walletStateNotBackedUp => '未备份';

  @override
  String get walletStateColdSigner => 'KT冷钱包';

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
  String get backupBannerText => '助记词尚未备份';

  @override
  String get backupNow => '立即备份';

  @override
  String get walletAddressesTitle => '账户地址';

  @override
  String get walletAddressSearchHint => '搜索网络或地址';

  @override
  String get balanceChangePeriod => '1日';

  @override
  String get marketUpdating => '正在更新余额…';

  @override
  String get marketCachedJustNow => '刚刚验证';

  @override
  String marketCachedMinutes(int count) {
    return '$count 分钟前验证';
  }

  @override
  String marketCachedHours(int count) {
    return '$count 小时前验证';
  }

  @override
  String get marketCachedStale => '部分资产数据暂未更新，有缓存的项目保留上次数据';

  @override
  String get marketRefreshing => '正在更新当前钱包的资产…';

  @override
  String get marketBalancesIncomplete => '部分余额暂未更新，有缓存的项目保留上次余额';

  @override
  String get marketPricesIncomplete => '行情暂未完整更新，部分估值可能使用上次价格';

  @override
  String get historyRefreshing => '正在更新当前钱包的交易记录…';

  @override
  String get historyCachedStale => '部分交易记录暂未更新，当前包含上次保存的记录';

  @override
  String get actionReceive => '收款';

  @override
  String get actionSend => '转账';

  @override
  String get actionMore => '更多';

  @override
  String get actionShare => '分享';

  @override
  String get actionScanSign => '扫签名';

  @override
  String get assetsSortByValue => '按持仓价值排序';

  @override
  String get assetsHideZero => '隐藏零余额';

  @override
  String get assetsFavoritesOnly => '只看收藏';

  @override
  String assetAddFavorite(Object symbol) {
    return '收藏 $symbol';
  }

  @override
  String assetRemoveFavorite(Object symbol) {
    return '取消收藏 $symbol';
  }

  @override
  String get recordsTitle => '交易记录';

  @override
  String get recordsWalletTab => '钱包';

  @override
  String get historyTypeFilterTitle => '按类型筛选';

  @override
  String get historyTypeAll => '全部类型';

  @override
  String get historyTypeTransfers => '发送/接收';

  @override
  String get historyTypeOther => '其他';

  @override
  String get historyNetworkFilterTitle => '按网络筛选';

  @override
  String get historyAllNetworks => '全部网络';

  @override
  String get historySent => '发送';

  @override
  String get historyReceived => '接收';

  @override
  String historyFromAddress(String address) {
    return '来自 $address';
  }

  @override
  String historyToAddress(String address) {
    return '至 $address';
  }

  @override
  String get historyAddressUnavailable => '地址不可用';

  @override
  String get historyUnverifiedTokenBadge => '未验证';

  @override
  String get historyLoadMore => '加载更多';

  @override
  String get historyLoadingMore => '正在加载更多…';

  @override
  String get historyNoRecognizedTransactions => '暂无已识别资产的交易记录';

  @override
  String get historyUnverifiedRecordsTitle => '未验证与风险代币记录';

  @override
  String get historyUnverifiedRecordsDescription => '已从主记录隐藏，请核对网络与合约后再操作';

  @override
  String get historyCustomTokenBadge => '自定义';

  @override
  String get historyRiskTokenBadge => '风险';

  @override
  String get transactionConfirmedNotice => '交易已在链上确认';

  @override
  String get transactionFailedNotice => '交易在链上执行失败';

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
  String get addWalletStandardSection => '本机签名 · 一台手机即可使用';

  @override
  String get createNewWallet => '创建新钱包';

  @override
  String get createNewWalletDesc => '在本机生成助记词，完成备份后使用';

  @override
  String get importMnemonic => '导入助记词';

  @override
  String get importMnemonicDesc => '已有 12 / 18 / 24 个单词的助记词';

  @override
  String get coldWalletSection => '离线设备签名 · 需要两台手机';

  @override
  String get connectColdWallet => '连接离线钱包';

  @override
  String get connectColdWalletDesc => '导入公开账户信息；转账需离线设备签名';

  @override
  String get createWalletTitle => '创建本机签名钱包';

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
  String get mnemonicUnavailableTitle => '无法显示助记词';

  @override
  String get mnemonicUnavailableBackup =>
      '此备份流程仅适用于新创建的钱包。要备份当前钱包，请打开「钱包详情 → 查看助记词」。';

  @override
  String get mnemonicAuthRequired => '需要通过身份验证才能显示助记词，请重试。';

  @override
  String get mnemonicNoKeyMaterial => '本机未保存该钱包的助记词，无法显示。';

  @override
  String get verifyBackupTitle => '校验备份';

  @override
  String mnemonicWordChallenge(int position) {
    return '第 $position 个单词是？';
  }

  @override
  String get mnemonicChallengeHint => '对照手写备份选择单词；抽查不能保证整份备份无误。';

  @override
  String get verifyWrong => '选择有误，请对照您手写的备份重试';

  @override
  String walletCreateAuthLocked(int seconds) {
    return '安全验证暂时锁定，请在 $seconds 秒后重试。';
  }

  @override
  String get walletCreateFailed => '钱包创建未完成，请重试。';

  @override
  String get walletDeviceAuthUnavailable =>
      '系统身份验证不可用。请先在系统设置中设置锁屏 PIN 或密码，再返回重试；若已设置，请检查生物识别或稍后重试。';

  @override
  String get walletCreatedBackedUp => '钱包已创建，已通过备份抽查。请妥善保管完整助记词。';

  @override
  String get backupVerified => '已记录备份确认。请确认完整助记词已按顺序保存。';

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
  String get connectColdSafety =>
      '此观察账户仅导入公开信息，不导入离线钱包的助记词、私钥或种子。在线 App 中其他本机签名钱包仍在本机保管私钥。';

  @override
  String get scanAccountHint => '对准 KT冷钱包的地址二维码';

  @override
  String get importConfirmTitle => '确认导入';

  @override
  String get createWatchWallet => '创建观察钱包';

  @override
  String get invalidOfflineWalletExport => '离线钱包导出数据无效';

  @override
  String get offlineWalletAlreadyPaired => '此离线钱包已完成配对';

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
  String get walletDeleteFailed => '无法安全删除钱包，当前内容未被移除，请重试。';

  @override
  String get walletUpdateFailed => '无法保存更改，当前内容未改变，请重试。';

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
  String get walletIdLabel => '钱包 ID';

  @override
  String get coldSignerWalletIdLabel => 'KT冷钱包 ID';

  @override
  String get standardWallet => '普通钱包';

  @override
  String get backupNotYet => '尚未备份助记词';

  @override
  String get viewMnemonic => '查看助记词';

  @override
  String get viewMnemonicDesc => '需要生物识别或密码验证';

  @override
  String get viewPrivateKey => '查看私钥';

  @override
  String privateKeyWarningProgress(int current, int total) {
    return '请注意 $current/$total';
  }

  @override
  String get privateKeyWarningOneTitle => '确认你的周围无人旁观，并且没有摄像和录屏';

  @override
  String get privateKeyWarningOneBody =>
      '切勿让他人观看你查看私钥的过程。若私钥被摄像或录屏，你将永久失去钱包的控制权。';

  @override
  String get privateKeyWarningTwoTitle => '请勿通过截屏或复制来保存私钥';

  @override
  String get privateKeyWarningTwoBody =>
      '复制操作会将私钥暂存于剪贴板。若不慎发送至云盘或通讯工具，极易被他人窃取。';

  @override
  String get privateKeyWarningThreeTitle => '谁拥有私钥，谁就能控制钱包';

  @override
  String get privateKeyWarningThreeBody =>
      '私钥一旦泄露，可能导致你的资产被盗。掌握私钥的人可以完全控制你的钱包。';

  @override
  String get privateKeyAcknowledge => '我已知悉';

  @override
  String get privateKeyBackupNow => '立即备份';

  @override
  String get privateKeyNotNow => '暂不备份';

  @override
  String privateKeyCountdownButton(String label, int seconds) {
    return '$label（${seconds}s）';
  }

  @override
  String get privateKeyAuthFailed => '无法验证身份，未显示或复制任何私钥。';

  @override
  String get privateKeyRetryAuth => '重新验证';

  @override
  String get privateKeyEvmNetworks => 'EVM 网络';

  @override
  String get privateKeyPrivacyHint => '请确保周围没有其他人及摄像头';

  @override
  String get privateKeySecureCopy => '安全复制';

  @override
  String get privateKeyFullCopy => '完整复制';

  @override
  String get privateKeySecureCopyTitle => '安全复制';

  @override
  String get privateKeySecureCopyBody =>
      '为保障你的资产安全，已复制缺少末尾 6 位字符的私钥。请手动补充以下字符，确保私钥可用。';

  @override
  String get privateKeySecureCopyConfirm => '确认';

  @override
  String get privateKeyFullCopyTitle => '完整复制';

  @override
  String get privateKeyFullCopyBody => '完整私钥会进入剪贴板，存在被其他应用读取或误粘贴的风险。确定继续复制吗？';

  @override
  String get privateKeyCopyAction => '复制';

  @override
  String get privateKeyCopiedSecurely => '已安全复制';

  @override
  String get privateKeyCopiedFully => '完整私钥已复制，剪贴板将在 60 秒后清除';

  @override
  String get privateKeySessionExpired => '私钥查看会话已失效，请重新验证。';

  @override
  String get privateKeyNoAccounts => '当前钱包没有可导出的私钥';

  @override
  String get deleteWalletDesc => '需身份验证，删除前将再次确认备份状态';

  @override
  String get amountMustBePositive => '金额需大于 0';

  @override
  String get insufficientBalance => '余额不足';

  @override
  String insufficientAssetBalance(String symbol) {
    return '余额不足，请检查 $symbol 是否足够';
  }

  @override
  String get amountFormatInvalid => '金额格式不正确';

  @override
  String get recipientAddress => '收款地址';

  @override
  String get pasteOrEnterAddress => '粘贴或输入地址';

  @override
  String compatibleContactsHint(String network) {
    return '仅显示可用于 $network 的联系人';
  }

  @override
  String noCompatibleContacts(String network) {
    return '没有可用于 $network 的联系人';
  }

  @override
  String enterChainAddress(String network) {
    return '请输入 $network 网络收款地址';
  }

  @override
  String addressValidOn(String network) {
    return '地址格式正确 · $network 网络';
  }

  @override
  String get addressInvalid => '地址不合法';

  @override
  String recipientLookalikeWarning(String label) {
    return '此地址与“$label”首尾高度相似，但并不相同，可能是剪贴板地址投毒。';
  }

  @override
  String get recipientLookalikeReview => '我已核对完整地址';

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
  String get expectedAssetChanges => '预计资产变化';

  @override
  String outgoingAsset(String symbol) {
    return '转出 $symbol';
  }

  @override
  String get maximumNetworkFee => '最高网络手续费';

  @override
  String get networkFeeEstimate => '网络手续费估算';

  @override
  String upToNegativeAmount(String amount) {
    return '最多 -$amount';
  }

  @override
  String get solanaRentReserve => '可回收账户租金';

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
  String get transactionSourceAddress => '来源地址';

  @override
  String get transactionDestinationAccount => '到账账户';

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
  String get chainParamsFallback => '无法获取链上参数，已使用预设 nonce 与手续费';

  @override
  String broadcastFailedMessage(String message) {
    return '广播失败：$message';
  }

  @override
  String get transactionNotSubmitted => '交易未提交，请重试。';

  @override
  String get broadcastUnsupported => '当前网络无法广播这笔签名交易。';

  @override
  String get rpcRejectInsufficientFunds => '余额不足，无法支付转账金额和最高网络手续费。';

  @override
  String get rpcRejectNonceTooLow => '交易 nonce 过低，请刷新后重试。';

  @override
  String get rpcRejectNonceTooHigh => '交易 nonce 过高，请刷新后重试。';

  @override
  String get rpcRejectReplacementFeeTooLow => '替换交易的网络手续费过低。';

  @override
  String get rpcRejectFeeTooLow => '网络手续费过低。';

  @override
  String get rpcRejectGasLimitTooLow => '交易 Gas Limit 过低。';

  @override
  String get rpcRejectBlockGasLimit => '交易超过当前网络的区块 Gas 上限。';

  @override
  String get rpcRejectFeeCapBelowBase => '手续费上限低于当前网络基础费。';

  @override
  String get rpcRejectAlreadyKnown => '网络已收到这笔交易，请查询状态，不要重复发送。';

  @override
  String get rpcRejectExecutionReverted => '交易执行时被链上合约回退。';

  @override
  String get rpcRejectInvalidSender => '交易发送地址无效。';

  @override
  String get rpcRejectExpiredReference => '交易引用的区块信息已过期，请重新构建交易。';

  @override
  String get rpcRejectAccountInUse => '交易所需账户正在使用中，请稍后重试。';

  @override
  String get rpcRejectSimulationFailed => '网络拒绝了本次交易预执行。';

  @override
  String get rpcRejectInvalidSignature => '交易签名无效。';

  @override
  String get rpcRejectGeneric => '网络拒绝了这笔交易。';

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
  String get txSubmissionUnknown => '广播结果待确认';

  @override
  String get txSubmissionUnknownMessage =>
      '签名交易可能已经到达网络，请勿再次发送。KT Wallet 将使用本地计算的交易哈希继续查询链上结果。';

  @override
  String transferBroadcastInProgress(String amount, String symbol) {
    return '正在转账 $amount $symbol';
  }

  @override
  String transferBroadcastCompleted(String amount, String symbol) {
    return '已转账 $amount $symbol';
  }

  @override
  String transferBroadcastFailed(String amount, String symbol) {
    return '转账失败 $amount $symbol';
  }

  @override
  String get transferProcessingState => '处理中';

  @override
  String get transferCompletedState => '已完成';

  @override
  String get transferStageProcessing => '处理中';

  @override
  String get transferStageBroadcasting => '正在广播';

  @override
  String get transferStageAwaitingConfirmation => '等待确认';

  @override
  String get transferStageConfirming => '确认中';

  @override
  String get networkCost => '网络费用';

  @override
  String get submissionTime => '提交时间';

  @override
  String get viewOnBlockchainExplorer => '在区块链浏览器上查看';

  @override
  String get txTimeLabel => '时间';

  @override
  String get txHash => '交易 Hash';

  @override
  String get statusLabel => '状态';

  @override
  String get txStatusSubmitted => '已提交';

  @override
  String get txStatusPending => '确认中';

  @override
  String get txStatusConfirmed => '已确认';

  @override
  String get txStatusFailed => '失败';

  @override
  String get txStatusUnknown => '状态暂不可用';

  @override
  String get txStatusDropped => '已丢弃';

  @override
  String get txStatusReplaced => '已替换';

  @override
  String get nonceConflict => '该 nonce 已被另一笔待处理交易占用，请刷新后重试';

  @override
  String get txSpeedUp => '加速交易';

  @override
  String get txCancelTransaction => '取消交易';

  @override
  String get txReplacementConfirmTitle => '确认替换交易';

  @override
  String get txSpeedUpConfirm => '将使用相同 nonce 和更高网络费重新发送。原收款地址与金额不会改变。';

  @override
  String get txCancelConfirm => '将使用相同 nonce 向自己发送 0 金额交易。仅当替换交易先被确认时，原交易才会取消。';

  @override
  String get txReplacementSubmitted => '替换交易已提交';

  @override
  String get txReplacementRace => '替换交易已提交，但原交易状态同时发生变化，请等待链上最终结果';

  @override
  String get txNonceAlreadyUsed => '该 nonce 已被链上交易使用，无法继续替换';

  @override
  String get txReplacementUnavailable => '这笔交易缺少替换所需的链上参数，无法加速或取消';

  @override
  String txReplacementWrongNetwork(String network) {
    return '这笔交易属于 $network，请先切换回该网络再加速或取消';
  }

  @override
  String get feeEstimating => '估算中…';

  @override
  String get feeAwaitingInput => '待估算';

  @override
  String get feeWaitingBalance => '余额不足，暂无法估算手续费';

  @override
  String get feeWaitingRecipient => '填写有效收款地址后估算手续费';

  @override
  String get feeWaitingAmount => '输入有效转账金额后估算手续费';

  @override
  String get feeUnavailable => '无法获取网络费';

  @override
  String get feeUnavailableHint => '无法估算网络费，暂时无法发送';

  @override
  String get tokenRiskChecking => '正在检查 Token 身份…';

  @override
  String get tokenRiskCheckingBody =>
      'KT Wallet 正在签名前通过验证目录和独立威胁情报核对当前网络与完整合约地址。';

  @override
  String get tokenRiskVerifiedTitle => '官方 Token 身份已核对';

  @override
  String get tokenRiskVerifiedBody => '网络与合约地址匹配运营方验证目录。蓝勾仅确认身份，不代表投资安全。';

  @override
  String get tokenRiskUnsafeTitle => '检测到高风险 Token 合约';

  @override
  String get tokenRiskUnsafeBody => '已配置的安全数据源发现该完整合约地址存在明确恶意证据。为保护钱包，本次签名已阻止。';

  @override
  String get tokenRiskUnknownTitle => 'Token 风险状态无法确认';

  @override
  String get tokenRiskUnknownBody =>
      '当前没有已配置的数据源能够确认该合约的身份或安全性。继续前请通过项目官方渠道核对完整合约地址。';

  @override
  String get tokenRiskUnavailableTitle => '暂时无法检查 Token 风险';

  @override
  String get tokenRiskUnavailableBody =>
      '风险服务当前不可用。KT Wallet 无法确认该合约安全，请独立核验后再继续。';

  @override
  String get tokenRiskBlockedHint => '该 Token 合约已被标记为高风险，暂时无法发送。';

  @override
  String get signRequestBuildFailed => '无法验证链上交易参数，签名已禁用。';

  @override
  String get signRequestSaveFailed => '无法安全保存待签名交易，签名二维码未生成。请返回后重试。';

  @override
  String get transactionSimulationFailed =>
      '交易预执行失败，未进行签名。请检查余额、金额、收款地址或 Token 合约。';

  @override
  String get txNonceLabel => 'Nonce';

  @override
  String get txMaxFeeLabel => '最高网络费（原始单位）';

  @override
  String get txRawAmountLabel => '金额（原始单位）';

  @override
  String get txReplacesLabel => '替换交易';

  @override
  String get txReplacedByLabel => '已由交易替换';

  @override
  String get txReplacementPendingLabel => '竞争中的替换交易';

  @override
  String get txNotFound => '未找到本地交易记录';

  @override
  String confirming(int received, int total) {
    return '确认中 ($received/$total)';
  }

  @override
  String get txDetailTitle => '交易详情';

  @override
  String get txBroadcastTime => '广播时间';

  @override
  String get txLastStatusCheck => '最后状态查询';

  @override
  String get txNotCheckedYet => '尚未查询';

  @override
  String get txCopyHash => '复制交易 Hash';

  @override
  String get txHashCopied => '交易 Hash 已复制';

  @override
  String get txViewInExplorer => '在区块浏览器查看';

  @override
  String get confirmedPrefix => '已确认';

  @override
  String get confirmations => '确认数';

  @override
  String get authToConfirmTransfer => '验证以确认转账';

  @override
  String get authEveryTransfer => '每次转账都需要生物识别或密码验证';

  @override
  String get useFaceId => '使用生物识别验证';

  @override
  String get usePasscode => '改用密码';

  @override
  String get biometricFailedRetry => '验证失败，请重试';

  @override
  String get searchAssetHint => '搜索名称 / 符号 / 合约地址';

  @override
  String get price => '价格';

  @override
  String get change24h => '24h 涨跌';

  @override
  String get contractAddress => '合约地址';

  @override
  String get unverifiedToken => '未经验证的代币，请核对合约地址';

  @override
  String tokenImpersonationWarning(String symbol) {
    return '⚠️ 名称显示为 $symbol，但此合约不在 KT Wallet 验证的官方 $symbol 地址列表中。它可能是同名或桥接资产，请勿仅凭名称转账。';
  }

  @override
  String get receiveWarning => '仅支持接收 TRON 网络（TRC-20）资产。从其他网络转入将导致资产丢失。';

  @override
  String get explorerLinkCopied => '区块浏览器链接已复制';

  @override
  String get addressCopied => '地址已复制';

  @override
  String get saveReceiveImage => '保存收款图片';

  @override
  String get privacyOverlayActive => 'KT 钱包保护已启动';

  @override
  String get privacyOverlayHidden => '您的钱包内容已隐藏';

  @override
  String get chooseNetwork => '选择网络';

  @override
  String get multiChainBadge => '多链';

  @override
  String assetOnChains(int count) {
    return '$count 条链';
  }

  @override
  String get receiveCardTitle => '收款地址';

  @override
  String get receiveCardNetwork => '网络';

  @override
  String get receiveCardGenerated => '生成时间';

  @override
  String get receiveImageSaved => '已保存到相册';

  @override
  String get receiveImageDenied => '未获得相册权限，无法保存';

  @override
  String get receiveImageUseShare => '此系统版本无法直接保存，请使用右上角分享';

  @override
  String get receiveImageFailed => '生成收款图片失败';

  @override
  String get receiveExportSubtitle => '包含地址、网络与可扫描的收款二维码';

  @override
  String get exportTransactionReceipt => '导出交易凭证';

  @override
  String get exportTransactionReceiptSubtitle => '包含本次交易明细与链上验证二维码';

  @override
  String get transactionReceiptTitle => '链上交易凭证';

  @override
  String get transactionReceiptTimeLabel => '交易时间';

  @override
  String get saveReceiptToPhotos => '保存到相册';

  @override
  String get shareReceiptImage => '分享凭证图片';

  @override
  String get transactionReceiptSaved => '交易凭证已保存到相册';

  @override
  String get transactionReceiptDenied => '未获得相册权限，无法保存交易凭证';

  @override
  String get transactionReceiptUseShare => '此系统版本无法直接保存，请改用分享';

  @override
  String get transactionReceiptFailed => '生成交易凭证失败';

  @override
  String get scanToVerifyOnChain => '扫描二维码，在区块浏览器验证';

  @override
  String get transactionReceiptFooter => '由 KT Wallet 生成 · 请以链上数据为准';

  @override
  String transactionReceiptSubject(String network) {
    return '$network 交易凭证';
  }

  @override
  String get actionCopy => '复制地址';

  @override
  String get addressBookTitle => '地址管理';

  @override
  String get localWalletAddresses => '本地钱包地址';

  @override
  String get savedContacts => '已保存联系人';

  @override
  String get localWalletLabel => '本地钱包';

  @override
  String get currentWalletLabel => '当前钱包';

  @override
  String evmNetworksLabel(int count) {
    return 'EVM · $count 条网络';
  }

  @override
  String get searchNameOrAddress => '搜索名称或地址';

  @override
  String get assetUnavailable => '该资产已不可用';

  @override
  String get noMatchingContacts => '没有匹配的联系人';

  @override
  String get contactsEmpty => '还没有联系人，点右上角 + 添加';

  @override
  String get tokensEmpty => '还没有自定义代币，点右上角 + 添加';

  @override
  String get contactBobExchange => 'Bob 交易所';

  @override
  String get contactColdBackup => '冷钱包备份';

  @override
  String get editContactTitle => '编辑联系人';

  @override
  String get actionEdit => '编辑';

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
  String get searchTokenHint => '搜索币种名称、符号或合约地址';

  @override
  String get myTokens => '我的币种';

  @override
  String get addedTokenSearchResults => '已添加';

  @override
  String get popularOfficialTokens => '热门官方币';

  @override
  String get officialTokenSearchResults => '官方币';

  @override
  String get officialTokenVerified => 'KT Wallet 官方认证';

  @override
  String get noMatchingTokens => '没有找到相关币种\\n可点右上角 + 按合约地址添加';

  @override
  String addOfficialToken(String symbol) {
    return '添加官方币 $symbol';
  }

  @override
  String officialTokenAdded(String symbol) {
    return '已添加官方币 $symbol';
  }

  @override
  String get networkSettingsTitle => '网络设置';

  @override
  String get screenCaptureBlocked => '检测到录屏或投屏';

  @override
  String get screenCaptureBlockedHint => '为保护助记词，内容已隐藏。停止录屏或断开投屏后会自动恢复。';

  @override
  String get screenshotWarning =>
      '你刚刚截图了助记词。它已存入相册，任何能看到相册的人都能取走你的资产 —— 请立刻把资产转移到新钱包。';

  @override
  String get rpcMeasuring => '测量中…';

  @override
  String get rpcUnreachable => '无法连接';

  @override
  String get rpcNotMeasured => '—';

  @override
  String get rpcTimeout => '超时';

  @override
  String get rpcNode => 'RPC 节点';

  @override
  String get networkResetDefault => '恢复默认';

  @override
  String get gatewayTitle => '网关';

  @override
  String get gatewayDesc => '统一查询网关，留空则直连各链节点';

  @override
  String get gatewayNotSet => '未设置';

  @override
  String get gatewayTest => '测试连接';

  @override
  String get gatewayTestOk => '网关连接成功';

  @override
  String get gatewayTestFail => '网关连接失败';

  @override
  String get accessControl => '访问控制';

  @override
  String get appLock => 'App 锁';

  @override
  String get appLockDesc => '打开 App 时进行安全验证';

  @override
  String get authMethod => '验证方式';

  @override
  String get authMethodDesc => '用于解锁 App 和确认转账';

  @override
  String get authBiometrics => '人脸 / 生物识别';

  @override
  String get authBiometricsDesc => '使用本机生物识别快速确认';

  @override
  String get authPassword => '钱包密码';

  @override
  String get authPasswordDesc => '使用 6 位钱包密码验证';

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
  String get fiatUnit => '计价货币';

  @override
  String get displayLanguage => '显示语言';

  @override
  String get deleteWatchWallet => '删除观察钱包';

  @override
  String get deleteWatchWalletDesc => '仅移除公开地址与本地记录，不影响资产';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get walletLoadErrorTitle => '钱包加载失败';

  @override
  String get walletLoadErrorDesc =>
      '无法读取本机的钱包数据。请重试。若问题持续，请保留应用及其数据，以免丢失尚未备份的钱包。';

  @override
  String get pendingDeletionAuthTitle => '删除尚未完成';

  @override
  String get pendingDeletionAuthDesc =>
      '上次删除钱包需要完成系统身份验证。未完成的删除记录已保留，这不表示安全存储损坏。准备好后，请验证身份以继续删除；若认证暂不可用或已锁定，请稍后重试或检查设备锁屏设置。';

  @override
  String get pendingDeletionAuthAction => '验证身份并继续删除';

  @override
  String get walletPersistenceFailed => '无法安全保存钱包，本次未添加任何钱包。请重试。';

  @override
  String get walletAlreadyExists => '该钱包已存在于本机。';

  @override
  String get cryptoUnavailableTitle => '钱包引擎不可用';

  @override
  String get cryptoUnavailableDesc =>
      '此 Android 构建未包含 Trust Wallet Core。请安装启用了 Wallet Core 的构建；应用不会自动改用模拟密钥。';

  @override
  String get secureStorageUnavailableTitle => '安全存储不可用';

  @override
  String get secureStorageUnavailableDesc =>
      'KT钱包无法安全读取密码和锁定状态，钱包将保持锁定。请重新启动 App，或从可信来源重新安装。';

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
  String get marketOfflineDemo => '暂时无法获取资产数据，请稍后重试';

  @override
  String get actionDone => '完成';

  @override
  String get historyUnsupportedChain => '该链暂不支持历史查询';

  @override
  String get historyEmpty => '暂无交易记录';

  @override
  String get historyEmptyDescription => '交易动态会显示在这里\n下拉刷新，或切换筛选条件查看';

  @override
  String get transferPaste => '粘贴';

  @override
  String get transferScan => '扫码';

  @override
  String get setPinTitle => '设置解锁密码';

  @override
  String get setPinPrompt => '设置 6 位密码';

  @override
  String get setPinConfirmPrompt => '再次输入以确认';

  @override
  String get setPinDesc => '生物识别不可用时用密码解锁 App。密码仅保存在本机安全区域。';

  @override
  String get changeWalletPin => '修改钱包密码';

  @override
  String get changeWalletPinDesc => '更换 6 位密码前必须验证当前身份';

  @override
  String get enterCurrentPin => '请输入当前钱包密码';

  @override
  String get walletPinChanged => '钱包密码已修改';

  @override
  String get pinMismatch => '两次输入不一致，请重新设置';

  @override
  String get enterPinToUnlock => '输入密码解锁';

  @override
  String get enterPinToDisable => '输入密码以关闭 App 锁';

  @override
  String get pinIncorrect => '密码错误，请重试';

  @override
  String pinLockedRetry(int seconds) {
    return '尝试次数过多，请 $seconds 秒后重试';
  }

  @override
  String get usePinUnlock => '使用密码解锁';

  @override
  String get networkEnvironment => '网络环境';

  @override
  String get envMainnet => '主网';

  @override
  String get envTestnet => '测试网';

  @override
  String get testnetBadge => '测试网';

  @override
  String get perChainNetwork => '逐链网络';

  @override
  String get addNetwork => '添加网络';

  @override
  String get networkNameLabel => '网络名称';

  @override
  String get chainFamilyLabel => '协议族';

  @override
  String get chainIdLabel => 'Chain ID';

  @override
  String get explorerLabel => '区块浏览器 URL(可选)';

  @override
  String get symbolLabel => '币种符号';

  @override
  String get probeChecking => '正在探测 RPC…';

  @override
  String get probeOkSave => '探测通过，已保存';

  @override
  String get rpcProbeFailed => 'RPC 探测失败，请检查地址';

  @override
  String get endpointUrlInvalid =>
      '请输入不包含账号凭证的有效 HTTPS 地址。仅 localhost 可使用 HTTP。';

  @override
  String chainIdMismatch(Object actual) {
    return 'Chain ID 不匹配：节点返回 $actual';
  }

  @override
  String transferNetworkUnavailable(String network) {
    return '当前没有可用于 $network 的活动网络。';
  }

  @override
  String get transferChainIdUnavailable => '当前选择的 EVM 网络缺少 Chain ID。';

  @override
  String get deleteNetwork => '删除网络';

  @override
  String get networkInUse => '该网络正在使用中';

  @override
  String get faucetAction => '领取测试币';

  @override
  String get faucetOpened => '已打开测试币水龙头';

  @override
  String get externalActionFailed => '无法打开外部应用，请稍后重试';

  @override
  String shareAddressSubject(String network) {
    return '$network 收款地址';
  }

  @override
  String get cameraUnavailable => '相机不可用，请检查权限后重试';

  @override
  String get biometricUnavailable => '生物识别不可用，请使用钱包 PIN';

  @override
  String get airdropRequesting => '正在请求空投…';

  @override
  String get airdropOk => '空投成功，余额稍后刷新';

  @override
  String airdropFailed(Object message) {
    return '空投失败：$message';
  }

  @override
  String get airdropRateLimited => '请求过于频繁，请稍后重试';

  @override
  String get airdropUnavailable => '测试币服务暂时不可用';

  @override
  String get airdropInvalidRequest => '水龙头拒绝了该地址或请求';

  @override
  String get airdropInsufficientFunds => '水龙头测试币余额不足';

  @override
  String get airdropRejected => '水龙头拒绝了请求';

  @override
  String get airdropMalformedResponse => '测试币服务返回了无效响应';

  @override
  String get fiatHiddenTestnet => '测试网资产无市场价格';

  @override
  String get backupEncryptedTitle => '加密备份';

  @override
  String get backupEncryptedRow => '加密备份';

  @override
  String get backupEncryptedRowDesc => '使用强密码保存加密文件或二维码图片';

  @override
  String get backupIntro => '备份文件用你设置的密码加密。同时拿到文件和密码的人，就掌握了这个钱包。';

  @override
  String get backupPasswordLabel => '备份密码';

  @override
  String get backupPasswordConfirm => '再次输入密码';

  @override
  String get backupPasswordTooShort => '请至少输入 14 个字符';

  @override
  String get backupPasswordTooLong => '最多输入 128 个字符';

  @override
  String get backupPasswordTooWeak => '请勿使用重复、连续或常见密码';

  @override
  String get backupPasswordMismatch => '两次输入的密码不一致';

  @override
  String get backupPasswordWarning =>
      '请使用独立且足够长的密码短语。这个密码无法找回，丢失后备份将无法打开；请同时保留手抄的助记词。';

  @override
  String get backupCreate => '生成备份';

  @override
  String get backupSaved => '备份已保存';

  @override
  String get backupCancelled => '已取消备份';

  @override
  String get backupFailed => '生成备份失败';

  @override
  String get backupUnsupported => '此设备无法保存文件';

  @override
  String get restoreFromBackup => '从备份恢复';

  @override
  String get restoreFromBackupDesc => '使用备份文件、二维码或图片恢复';

  @override
  String get restorePickFile => '选择备份文件';

  @override
  String get restoreEnterPassword => '输入备份密码';

  @override
  String get restoreWrongPassword => '密码错误，或文件已损坏';

  @override
  String get restoreNotABackup => '这不是 KT 钱包的备份文件';

  @override
  String get restoreTooNew => '此备份由更新版本的 App 生成';

  @override
  String get restoreFileTooLarge => '此文件过大，不可能是 KT 钱包备份';

  @override
  String get restoreFileUnavailable => '此设备无法打开备份文件';

  @override
  String get restoreFileReadFailed => '无法读取所选文件，请重试';

  @override
  String get restoreSelectedFileFallback => '备份文件';

  @override
  String get restoreRestored => '钱包已恢复';

  @override
  String get restoreAction => '恢复';

  @override
  String backupFileChosen(String name) {
    return '已选择：$name';
  }

  @override
  String get settingsAbout => '关于';

  @override
  String get aboutTitle => '关于';

  @override
  String get aboutVersion => '版本';

  @override
  String get aboutOpenSource => '开源地址';

  @override
  String get aboutOpenSourceDesc => '你的私钥交给了这份代码，它是可以被审阅的';

  @override
  String get aboutTagline => '气隙钱包 —— 私钥永不离开你的设备。';

  @override
  String get aboutCopiedLink => '链接已复制';

  @override
  String get aboutTrustTitle => '信任与法律信息';

  @override
  String get aboutPrivacyPolicy => '隐私政策';

  @override
  String get aboutPrivacyPolicyDesc => '了解 App 在本地处理及联网发送的数据';

  @override
  String get aboutSecurityRisk => '安全与风险说明';

  @override
  String get aboutSecurityRiskDesc => '当前安全保证、已知限制与使用边界';

  @override
  String get aboutSecurityPolicy => '安全政策';

  @override
  String get aboutSecurityPolicyDesc => '漏洞范围、安全研究与响应时限';

  @override
  String get aboutThirdPartyNotices => '开源依赖与许可证';

  @override
  String get aboutThirdPartyNoticesDesc => '查看随 App 分发的第三方组件说明';

  @override
  String get aboutReportSecurity => '报告安全问题';

  @override
  String get aboutReportSecurityDesc => '先阅读私密报告流程与敏感信息要求';

  @override
  String get aboutNeverShareSecrets => 'KT Wallet 永远不会索要您的助记词或私钥。';

  @override
  String get diagnosticsTitle => '支持诊断';

  @override
  String get diagnosticsSubtitle => '导出用于排查问题的隐私安全 JSON 包';

  @override
  String get diagnosticsConfirmTitle => '导出诊断包？';

  @override
  String get diagnosticsConfirmBody => '分享前请确认包含和排除的信息。';

  @override
  String get diagnosticsIncludesTitle => '包含';

  @override
  String get diagnosticsIncludesBody => 'App 与构建信息、网络模式、服务状态和汇总性能';

  @override
  String get diagnosticsExcludesTitle => '永不包含';

  @override
  String get diagnosticsExcludesBody => '地址、余额、金额、交易、密钥、签名、助记词或节点地址';

  @override
  String get diagnosticsExportAction => '导出并分享';

  @override
  String get diagnosticsShareSubject => 'KT钱包支持诊断';

  @override
  String get diagnosticsShareText => '已脱敏的 KT钱包诊断信息。分享前请检查文件。';

  @override
  String get diagnosticsReady => '诊断包已准备好';

  @override
  String get diagnosticsFailed => '无法创建诊断包';

  @override
  String get diagnosticsUploadTitle => '发送匿名性能报告';

  @override
  String get diagnosticsUploadSubtitle => '审阅后单次发送固定聚合指标；不会在后台自动上传';

  @override
  String get diagnosticsUploadConfirmTitle => '发送匿名性能报告？';

  @override
  String get diagnosticsUploadConfirmBody =>
      '这是一次由您主动发起的上传，不会在后台自动上传，也不会自动重试。服务端只保留匿名汇总指标 7 天。';

  @override
  String get diagnosticsUploadIncludesBody =>
      'App 版本、平台、大致语言、构建模式，以及固定性能项的计数、成功/失败数和 P50/P95';

  @override
  String get diagnosticsUploadExcludesBody =>
      '钱包或设备标识、地址、余额、金额、交易、txHash、时间戳、错误文本、调用栈、密钥、签名、助记词或节点地址';

  @override
  String get diagnosticsUploadAction => '同意并发送';

  @override
  String get diagnosticsUploadSent => '匿名性能报告已发送';

  @override
  String get diagnosticsUploadAlreadySent => '相同的匿名报告已经发送过';

  @override
  String get diagnosticsUploadNoSamples => '目前没有可发送的性能样本';

  @override
  String get diagnosticsUploadFailed => '匿名性能报告发送失败；没有自动重试';

  @override
  String get diagnosticsUploadGatewayRequired => '直接连接模式不会上传诊断；请先启用 KT Gateway';

  @override
  String get settingsApprovals => 'Token 授权管理';

  @override
  String get approvalsTitle => 'Token 授权管理';

  @override
  String get approvalsSubtitle => '查看哪些合约可以动用您的 ERC-20 Token';

  @override
  String get approvalPrivacyTitle => '外部授权扫描';

  @override
  String get approvalPrivacyBody =>
      '为了查询尚未撤销的授权，KT钱包会通过当前配置的 Gateway，将此钱包的公开地址和所选主网发送给 GoPlus。不会发送密钥、余额或交易内容，您可随时关闭。';

  @override
  String get approvalEnableAndScan => '允许并开始扫描';

  @override
  String get approvalDisableScan => '关闭外部扫描';

  @override
  String get approvalScanAgain => '重新扫描';

  @override
  String get approvalLoading => '正在检查尚未撤销的授权…';

  @override
  String get approvalEmptyTitle => '未发现尚未撤销的授权';

  @override
  String get approvalEmptyBody => '服务已完整完成本次扫描，并确认此钱包在所选网络没有 ERC-20 allowance。';

  @override
  String get approvalUnavailableTitle => '授权状态暂不可用';

  @override
  String get approvalUnavailableBody => '服务未能完成扫描，当前授权清单未知；这不代表没有授权。';

  @override
  String get approvalUnsupportedTitle => '当前网络尚未覆盖';

  @override
  String get approvalUnsupportedBody =>
      '授权扫描目前仅支持 Ethereum、Polygon、Base、Arbitrum 与 BNB Smart Chain 主网。';

  @override
  String get approvalUnlimited => '无限额度授权';

  @override
  String approvalAmount(String amount) {
    return '授权额度：$amount';
  }

  @override
  String get approvalSpender => '被授权合约';

  @override
  String get approvalTokenContract => 'Token 合约';

  @override
  String get approvalApprovedAt => '最后变更时间';

  @override
  String get approvalRisky => '发现风险信号';

  @override
  String get approvalIdentityUnknown => '安全性尚未确认';

  @override
  String get approvalKnownSpender => '服务商已识别标签';

  @override
  String get approvalReadOnlyNotice =>
      '热钱包通过精确的零额度交易在本机撤销；观察钱包通过配对的 KT冷钱包完成二维码往返签名。';

  @override
  String get approvalPrivacyEnabled => '此设备已允许外部授权扫描';

  @override
  String get approvalNoWallet => '请先选择钱包再检查授权';

  @override
  String get approvalRevoke => '撤销授权';

  @override
  String get approvalRevokeTitle => '撤销这项 Token 授权？';

  @override
  String get approvalRevokeBody =>
      'KT钱包会向 Token 合约发送 approve(被授权合约, 0)。这只会把授权额度归零，不会转出 Token。';

  @override
  String get approvalRevokeConfirm => '验证并撤销';

  @override
  String get approvalRevokePreparing => '正在模拟精确的撤销交易并估算最高网络费…';

  @override
  String approvalRevokeMaximumFee(String fee) {
    return '最高网络费：$fee';
  }

  @override
  String get approvalRevokeSubmitted => '撤销交易已提交；链上确认前仍显示为 Pending。';

  @override
  String get approvalRevokePending => '撤销确认中';

  @override
  String get approvalRevokeFailed => '撤销交易未提交，不会把授权显示为已撤销。';

  @override
  String get approvalRevokeAuthFailed => '未完成身份验证，没有签名任何内容。';

  @override
  String get approvalRevokeHotOnly => '当前没有可用于这笔撤销交易的签名钱包。';

  @override
  String get tronAccountStatus => 'TRON 账户状态';

  @override
  String get tronActivationChecking => '检测中';

  @override
  String get tronActivated => '已激活';

  @override
  String get tronUnactivated => '未激活';

  @override
  String get tronActivationUnknown => '状态未知';

  @override
  String get tronActivationRequiredHint =>
      '此 TRON 地址尚未激活，可以接收并显示 TRC-20 资产，但暂时不能发起交易。请先向该地址转入 TRX 完成链上激活，并预留网络手续费。';
}
