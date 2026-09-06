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

  /// No description provided for @signerBackupEntryDesc.
  ///
  /// In zh, this message translates to:
  /// **'强密码加密 · 保存到本地'**
  String get signerBackupEntryDesc;

  /// No description provided for @backupQrTitle.
  ///
  /// In zh, this message translates to:
  /// **'加密二维码'**
  String get backupQrTitle;

  /// No description provided for @backupQrIntro.
  ///
  /// In zh, this message translates to:
  /// **'使用独立强密码在本机加密助记词，生成带 KT Wallet 品牌的二维码图片。图片不包含明文助记词或密码。'**
  String get backupQrIntro;

  /// No description provided for @backupQrImageInstruction.
  ///
  /// In zh, this message translates to:
  /// **'需要密码 · 不是收款码\n在 KT Wallet 中选择「从备份恢复」→「扫描加密二维码」或「选择二维码图片」。请勿公开此图片，密码须分开保管。'**
  String get backupQrImageInstruction;

  /// No description provided for @backupQrGenerate.
  ///
  /// In zh, this message translates to:
  /// **'生成加密二维码'**
  String get backupQrGenerate;

  /// No description provided for @backupQrSave.
  ///
  /// In zh, this message translates to:
  /// **'保存二维码图片到本地'**
  String get backupQrSave;

  /// No description provided for @backupPasswordLabel.
  ///
  /// In zh, this message translates to:
  /// **'备份密码'**
  String get backupPasswordLabel;

  /// No description provided for @backupPasswordConfirm.
  ///
  /// In zh, this message translates to:
  /// **'再次输入密码'**
  String get backupPasswordConfirm;

  /// No description provided for @backupPasswordTooShort.
  ///
  /// In zh, this message translates to:
  /// **'请至少输入 14 个字符'**
  String get backupPasswordTooShort;

  /// No description provided for @backupPasswordTooLong.
  ///
  /// In zh, this message translates to:
  /// **'最多输入 128 个字符'**
  String get backupPasswordTooLong;

  /// No description provided for @backupPasswordTooWeak.
  ///
  /// In zh, this message translates to:
  /// **'请勿使用重复、连续或常见密码'**
  String get backupPasswordTooWeak;

  /// No description provided for @backupPasswordMismatch.
  ///
  /// In zh, this message translates to:
  /// **'两次输入的密码不一致'**
  String get backupPasswordMismatch;

  /// No description provided for @backupFailed.
  ///
  /// In zh, this message translates to:
  /// **'生成备份失败'**
  String get backupFailed;

  /// No description provided for @backupSaved.
  ///
  /// In zh, this message translates to:
  /// **'备份已保存'**
  String get backupSaved;

  /// No description provided for @backupCancelled.
  ///
  /// In zh, this message translates to:
  /// **'已取消备份'**
  String get backupCancelled;

  /// No description provided for @walletUnlockRequired.
  ///
  /// In zh, this message translates to:
  /// **'钱包已锁定'**
  String get walletUnlockRequired;

  /// No description provided for @walletUnlockRequiredDesc.
  ///
  /// In zh, this message translates to:
  /// **'需要系统身份认证才能读取钱包。认证取消或过期不会删除钱包，请解锁后重试。'**
  String get walletUnlockRequiredDesc;

  /// No description provided for @walletUnlockAction.
  ///
  /// In zh, this message translates to:
  /// **'验证身份并解锁'**
  String get walletUnlockAction;

  /// No description provided for @signerBackupScope.
  ///
  /// In zh, this message translates to:
  /// **'仅备份当前钱包的助记词，不包含 App 密码、设置或签名记录。'**
  String get signerBackupScope;

  /// No description provided for @signerBackupLocalWarning.
  ///
  /// In zh, this message translates to:
  /// **'二维码与密码一起等同于助记词。请选择本地保存位置，关闭云同步，密码请分开保管；遗忘密码无法恢复。'**
  String get signerBackupLocalWarning;

  /// No description provided for @signRejectWallet.
  ///
  /// In zh, this message translates to:
  /// **'此请求属于另一个冷钱包。请在在线端重新配对当前冷钱包，再生成交易二维码。'**
  String get signRejectWallet;

  /// No description provided for @signRejectExpired.
  ///
  /// In zh, this message translates to:
  /// **'交易请求已过期。请在在线端重新生成交易二维码。'**
  String get signRejectExpired;

  /// No description provided for @signRejectClock.
  ///
  /// In zh, this message translates to:
  /// **'两台设备的时间不一致。请检查系统时间后重新生成请求。'**
  String get signRejectClock;

  /// No description provided for @signRejectDuplicate.
  ///
  /// In zh, this message translates to:
  /// **'此请求已处理或已保留，不能重复签名。请检查签名记录。'**
  String get signRejectDuplicate;

  /// No description provided for @signRejectUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'无法安全解析此交易或网络信息不匹配。仅支持原生币转账、Token 转账及 approve(被授权合约, 0) 撤销。'**
  String get signRejectUnsupported;

  /// No description provided for @signRejectInvalid.
  ///
  /// In zh, this message translates to:
  /// **'二维码不是有效的待签名交易。请扫描在线钱包生成的交易二维码。'**
  String get signRejectInvalid;

  /// No description provided for @signRejectNoWallet.
  ///
  /// In zh, this message translates to:
  /// **'当前冷钱包不可用。请先创建或导入钱包，再重新配对。'**
  String get signRejectNoWallet;

  /// No description provided for @signRejectStorage.
  ///
  /// In zh, this message translates to:
  /// **'无法读取安全签名记录。请返回后重试。'**
  String get signRejectStorage;

  /// No description provided for @signRejectNoSignature.
  ///
  /// In zh, this message translates to:
  /// **'本次请求未获签名，请查看以下原因。'**
  String get signRejectNoSignature;

  /// No description provided for @amountPrecisionUnknown.
  ///
  /// In zh, this message translates to:
  /// **'Token 精度未经验证，请核对原始数量与合约地址。'**
  String get amountPrecisionUnknown;

  /// No description provided for @amountBaseUnits.
  ///
  /// In zh, this message translates to:
  /// **'基础单位'**
  String get amountBaseUnits;

  /// No description provided for @qrImportTitle.
  ///
  /// In zh, this message translates to:
  /// **'加密二维码导入'**
  String get qrImportTitle;

  /// No description provided for @qrImportDescription.
  ///
  /// In zh, this message translates to:
  /// **'扫描 KT Wallet 加密备份二维码，或选择本机保存的二维码图片。解密全程在本地完成。'**
  String get qrImportDescription;

  /// No description provided for @qrImportScan.
  ///
  /// In zh, this message translates to:
  /// **'扫描备份二维码'**
  String get qrImportScan;

  /// No description provided for @qrImportImage.
  ///
  /// In zh, this message translates to:
  /// **'选择本地二维码图片'**
  String get qrImportImage;

  /// No description provided for @qrImportReady.
  ///
  /// In zh, this message translates to:
  /// **'已识别加密备份'**
  String get qrImportReady;

  /// No description provided for @qrImportPassword.
  ///
  /// In zh, this message translates to:
  /// **'备份加密密码'**
  String get qrImportPassword;

  /// No description provided for @qrImportContinue.
  ///
  /// In zh, this message translates to:
  /// **'解密并继续'**
  String get qrImportContinue;

  /// No description provided for @qrImportInvalid.
  ///
  /// In zh, this message translates to:
  /// **'无法读取此备份。请选择小于 8 MB 的本地 PNG/JPEG 图片，且只包含一个 KT Wallet 加密备份二维码。'**
  String get qrImportInvalid;

  /// No description provided for @qrImportWrongPassword.
  ///
  /// In zh, this message translates to:
  /// **'密码错误或备份已损坏，请检查密码后重试。'**
  String get qrImportWrongPassword;

  /// No description provided for @qrImportSafety.
  ///
  /// In zh, this message translates to:
  /// **'请保持设备离线。输入导出备份时设置的加密密码，而非钱包 PIN。若助记词曾在联网设备上使用，导入离线版并不能使它成为从未触网的冷钱包。'**
  String get qrImportSafety;

  /// No description provided for @walletDeviceAuthRequired.
  ///
  /// In zh, this message translates to:
  /// **'请先在系统设置中启用锁屏密码或生物识别，再重试。钱包 PIN 不能替代系统认证；模拟器也需要配置。'**
  String get walletDeviceAuthRequired;

  /// No description provided for @walletCreationAuthRequired.
  ///
  /// In zh, this message translates to:
  /// **'系统认证未完成，钱包尚未创建。请重试并完成系统验证。'**
  String get walletCreationAuthRequired;

  /// No description provided for @introOpenTitle.
  ///
  /// In zh, this message translates to:
  /// **'前后端 100% 开源'**
  String get introOpenTitle;

  /// No description provided for @introOpenDescription.
  ///
  /// In zh, this message translates to:
  /// **'从钱包界面、离线签名到后端网关，代码全部公开。让信任建立在可审查的代码上。'**
  String get introOpenDescription;

  /// No description provided for @introOpenNote.
  ///
  /// In zh, this message translates to:
  /// **'查看完整源码，了解资产如何被保护。公开可审查，也欢迎持续改进。'**
  String get introOpenNote;

  /// No description provided for @introSecurityTitle.
  ///
  /// In zh, this message translates to:
  /// **'安全第一。\n掌控始终在你。'**
  String get introSecurityTitle;

  /// No description provided for @introFrontend.
  ///
  /// In zh, this message translates to:
  /// **'客户端'**
  String get introFrontend;

  /// No description provided for @introBackend.
  ///
  /// In zh, this message translates to:
  /// **'后端网关'**
  String get introBackend;

  /// No description provided for @introOnline.
  ///
  /// In zh, this message translates to:
  /// **'在线钱包'**
  String get introOnline;

  /// No description provided for @introOffline.
  ///
  /// In zh, this message translates to:
  /// **'离线签名端'**
  String get introOffline;

  /// No description provided for @introNext.
  ///
  /// In zh, this message translates to:
  /// **'继续'**
  String get introNext;

  /// No description provided for @introSkip.
  ///
  /// In zh, this message translates to:
  /// **'跳过引导'**
  String get introSkip;

  /// No description provided for @introBack.
  ///
  /// In zh, this message translates to:
  /// **'上一步'**
  String get introBack;

  /// No description provided for @introSource.
  ///
  /// In zh, this message translates to:
  /// **'查看开源代码'**
  String get introSource;

  /// No description provided for @introSourceHint.
  ///
  /// In zh, this message translates to:
  /// **'使用联网设备扫描二维码查看完整源码。此页面不会发起网络请求。'**
  String get introSourceHint;

  /// No description provided for @introCopyLink.
  ///
  /// In zh, this message translates to:
  /// **'复制源码地址'**
  String get introCopyLink;

  /// No description provided for @introCopied.
  ///
  /// In zh, this message translates to:
  /// **'源码地址已复制'**
  String get introCopied;

  /// No description provided for @introSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'未能保存引导状态，请重试。'**
  String get introSaveFailed;

  /// No description provided for @introRole.
  ///
  /// In zh, this message translates to:
  /// **'独立离线签名端'**
  String get introRole;

  /// No description provided for @introSecurityDescription.
  ///
  /// In zh, this message translates to:
  /// **'私钥保存在这台离线设备上。每次签名前核对交易详情，并验证身份；助记词仅由你离线备份。'**
  String get introSecurityDescription;

  /// No description provided for @introSecurityNote.
  ///
  /// In zh, this message translates to:
  /// **'开启飞行模式，关闭 Wi-Fi 与蓝牙。把这台手机专用于离线签名，并始终保持离线。'**
  String get introSecurityNote;

  /// No description provided for @introPairTitle.
  ///
  /// In zh, this message translates to:
  /// **'只签名。\n不联网。'**
  String get introPairTitle;

  /// No description provided for @introPairDescription.
  ///
  /// In zh, this message translates to:
  /// **'在联网手机安装 KT Wallet，生成待签名交易。用本机扫码、核对、签名，再将签名二维码交回在线钱包广播。'**
  String get introPairDescription;

  /// No description provided for @introPairNote.
  ///
  /// In zh, this message translates to:
  /// **'扫码传递交易与签名结果，不传递私钥或助记词。此 App 不查询余额，也不广播交易。'**
  String get introPairNote;

  /// No description provided for @introStart.
  ///
  /// In zh, this message translates to:
  /// **'设置离线签名端'**
  String get introStart;

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

  /// No description provided for @actionValidating.
  ///
  /// In zh, this message translates to:
  /// **'正在校验…'**
  String get actionValidating;

  /// No description provided for @cameraUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'相机不可用'**
  String get cameraUnavailable;

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
  /// **'不要保存到相册、云盘或聊天软件；iOS 截图后提醒，Android 助记词页面禁止截图'**
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

  /// No description provided for @mnemonicInvalidChecksum.
  ///
  /// In zh, this message translates to:
  /// **'助记词无效，请检查每个单词、单词数量和 BIP-39 校验和。'**
  String get mnemonicInvalidChecksum;

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

  /// No description provided for @biometricUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'此设备尚未设置可用的生物识别或设备认证。'**
  String get biometricUnavailable;

  /// No description provided for @walletSecureStorageFailed.
  ///
  /// In zh, this message translates to:
  /// **'钱包安全存储失败，未保存任何密钥。'**
  String get walletSecureStorageFailed;

  /// No description provided for @secureStorageUnavailableTitle.
  ///
  /// In zh, this message translates to:
  /// **'安全存储不可用'**
  String get secureStorageUnavailableTitle;

  /// No description provided for @secureStorageUnavailableDesc.
  ///
  /// In zh, this message translates to:
  /// **'KT冷钱包无法安全读取钱包、密码和锁定状态，签名功能将保持锁定。请重新启动 App，或从可信来源重新安装。'**
  String get secureStorageUnavailableDesc;

  /// No description provided for @actionRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get actionRetry;

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

  /// No description provided for @offlineStatusConfirmed.
  ///
  /// In zh, this message translates to:
  /// **'网络已断开'**
  String get offlineStatusConfirmed;

  /// No description provided for @offlineStatusConnected.
  ///
  /// In zh, this message translates to:
  /// **'检测到网络连接'**
  String get offlineStatusConnected;

  /// No description provided for @offlineStatusUnknown.
  ///
  /// In zh, this message translates to:
  /// **'无法确认网络状态'**
  String get offlineStatusUnknown;

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
  /// **'地址二维码'**
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

  /// No description provided for @addWallet.
  ///
  /// In zh, this message translates to:
  /// **'添加钱包'**
  String get addWallet;

  /// No description provided for @signatureIncomplete.
  ///
  /// In zh, this message translates to:
  /// **'签名未完成'**
  String get signatureIncomplete;

  /// No description provided for @recordsLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法读取签名记录，请返回后重试。'**
  String get recordsLoadFailed;

  /// No description provided for @noWalletRecords.
  ///
  /// In zh, this message translates to:
  /// **'此钱包暂无签名记录'**
  String get noWalletRecords;

  /// No description provided for @switchWallet.
  ///
  /// In zh, this message translates to:
  /// **'切换 / 添加钱包'**
  String get switchWallet;

  /// No description provided for @walletSwitchFailed.
  ///
  /// In zh, this message translates to:
  /// **'钱包切换未完成，请完成系统认证后重试。原钱包未更改。'**
  String get walletSwitchFailed;

  /// No description provided for @multiWalletScope.
  ///
  /// In zh, this message translates to:
  /// **'每个钱包独立保存密钥和备份，共用本机 App PIN。删除一个钱包不会删除其他钱包。'**
  String get multiWalletScope;

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

  /// No description provided for @checkDetailUnknown.
  ///
  /// In zh, this message translates to:
  /// **'无法确认状态'**
  String get checkDetailUnknown;

  /// No description provided for @checkDetailNetworkSafe.
  ///
  /// In zh, this message translates to:
  /// **'未检测到网络连接'**
  String get checkDetailNetworkSafe;

  /// No description provided for @checkDetailNetworkUnsafe.
  ///
  /// In zh, this message translates to:
  /// **'检测到网络连接'**
  String get checkDetailNetworkUnsafe;

  /// No description provided for @checkDetailAirplaneSafe.
  ///
  /// In zh, this message translates to:
  /// **'飞行模式已开启'**
  String get checkDetailAirplaneSafe;

  /// No description provided for @checkDetailAirplaneUnsafe.
  ///
  /// In zh, this message translates to:
  /// **'飞行模式未开启'**
  String get checkDetailAirplaneUnsafe;

  /// No description provided for @checkDetailBluetoothSafe.
  ///
  /// In zh, this message translates to:
  /// **'蓝牙已关闭'**
  String get checkDetailBluetoothSafe;

  /// No description provided for @checkDetailBluetoothUnsafe.
  ///
  /// In zh, this message translates to:
  /// **'蓝牙已开启'**
  String get checkDetailBluetoothUnsafe;

  /// No description provided for @checkDetailPasscodeSafe.
  ///
  /// In zh, this message translates to:
  /// **'设备密码已设置'**
  String get checkDetailPasscodeSafe;

  /// No description provided for @checkDetailPasscodeUnsafe.
  ///
  /// In zh, this message translates to:
  /// **'设备密码未设置'**
  String get checkDetailPasscodeUnsafe;

  /// No description provided for @checkDetailBiometricSafe.
  ///
  /// In zh, this message translates to:
  /// **'生物识别可用'**
  String get checkDetailBiometricSafe;

  /// No description provided for @checkDetailBiometricUnsafe.
  ///
  /// In zh, this message translates to:
  /// **'生物识别不可用'**
  String get checkDetailBiometricUnsafe;

  /// No description provided for @checkDetailScreenCaptureSafe.
  ///
  /// In zh, this message translates to:
  /// **'未检测到屏幕录制'**
  String get checkDetailScreenCaptureSafe;

  /// No description provided for @checkDetailScreenCaptureUnsafe.
  ///
  /// In zh, this message translates to:
  /// **'检测到屏幕录制'**
  String get checkDetailScreenCaptureUnsafe;

  /// No description provided for @checkDetailIntegritySafe.
  ///
  /// In zh, this message translates to:
  /// **'系统完整性检查通过'**
  String get checkDetailIntegritySafe;

  /// No description provided for @checkDetailIntegrityUnsafe.
  ///
  /// In zh, this message translates to:
  /// **'检测到 root 或越狱'**
  String get checkDetailIntegrityUnsafe;

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
  /// **'转出账户'**
  String get fromAccount;

  /// No description provided for @toAddress.
  ///
  /// In zh, this message translates to:
  /// **'收款地址'**
  String get toAddress;

  /// No description provided for @spenderAddress.
  ///
  /// In zh, this message translates to:
  /// **'被授权合约'**
  String get spenderAddress;

  /// No description provided for @nativeTransferOperation.
  ///
  /// In zh, this message translates to:
  /// **'原生币转账'**
  String get nativeTransferOperation;

  /// No description provided for @tokenTransferOperation.
  ///
  /// In zh, this message translates to:
  /// **'Token 转账'**
  String get tokenTransferOperation;

  /// No description provided for @approvalRevokeOperation.
  ///
  /// In zh, this message translates to:
  /// **'撤销 Token 授权'**
  String get approvalRevokeOperation;

  /// No description provided for @approvalRevokeZeroAllowance.
  ///
  /// In zh, this message translates to:
  /// **'将授权额度设为零'**
  String get approvalRevokeZeroAllowance;

  /// No description provided for @approvalRevokeSignerNotice.
  ///
  /// In zh, this message translates to:
  /// **'这是精确的 ERC-20 approve(被授权合约, 0) 调用，只撤销额度，不会转出 Token。'**
  String get approvalRevokeSignerNotice;

  /// No description provided for @tokenContractLabel.
  ///
  /// In zh, this message translates to:
  /// **'Token 合约'**
  String get tokenContractLabel;

  /// No description provided for @chainIdLabel.
  ///
  /// In zh, this message translates to:
  /// **'Chain ID'**
  String get chainIdLabel;

  /// No description provided for @maximumFeeBaseUnits.
  ///
  /// In zh, this message translates to:
  /// **'最高网络费（最小单位）'**
  String get maximumFeeBaseUnits;

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
  /// **'该交易包含无法安全解析的内容，KT冷钱包已拒绝签名以保护你的资产。'**
  String get signingBlockedDesc;

  /// No description provided for @transactionParseFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法安全解析'**
  String get transactionParseFailed;

  /// No description provided for @signingFailed.
  ///
  /// In zh, this message translates to:
  /// **'签名失败，交易、钱包或认证未通过校验。'**
  String get signingFailed;

  /// No description provided for @unknownContractCallDetected.
  ///
  /// In zh, this message translates to:
  /// **'检测到未知合约调用：{method}'**
  String unknownContractCallDetected(String method);

  /// No description provided for @unknownContractCallDesc.
  ///
  /// In zh, this message translates to:
  /// **'仅支持原生币转账、Token 转账和精确的 approve(被授权合约, 0) 撤销。非零 approve、permit 与未知调用一律拒绝。'**
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

  /// No description provided for @enterPinToDelete.
  ///
  /// In zh, this message translates to:
  /// **'输入 App 密码以继续删除'**
  String get enterPinToDelete;

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
  /// **'关闭签名二维码'**
  String get voidThisSignature;

  /// No description provided for @voidSignatureTitle.
  ///
  /// In zh, this message translates to:
  /// **'关闭签名二维码？'**
  String get voidSignatureTitle;

  /// No description provided for @voidSignatureDesc.
  ///
  /// In zh, this message translates to:
  /// **'仅关闭本机二维码。已被其他设备扫描或保存的签名不会被撤销，仍可能被广播。关闭页面不等于取消交易。'**
  String get voidSignatureDesc;

  /// No description provided for @signatureVoided.
  ///
  /// In zh, this message translates to:
  /// **'二维码已关闭，未撤销签名'**
  String get signatureVoided;

  /// No description provided for @signResultUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'签名结果不可用'**
  String get signResultUnavailable;

  /// No description provided for @dynamicShard.
  ///
  /// In zh, this message translates to:
  /// **'动态分片 {received} / {total}'**
  String dynamicShard(int received, int total);

  /// No description provided for @scanResultInstruction.
  ///
  /// In zh, this message translates to:
  /// **'请在联网钱包当前交易中点击「离线设备已签名，扫描结果」，读取此二维码。'**
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

  /// No description provided for @mnemonicReviewFailed.
  ///
  /// In zh, this message translates to:
  /// **'认证或助记词校验失败，未显示任何助记词。'**
  String get mnemonicReviewFailed;

  /// No description provided for @deleteWallet.
  ///
  /// In zh, this message translates to:
  /// **'删除钱包'**
  String get deleteWallet;

  /// No description provided for @deleteWalletReqDesc.
  ///
  /// In zh, this message translates to:
  /// **'需要 App 密码和确认文字；已开启系统认证时还必须通过系统认证'**
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
  /// **'截图安全提醒'**
  String get screenCaptureProtection;

  /// No description provided for @screenCaptureBlocked.
  ///
  /// In zh, this message translates to:
  /// **'检测到录屏或投屏'**
  String get screenCaptureBlocked;

  /// No description provided for @screenCaptureBlockedHint.
  ///
  /// In zh, this message translates to:
  /// **'录屏或投屏期间助记词已隐藏。停止捕获后会自动恢复。'**
  String get screenCaptureBlockedHint;

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

  /// No description provided for @deleteWalletConfirmationPhrase.
  ///
  /// In zh, this message translates to:
  /// **'删除钱包'**
  String get deleteWalletConfirmationPhrase;

  /// No description provided for @verifyToDeleteWallet.
  ///
  /// In zh, this message translates to:
  /// **'验证以永久删除此钱包'**
  String get verifyToDeleteWallet;

  /// No description provided for @deleteAuthenticationFailed.
  ///
  /// In zh, this message translates to:
  /// **'认证失败，钱包未删除。'**
  String get deleteAuthenticationFailed;

  /// No description provided for @deleteWalletFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法安全删除钱包，当前钱包未被移除，请重试。'**
  String get deleteWalletFailed;

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

  /// No description provided for @settingsSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法保存设置，当前内容未改变，请重试。'**
  String get settingsSaveFailed;

  /// No description provided for @pinKeyDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除最后一位'**
  String get pinKeyDelete;
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
