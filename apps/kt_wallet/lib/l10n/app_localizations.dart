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
  /// **'KT钱包'**
  String get appName;

  /// No description provided for @appTagline.
  ///
  /// In zh, this message translates to:
  /// **'双机离线钱包 · 联网观察端'**
  String get appTagline;

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

  /// No description provided for @actionDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get actionDelete;

  /// No description provided for @actionNext.
  ///
  /// In zh, this message translates to:
  /// **'下一步'**
  String get actionNext;

  /// No description provided for @actionImport.
  ///
  /// In zh, this message translates to:
  /// **'导入'**
  String get actionImport;

  /// No description provided for @manage.
  ///
  /// In zh, this message translates to:
  /// **'管理'**
  String get manage;

  /// No description provided for @viewAll.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get viewAll;

  /// No description provided for @max.
  ///
  /// In zh, this message translates to:
  /// **'最大'**
  String get max;

  /// No description provided for @tabHome.
  ///
  /// In zh, this message translates to:
  /// **'首页'**
  String get tabHome;

  /// No description provided for @tabAssets.
  ///
  /// In zh, this message translates to:
  /// **'资产'**
  String get tabAssets;

  /// No description provided for @tabRecords.
  ///
  /// In zh, this message translates to:
  /// **'记录'**
  String get tabRecords;

  /// No description provided for @tabSettings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get tabSettings;

  /// No description provided for @walletKindHot.
  ///
  /// In zh, this message translates to:
  /// **'普通'**
  String get walletKindHot;

  /// No description provided for @walletKindWatch.
  ///
  /// In zh, this message translates to:
  /// **'观察'**
  String get walletKindWatch;

  /// No description provided for @walletStateBackedUp.
  ///
  /// In zh, this message translates to:
  /// **'已备份'**
  String get walletStateBackedUp;

  /// No description provided for @walletStateNotBackedUp.
  ///
  /// In zh, this message translates to:
  /// **'未备份'**
  String get walletStateNotBackedUp;

  /// No description provided for @walletSeedDaily.
  ///
  /// In zh, this message translates to:
  /// **'日常钱包'**
  String get walletSeedDaily;

  /// No description provided for @walletSeedMain.
  ///
  /// In zh, this message translates to:
  /// **'主钱包'**
  String get walletSeedMain;

  /// No description provided for @walletDefaultName.
  ///
  /// In zh, this message translates to:
  /// **'钱包 {index}'**
  String walletDefaultName(int index);

  /// No description provided for @walletImportedName.
  ///
  /// In zh, this message translates to:
  /// **'导入钱包 {index}'**
  String walletImportedName(int index);

  /// No description provided for @backupBannerText.
  ///
  /// In zh, this message translates to:
  /// **'尚未备份助记词，存在丢失风险'**
  String get backupBannerText;

  /// No description provided for @backupNow.
  ///
  /// In zh, this message translates to:
  /// **'立即备份'**
  String get backupNow;

  /// No description provided for @balanceTitle.
  ///
  /// In zh, this message translates to:
  /// **'总资产估值 (USD)'**
  String get balanceTitle;

  /// No description provided for @balanceChangePeriod.
  ///
  /// In zh, this message translates to:
  /// **'过去24小时'**
  String get balanceChangePeriod;

  /// No description provided for @actionReceive.
  ///
  /// In zh, this message translates to:
  /// **'收款'**
  String get actionReceive;

  /// No description provided for @actionSend.
  ///
  /// In zh, this message translates to:
  /// **'转账'**
  String get actionSend;

  /// No description provided for @actionMore.
  ///
  /// In zh, this message translates to:
  /// **'更多'**
  String get actionMore;

  /// No description provided for @actionScanSign.
  ///
  /// In zh, this message translates to:
  /// **'扫签名'**
  String get actionScanSign;

  /// No description provided for @assetsSortByValue.
  ///
  /// In zh, this message translates to:
  /// **'按持仓价值排序'**
  String get assetsSortByValue;

  /// No description provided for @recordsTitle.
  ///
  /// In zh, this message translates to:
  /// **'交易记录'**
  String get recordsTitle;

  /// No description provided for @txSent.
  ///
  /// In zh, this message translates to:
  /// **'转出'**
  String get txSent;

  /// No description provided for @txReceived.
  ///
  /// In zh, this message translates to:
  /// **'收款'**
  String get txReceived;

  /// No description provided for @dateToday.
  ///
  /// In zh, this message translates to:
  /// **'今天'**
  String get dateToday;

  /// No description provided for @dateYesterday.
  ///
  /// In zh, this message translates to:
  /// **'昨天'**
  String get dateYesterday;

  /// No description provided for @monthDay.
  ///
  /// In zh, this message translates to:
  /// **'{month}月{day}日'**
  String monthDay(int month, int day);

  /// No description provided for @settingsWalletManage.
  ///
  /// In zh, this message translates to:
  /// **'钱包管理'**
  String get settingsWalletManage;

  /// No description provided for @settingsSecurity.
  ///
  /// In zh, this message translates to:
  /// **'安全设置'**
  String get settingsSecurity;

  /// No description provided for @settingsAddressBook.
  ///
  /// In zh, this message translates to:
  /// **'地址簿'**
  String get settingsAddressBook;

  /// No description provided for @settingsNetwork.
  ///
  /// In zh, this message translates to:
  /// **'网络'**
  String get settingsNetwork;

  /// No description provided for @settingsTokenManage.
  ///
  /// In zh, this message translates to:
  /// **'代币管理'**
  String get settingsTokenManage;

  /// No description provided for @addWalletTitle.
  ///
  /// In zh, this message translates to:
  /// **'添加钱包'**
  String get addWalletTitle;

  /// No description provided for @addWalletStandardSection.
  ///
  /// In zh, this message translates to:
  /// **'普通钱包 · 便捷'**
  String get addWalletStandardSection;

  /// No description provided for @createNewWallet.
  ///
  /// In zh, this message translates to:
  /// **'创建新钱包'**
  String get createNewWallet;

  /// No description provided for @createNewWalletDesc.
  ///
  /// In zh, this message translates to:
  /// **'在本机生成新的助记词，立即可用'**
  String get createNewWalletDesc;

  /// No description provided for @importMnemonic.
  ///
  /// In zh, this message translates to:
  /// **'导入助记词'**
  String get importMnemonic;

  /// No description provided for @importMnemonicDesc.
  ///
  /// In zh, this message translates to:
  /// **'已有 12 / 18 / 24 个单词的助记词'**
  String get importMnemonicDesc;

  /// No description provided for @coldWalletSection.
  ///
  /// In zh, this message translates to:
  /// **'离线钱包组合 · 高安全'**
  String get coldWalletSection;

  /// No description provided for @connectColdWallet.
  ///
  /// In zh, this message translates to:
  /// **'连接离线钱包'**
  String get connectColdWallet;

  /// No description provided for @connectColdWalletDesc.
  ///
  /// In zh, this message translates to:
  /// **'扫码配对 KT Wallet Cold Signer，私钥永不进入本机'**
  String get connectColdWalletDesc;

  /// No description provided for @createWalletTitle.
  ///
  /// In zh, this message translates to:
  /// **'创建普通钱包'**
  String get createWalletTitle;

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

  /// No description provided for @hotWalletNotice.
  ///
  /// In zh, this message translates to:
  /// **'这是一个热钱包：助记词保存在本机安全区。适合小额日常使用，大额资产建议使用离线钱包组合。'**
  String get hotWalletNotice;

  /// No description provided for @ruleFullControlTitle.
  ///
  /// In zh, this message translates to:
  /// **'助记词等于资产的完全控制权'**
  String get ruleFullControlTitle;

  /// No description provided for @ruleFullControlDesc.
  ///
  /// In zh, this message translates to:
  /// **'任何人拿到这 12 个单词，即可转走你的全部资产'**
  String get ruleFullControlDesc;

  /// No description provided for @ruleHandwriteTitle.
  ///
  /// In zh, this message translates to:
  /// **'只用纸笔手写备份'**
  String get ruleHandwriteTitle;

  /// No description provided for @ruleHandwriteDesc.
  ///
  /// In zh, this message translates to:
  /// **'不要保存到相册、云盘、备忘录或聊天软件'**
  String get ruleHandwriteDesc;

  /// No description provided for @backupMnemonicTitle.
  ///
  /// In zh, this message translates to:
  /// **'备份助记词'**
  String get backupMnemonicTitle;

  /// No description provided for @mnemonicShowConfirmBtn.
  ///
  /// In zh, this message translates to:
  /// **'我已手写备份，开始校验'**
  String get mnemonicShowConfirmBtn;

  /// No description provided for @mnemonicShowWarning.
  ///
  /// In zh, this message translates to:
  /// **'请按顺序手写抄录，请勿截图或拍照。任何人获得助记词即可控制资产。'**
  String get mnemonicShowWarning;

  /// No description provided for @mnemonicUnavailableTitle.
  ///
  /// In zh, this message translates to:
  /// **'无法显示助记词'**
  String get mnemonicUnavailableTitle;

  /// No description provided for @mnemonicUnavailableBackup.
  ///
  /// In zh, this message translates to:
  /// **'此备份流程仅适用于新创建的钱包。要备份当前钱包，请打开「钱包详情 → 查看助记词」。'**
  String get mnemonicUnavailableBackup;

  /// No description provided for @mnemonicAuthRequired.
  ///
  /// In zh, this message translates to:
  /// **'需要通过身份验证才能显示助记词，请重试。'**
  String get mnemonicAuthRequired;

  /// No description provided for @mnemonicNoKeyMaterial.
  ///
  /// In zh, this message translates to:
  /// **'本机未保存该钱包的助记词，无法显示。'**
  String get mnemonicNoKeyMaterial;

  /// No description provided for @verifyBackupTitle.
  ///
  /// In zh, this message translates to:
  /// **'校验备份'**
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

  /// No description provided for @walletCreatedBackedUp.
  ///
  /// In zh, this message translates to:
  /// **'钱包已创建并完成备份'**
  String get walletCreatedBackedUp;

  /// No description provided for @backupVerified.
  ///
  /// In zh, this message translates to:
  /// **'备份已验证，助记词记录正确'**
  String get backupVerified;

  /// No description provided for @mnemonicInvalid.
  ///
  /// In zh, this message translates to:
  /// **'助记词无效，请检查每个单词后重试'**
  String get mnemonicInvalid;

  /// No description provided for @mnemonicImported.
  ///
  /// In zh, this message translates to:
  /// **'助记词已导入'**
  String get mnemonicImported;

  /// No description provided for @wordsCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个单词'**
  String wordsCount(int count);

  /// No description provided for @pasteMnemonic.
  ///
  /// In zh, this message translates to:
  /// **'粘贴助记词（解析后自动清空剪贴板）'**
  String get pasteMnemonic;

  /// No description provided for @scanAccountQr.
  ///
  /// In zh, this message translates to:
  /// **'扫描账户二维码'**
  String get scanAccountQr;

  /// No description provided for @connectColdSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'从离线手机导入公开地址，创建观察钱包'**
  String get connectColdSubtitle;

  /// No description provided for @connectColdSafety.
  ///
  /// In zh, this message translates to:
  /// **'本机永远不会接收或保存助记词、私钥或 Seed。'**
  String get connectColdSafety;

  /// No description provided for @scanAccountHint.
  ///
  /// In zh, this message translates to:
  /// **'对准 KT Wallet Cold Signer 的地址二维码'**
  String get scanAccountHint;

  /// No description provided for @importConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'确认导入'**
  String get importConfirmTitle;

  /// No description provided for @createWatchWallet.
  ///
  /// In zh, this message translates to:
  /// **'创建观察钱包'**
  String get createWatchWallet;

  /// No description provided for @walletIdProtocol.
  ///
  /// In zh, this message translates to:
  /// **'Wallet ID: {id} · 协议 v{version}'**
  String walletIdProtocol(String id, int version);

  /// No description provided for @walletsTitle.
  ///
  /// In zh, this message translates to:
  /// **'钱包'**
  String get walletsTitle;

  /// No description provided for @deleteWalletTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除钱包'**
  String get deleteWalletTitle;

  /// No description provided for @deleteWalletConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定删除「{name}」？此操作仅移除本机记录，不影响链上资产。'**
  String deleteWalletConfirm(String name);

  /// No description provided for @deletedWallet.
  ///
  /// In zh, this message translates to:
  /// **'已删除「{name}」'**
  String deletedWallet(String name);

  /// No description provided for @sortAction.
  ///
  /// In zh, this message translates to:
  /// **'排序'**
  String get sortAction;

  /// No description provided for @walletCountLimit.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 个钱包 · 上限 {max} 个'**
  String walletCountLimit(int count, int max);

  /// No description provided for @walletDetailTitle.
  ///
  /// In zh, this message translates to:
  /// **'钱包详情'**
  String get walletDetailTitle;

  /// No description provided for @walletTypeLabel.
  ///
  /// In zh, this message translates to:
  /// **'钱包类型'**
  String get walletTypeLabel;

  /// No description provided for @standardWallet.
  ///
  /// In zh, this message translates to:
  /// **'普通钱包'**
  String get standardWallet;

  /// No description provided for @backupNotYet.
  ///
  /// In zh, this message translates to:
  /// **'尚未备份助记词'**
  String get backupNotYet;

  /// No description provided for @viewMnemonic.
  ///
  /// In zh, this message translates to:
  /// **'查看助记词'**
  String get viewMnemonic;

  /// No description provided for @viewMnemonicDesc.
  ///
  /// In zh, this message translates to:
  /// **'需要生物识别或密码验证'**
  String get viewMnemonicDesc;

  /// No description provided for @deleteWalletDesc.
  ///
  /// In zh, this message translates to:
  /// **'需身份验证，删除前将再次确认备份状态'**
  String get deleteWalletDesc;

  /// No description provided for @amountMustBePositive.
  ///
  /// In zh, this message translates to:
  /// **'金额需大于 0'**
  String get amountMustBePositive;

  /// No description provided for @insufficientBalance.
  ///
  /// In zh, this message translates to:
  /// **'余额不足'**
  String get insufficientBalance;

  /// No description provided for @amountFormatInvalid.
  ///
  /// In zh, this message translates to:
  /// **'金额格式不正确'**
  String get amountFormatInvalid;

  /// No description provided for @recipientAddress.
  ///
  /// In zh, this message translates to:
  /// **'收款地址'**
  String get recipientAddress;

  /// No description provided for @pasteOrEnterAddress.
  ///
  /// In zh, this message translates to:
  /// **'粘贴或输入地址'**
  String get pasteOrEnterAddress;

  /// No description provided for @enterChainAddress.
  ///
  /// In zh, this message translates to:
  /// **'请输入 {network} 网络收款地址'**
  String enterChainAddress(String network);

  /// No description provided for @addressValidOn.
  ///
  /// In zh, this message translates to:
  /// **'地址格式正确 · {network} 网络'**
  String addressValidOn(String network);

  /// No description provided for @addressInvalid.
  ///
  /// In zh, this message translates to:
  /// **'地址无效'**
  String get addressInvalid;

  /// No description provided for @amountLabel.
  ///
  /// In zh, this message translates to:
  /// **'金额'**
  String get amountLabel;

  /// No description provided for @availableBalance.
  ///
  /// In zh, this message translates to:
  /// **'可用 {amount} {symbol}'**
  String availableBalance(String amount, String symbol);

  /// No description provided for @selectAsset.
  ///
  /// In zh, this message translates to:
  /// **'选择资产'**
  String get selectAsset;

  /// No description provided for @scanAddressTitle.
  ///
  /// In zh, this message translates to:
  /// **'扫描地址二维码'**
  String get scanAddressTitle;

  /// No description provided for @scanAddressHint.
  ///
  /// In zh, this message translates to:
  /// **'对准收款地址二维码'**
  String get scanAddressHint;

  /// No description provided for @networkFee.
  ///
  /// In zh, this message translates to:
  /// **'网络手续费'**
  String get networkFee;

  /// No description provided for @feeCustom.
  ///
  /// In zh, this message translates to:
  /// **'自定义'**
  String get feeCustom;

  /// No description provided for @feeSlow.
  ///
  /// In zh, this message translates to:
  /// **'慢'**
  String get feeSlow;

  /// No description provided for @feeStandard.
  ///
  /// In zh, this message translates to:
  /// **'标准'**
  String get feeStandard;

  /// No description provided for @feeFast.
  ///
  /// In zh, this message translates to:
  /// **'快'**
  String get feeFast;

  /// No description provided for @confirmFee.
  ///
  /// In zh, this message translates to:
  /// **'确认手续费'**
  String get confirmFee;

  /// No description provided for @feeExplainer.
  ///
  /// In zh, this message translates to:
  /// **'手续费越高，交易确认越快。费用支付给网络，不进入本 App。'**
  String get feeExplainer;

  /// No description provided for @feeEtaSlow.
  ///
  /// In zh, this message translates to:
  /// **'≈ 3-5 分钟'**
  String get feeEtaSlow;

  /// No description provided for @feeEtaStandard.
  ///
  /// In zh, this message translates to:
  /// **'≈ 1 分钟'**
  String get feeEtaStandard;

  /// No description provided for @feeEtaFast.
  ///
  /// In zh, this message translates to:
  /// **'≈ 15 秒'**
  String get feeEtaFast;

  /// No description provided for @feeLowWarning.
  ///
  /// In zh, this message translates to:
  /// **'手续费过低可能导致交易长时间未确认甚至失败。TRON Energy 不足时将燃烧 TRX 抵扣。'**
  String get feeLowWarning;

  /// No description provided for @confirmTransactionTitle.
  ///
  /// In zh, this message translates to:
  /// **'确认交易'**
  String get confirmTransactionTitle;

  /// No description provided for @confirmTransfer.
  ///
  /// In zh, this message translates to:
  /// **'确认转账'**
  String get confirmTransfer;

  /// No description provided for @generateSignQr.
  ///
  /// In zh, this message translates to:
  /// **'生成待签名二维码'**
  String get generateSignQr;

  /// No description provided for @hotConfirmHint.
  ///
  /// In zh, this message translates to:
  /// **'验证身份后本机签名并自动广播'**
  String get hotConfirmHint;

  /// No description provided for @watchConfirmHint.
  ///
  /// In zh, this message translates to:
  /// **'二维码中不包含助记词或私钥'**
  String get watchConfirmHint;

  /// No description provided for @fromAddress.
  ///
  /// In zh, this message translates to:
  /// **'转出地址'**
  String get fromAddress;

  /// No description provided for @totalSpend.
  ///
  /// In zh, this message translates to:
  /// **'总支出'**
  String get totalSpend;

  /// No description provided for @unbackedTransferWarning.
  ///
  /// In zh, this message translates to:
  /// **'该钱包尚未备份助记词。建议先完成备份，再进行转账。'**
  String get unbackedTransferWarning;

  /// No description provided for @pendingSignTitle.
  ///
  /// In zh, this message translates to:
  /// **'待签名交易'**
  String get pendingSignTitle;

  /// No description provided for @dynamicShard.
  ///
  /// In zh, this message translates to:
  /// **'动态分片 {received} / {total}'**
  String dynamicShard(int received, int total);

  /// No description provided for @networkRow.
  ///
  /// In zh, this message translates to:
  /// **'网络'**
  String get networkRow;

  /// No description provided for @requestId.
  ///
  /// In zh, this message translates to:
  /// **'请求 ID'**
  String get requestId;

  /// No description provided for @scanWithOfflinePhone.
  ///
  /// In zh, this message translates to:
  /// **'请使用离线签名手机扫描此二维码'**
  String get scanWithOfflinePhone;

  /// No description provided for @scanSignResultTitle.
  ///
  /// In zh, this message translates to:
  /// **'扫描签名结果'**
  String get scanSignResultTitle;

  /// No description provided for @recognizedShard.
  ///
  /// In zh, this message translates to:
  /// **'已识别分片 {received} / {total}'**
  String recognizedShard(int received, int total);

  /// No description provided for @broadcastTitle.
  ///
  /// In zh, this message translates to:
  /// **'广播交易'**
  String get broadcastTitle;

  /// No description provided for @dontBroadcastYet.
  ///
  /// In zh, this message translates to:
  /// **'暂不广播'**
  String get dontBroadcastYet;

  /// No description provided for @chainParamsFallback.
  ///
  /// In zh, this message translates to:
  /// **'无法获取链上参数，已使用预设 nonce 与手续费'**
  String get chainParamsFallback;

  /// No description provided for @broadcastFailedMessage.
  ///
  /// In zh, this message translates to:
  /// **'广播失败：{message}'**
  String broadcastFailedMessage(String message);

  /// No description provided for @signatureVerified.
  ///
  /// In zh, this message translates to:
  /// **'签名已验证 · 签名者与钱包地址一致，交易内容未被篡改'**
  String get signatureVerified;

  /// No description provided for @signerAddress.
  ///
  /// In zh, this message translates to:
  /// **'签名地址'**
  String get signerAddress;

  /// No description provided for @txHashPreview.
  ///
  /// In zh, this message translates to:
  /// **'交易 Hash 预览'**
  String get txHashPreview;

  /// No description provided for @backToHome.
  ///
  /// In zh, this message translates to:
  /// **'返回首页'**
  String get backToHome;

  /// No description provided for @txSubmitted.
  ///
  /// In zh, this message translates to:
  /// **'交易已提交'**
  String get txSubmitted;

  /// No description provided for @txTimeLabel.
  ///
  /// In zh, this message translates to:
  /// **'时间'**
  String get txTimeLabel;

  /// No description provided for @txHash.
  ///
  /// In zh, this message translates to:
  /// **'交易 Hash'**
  String get txHash;

  /// No description provided for @statusLabel.
  ///
  /// In zh, this message translates to:
  /// **'状态'**
  String get statusLabel;

  /// No description provided for @txStatusSubmitted.
  ///
  /// In zh, this message translates to:
  /// **'已提交'**
  String get txStatusSubmitted;

  /// No description provided for @txStatusPending.
  ///
  /// In zh, this message translates to:
  /// **'确认中'**
  String get txStatusPending;

  /// No description provided for @txStatusConfirmed.
  ///
  /// In zh, this message translates to:
  /// **'已确认'**
  String get txStatusConfirmed;

  /// No description provided for @txStatusFailed.
  ///
  /// In zh, this message translates to:
  /// **'失败'**
  String get txStatusFailed;

  /// No description provided for @txStatusDropped.
  ///
  /// In zh, this message translates to:
  /// **'已丢弃'**
  String get txStatusDropped;

  /// No description provided for @txStatusReplaced.
  ///
  /// In zh, this message translates to:
  /// **'已替换'**
  String get txStatusReplaced;

  /// No description provided for @nonceConflict.
  ///
  /// In zh, this message translates to:
  /// **'该 nonce 已被另一笔待处理交易占用，请刷新后重试'**
  String get nonceConflict;

  /// No description provided for @txSpeedUp.
  ///
  /// In zh, this message translates to:
  /// **'加速交易'**
  String get txSpeedUp;

  /// No description provided for @txCancelTransaction.
  ///
  /// In zh, this message translates to:
  /// **'取消交易'**
  String get txCancelTransaction;

  /// No description provided for @txReplacementConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'确认替换交易'**
  String get txReplacementConfirmTitle;

  /// No description provided for @txSpeedUpConfirm.
  ///
  /// In zh, this message translates to:
  /// **'将使用相同 nonce 和更高网络费重新发送。原收款地址与金额不会改变。'**
  String get txSpeedUpConfirm;

  /// No description provided for @txCancelConfirm.
  ///
  /// In zh, this message translates to:
  /// **'将使用相同 nonce 向自己发送 0 金额交易。仅当替换交易先被确认时，原交易才会取消。'**
  String get txCancelConfirm;

  /// No description provided for @txReplacementSubmitted.
  ///
  /// In zh, this message translates to:
  /// **'替换交易已提交'**
  String get txReplacementSubmitted;

  /// No description provided for @txReplacementRace.
  ///
  /// In zh, this message translates to:
  /// **'替换交易已提交，但原交易状态同时发生变化，请等待链上最终结果'**
  String get txReplacementRace;

  /// No description provided for @txNonceAlreadyUsed.
  ///
  /// In zh, this message translates to:
  /// **'该 nonce 已被链上交易使用，无法继续替换'**
  String get txNonceAlreadyUsed;

  /// No description provided for @txReplacementUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'这笔交易缺少替换所需的链上参数，无法加速或取消'**
  String get txReplacementUnavailable;

  /// No description provided for @txReplacementWrongNetwork.
  ///
  /// In zh, this message translates to:
  /// **'这笔交易属于 {network}，请先切换回该网络再加速或取消'**
  String txReplacementWrongNetwork(String network);

  /// No description provided for @feeEstimating.
  ///
  /// In zh, this message translates to:
  /// **'估算中…'**
  String get feeEstimating;

  /// No description provided for @feeUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'无法获取网络费'**
  String get feeUnavailable;

  /// No description provided for @feeUnavailableHint.
  ///
  /// In zh, this message translates to:
  /// **'无法估算网络费，暂时无法发送'**
  String get feeUnavailableHint;

  /// No description provided for @txNonceLabel.
  ///
  /// In zh, this message translates to:
  /// **'Nonce'**
  String get txNonceLabel;

  /// No description provided for @txMaxFeeLabel.
  ///
  /// In zh, this message translates to:
  /// **'最高网络费（原始单位）'**
  String get txMaxFeeLabel;

  /// No description provided for @txRawAmountLabel.
  ///
  /// In zh, this message translates to:
  /// **'金额（原始单位）'**
  String get txRawAmountLabel;

  /// No description provided for @txReplacesLabel.
  ///
  /// In zh, this message translates to:
  /// **'替换交易'**
  String get txReplacesLabel;

  /// No description provided for @txReplacedByLabel.
  ///
  /// In zh, this message translates to:
  /// **'已由交易替换'**
  String get txReplacedByLabel;

  /// No description provided for @txNotFound.
  ///
  /// In zh, this message translates to:
  /// **'未找到本地交易记录'**
  String get txNotFound;

  /// No description provided for @confirming.
  ///
  /// In zh, this message translates to:
  /// **'确认中 ({received}/{total})'**
  String confirming(int received, int total);

  /// No description provided for @txDetailTitle.
  ///
  /// In zh, this message translates to:
  /// **'交易详情'**
  String get txDetailTitle;

  /// No description provided for @confirmedPrefix.
  ///
  /// In zh, this message translates to:
  /// **'已确认'**
  String get confirmedPrefix;

  /// No description provided for @confirmations.
  ///
  /// In zh, this message translates to:
  /// **'确认数'**
  String get confirmations;

  /// No description provided for @authToConfirmTransfer.
  ///
  /// In zh, this message translates to:
  /// **'验证以确认转账'**
  String get authToConfirmTransfer;

  /// No description provided for @authEveryTransfer.
  ///
  /// In zh, this message translates to:
  /// **'每次转账都需要生物识别或密码验证'**
  String get authEveryTransfer;

  /// No description provided for @useFaceId.
  ///
  /// In zh, this message translates to:
  /// **'使用生物识别验证'**
  String get useFaceId;

  /// No description provided for @usePasscode.
  ///
  /// In zh, this message translates to:
  /// **'改用密码'**
  String get usePasscode;

  /// No description provided for @biometricFailedRetry.
  ///
  /// In zh, this message translates to:
  /// **'验证失败，请重试'**
  String get biometricFailedRetry;

  /// No description provided for @searchAssetHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索名称 / Symbol / 合约地址'**
  String get searchAssetHint;

  /// No description provided for @price.
  ///
  /// In zh, this message translates to:
  /// **'价格'**
  String get price;

  /// No description provided for @change24h.
  ///
  /// In zh, this message translates to:
  /// **'24h 涨跌'**
  String get change24h;

  /// No description provided for @contractAddress.
  ///
  /// In zh, this message translates to:
  /// **'合约地址'**
  String get contractAddress;

  /// No description provided for @unverifiedToken.
  ///
  /// In zh, this message translates to:
  /// **'未经验证的代币，请核对合约地址'**
  String get unverifiedToken;

  /// No description provided for @receiveWarning.
  ///
  /// In zh, this message translates to:
  /// **'仅支持接收 TRON 网络（TRC-20）资产。从其他网络转入将导致资产丢失。'**
  String get receiveWarning;

  /// No description provided for @explorerLinkCopied.
  ///
  /// In zh, this message translates to:
  /// **'区块浏览器链接已复制'**
  String get explorerLinkCopied;

  /// No description provided for @addressCopied.
  ///
  /// In zh, this message translates to:
  /// **'地址已复制'**
  String get addressCopied;

  /// No description provided for @saveReceiveImage.
  ///
  /// In zh, this message translates to:
  /// **'保存收款图片'**
  String get saveReceiveImage;

  /// No description provided for @privacyOverlayActive.
  ///
  /// In zh, this message translates to:
  /// **'KT 钱包保护已启动'**
  String get privacyOverlayActive;

  /// No description provided for @privacyOverlayHidden.
  ///
  /// In zh, this message translates to:
  /// **'您的钱包内容已隐藏'**
  String get privacyOverlayHidden;

  /// No description provided for @chooseNetwork.
  ///
  /// In zh, this message translates to:
  /// **'选择网络'**
  String get chooseNetwork;

  /// No description provided for @assetOnChains.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条链'**
  String assetOnChains(int count);

  /// No description provided for @receiveCardTitle.
  ///
  /// In zh, this message translates to:
  /// **'收款地址'**
  String get receiveCardTitle;

  /// No description provided for @receiveCardNetwork.
  ///
  /// In zh, this message translates to:
  /// **'网络'**
  String get receiveCardNetwork;

  /// No description provided for @receiveCardGenerated.
  ///
  /// In zh, this message translates to:
  /// **'生成时间'**
  String get receiveCardGenerated;

  /// No description provided for @receiveImageSaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存到相册'**
  String get receiveImageSaved;

  /// No description provided for @receiveImageDenied.
  ///
  /// In zh, this message translates to:
  /// **'未获得相册权限,无法保存'**
  String get receiveImageDenied;

  /// No description provided for @receiveImageUseShare.
  ///
  /// In zh, this message translates to:
  /// **'此系统版本无法直接保存,请使用右上角分享'**
  String get receiveImageUseShare;

  /// No description provided for @receiveImageFailed.
  ///
  /// In zh, this message translates to:
  /// **'生成收款图片失败'**
  String get receiveImageFailed;

  /// No description provided for @actionCopy.
  ///
  /// In zh, this message translates to:
  /// **'复制地址'**
  String get actionCopy;

  /// No description provided for @addressBookTitle.
  ///
  /// In zh, this message translates to:
  /// **'地址管理'**
  String get addressBookTitle;

  /// No description provided for @searchNameOrAddress.
  ///
  /// In zh, this message translates to:
  /// **'搜索名称或地址'**
  String get searchNameOrAddress;

  /// No description provided for @assetUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'该资产已不可用'**
  String get assetUnavailable;

  /// No description provided for @noMatchingContacts.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的联系人'**
  String get noMatchingContacts;

  /// No description provided for @contactsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有联系人,点右上角 + 添加'**
  String get contactsEmpty;

  /// No description provided for @tokensEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有自定义代币,点右上角 + 添加'**
  String get tokensEmpty;

  /// No description provided for @contactBobExchange.
  ///
  /// In zh, this message translates to:
  /// **'Bob 交易所'**
  String get contactBobExchange;

  /// No description provided for @contactColdBackup.
  ///
  /// In zh, this message translates to:
  /// **'冷钱包备份'**
  String get contactColdBackup;

  /// No description provided for @editContactTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑联系人'**
  String get editContactTitle;

  /// No description provided for @actionEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get actionEdit;

  /// No description provided for @addContactTitle.
  ///
  /// In zh, this message translates to:
  /// **'添加联系人'**
  String get addContactTitle;

  /// No description provided for @nameLabel.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get nameLabel;

  /// No description provided for @addressLabel.
  ///
  /// In zh, this message translates to:
  /// **'地址'**
  String get addressLabel;

  /// No description provided for @invalidChainAddress.
  ///
  /// In zh, this message translates to:
  /// **'不是有效的链地址'**
  String get invalidChainAddress;

  /// No description provided for @actionSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get actionSave;

  /// No description provided for @tokenManageTitle.
  ///
  /// In zh, this message translates to:
  /// **'Token 管理'**
  String get tokenManageTitle;

  /// No description provided for @addTokenTitle.
  ///
  /// In zh, this message translates to:
  /// **'添加代币'**
  String get addTokenTitle;

  /// No description provided for @tokenSymbolLabel.
  ///
  /// In zh, this message translates to:
  /// **'代币符号'**
  String get tokenSymbolLabel;

  /// No description provided for @networkSettingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'网络设置'**
  String get networkSettingsTitle;

  /// No description provided for @screenCaptureBlocked.
  ///
  /// In zh, this message translates to:
  /// **'检测到录屏或投屏'**
  String get screenCaptureBlocked;

  /// No description provided for @screenCaptureBlockedHint.
  ///
  /// In zh, this message translates to:
  /// **'为保护助记词,内容已隐藏。停止录屏或断开投屏后会自动恢复。'**
  String get screenCaptureBlockedHint;

  /// No description provided for @screenshotWarning.
  ///
  /// In zh, this message translates to:
  /// **'你刚刚截图了助记词。它已存入相册,任何能看到相册的人都能取走你的资产 —— 请立刻把资产转移到新钱包。'**
  String get screenshotWarning;

  /// No description provided for @rpcMeasuring.
  ///
  /// In zh, this message translates to:
  /// **'测量中…'**
  String get rpcMeasuring;

  /// No description provided for @rpcUnreachable.
  ///
  /// In zh, this message translates to:
  /// **'无法连接'**
  String get rpcUnreachable;

  /// No description provided for @rpcNotMeasured.
  ///
  /// In zh, this message translates to:
  /// **'—'**
  String get rpcNotMeasured;

  /// No description provided for @rpcTimeout.
  ///
  /// In zh, this message translates to:
  /// **'超时'**
  String get rpcTimeout;

  /// No description provided for @rpcNode.
  ///
  /// In zh, this message translates to:
  /// **'RPC 节点'**
  String get rpcNode;

  /// No description provided for @networkResetDefault.
  ///
  /// In zh, this message translates to:
  /// **'恢复默认'**
  String get networkResetDefault;

  /// No description provided for @gatewayTitle.
  ///
  /// In zh, this message translates to:
  /// **'网关'**
  String get gatewayTitle;

  /// No description provided for @gatewayDesc.
  ///
  /// In zh, this message translates to:
  /// **'统一查询网关，留空则直连各链节点'**
  String get gatewayDesc;

  /// No description provided for @gatewayNotSet.
  ///
  /// In zh, this message translates to:
  /// **'未设置'**
  String get gatewayNotSet;

  /// No description provided for @gatewayTest.
  ///
  /// In zh, this message translates to:
  /// **'测试连接'**
  String get gatewayTest;

  /// No description provided for @gatewayTestOk.
  ///
  /// In zh, this message translates to:
  /// **'网关连接成功'**
  String get gatewayTestOk;

  /// No description provided for @gatewayTestFail.
  ///
  /// In zh, this message translates to:
  /// **'网关连接失败'**
  String get gatewayTestFail;

  /// No description provided for @accessControl.
  ///
  /// In zh, this message translates to:
  /// **'访问控制'**
  String get accessControl;

  /// No description provided for @appLock.
  ///
  /// In zh, this message translates to:
  /// **'App 锁'**
  String get appLock;

  /// No description provided for @appLockDesc.
  ///
  /// In zh, this message translates to:
  /// **'打开 App 时进行安全验证'**
  String get appLockDesc;

  /// No description provided for @authMethod.
  ///
  /// In zh, this message translates to:
  /// **'验证方式'**
  String get authMethod;

  /// No description provided for @authMethodDesc.
  ///
  /// In zh, this message translates to:
  /// **'用于解锁 App 和确认转账'**
  String get authMethodDesc;

  /// No description provided for @authBiometrics.
  ///
  /// In zh, this message translates to:
  /// **'人脸 / 生物识别'**
  String get authBiometrics;

  /// No description provided for @authBiometricsDesc.
  ///
  /// In zh, this message translates to:
  /// **'使用本机生物识别快速确认'**
  String get authBiometricsDesc;

  /// No description provided for @authPassword.
  ///
  /// In zh, this message translates to:
  /// **'钱包密码'**
  String get authPassword;

  /// No description provided for @authPasswordDesc.
  ///
  /// In zh, this message translates to:
  /// **'使用 6 位钱包密码验证'**
  String get authPasswordDesc;

  /// No description provided for @autoLock.
  ///
  /// In zh, this message translates to:
  /// **'自动锁定'**
  String get autoLock;

  /// No description provided for @autoLockDesc.
  ///
  /// In zh, this message translates to:
  /// **'后台超过时限后重新锁定'**
  String get autoLockDesc;

  /// No description provided for @autoLockValue.
  ///
  /// In zh, this message translates to:
  /// **'1 分钟'**
  String get autoLockValue;

  /// No description provided for @privacyMode.
  ///
  /// In zh, this message translates to:
  /// **'隐私模式'**
  String get privacyMode;

  /// No description provided for @privacyModeDesc.
  ///
  /// In zh, this message translates to:
  /// **'首页默认隐藏余额'**
  String get privacyModeDesc;

  /// No description provided for @dataSection.
  ///
  /// In zh, this message translates to:
  /// **'数据'**
  String get dataSection;

  /// No description provided for @fiatUnit.
  ///
  /// In zh, this message translates to:
  /// **'法币单位'**
  String get fiatUnit;

  /// No description provided for @displayLanguage.
  ///
  /// In zh, this message translates to:
  /// **'显示语言'**
  String get displayLanguage;

  /// No description provided for @deleteWatchWallet.
  ///
  /// In zh, this message translates to:
  /// **'删除观察钱包'**
  String get deleteWatchWallet;

  /// No description provided for @deleteWatchWalletDesc.
  ///
  /// In zh, this message translates to:
  /// **'仅移除公开地址与本地记录，不影响资产'**
  String get deleteWatchWalletDesc;

  /// No description provided for @languageSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get languageSystem;

  /// No description provided for @modeSelectTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择设备模式'**
  String get modeSelectTitle;

  /// No description provided for @modeSelectSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'首次使用前，请先确定这台手机的角色'**
  String get modeSelectSubtitle;

  /// No description provided for @modeWalletTitle.
  ///
  /// In zh, this message translates to:
  /// **'联网钱包'**
  String get modeWalletTitle;

  /// No description provided for @modeWalletDesc.
  ///
  /// In zh, this message translates to:
  /// **'日常使用、查看余额、发起转账'**
  String get modeWalletDesc;

  /// No description provided for @modeSignerTitle.
  ///
  /// In zh, this message translates to:
  /// **'离线签名器'**
  String get modeSignerTitle;

  /// No description provided for @modeSignerDesc.
  ///
  /// In zh, this message translates to:
  /// **'安装在永不联网的手机上，离线保管私钥并签名'**
  String get modeSignerDesc;

  /// No description provided for @modeSignerConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'启用离线签名器'**
  String get modeSignerConfirmTitle;

  /// No description provided for @modeSignerConfirmBody.
  ///
  /// In zh, this message translates to:
  /// **'此模式供离线设备使用，请开启飞行模式并保持设备永不联网。'**
  String get modeSignerConfirmBody;

  /// No description provided for @deviceMode.
  ///
  /// In zh, this message translates to:
  /// **'设备模式'**
  String get deviceMode;

  /// No description provided for @deviceModeSwitchTitle.
  ///
  /// In zh, this message translates to:
  /// **'切换设备模式'**
  String get deviceModeSwitchTitle;

  /// No description provided for @deviceModeSwitchDesc.
  ///
  /// In zh, this message translates to:
  /// **'切换后将返回模式选择页。'**
  String get deviceModeSwitchDesc;

  /// No description provided for @walletLoadErrorTitle.
  ///
  /// In zh, this message translates to:
  /// **'钱包加载失败'**
  String get walletLoadErrorTitle;

  /// No description provided for @walletLoadErrorDesc.
  ///
  /// In zh, this message translates to:
  /// **'无法读取本机的钱包数据。请重试;若问题持续,请重新安装应用。'**
  String get walletLoadErrorDesc;

  /// No description provided for @cryptoUnavailableTitle.
  ///
  /// In zh, this message translates to:
  /// **'钱包引擎不可用'**
  String get cryptoUnavailableTitle;

  /// No description provided for @cryptoUnavailableDesc.
  ///
  /// In zh, this message translates to:
  /// **'此 Android 构建未包含 Trust Wallet Core。请安装启用了 Wallet Core 的构建；应用不会自动改用模拟密钥。'**
  String get cryptoUnavailableDesc;

  /// No description provided for @actionRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get actionRetry;

  /// No description provided for @renameWallet.
  ///
  /// In zh, this message translates to:
  /// **'重命名钱包'**
  String get renameWallet;

  /// No description provided for @backupTranscribed.
  ///
  /// In zh, this message translates to:
  /// **'我已抄写'**
  String get backupTranscribed;

  /// No description provided for @receiveWarningFor.
  ///
  /// In zh, this message translates to:
  /// **'仅支持接收 {network} 网络资产。从其他网络转入将导致资产丢失。'**
  String receiveWarningFor(String network);

  /// No description provided for @autoLockImmediate.
  ///
  /// In zh, this message translates to:
  /// **'立即'**
  String get autoLockImmediate;

  /// No description provided for @autoLockMinutesLabel.
  ///
  /// In zh, this message translates to:
  /// **'{minutes} 分钟'**
  String autoLockMinutesLabel(int minutes);

  /// No description provided for @copyAddress.
  ///
  /// In zh, this message translates to:
  /// **'复制地址'**
  String get copyAddress;

  /// No description provided for @noMatchingAssets.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的资产'**
  String get noMatchingAssets;

  /// No description provided for @noWatchWallet.
  ///
  /// In zh, this message translates to:
  /// **'当前没有观察钱包'**
  String get noWatchWallet;

  /// No description provided for @watchWalletCreated.
  ///
  /// In zh, this message translates to:
  /// **'观察钱包已创建'**
  String get watchWalletCreated;

  /// No description provided for @marketOfflineDemo.
  ///
  /// In zh, this message translates to:
  /// **'网络不可用，实时数据加载失败'**
  String get marketOfflineDemo;

  /// No description provided for @actionDone.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get actionDone;

  /// No description provided for @historyUnsupportedChain.
  ///
  /// In zh, this message translates to:
  /// **'该链暂不支持历史查询'**
  String get historyUnsupportedChain;

  /// No description provided for @historyEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无交易记录'**
  String get historyEmpty;

  /// No description provided for @setPinTitle.
  ///
  /// In zh, this message translates to:
  /// **'设置解锁密码'**
  String get setPinTitle;

  /// No description provided for @setPinPrompt.
  ///
  /// In zh, this message translates to:
  /// **'设置 6 位密码'**
  String get setPinPrompt;

  /// No description provided for @setPinConfirmPrompt.
  ///
  /// In zh, this message translates to:
  /// **'再次输入以确认'**
  String get setPinConfirmPrompt;

  /// No description provided for @setPinDesc.
  ///
  /// In zh, this message translates to:
  /// **'生物识别不可用时用密码解锁 App。密码仅保存在本机安全区域。'**
  String get setPinDesc;

  /// No description provided for @pinMismatch.
  ///
  /// In zh, this message translates to:
  /// **'两次输入不一致，请重新设置'**
  String get pinMismatch;

  /// No description provided for @enterPinToUnlock.
  ///
  /// In zh, this message translates to:
  /// **'输入密码解锁'**
  String get enterPinToUnlock;

  /// No description provided for @enterPinToDisable.
  ///
  /// In zh, this message translates to:
  /// **'输入密码以关闭 App 锁'**
  String get enterPinToDisable;

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

  /// No description provided for @usePinUnlock.
  ///
  /// In zh, this message translates to:
  /// **'使用密码解锁'**
  String get usePinUnlock;

  /// No description provided for @networkEnvironment.
  ///
  /// In zh, this message translates to:
  /// **'网络环境'**
  String get networkEnvironment;

  /// No description provided for @envMainnet.
  ///
  /// In zh, this message translates to:
  /// **'主网'**
  String get envMainnet;

  /// No description provided for @envTestnet.
  ///
  /// In zh, this message translates to:
  /// **'测试网'**
  String get envTestnet;

  /// No description provided for @testnetBadge.
  ///
  /// In zh, this message translates to:
  /// **'测试网'**
  String get testnetBadge;

  /// No description provided for @perChainNetwork.
  ///
  /// In zh, this message translates to:
  /// **'逐链网络'**
  String get perChainNetwork;

  /// No description provided for @addNetwork.
  ///
  /// In zh, this message translates to:
  /// **'添加网络'**
  String get addNetwork;

  /// No description provided for @networkNameLabel.
  ///
  /// In zh, this message translates to:
  /// **'网络名称'**
  String get networkNameLabel;

  /// No description provided for @chainFamilyLabel.
  ///
  /// In zh, this message translates to:
  /// **'协议族'**
  String get chainFamilyLabel;

  /// No description provided for @chainIdLabel.
  ///
  /// In zh, this message translates to:
  /// **'Chain ID'**
  String get chainIdLabel;

  /// No description provided for @explorerLabel.
  ///
  /// In zh, this message translates to:
  /// **'区块浏览器 URL(可选)'**
  String get explorerLabel;

  /// No description provided for @symbolLabel.
  ///
  /// In zh, this message translates to:
  /// **'币种符号'**
  String get symbolLabel;

  /// No description provided for @probeChecking.
  ///
  /// In zh, this message translates to:
  /// **'正在探测 RPC…'**
  String get probeChecking;

  /// No description provided for @probeOkSave.
  ///
  /// In zh, this message translates to:
  /// **'探测通过,已保存'**
  String get probeOkSave;

  /// No description provided for @rpcProbeFailed.
  ///
  /// In zh, this message translates to:
  /// **'RPC 探测失败,请检查地址'**
  String get rpcProbeFailed;

  /// No description provided for @chainIdMismatch.
  ///
  /// In zh, this message translates to:
  /// **'Chain ID 不匹配:节点返回 {actual}'**
  String chainIdMismatch(Object actual);

  /// No description provided for @deleteNetwork.
  ///
  /// In zh, this message translates to:
  /// **'删除网络'**
  String get deleteNetwork;

  /// No description provided for @networkInUse.
  ///
  /// In zh, this message translates to:
  /// **'该网络正在使用中'**
  String get networkInUse;

  /// No description provided for @faucetAction.
  ///
  /// In zh, this message translates to:
  /// **'领取测试币'**
  String get faucetAction;

  /// No description provided for @faucetOpened.
  ///
  /// In zh, this message translates to:
  /// **'已打开测试币水龙头'**
  String get faucetOpened;

  /// No description provided for @externalActionFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法打开外部应用，请稍后重试'**
  String get externalActionFailed;

  /// No description provided for @shareAddressSubject.
  ///
  /// In zh, this message translates to:
  /// **'{network} 收款地址'**
  String shareAddressSubject(String network);

  /// No description provided for @cameraUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'相机不可用，请检查权限后重试'**
  String get cameraUnavailable;

  /// No description provided for @biometricUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'生物识别不可用，请使用钱包 PIN'**
  String get biometricUnavailable;

  /// No description provided for @airdropRequesting.
  ///
  /// In zh, this message translates to:
  /// **'正在请求空投…'**
  String get airdropRequesting;

  /// No description provided for @airdropOk.
  ///
  /// In zh, this message translates to:
  /// **'空投成功,余额稍后刷新'**
  String get airdropOk;

  /// No description provided for @airdropFailed.
  ///
  /// In zh, this message translates to:
  /// **'空投失败:{message}'**
  String airdropFailed(Object message);

  /// No description provided for @fiatHiddenTestnet.
  ///
  /// In zh, this message translates to:
  /// **'测试网资产无市场价格'**
  String get fiatHiddenTestnet;

  /// No description provided for @backupEncryptedTitle.
  ///
  /// In zh, this message translates to:
  /// **'加密备份'**
  String get backupEncryptedTitle;

  /// No description provided for @backupEncryptedRow.
  ///
  /// In zh, this message translates to:
  /// **'加密备份'**
  String get backupEncryptedRow;

  /// No description provided for @backupEncryptedRowDesc.
  ///
  /// In zh, this message translates to:
  /// **'把加密副本保存到 iCloud Drive 或文件'**
  String get backupEncryptedRowDesc;

  /// No description provided for @backupIntro.
  ///
  /// In zh, this message translates to:
  /// **'备份文件用你设置的密码加密。同时拿到文件和密码的人，就掌握了这个钱包。'**
  String get backupIntro;

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
  /// **'至少 8 位'**
  String get backupPasswordTooShort;

  /// No description provided for @backupPasswordMismatch.
  ///
  /// In zh, this message translates to:
  /// **'两次输入的密码不一致'**
  String get backupPasswordMismatch;

  /// No description provided for @backupPasswordWarning.
  ///
  /// In zh, this message translates to:
  /// **'这个密码无法找回。密码丢了备份就打不开了 —— 请同时保留手抄的助记词。'**
  String get backupPasswordWarning;

  /// No description provided for @backupCreate.
  ///
  /// In zh, this message translates to:
  /// **'生成备份'**
  String get backupCreate;

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

  /// No description provided for @backupFailed.
  ///
  /// In zh, this message translates to:
  /// **'生成备份失败'**
  String get backupFailed;

  /// No description provided for @backupUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'此设备无法保存文件'**
  String get backupUnsupported;

  /// No description provided for @restoreFromBackup.
  ///
  /// In zh, this message translates to:
  /// **'从备份恢复'**
  String get restoreFromBackup;

  /// No description provided for @restoreFromBackupDesc.
  ///
  /// In zh, this message translates to:
  /// **'打开加密的 .ktbak 文件'**
  String get restoreFromBackupDesc;

  /// No description provided for @restorePickFile.
  ///
  /// In zh, this message translates to:
  /// **'选择备份文件'**
  String get restorePickFile;

  /// No description provided for @restoreEnterPassword.
  ///
  /// In zh, this message translates to:
  /// **'输入备份密码'**
  String get restoreEnterPassword;

  /// No description provided for @restoreWrongPassword.
  ///
  /// In zh, this message translates to:
  /// **'密码错误，或文件已损坏'**
  String get restoreWrongPassword;

  /// No description provided for @restoreNotABackup.
  ///
  /// In zh, this message translates to:
  /// **'这不是 KT 钱包的备份文件'**
  String get restoreNotABackup;

  /// No description provided for @restoreTooNew.
  ///
  /// In zh, this message translates to:
  /// **'此备份由更新版本的 App 生成'**
  String get restoreTooNew;

  /// No description provided for @restoreRestored.
  ///
  /// In zh, this message translates to:
  /// **'钱包已恢复'**
  String get restoreRestored;

  /// No description provided for @restoreAction.
  ///
  /// In zh, this message translates to:
  /// **'恢复'**
  String get restoreAction;

  /// No description provided for @backupFileChosen.
  ///
  /// In zh, this message translates to:
  /// **'已选择：{name}'**
  String backupFileChosen(String name);
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
