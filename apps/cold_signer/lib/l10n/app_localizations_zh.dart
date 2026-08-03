// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appName => 'KT冷钱包';

  @override
  String get actionConfirm => '确认';

  @override
  String get actionCancel => '取消';

  @override
  String get actionSave => '保存';

  @override
  String get actionImport => '导入';

  @override
  String get actionValidating => '正在校验…';

  @override
  String get cameraUnavailable => '相机不可用';

  @override
  String get done => '完成';

  @override
  String get later => '稍后再说';

  @override
  String get splashTagline => '双机离线钱包 · 离线签名端';

  @override
  String get welcomeSubtitle => '离线签名 · 助记词永不触网';

  @override
  String get welcomeFeatOfflineTitle => '完全离线运行';

  @override
  String get welcomeFeatOfflineDesc => '本机不请求任何网络接口，建议全程开启飞行模式';

  @override
  String get welcomeFeatLocalTitle => '助记词只存在本机';

  @override
  String get welcomeFeatLocalDesc => '在本设备生成和加密保存，绝不进入联网手机';

  @override
  String get createNewWallet => '创建新钱包';

  @override
  String get importExistingWallet => '导入已有钱包';

  @override
  String get securityNoticeTitle => '安全提示';

  @override
  String get showMnemonic => '显示助记词';

  @override
  String get mnemonicWillGenerate => '接下来将生成助记词';

  @override
  String get ruleFullControlTitle => '助记词等于资产的完全控制权';

  @override
  String get ruleFullControlDesc => '任何人拿到这 12 个单词，即可在任何设备恢复并转走你的全部资产';

  @override
  String get ruleHandwriteTitle => '只用纸笔手写备份';

  @override
  String get ruleHandwriteDesc => '抄写两份，分开存放在安全的物理位置';

  @override
  String get ruleNoCaptureTitle => '永不拍照、截图或输入联网设备';

  @override
  String get ruleNoCaptureDesc => '不要保存到相册、云盘或聊天软件；iOS 截图后提醒，Android 助记词页面禁止截图';

  @override
  String get backupMnemonicTitle => '备份助记词';

  @override
  String get mnemonicShowConfirmBtn => '我已手写备份，开始验证';

  @override
  String get mnemonicShowInstruction => '请按顺序手写抄录以下 12 个单词，并保存在安全的物理位置。';

  @override
  String get mnemonicShowWarning => '请勿截图、拍照或抄录到任何联网设备。';

  @override
  String get verifyBackupTitle => '验证备份';

  @override
  String mnemonicWordChallenge(int position) {
    return '第 $position 个单词是？';
  }

  @override
  String get mnemonicChallengeHint => '从下列单词中选择正确的一项';

  @override
  String get verifyWrong => '选择有误，请对照您手写的备份重试';

  @override
  String get importWalletTitle => '导入钱包';

  @override
  String get mnemonicInvalidChecksum => '助记词无效，请检查每个单词、单词数量和 BIP-39 校验和。';

  @override
  String wordCountOption(int count) {
    return '$count 个单词';
  }

  @override
  String get setPasswordTitle => '设置解锁密码';

  @override
  String get setPasswordPrompt => '设置 6 位密码';

  @override
  String get setPasswordConfirmPrompt => '再次输入以确认';

  @override
  String get setPasswordDesc => '用于解锁 App 和确认签名。密码仅保存在本机安全区域。';

  @override
  String get passwordMismatch => '两次输入不一致，请重新设置';

  @override
  String get biometricTitle => '生物识别';

  @override
  String get enableFaceId => '启用 Face ID';

  @override
  String get biometricUnavailable => '此设备尚未设置可用的生物识别或设备认证。';

  @override
  String get walletSecureStorageFailed => '钱包安全存储失败，未保存任何密钥。';

  @override
  String get secureStorageUnavailableTitle => '安全存储不可用';

  @override
  String get secureStorageUnavailableDesc =>
      'KT冷钱包无法安全读取钱包、密码和锁定状态，签名功能将保持锁定。请重新启动 App，或从可信来源重新安装。';

  @override
  String get actionRetry => '重试';

  @override
  String get biometricSkip => '暂不启用，仅使用密码';

  @override
  String get biometricDesc => '每次签名前都需要验证身份。启用 Face ID 可以更快完成验证，也可以随时改用设备密码。';

  @override
  String get exportPublicAddress => '导出公开地址';

  @override
  String get walletCreated => '钱包创建完成';

  @override
  String get mnemonicBackedUpVerified => '助记词已备份并通过验证';

  @override
  String get walletNameLabel => '钱包名称';

  @override
  String get walletMainName => '主钱包';

  @override
  String get mnemonicBackupLabel => '助记词备份';

  @override
  String get verified => '已验证';

  @override
  String get supportedNetworks => '支持网络';

  @override
  String offlineForDays(int days) {
    return '已持续离线 $days 天';
  }

  @override
  String get securityCheckPassed => '安全检查通过 · 飞行模式已开启';

  @override
  String get offlineStatusConfirmed => '网络已断开';

  @override
  String get offlineStatusConnected => '检测到网络连接';

  @override
  String get offlineStatusUnknown => '无法确认网络状态';

  @override
  String get scanPendingTx => '扫描待签名交易';

  @override
  String get scanPendingTxDesc => '扫描联网钱包生成的动态二维码';

  @override
  String get exportAddress => '导出地址';

  @override
  String get signRecords => '签名记录';

  @override
  String get securityCheck => '安全检查';

  @override
  String get walletManage => '钱包管理';

  @override
  String get offlineSecurityCheck => '离线安全检查';

  @override
  String get checkAirplaneMode => '飞行模式';

  @override
  String get checkCellular => '蜂窝网络';

  @override
  String get checkBluetooth => '蓝牙';

  @override
  String get checkDevicePasscode => '设备密码';

  @override
  String get checkBiometric => '生物识别';

  @override
  String get checkScreenRecording => '屏幕录制';

  @override
  String get statusOn => '已开启';

  @override
  String get statusOff => '已关闭';

  @override
  String get statusDetectedOn => '检测到开启';

  @override
  String get statusEnabled => '已启用';

  @override
  String get statusNotDetected => '未检测到';

  @override
  String get riskCannotSign => '存在风险 · 暂不能签名';

  @override
  String get bluetoothWarning => '检测到蓝牙处于开启状态，请关闭后重新检测。';

  @override
  String get checkNetwork => '网络连接';

  @override
  String get checkIntegrity => '系统完整性';

  @override
  String get checkLevelPass => '通过';

  @override
  String get checkLevelWarn => '警告';

  @override
  String get checkLevelBlock => '危险';

  @override
  String get checkDetailUnknown => '无法确认状态';

  @override
  String get checkDetailNetworkSafe => '未检测到网络连接';

  @override
  String get checkDetailNetworkUnsafe => '检测到网络连接';

  @override
  String get checkDetailAirplaneSafe => '飞行模式已开启';

  @override
  String get checkDetailAirplaneUnsafe => '飞行模式未开启';

  @override
  String get checkDetailBluetoothSafe => '蓝牙已关闭';

  @override
  String get checkDetailBluetoothUnsafe => '蓝牙已开启';

  @override
  String get checkDetailPasscodeSafe => '设备密码已设置';

  @override
  String get checkDetailPasscodeUnsafe => '设备密码未设置';

  @override
  String get checkDetailBiometricSafe => '生物识别可用';

  @override
  String get checkDetailBiometricUnsafe => '生物识别不可用';

  @override
  String get checkDetailScreenCaptureSafe => '未检测到屏幕录制';

  @override
  String get checkDetailScreenCaptureUnsafe => '检测到屏幕录制';

  @override
  String get checkDetailIntegritySafe => '系统完整性检查通过';

  @override
  String get checkDetailIntegrityUnsafe => '检测到 root 或越狱';

  @override
  String get securityChecking => '正在检查设备状态…';

  @override
  String get securityOverallPass => '检查通过 · 可以签名';

  @override
  String get securityOverallWarn => '存在风险 · 请谨慎操作';

  @override
  String get securityOverallBlock => '存在高危项 · 已禁止签名';

  @override
  String get securityRecheck => '重新检查';

  @override
  String receivingShard(int received, int total) {
    return '接收分片 $received / $total';
  }

  @override
  String get confirmTxContent => '确认交易内容';

  @override
  String get reject => '拒绝';

  @override
  String get confirmSign => '确认签名';

  @override
  String rawAmountPrecision(String amount, int precision) {
    return '原始数量 $amount（精度 $precision）';
  }

  @override
  String get fromAccount => '转出账户（From）';

  @override
  String get toAddress => '收款地址（To）';

  @override
  String get spenderAddress => '被授权合约';

  @override
  String get nativeTransferOperation => '原生币转账';

  @override
  String get tokenTransferOperation => 'Token 转账';

  @override
  String get approvalRevokeOperation => '撤销 Token 授权';

  @override
  String get approvalRevokeZeroAllowance => '将授权额度设为零';

  @override
  String get approvalRevokeSignerNotice =>
      '这是精确的 ERC-20 approve(被授权合约, 0) 调用，只撤销额度，不会转出 Token。';

  @override
  String get tokenContractLabel => 'Token 合约';

  @override
  String get chainIdLabel => 'Chain ID';

  @override
  String get maximumFeeBaseUnits => '最高网络费（最小单位）';

  @override
  String get walletIdLabel => '钱包 ID';

  @override
  String get createdAtLabel => '创建时间';

  @override
  String get expiresAtLabel => '有效期至';

  @override
  String get riskWarningTitle => '风险警告';

  @override
  String get backToHome => '返回首页';

  @override
  String get viewRawTxData => '查看原始交易数据';

  @override
  String get signingBlocked => '已禁止签名';

  @override
  String get signingBlockedDesc => '该交易包含无法安全解析的内容，KT冷钱包已拒绝签名以保护你的资产。';

  @override
  String get transactionParseFailed => '无法安全解析';

  @override
  String get signingFailed => '签名失败，交易、钱包或认证未通过校验。';

  @override
  String unknownContractCallDetected(String method) {
    return '检测到未知合约调用：$method';
  }

  @override
  String get unknownContractCallDesc =>
      '仅支持原生币转账、Token 转账和精确的 approve(被授权合约, 0) 撤销。非零 approve、permit 与未知调用一律拒绝。';

  @override
  String get authTitle => '身份验证';

  @override
  String get useFaceIdVerify => '使用 Face ID 验证';

  @override
  String get useDevicePasscode => '改用设备密码';

  @override
  String get biometricFailedRetry => '验证失败，请重试';

  @override
  String get verifyToSign => '验证以完成签名';

  @override
  String get verifyToSignDesc => '每次签名都需要通过 Face ID 或设备密码验证';

  @override
  String get amountLabel => '金额';

  @override
  String get requestId => '请求 ID';

  @override
  String get enterPinToSign => '输入 App 密码以完成签名';

  @override
  String get enterPinToDelete => '输入 App 密码以继续删除';

  @override
  String get pinIncorrect => '密码错误，请重试';

  @override
  String pinLockedRetry(int seconds) {
    return '尝试次数过多，请 $seconds 秒后重试';
  }

  @override
  String get signComplete => '签名完成';

  @override
  String get voidThisSignature => '作废本次签名';

  @override
  String get voidSignatureTitle => '作废本次签名？';

  @override
  String get voidSignatureDesc => '作废后该签名结果二维码将失效，联网钱包将无法广播这笔交易。';

  @override
  String get signatureVoided => '签名已作废';

  @override
  String get signResultUnavailable => '签名结果不可用';

  @override
  String dynamicShard(int received, int total) {
    return '动态分片 $received / $total';
  }

  @override
  String get scanResultInstruction => '请使用联网钱包「扫描签名结果」读取此二维码';

  @override
  String get allAddresses => '全部地址';

  @override
  String exportQrCaption(int count) {
    return '包含 $count 条链公开地址 · 不含任何私密数据';
  }

  @override
  String get filterAll => '全部';

  @override
  String get stateSigned => '已签名';

  @override
  String get stateRejected => '已拒绝';

  @override
  String get stateExpired => '已过期';

  @override
  String get unknownContractCallLabel => '未知合约调用';

  @override
  String walletCreatedOn(String date) {
    return '创建于 $date';
  }

  @override
  String get backedUp => '已备份';

  @override
  String get editWalletName => '修改钱包名称';

  @override
  String get mnemonicBackupCheck => '助记词备份验证';

  @override
  String get mnemonicBackupCheckDesc => '定期抽查助记词是否仍能正确抄录';

  @override
  String get mnemonicReviewFailed => '认证或助记词校验失败，未显示任何助记词。';

  @override
  String get deleteWallet => '删除钱包';

  @override
  String get deleteWalletReqDesc => '需要 App 密码和确认文字；已开启系统认证时还必须通过系统认证';

  @override
  String get destroyAllData => '销毁全部钱包数据';

  @override
  String get destroyAllDataDesc => '不可恢复，仅在设备处置前使用';

  @override
  String get securitySettingsTitle => '安全设置';

  @override
  String get verificationPolicy => '验证策略';

  @override
  String get biometricUsageDesc => 'Face ID 用于解锁与签名';

  @override
  String get verifyEverySign => '每次签名验证';

  @override
  String get verifyEverySignDesc => '不可关闭（V1 强制）';

  @override
  String get accessSection => '访问';

  @override
  String get changeAppPassword => '修改 App 密码';

  @override
  String get screenCaptureProtection => '截图安全提醒';

  @override
  String get screenCaptureBlocked => '检测到录屏或投屏';

  @override
  String get screenCaptureBlockedHint => '录屏或投屏期间助记词已隐藏。停止捕获后会自动恢复。';

  @override
  String get permanentlyDeleteWallet => '永久删除钱包';

  @override
  String get stepPassword => '密码';

  @override
  String get stepConfirmText => '确认文字';

  @override
  String get irreversibleAction => '此操作不可恢复';

  @override
  String get deleteWalletWarningDesc =>
      '删除后，本机将清除该钱包的全部密钥数据。若助记词未备份或备份遗失，资产将永久无法找回。';

  @override
  String get typeToConfirmDelete => '请输入「删除钱包」以继续';

  @override
  String get deleteWalletConfirmationPhrase => '删除钱包';

  @override
  String get verifyToDeleteWallet => '验证以永久删除此钱包';

  @override
  String get deleteAuthenticationFailed => '认证失败，钱包未删除。';

  @override
  String get deleteWalletFailed => '无法安全删除钱包，当前钱包未被移除，请重试。';

  @override
  String get displayLanguage => '显示语言';

  @override
  String get settingsTitle => '设置';

  @override
  String get fiatUnit => '法币单位';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get settingsSaveFailed => '无法保存设置，当前内容未改变，请重试。';

  @override
  String get deviceMode => '设备模式';

  @override
  String get deviceModeSigner => '离线签名器';

  @override
  String get deviceModeSwitchTitle => '切换设备模式';

  @override
  String get deviceModeSwitchDesc => '切换前请确认本机不再用作签名器。切换后将返回模式选择页。';

  @override
  String get deviceModeSaveFailed => '无法保存设备模式，当前模式未改变，请重试。';

  @override
  String get pinKeyDelete => '删除最后一位';
}
