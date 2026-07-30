// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

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
  String get marketCachedStale => '网络恢复前将继续显示已保存的真实余额';

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
  String get historyLoadMore => '加载更多';

  @override
  String get historyLoadingMore => '正在加载更多…';

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
  String get connectColdWalletDesc => '扫码配对 KT Wallet Cold Signer，私钥永不进入本机';

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
  String get mnemonicChallengeHint => '从下列单词中选择正确的一项';

  @override
  String get verifyWrong => '选择有误，请对照您手写的备份重试';

  @override
  String walletCreateAuthLocked(int seconds) {
    return '安全验证暂时锁定，请在 $seconds 秒后重试。';
  }

  @override
  String get walletCreateFailed => '钱包创建未完成，请重试。';

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
  String get scanAccountHint => '对准 KT Wallet Cold Signer 的地址二维码';

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
  String get viewMnemonicDesc => '需要生物识别或密码验证';

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
  String get feeUnavailable => '无法获取网络费';

  @override
  String get feeUnavailableHint => '无法估算网络费，暂时无法发送';

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
  String get txNotFound => '未找到本地交易记录';

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
  String get authEveryTransfer => '每次转账都需要生物识别或密码验证';

  @override
  String get useFaceId => '使用生物识别验证';

  @override
  String get usePasscode => '改用密码';

  @override
  String get biometricFailedRetry => '验证失败，请重试';

  @override
  String get searchAssetHint => '搜索名称 / Symbol / 合约地址';

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
  String get receiveImageDenied => '未获得相册权限,无法保存';

  @override
  String get receiveImageUseShare => '此系统版本无法直接保存,请使用右上角分享';

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
  String get contactsEmpty => '还没有联系人,点右上角 + 添加';

  @override
  String get tokensEmpty => '还没有自定义代币,点右上角 + 添加';

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
  String get screenCaptureBlockedHint => '为保护助记词,内容已隐藏。停止录屏或断开投屏后会自动恢复。';

  @override
  String get screenshotWarning =>
      '你刚刚截图了助记词。它已存入相册,任何能看到相册的人都能取走你的资产 —— 请立刻把资产转移到新钱包。';

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
  String get cryptoUnavailableTitle => '钱包引擎不可用';

  @override
  String get cryptoUnavailableDesc =>
      '此 Android 构建未包含 Trust Wallet Core。请安装启用了 Wallet Core 的构建；应用不会自动改用模拟密钥。';

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
  String get marketOfflineDemo => '网络不可用，实时数据加载失败';

  @override
  String get actionDone => '完成';

  @override
  String get historyUnsupportedChain => '该链暂不支持历史查询';

  @override
  String get historyEmpty => '暂无交易记录';

  @override
  String get setPinTitle => '设置解锁密码';

  @override
  String get setPinPrompt => '设置 6 位密码';

  @override
  String get setPinConfirmPrompt => '再次输入以确认';

  @override
  String get setPinDesc => '生物识别不可用时用密码解锁 App。密码仅保存在本机安全区域。';

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
  String get probeOkSave => '探测通过,已保存';

  @override
  String get rpcProbeFailed => 'RPC 探测失败,请检查地址';

  @override
  String chainIdMismatch(Object actual) {
    return 'Chain ID 不匹配:节点返回 $actual';
  }

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
  String get airdropOk => '空投成功,余额稍后刷新';

  @override
  String airdropFailed(Object message) {
    return '空投失败:$message';
  }

  @override
  String get fiatHiddenTestnet => '测试网资产无市场价格';

  @override
  String get backupEncryptedTitle => '加密备份';

  @override
  String get backupEncryptedRow => '加密备份';

  @override
  String get backupEncryptedRowDesc => '把加密副本保存到 iCloud Drive 或文件';

  @override
  String get backupIntro => '备份文件用你设置的密码加密。同时拿到文件和密码的人，就掌握了这个钱包。';

  @override
  String get backupPasswordLabel => '备份密码';

  @override
  String get backupPasswordConfirm => '再次输入密码';

  @override
  String get backupPasswordTooShort => '至少 8 位';

  @override
  String get backupPasswordMismatch => '两次输入的密码不一致';

  @override
  String get backupPasswordWarning => '这个密码无法找回。密码丢了备份就打不开了 —— 请同时保留手抄的助记词。';

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
  String get restoreFromBackupDesc => '打开加密的 .ktbak 文件';

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
  String get aboutOpenSourceDesc => '你的私钥交给了这份代码,它是可以被审阅的';

  @override
  String get aboutTagline => '气隙钱包 —— 私钥永不离开你的设备。';

  @override
  String get aboutCopiedLink => '链接已复制';
}
