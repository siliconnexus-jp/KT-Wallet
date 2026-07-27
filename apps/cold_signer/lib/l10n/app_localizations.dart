import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja'),
    Locale('zh'),
  ];

  /// No description provided for @appName.
  ///
  /// In zh, this message translates to:
  /// **'KT冷钱包'**
  String get appName;

  /// No description provided for @actionConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确认'**
  String get actionConfirm;

  /// No description provided for @actionCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get actionCancel;

  /// No description provided for @actionSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get actionSave;

  /// No description provided for @actionImport.
  ///
  /// In zh, this message translates to:
  /// **'导入'**
  String get actionImport;

  /// No description provided for @done.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get done;

  /// No description provided for @later.
  ///
  /// In zh, this message translates to:
  /// **'稍后再说'**
  String get later;

  /// No description provided for @splashTagline.
  ///
  /// In zh, this message translates to:
  /// **'双机离线钱包 · 离线签名端'**
  String get splashTagline;

  /// No description provided for @welcomeSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'离线签名 · 助记词永不触网'**
  String get welcomeSubtitle;

  /// No description provided for @welcomeFeatOfflineTitle.
  ///
  /// In zh, this message translates to:
  /// **'完全离线运行'**
  String get welcomeFeatOfflineTitle;

  /// No description provided for @welcomeFeatOfflineDesc.
  ///
  /// In zh, this message translates to:
  /// **'本机不请求任何网络接口，建议全程开启飞行模式'**
  String get welcomeFeatOfflineDesc;

  /// No description provided for @welcomeFeatLocalTitle.
  ///
  /// In zh, this message translates to:
  /// **'助记词只存在本机'**
  String get welcomeFeatLocalTitle;

  /// No description provided for @welcomeFeatLocalDesc.
  ///
  /// In zh, this message translates to:
  /// **'在本设备生成和加密保存，绝不进入联网手机'**
  String get welcomeFeatLocalDesc;

  /// No description provided for @createNewWallet.
  ///
  /// In zh, this message translates to:
  /// **'创建新钱包'**
  String get createNewWallet;

  /// No description provided for @importExistingWallet.
  ///
  /// In zh, this message translates to:
  /// **'导入已有钱包'**
  String get importExistingWallet;

  /// No description provided for @securityNoticeTitle.
  ///
  /// In zh, this message translates to:
  /// **'安全提示'**
  String get securityNoticeTitle;

  /// No description provided for @showMnemonic.
  ///
  /// In zh, this message translates to:
  /// **'显示助记词'**
  String get showMnemonic;

  /// No description provided for @mnemonicWillGenerate.
  ///
  /// In zh, this message translates to:
  /// **'接下来将生成助记词'**
  String get mnemonicWillGenerate;

  /// No description provided for @ruleFullControlTitle.
  ///
  /// In zh, this message translates to:
  /// **'助记词等于资产的完全控制权'**
  String get ruleFullControlTitle;

  /// No description provided for @ruleFullControlDesc.
  ///
  /// In zh, this message translates to:
  /// **'任何人拿到这 12 个单词，即可在任何设备恢复并转走你的全部资产'**
  String get ruleFullControlDesc;

  /// No description provided for @ruleHandwriteTitle.
  ///
  /// In zh, this message translates to:
  /// **'只用纸笔手写备份'**
  String get ruleHandwriteTitle;

  /// No description provided for @ruleHandwriteDesc.
  ///
  /// In zh, this message translates to:
  /// **'抄写两份，分开存放在安全的物理位置'**
  String get ruleHandwriteDesc;

  /// No description provided for @ruleNoCaptureTitle.
  ///
  /// In zh, this message translates to:
  /// **'永不拍照、截图或输入联网设备'**
  String get ruleNoCaptureTitle;

  /// No description provided for @ruleNoCaptureDesc.
  ///
  /// In zh, this message translates to:
  /// **'不要保存到相册、云盘或聊天软件，本 App 已禁用截图'**
  String get ruleNoCaptureDesc;

  /// No description provided for @backupMnemonicTitle.
  ///
  /// In zh, this message translates to:
  /// **'备份助记词'**
  String get backupMnemonicTitle;

  /// No description provided for @mnemonicShowConfirmBtn.
  ///
  /// In zh, this message translates to:
  /// **'我已手写备份，开始验证'**
  String get mnemonicShowConfirmBtn;

  /// No description provided for @mnemonicShowInstruction.
  ///
  /// In zh, this message translates to:
  /// **'请按顺序手写抄录以下 12 个单词，并保存在安全的物理位置。'**
  String get mnemonicShowInstruction;

  /// No description provided for @mnemonicShowWarning.
  ///
  /// In zh, this message translates to:
  /// **'请勿截图、拍照或抄录到任何联网设备。'**
  String get mnemonicShowWarning;

  /// No description provided for @verifyBackupTitle.
  ///
  /// In zh, this message translates to:
  /// **'验证备份'**
  String get verifyBackupTitle;

  /// No description provided for @mnemonicWordChallenge.
  ///
  /// In zh, this message translates to:
  /// **'第 {position} 个单词是？'**
  String mnemonicWordChallenge(int position);

  /// No description provided for @mnemonicChallengeHint.
  ///
  /// In zh, this message translates to:
  /// **'从下列单词中选择正确的一项'**
  String get mnemonicChallengeHint;

  /// No description provided for @verifyWrong.
  ///
  /// In zh, this message translates to:
  /// **'选择有误，请对照您手写的备份重试'**
  String get verifyWrong;

  /// No description provided for @importWalletTitle.
  ///
  /// In zh, this message translates to:
  /// **'导入钱包'**
  String get importWalletTitle;

  /// No description provided for @wordCountOption.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个单词'**
  String wordCountOption(int count);

  /// No description provided for @setPasswordTitle.
  ///
  /// In zh, this message translates to:
  /// **'设置解锁密码'**
  String get setPasswordTitle;

  /// No description provided for @setPasswordPrompt.
  ///
  /// In zh, this message translates to:
  /// **'设置 6 位密码'**
  String get setPasswordPrompt;

  /// No description provided for @setPasswordConfirmPrompt.
  ///
  /// In zh, this message translates to:
  /// **'再次输入以确认'**
  String get setPasswordConfirmPrompt;

  /// No description provided for @setPasswordDesc.
  ///
  /// In zh, this message translates to:
  /// **'用于解锁 App 和确认签名。密码仅保存在本机安全区域。'**
  String get setPasswordDesc;

  /// No description provided for @passwordMismatch.
  ///
  /// In zh, this message translates to:
  /// **'两次输入不一致，请重新设置'**
  String get passwordMismatch;

  /// No description provided for @biometricTitle.
  ///
  /// In zh, this message translates to:
  /// **'生物识别'**
  String get biometricTitle;

  /// No description provided for @enableFaceId.
  ///
  /// In zh, this message translates to:
  /// **'启用 Face ID'**
  String get enableFaceId;

  /// No description provided for @biometricSkip.
  ///
  /// In zh, this message translates to:
  /// **'暂不启用，仅使用密码'**
  String get biometricSkip;

  /// No description provided for @biometricDesc.
  ///
  /// In zh, this message translates to:
  /// **'每次签名前都需要验证身份。启用 Face ID 可以更快完成验证，也可以随时改用设备密码。'**
  String get biometricDesc;

  /// No description provided for @exportPublicAddress.
  ///
  /// In zh, this message translates to:
  /// **'导出公开地址'**
  String get exportPublicAddress;

  /// No description provided for @walletCreated.
  ///
  /// In zh, this message translates to:
  /// **'钱包创建完成'**
  String get walletCreated;

  /// No description provided for @mnemonicBackedUpVerified.
  ///
  /// In zh, this message translates to:
  /// **'助记词已备份并通过验证'**
  String get mnemonicBackedUpVerified;

  /// No description provided for @walletNameLabel.
  ///
  /// In zh, this message translates to:
  /// **'钱包名称'**
  String get walletNameLabel;

  /// No description provided for @walletMainName.
  ///
  /// In zh, this message translates to:
  /// **'主钱包'**
  String get walletMainName;

  /// No description provided for @mnemonicBackupLabel.
  ///
  /// In zh, this message translates to:
  /// **'助记词备份'**
  String get mnemonicBackupLabel;

  /// No description provided for @verified.
  ///
  /// In zh, this message translates to:
  /// **'已验证'**
  String get verified;

  /// No description provided for @supportedNetworks.
  ///
  /// In zh, this message translates to:
  /// **'支持网络'**
  String get supportedNetworks;

  /// No description provided for @offlineForDays.
  ///
  /// In zh, this message translates to:
  /// **'已持续离线 {days} 天'**
  String offlineForDays(int days);

  /// No description provided for @securityCheckPassed.
  ///
  /// In zh, this message translates to:
  /// **'安全检查通过 · 飞行模式已开启'**
  String get securityCheckPassed;

  /// No description provided for @scanPendingTx.
  ///
  /// In zh, this message translates to:
  /// **'扫描待签名交易'**
  String get scanPendingTx;

  /// No description provided for @scanPendingTxDesc.
  ///
  /// In zh, this message translates to:
  /// **'扫描联网钱包生成的动态二维码'**
  String get scanPendingTxDesc;

  /// No description provided for @exportAddress.
  ///
  /// In zh, this message translates to:
  /// **'导出地址'**
  String get exportAddress;

  /// No description provided for @signRecords.
  ///
  /// In zh, this message translates to:
  /// **'签名记录'**
  String get signRecords;

  /// No description provided for @securityCheck.
  ///
  /// In zh, this message translates to:
  /// **'安全检查'**
  String get securityCheck;

  /// No description provided for @walletManage.
  ///
  /// In zh, this message translates to:
  /// **'钱包管理'**
  String get walletManage;

  /// No description provided for @offlineSecurityCheck.
  ///
  /// In zh, this message translates to:
  /// **'离线安全检查'**
  String get offlineSecurityCheck;

  /// No description provided for @checkAirplaneMode.
  ///
  /// In zh, this message translates to:
  /// **'飞行模式'**
  String get checkAirplaneMode;

  /// No description provided for @checkCellular.
  ///
  /// In zh, this message translates to:
  /// **'蜂窝网络'**
  String get checkCellular;

  /// No description provided for @checkBluetooth.
  ///
  /// In zh, this message translates to:
  /// **'蓝牙'**
  String get checkBluetooth;

  /// No description provided for @checkDevicePasscode.
  ///
  /// In zh, this message translates to:
  /// **'设备密码'**
  String get checkDevicePasscode;

  /// No description provided for @checkBiometric.
  ///
  /// In zh, this message translates to:
  /// **'生物识别'**
  String get checkBiometric;

  /// No description provided for @checkScreenRecording.
  ///
  /// In zh, this message translates to:
  /// **'屏幕录制'**
  String get checkScreenRecording;

  /// No description provided for @statusOn.
  ///
  /// In zh, this message translates to:
  /// **'已开启'**
  String get statusOn;

  /// No description provided for @statusOff.
  ///
  /// In zh, this message translates to:
  /// **'已关闭'**
  String get statusOff;

  /// No description provided for @statusDetectedOn.
  ///
  /// In zh, this message translates to:
  /// **'检测到开启'**
  String get statusDetectedOn;

  /// No description provided for @statusEnabled.
  ///
  /// In zh, this message translates to:
  /// **'已启用'**
  String get statusEnabled;

  /// No description provided for @statusNotDetected.
  ///
  /// In zh, this message translates to:
  /// **'未检测到'**
  String get statusNotDetected;

  /// No description provided for @riskCannotSign.
  ///
  /// In zh, this message translates to:
  /// **'存在风险 · 暂不能签名'**
  String get riskCannotSign;

  /// No description provided for @bluetoothWarning.
  ///
  /// In zh, this message translates to:
  /// **'检测到蓝牙处于开启状态，请关闭后重新检测。'**
  String get bluetoothWarning;

  /// No description provided for @checkNetwork.
  ///
  /// In zh, this message translates to:
  /// **'网络连接'**
  String get checkNetwork;

  /// No description provided for @checkIntegrity.
  ///
  /// In zh, this message translates to:
  /// **'系统完整性'**
  String get checkIntegrity;

  /// No description provided for @checkLevelPass.
  ///
  /// In zh, this message translates to:
  /// **'通过'**
  String get checkLevelPass;

  /// No description provided for @checkLevelWarn.
  ///
  /// In zh, this message translates to:
  /// **'警告'**
  String get checkLevelWarn;

  /// No description provided for @checkLevelBlock.
  ///
  /// In zh, this message translates to:
  /// **'危险'**
  String get checkLevelBlock;

  /// No description provided for @securityChecking.
  ///
  /// In zh, this message translates to:
  /// **'正在检查设备状态…'**
  String get securityChecking;

  /// No description provided for @securityOverallPass.
  ///
  /// In zh, this message translates to:
  /// **'检查通过 · 可以签名'**
  String get securityOverallPass;

  /// No description provided for @securityOverallWarn.
  ///
  /// In zh, this message translates to:
  /// **'存在风险 · 请谨慎操作'**
  String get securityOverallWarn;

  /// No description provided for @securityOverallBlock.
  ///
  /// In zh, this message translates to:
  /// **'存在高危项 · 已禁止签名'**
  String get securityOverallBlock;

  /// No description provided for @securityRecheck.
  ///
  /// In zh, this message translates to:
  /// **'重新检查'**
  String get securityRecheck;

  /// No description provided for @receivingShard.
  ///
  /// In zh, this message translates to:
  /// **'接收分片 {received} / {total}'**
  String receivingShard(int received, int total);

  /// No description provided for @confirmTxContent.
  ///
  /// In zh, this message translates to:
  /// **'确认交易内容'**
  String get confirmTxContent;

  /// No description provided for @reject.
  ///
  /// In zh, this message translates to:
  /// **'拒绝'**
  String get reject;

  /// No description provided for @confirmSign.
  ///
  /// In zh, this message translates to:
  /// **'确认签名'**
  String get confirmSign;

  /// No description provided for @rawAmountPrecision.
  ///
  /// In zh, this message translates to:
  /// **'原始数量 {amount}（精度 {precision}）'**
  String rawAmountPrecision(String amount, int precision);

  /// No description provided for @fromAccount.
  ///
  /// In zh, this message translates to:
  /// **'转出账户（From）'**
  String get fromAccount;

  /// No description provided for @toAddress.
  ///
  /// In zh, this message translates to:
  /// **'收款地址（To）'**
  String get toAddress;

  /// No description provided for @walletIdLabel.
  ///
  /// In zh, this message translates to:
  /// **'钱包 ID'**
  String get walletIdLabel;

  /// No description provided for @createdAtLabel.
  ///
  /// In zh, this message translates to:
  /// **'创建时间'**
  String get createdAtLabel;

  /// No description provided for @expiresAtLabel.
  ///
  /// In zh, this message translates to:
  /// **'有效期至'**
  String get expiresAtLabel;

  /// No description provided for @riskWarningTitle.
  ///
  /// In zh, this message translates to:
  /// **'风险警告'**
  String get riskWarningTitle;

  /// No description provided for @backToHome.
  ///
  /// In zh, this message translates to:
  /// **'返回首页'**
  String get backToHome;

  /// No description provided for @viewRawTxData.
  ///
  /// In zh, this message translates to:
  /// **'查看原始交易数据'**
  String get viewRawTxData;

  /// No description provided for @signingBlocked.
  ///
  /// In zh, this message translates to:
  /// **'已禁止签名'**
  String get signingBlocked;

  /// No description provided for @signingBlockedDesc.
  ///
  /// In zh, this message translates to:
  /// **'该交易包含无法安全解析的内容，KT Cold Signer 已拒绝签名以保护你的资产。'**
  String get signingBlockedDesc;

  /// No description provided for @unknownContractCallDetected.
  ///
  /// In zh, this message translates to:
  /// **'检测到未知合约调用：{method}'**
  String unknownContractCallDetected(String method);

  /// No description provided for @unknownContractCallDesc.
  ///
  /// In zh, this message translates to:
  /// **'V1 仅支持原生币和 Token 转账。approve、permit 等授权类调用一律拒绝。'**
  String get unknownContractCallDesc;

  /// No description provided for @authTitle.
  ///
  /// In zh, this message translates to:
  /// **'身份验证'**
  String get authTitle;

  /// No description provided for @useFaceIdVerify.
  ///
  /// In zh, this message translates to:
  /// **'使用 Face ID 验证'**
  String get useFaceIdVerify;

  /// No description provided for @useDevicePasscode.
  ///
  /// In zh, this message translates to:
  /// **'改用设备密码'**
  String get useDevicePasscode;

  /// No description provided for @biometricFailedRetry.
  ///
  /// In zh, this message translates to:
  /// **'验证失败，请重试'**
  String get biometricFailedRetry;

  /// No description provided for @verifyToSign.
  ///
  /// In zh, this message translates to:
  /// **'验证以完成签名'**
  String get verifyToSign;

  /// No description provided for @verifyToSignDesc.
  ///
  /// In zh, this message translates to:
  /// **'每次签名都需要通过 Face ID 或设备密码验证'**
  String get verifyToSignDesc;

  /// No description provided for @amountLabel.
  ///
  /// In zh, this message translates to:
  /// **'金额'**
  String get amountLabel;

  /// No description provided for @requestId.
  ///
  /// In zh, this message translates to:
  /// **'请求 ID'**
  String get requestId;

  /// No description provided for @enterPinToSign.
  ///
  /// In zh, this message translates to:
  /// **'输入 App 密码以完成签名'**
  String get enterPinToSign;

  /// No description provided for @pinIncorrect.
  ///
  /// In zh, this message translates to:
  /// **'密码错误，请重试'**
  String get pinIncorrect;

  /// No description provided for @pinLockedRetry.
  ///
  /// In zh, this message translates to:
  /// **'尝试次数过多，请 {seconds} 秒后重试'**
  String pinLockedRetry(int seconds);

  /// No description provided for @signComplete.
  ///
  /// In zh, this message translates to:
  /// **'签名完成'**
  String get signComplete;

  /// No description provided for @voidThisSignature.
  ///
  /// In zh, this message translates to:
  /// **'作废本次签名'**
  String get voidThisSignature;

  /// No description provided for @voidSignatureTitle.
  ///
  /// In zh, this message translates to:
  /// **'作废本次签名？'**
  String get voidSignatureTitle;

  /// No description provided for @voidSignatureDesc.
  ///
  /// In zh, this message translates to:
  /// **'作废后该签名结果二维码将失效，联网钱包将无法广播这笔交易。'**
  String get voidSignatureDesc;

  /// No description provided for @signatureVoided.
  ///
  /// In zh, this message translates to:
  /// **'签名已作废'**
  String get signatureVoided;

  /// No description provided for @dynamicShard.
  ///
  /// In zh, this message translates to:
  /// **'动态分片 {received} / {total}'**
  String dynamicShard(int received, int total);

  /// No description provided for @scanResultInstruction.
  ///
  /// In zh, this message translates to:
  /// **'请使用联网钱包「扫描签名结果」读取此二维码'**
  String get scanResultInstruction;

  /// No description provided for @allAddresses.
  ///
  /// In zh, this message translates to:
  /// **'全部地址'**
  String get allAddresses;

  /// No description provided for @exportQrCaption.
  ///
  /// In zh, this message translates to:
  /// **'包含 {count} 条链公开地址 · 不含任何私密数据'**
  String exportQrCaption(int count);

  /// No description provided for @filterAll.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get filterAll;

  /// No description provided for @stateSigned.
  ///
  /// In zh, this message translates to:
  /// **'已签名'**
  String get stateSigned;

  /// No description provided for @stateRejected.
  ///
  /// In zh, this message translates to:
  /// **'已拒绝'**
  String get stateRejected;

  /// No description provided for @stateExpired.
  ///
  /// In zh, this message translates to:
  /// **'已过期'**
  String get stateExpired;

  /// No description provided for @unknownContractCallLabel.
  ///
  /// In zh, this message translates to:
  /// **'未知合约调用'**
  String get unknownContractCallLabel;

  /// No description provided for @walletCreatedOn.
  ///
  /// In zh, this message translates to:
  /// **'创建于 {date}'**
  String walletCreatedOn(String date);

  /// No description provided for @backedUp.
  ///
  /// In zh, this message translates to:
  /// **'已备份'**
  String get backedUp;

  /// No description provided for @editWalletName.
  ///
  /// In zh, this message translates to:
  /// **'修改钱包名称'**
  String get editWalletName;

  /// No description provided for @mnemonicBackupCheck.
  ///
  /// In zh, this message translates to:
  /// **'助记词备份验证'**
  String get mnemonicBackupCheck;

  /// No description provided for @mnemonicBackupCheckDesc.
  ///
  /// In zh, this message translates to:
  /// **'定期抽查助记词是否仍能正确抄录'**
  String get mnemonicBackupCheckDesc;

  /// No description provided for @deleteWallet.
  ///
  /// In zh, this message translates to:
  /// **'删除钱包'**
  String get deleteWallet;

  /// No description provided for @deleteWalletReqDesc.
  ///
  /// In zh, this message translates to:
  /// **'需要密码、生物识别和确认文字'**
  String get deleteWalletReqDesc;

  /// No description provided for @destroyAllData.
  ///
  /// In zh, this message translates to:
  /// **'销毁全部钱包数据'**
  String get destroyAllData;

  /// No description provided for @destroyAllDataDesc.
  ///
  /// In zh, this message translates to:
  /// **'不可恢复，仅在设备处置前使用'**
  String get destroyAllDataDesc;

  /// No description provided for @securitySettingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'安全设置'**
  String get securitySettingsTitle;

  /// No description provided for @verificationPolicy.
  ///
  /// In zh, this message translates to:
  /// **'验证策略'**
  String get verificationPolicy;

  /// No description provided for @biometricUsageDesc.
  ///
  /// In zh, this message translates to:
  /// **'Face ID 用于解锁与签名'**
  String get biometricUsageDesc;

  /// No description provided for @verifyEverySign.
  ///
  /// In zh, this message translates to:
  /// **'每次签名验证'**
  String get verifyEverySign;

  /// No description provided for @verifyEverySignDesc.
  ///
  /// In zh, this message translates to:
  /// **'不可关闭（V1 强制）'**
  String get verifyEverySignDesc;

  /// No description provided for @accessSection.
  ///
  /// In zh, this message translates to:
  /// **'访问'**
  String get accessSection;

  /// No description provided for @changeAppPassword.
  ///
  /// In zh, this message translates to:
  /// **'修改 App 密码'**
  String get changeAppPassword;

  /// No description provided for @screenCaptureProtection.
  ///
  /// In zh, this message translates to:
  /// **'截图与录屏防护'**
  String get screenCaptureProtection;

  /// No description provided for @permanentlyDeleteWallet.
  ///
  /// In zh, this message translates to:
  /// **'永久删除钱包'**
  String get permanentlyDeleteWallet;

  /// No description provided for @stepPassword.
  ///
  /// In zh, this message translates to:
  /// **'密码'**
  String get stepPassword;

  /// No description provided for @stepConfirmText.
  ///
  /// In zh, this message translates to:
  /// **'确认文字'**
  String get stepConfirmText;

  /// No description provided for @irreversibleAction.
  ///
  /// In zh, this message translates to:
  /// **'此操作不可恢复'**
  String get irreversibleAction;

  /// No description provided for @deleteWalletWarningDesc.
  ///
  /// In zh, this message translates to:
  /// **'删除后，本机将清除该钱包的全部密钥数据。若助记词未备份或备份遗失，资产将永久无法找回。'**
  String get deleteWalletWarningDesc;

  /// No description provided for @typeToConfirmDelete.
  ///
  /// In zh, this message translates to:
  /// **'请输入「删除钱包」以继续'**
  String get typeToConfirmDelete;

  /// No description provided for @displayLanguage.
  ///
  /// In zh, this message translates to:
  /// **'显示语言'**
  String get displayLanguage;

  /// No description provided for @settingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settingsTitle;

  /// No description provided for @fiatUnit.
  ///
  /// In zh, this message translates to:
  /// **'法币单位'**
  String get fiatUnit;

  /// No description provided for @languageSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get languageSystem;

  /// No description provided for @deviceMode.
  ///
  /// In zh, this message translates to:
  /// **'设备模式'**
  String get deviceMode;

  /// No description provided for @deviceModeSigner.
  ///
  /// In zh, this message translates to:
  /// **'离线签名器'**
  String get deviceModeSigner;

  /// No description provided for @deviceModeSwitchTitle.
  ///
  /// In zh, this message translates to:
  /// **'切换设备模式'**
  String get deviceModeSwitchTitle;

  /// No description provided for @deviceModeSwitchDesc.
  ///
  /// In zh, this message translates to:
  /// **'切换前请确认本机不再用作签名器。切换后将返回模式选择页。'**
  String get deviceModeSwitchDesc;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
