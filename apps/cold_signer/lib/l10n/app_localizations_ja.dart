// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get aboutPoweredBy => 'Silicon Nexus LLC が提供';

  @override
  String get aboutTitle => 'このアプリについて';

  @override
  String get aboutVersion => 'バージョン';

  @override
  String get aboutOpenSource => 'ソースコード';

  @override
  String get aboutOfflineNote =>
      'このページは完全にオフラインで動作します。ソースコードは別のオンライン端末で確認してください。';

  @override
  String get signerBackupEntryDesc => '強力なパスワードで暗号化・端末に保存';

  @override
  String get backupQrTitle => '暗号化QR';

  @override
  String get backupQrIntro =>
      'この端末で独自の強いパスワードを使ってリカバリーフレーズを暗号化し、KT WalletのQR画像を作成します。画像に平文のフレーズやパスワードは含まれません。';

  @override
  String get backupQrImageInstruction =>
      'パスワードが必要 · 受取用QRではありません\nKT Walletの「バックアップから復元」で「暗号化QRをスキャン」または「QR画像を選択」を使用してください。画像を公開せず、パスワードは別に保管してください。';

  @override
  String get backupQrGenerate => '暗号化QRを作成';

  @override
  String get backupQrSave => 'QR画像を端末に保存';

  @override
  String get backupPasswordLabel => 'バックアップパスワード';

  @override
  String get backupPasswordConfirm => 'パスワードを再入力';

  @override
  String get backupPasswordTooShort => '14 文字以上入力してください';

  @override
  String get backupPasswordTooLong => '128 文字以内で入力してください';

  @override
  String get backupPasswordTooWeak => '繰り返し・連続・一般的なパスワードは使用できません';

  @override
  String get backupPasswordMismatch => 'パスワードが一致しません';

  @override
  String get backupFailed => 'バックアップを作成できませんでした';

  @override
  String get backupSaved => 'バックアップを保存しました';

  @override
  String get backupCancelled => 'バックアップをキャンセルしました';

  @override
  String get walletUnlockRequired => 'ウォレットはロックされています';

  @override
  String get walletUnlockRequiredDesc =>
      'ウォレットの読み取りにはシステム認証が必要です。認証のキャンセルや期限切れでウォレットが削除されることはありません。解除して再試行してください。';

  @override
  String get walletUnlockAction => '本人認証して解除';

  @override
  String get signerBackupScope =>
      '現在のウォレットのリカバリーフレーズのみをバックアップします。アプリのPIN、設定、署名履歴は含みません。';

  @override
  String get signerBackupLocalWarning =>
      'QRとパスワードでリカバリーフレーズを復元できます。端末内に保存し、クラウド同期をオフにして、パスワードは別に保管してください。紛失したパスワードは復元できません。';

  @override
  String get signRejectWallet =>
      '別のコールドウォレット宛てのリクエストです。オンライン端末で現在のウォレットを再ペアリングし、取引QRを再生成してください。';

  @override
  String get signRejectExpired => 'リクエストの有効期限が切れました。オンライン端末で取引QRを再生成してください。';

  @override
  String get signRejectClock => '端末間の時刻が一致しません。システム時刻を確認し、リクエストを再生成してください。';

  @override
  String get signRejectDuplicate => '処理済みまたは予約済みのリクエストは再署名できません。署名履歴を確認してください。';

  @override
  String get signRejectUnsupported =>
      '取引を安全に解析できないか、ネットワークが一致しません。ネイティブ通貨・トークンの送金と approve(spender, 0) による承認取消のみ対応しています。';

  @override
  String get signRejectInvalid =>
      '有効な署名リクエストではありません。オンラインウォレットの取引QRをスキャンしてください。';

  @override
  String get signRejectNoWallet =>
      'コールドウォレットが利用できません。作成またはインポート後に再ペアリングしてください。';

  @override
  String get signRejectStorage => '安全な署名履歴を読み込めません。戻って再試行してください。';

  @override
  String get signRejectNoSignature => 'このリクエストには署名していません。以下の理由を確認してください。';

  @override
  String get amountPrecisionUnknown =>
      'トークンの精度は未検証です。最小単位の数量とコントラクトアドレスを確認してください。';

  @override
  String get amountBaseUnits => '最小単位';

  @override
  String get qrImportTitle => '暗号化QRから復元';

  @override
  String get qrImportDescription =>
      'KT Walletの暗号化バックアップQRをスキャンするか、端末内の画像を選択します。復号はすべてオフラインで行います。';

  @override
  String get qrImportScan => 'バックアップQRをスキャン';

  @override
  String get qrImportImage => '端末内のQR画像を選択';

  @override
  String get qrImportReady => '暗号化バックアップを認識しました';

  @override
  String get qrImportPassword => 'バックアップの暗号化パスワード';

  @override
  String get qrImportContinue => '復号して次へ';

  @override
  String get qrImportInvalid =>
      '読み取れません。KT Walletの暗号化バックアップQRが1つだけ含まれる、8 MB未満の端末内のPNG/JPEG画像を選択してください。';

  @override
  String get qrImportWrongPassword => 'パスワードが違うか、バックアップが破損しています。確認して再試行してください。';

  @override
  String get qrImportSafety =>
      '端末をオフラインに保ってください。ウォレットPINではなく、バックアップ作成時のパスワードを入力します。オンライン端末で使用したフレーズは、ここに復元しても未接続のコールドウォレットにはなりません。';

  @override
  String get walletDeviceAuthRequired =>
      'システム設定で画面ロックのパスコードまたは生体認証を設定してから再試行してください。ウォレットの PIN は端末認証の代わりにはなりません。エミュレーターでも設定が必要です。';

  @override
  String get walletCreationAuthRequired =>
      '端末認証が完了していないため、ウォレットはまだ作成されていません。再試行し、システム認証を完了してください。';

  @override
  String get introOpenTitle => 'フロントもバックも\n100% オープンソース。';

  @override
  String get introOpenDescription =>
      'ウォレット、オフライン署名、バックエンドゲートウェイ。すべてのソースコードを公開し、検証できる信頼を目指します。';

  @override
  String get introOpenNote => '資産を守る仕組みをソースコードで確認できます。誰でも検証し、改善に参加できます。';

  @override
  String get introSecurityTitle => '安全を、最優先に。\n管理するのは、あなた。';

  @override
  String get introFrontend => 'クライアント';

  @override
  String get introBackend => 'バックエンド';

  @override
  String get introOnline => 'オンライン';

  @override
  String get introOffline => 'オフライン署名';

  @override
  String get introNext => '次へ';

  @override
  String get introSkip => 'スキップ';

  @override
  String get introBack => '戻る';

  @override
  String get introSource => 'ソースコードを見る';

  @override
  String get introSourceHint =>
      'ネット接続のある端末で QR コードを読み取り、ソースを確認できます。この画面は通信を行いません。';

  @override
  String get introCopyLink => 'ソースの URL をコピー';

  @override
  String get introCopied => 'URL をコピーしました';

  @override
  String get introSaveFailed => 'ガイドの状態を保存できませんでした。再試行してください。';

  @override
  String get introRole => '独立したオフライン署名アプリ';

  @override
  String get introSecurityDescription =>
      '秘密鍵はこのオフライン端末に保管。署名のたびに取引内容を確認し、本人認証を行います。復元フレーズはオフラインで保管してください。';

  @override
  String get introSecurityNote =>
      '機内モードを有効にし、Wi-Fi と Bluetooth をオフに。この端末を署名専用として、常にオフラインに保ちます。';

  @override
  String get introPairTitle => '署名に専念。\n通信はしない。';

  @override
  String get introPairDescription =>
      'ネット接続端末の KT Wallet で取引を準備。この端末で QR を読み取り、確認・署名した後、署名済み QR をオンライン側へ戻して送信します。';

  @override
  String get introPairNote =>
      'QR で渡すのは取引と署名結果だけ。秘密鍵や復元フレーズは渡しません。残高照会・送信は行いません。';

  @override
  String get introStart => 'オフライン署名を設定';

  @override
  String get appName => 'KT Cold Signer';

  @override
  String get actionConfirm => '確認';

  @override
  String get actionCancel => 'キャンセル';

  @override
  String get actionSave => '保存';

  @override
  String get actionImport => 'インポート';

  @override
  String get actionValidating => '検証中…';

  @override
  String get cameraUnavailable => 'カメラを利用できません';

  @override
  String get done => '完了';

  @override
  String get later => '後で';

  @override
  String get splashTagline => '二台構成のコールドウォレット・オフライン署名端末';

  @override
  String get welcomeSubtitle => 'オフライン署名・リカバリーフレーズは決してネットに触れません';

  @override
  String get welcomeFeatOfflineTitle => '完全オフライン動作';

  @override
  String get welcomeFeatOfflineDesc => '本端末はネットワークに一切接続しません。常に機内モードの利用を推奨します';

  @override
  String get welcomeFeatLocalTitle => 'リカバリーフレーズは本端末のみに保存';

  @override
  String get welcomeFeatLocalDesc => '本端末で生成・暗号化して保存し、オンライン端末には決して渡しません';

  @override
  String get createNewWallet => '新規ウォレットを作成';

  @override
  String get importExistingWallet => '既存のウォレットをインポート';

  @override
  String get securityNoticeTitle => 'セキュリティ注意事項';

  @override
  String get showMnemonic => 'リカバリーフレーズを表示';

  @override
  String get mnemonicWillGenerate => '次にリカバリーフレーズを生成します';

  @override
  String get ruleFullControlTitle => 'リカバリーフレーズは資産の完全な管理権です';

  @override
  String get ruleFullControlDesc => 'この12単語を得た者は、どの端末でもウォレットを復元し全資産を送金できます';

  @override
  String get ruleHandwriteTitle => '紙とペンで手書きバックアップのみ';

  @override
  String get ruleHandwriteDesc => '2部書き写し、安全な物理的場所に分けて保管してください';

  @override
  String get ruleNoCaptureTitle => '撮影・スクリーンショット・オンライン端末への入力は厳禁';

  @override
  String get ruleNoCaptureDesc =>
      '写真・クラウド・チャットアプリに保存しないでください。iOS は撮影後に警告し、Android は復元フレーズ画面の撮影を禁止します';

  @override
  String get backupMnemonicTitle => 'リカバリーフレーズをバックアップ';

  @override
  String get mnemonicShowConfirmBtn => '手書きしました — 確認へ';

  @override
  String get mnemonicShowInstruction =>
      '以下の12単語を順番通りに手書きで書き写し、安全な物理的場所に保管してください。';

  @override
  String get mnemonicShowWarning => 'スクリーンショット・撮影・オンライン端末への転記は禁止です。';

  @override
  String get verifyBackupTitle => 'バックアップを確認';

  @override
  String mnemonicWordChallenge(int position) {
    return '$position 番目の単語は？';
  }

  @override
  String get mnemonicChallengeHint => '下から正しい単語を選択してください';

  @override
  String get verifyWrong => '選択が違います。手書きバックアップを確認して再試行してください';

  @override
  String get importWalletTitle => 'ウォレットをインポート';

  @override
  String get mnemonicInvalidChecksum =>
      'リカバリーフレーズが無効です。各単語、単語数、BIP-39チェックサムを確認してください。';

  @override
  String wordCountOption(int count) {
    return '$count 単語';
  }

  @override
  String get setPasswordTitle => 'ロック解除パスワードを設定';

  @override
  String get setPasswordPrompt => '6桁のパスワードを設定';

  @override
  String get setPasswordConfirmPrompt => '確認のため再入力';

  @override
  String get setPasswordDesc =>
      'アプリのロック解除と署名の確認に使用します。パスワードは本端末のセキュアエリアにのみ保存されます。';

  @override
  String get passwordMismatch => '2回の入力が一致しません。もう一度設定してください';

  @override
  String get biometricTitle => '生体認証';

  @override
  String get enableFaceId => 'Face IDを有効化';

  @override
  String get biometricUnavailable => '利用可能な生体認証または端末認証が設定されていません。';

  @override
  String get walletSecureStorageFailed => 'ウォレットの安全な保存に失敗しました。鍵は保存されていません。';

  @override
  String get secureStorageUnavailableTitle => 'セキュアストレージを利用できません';

  @override
  String get secureStorageUnavailableDesc =>
      'KT Cold Signerはウォレット、パスワード、ロック状態を安全に読み取れないため、署名をロックしたままにします。アプリを再起動するか、信頼できる配布元から再インストールしてください。';

  @override
  String get actionRetry => '再試行';

  @override
  String get biometricSkip => '今は有効にせず、パスワードのみ使用';

  @override
  String get biometricDesc =>
      '署名のたびに本人認証が必要です。Face IDを有効にすると素早く認証でき、いつでも端末のパスコードに切り替えられます。';

  @override
  String get exportPublicAddress => '公開アドレスをエクスポート';

  @override
  String get walletCreated => 'ウォレットを作成しました';

  @override
  String get mnemonicBackedUpVerified => 'リカバリーフレーズをバックアップし確認しました';

  @override
  String get walletNameLabel => 'ウォレット名';

  @override
  String get walletMainName => 'メインウォレット';

  @override
  String get mnemonicBackupLabel => 'フレーズのバックアップ';

  @override
  String get verified => '確認済み';

  @override
  String get supportedNetworks => '対応ネットワーク';

  @override
  String offlineForDays(int days) {
    return '$days 日間オフラインを継続';
  }

  @override
  String get securityCheckPassed => 'セキュリティチェック通過 · 機内モードが有効';

  @override
  String get offlineStatusConfirmed => 'ネットワークはオフラインです';

  @override
  String get offlineStatusConnected => 'ネットワーク接続を検出しました';

  @override
  String get offlineStatusUnknown => 'ネットワーク状態を確認できません';

  @override
  String get scanPendingTx => '署名待ち取引をスキャン';

  @override
  String get scanPendingTxDesc => 'オンラインウォレットの取引QRをスキャン';

  @override
  String get exportAddress => 'アドレスQR';

  @override
  String get signRecords => '署名記録';

  @override
  String get securityCheck => '安全性チェック';

  @override
  String get walletManage => 'ウォレット管理';

  @override
  String get addWallet => 'ウォレットを追加';

  @override
  String get signatureIncomplete => '署名未完了';

  @override
  String get recordsLoadFailed => '署名履歴を読み込めませんでした。戻って再試行してください。';

  @override
  String get noWalletRecords => 'このウォレットの署名履歴はありません';

  @override
  String get switchWallet => 'ウォレットの切り替え / 追加';

  @override
  String get walletSwitchFailed =>
      '切り替えが完了しませんでした。端末で認証して再試行してください。元のウォレットは変更されていません。';

  @override
  String get multiWalletScope =>
      '鍵とバックアップはウォレットごとに独立し、端末のアプリ PIN は共通です。1 つ削除しても他のウォレットは削除されません。';

  @override
  String get offlineSecurityCheck => 'オフラインセキュリティチェック';

  @override
  String get checkAirplaneMode => '機内モード';

  @override
  String get checkCellular => 'モバイル通信';

  @override
  String get checkBluetooth => 'Bluetooth';

  @override
  String get checkDevicePasscode => '端末パスコード';

  @override
  String get checkBiometric => '生体認証';

  @override
  String get checkScreenRecording => '画面録画';

  @override
  String get statusOn => 'オン';

  @override
  String get statusOff => 'オフ';

  @override
  String get statusDetectedOn => 'オンを検出';

  @override
  String get statusEnabled => '有効';

  @override
  String get statusNotDetected => '未検出';

  @override
  String get riskCannotSign => 'リスクあり · 署名できません';

  @override
  String get bluetoothWarning => 'Bluetoothがオンになっています。オフにして再チェックしてください。';

  @override
  String get checkNetwork => 'ネットワーク接続';

  @override
  String get checkIntegrity => 'システム完全性';

  @override
  String get checkLevelPass => '合格';

  @override
  String get checkLevelWarn => '警告';

  @override
  String get checkLevelBlock => '危険';

  @override
  String get checkDetailUnknown => '状態を確認できません';

  @override
  String get checkDetailNetworkSafe => 'ネットワーク接続は検出されませんでした';

  @override
  String get checkDetailNetworkUnsafe => 'ネットワーク接続を検出しました';

  @override
  String get checkDetailAirplaneSafe => '機内モードはオンです';

  @override
  String get checkDetailAirplaneUnsafe => '機内モードはオフです';

  @override
  String get checkDetailBluetoothSafe => 'Bluetoothはオフです';

  @override
  String get checkDetailBluetoothUnsafe => 'Bluetoothはオンです';

  @override
  String get checkDetailPasscodeSafe => '端末パスコードは設定済みです';

  @override
  String get checkDetailPasscodeUnsafe => '端末パスコードが設定されていません';

  @override
  String get checkDetailBiometricSafe => '生体認証を利用できます';

  @override
  String get checkDetailBiometricUnsafe => '生体認証を利用できません';

  @override
  String get checkDetailScreenCaptureSafe => '画面録画は検出されませんでした';

  @override
  String get checkDetailScreenCaptureUnsafe => '画面録画を検出しました';

  @override
  String get checkDetailIntegritySafe => 'システム完全性チェックに合格しました';

  @override
  String get checkDetailIntegrityUnsafe => 'root化または脱獄を検出しました';

  @override
  String get securityChecking => 'デバイス状態を確認中…';

  @override
  String get securityOverallPass => 'チェック合格 · 署名できます';

  @override
  String get securityOverallWarn => 'リスクあり · 慎重に操作してください';

  @override
  String get securityOverallBlock => '重大なリスクあり · 署名は禁止されています';

  @override
  String get securityRecheck => '再チェック';

  @override
  String receivingShard(int received, int total) {
    return 'シャード受信 $received / $total';
  }

  @override
  String get confirmTxContent => '取引内容を確認';

  @override
  String get reject => '拒否';

  @override
  String get confirmSign => '署名を確認';

  @override
  String rawAmountPrecision(String amount, int precision) {
    return '生の数量 $amount（精度 $precision）';
  }

  @override
  String get fromAccount => '送金元アカウント';

  @override
  String get toAddress => '受取アドレス';

  @override
  String get spenderAddress => '承認先コントラクト';

  @override
  String get nativeTransferOperation => 'ネイティブ送金';

  @override
  String get tokenTransferOperation => 'トークン送金';

  @override
  String get approvalRevokeOperation => 'トークン承認を解除';

  @override
  String get approvalRevokeZeroAllowance => 'allowance をゼロに設定';

  @override
  String get approvalRevokeSignerNotice =>
      'これは正確な ERC-20 approve(spender, 0) 呼び出しです。allowance のみを解除し、トークンは送金しません。';

  @override
  String get tokenContractLabel => 'トークンコントラクト';

  @override
  String get chainIdLabel => 'Chain ID';

  @override
  String get maximumFeeBaseUnits => '最大手数料（最小単位）';

  @override
  String get walletIdLabel => 'ウォレット ID';

  @override
  String get createdAtLabel => '作成日時';

  @override
  String get expiresAtLabel => '有効期限';

  @override
  String get riskWarningTitle => 'リスク警告';

  @override
  String get backToHome => 'ホームへ戻る';

  @override
  String get viewRawTxData => '生の取引データを表示';

  @override
  String get signingBlocked => '署名を禁止しました';

  @override
  String get signingBlockedDesc =>
      'この取引には安全に解析できない内容が含まれます。KT Cold Signerは資産保護のため署名を拒否しました。';

  @override
  String get transactionParseFailed => '安全に解析できません';

  @override
  String get signingFailed => '署名に失敗しました。取引、ウォレット、または認証が検証を通過していません。';

  @override
  String unknownContractCallDetected(String method) {
    return '未知のコントラクト呼び出しを検出：$method';
  }

  @override
  String get unknownContractCallDesc =>
      'ネイティブ送金、トークン送金、正確な approve(spender, 0) 解除のみ対応します。非ゼロ approve、permit、未知の呼び出しは拒否します。';

  @override
  String get authTitle => '本人認証';

  @override
  String get useFaceIdVerify => 'Face IDで認証';

  @override
  String get useDevicePasscode => '端末パスコードを使う';

  @override
  String get biometricFailedRetry => '認証に失敗しました。もう一度お試しください';

  @override
  String get verifyToSign => '認証して署名を完了';

  @override
  String get verifyToSignDesc => '署名のたびにFace IDまたは端末パスコードでの認証が必要です';

  @override
  String get amountLabel => '金額';

  @override
  String get requestId => 'リクエストID';

  @override
  String get enterPinToSign => '署名を完了するにはアプリパスワードを入力';

  @override
  String get enterPinToDelete => '削除を続行するにはアプリパスワードを入力';

  @override
  String get pinIncorrect => 'パスワードが違います。再試行してください';

  @override
  String pinLockedRetry(int seconds) {
    return '試行回数が上限に達しました。$seconds 秒後に再試行してください';
  }

  @override
  String get signComplete => '署名完了';

  @override
  String get voidThisSignature => '署名QRコードを閉じる';

  @override
  String get voidSignatureTitle => '署名QRコードを閉じますか？';

  @override
  String get voidSignatureDesc =>
      '本機のQR表示を閉じるだけです。他の端末で読み取り・保存済みの署名は取り消されず、送信される可能性があります。この画面を閉じても取引はキャンセルされません。';

  @override
  String get signatureVoided => 'QRを閉じました。署名は取り消されていません。';

  @override
  String get signResultUnavailable => '署名結果を利用できません';

  @override
  String dynamicShard(int received, int total) {
    return '動的シャード $received / $total';
  }

  @override
  String get scanResultInstruction =>
      'オンラインウォレットの現在の取引で「オフラインで署名済み：結果をスキャン」を選び、このQRを読み取ってください。';

  @override
  String get allAddresses => 'すべてのアドレス';

  @override
  String exportQrCaption(int count) {
    return '$count 個のチェーンの公開アドレスを含む · 秘密データは含みません';
  }

  @override
  String get filterAll => 'すべて';

  @override
  String get stateSigned => '署名済み';

  @override
  String get stateRejected => '拒否済み';

  @override
  String get stateExpired => '期限切れ';

  @override
  String get unknownContractCallLabel => '未知のコントラクト呼び出し';

  @override
  String walletCreatedOn(String date) {
    return '作成日 $date';
  }

  @override
  String get backedUp => 'バックアップ済み';

  @override
  String get editWalletName => 'ウォレット名を変更';

  @override
  String get mnemonicBackupCheck => 'リカバリーフレーズのバックアップ確認';

  @override
  String get mnemonicBackupCheckDesc => 'フレーズが今も正しく書き写せるか定期的に抜き取り確認します';

  @override
  String get mnemonicReviewFailed => '認証またはフレーズ検証に失敗しました。リカバリーフレーズは表示されていません。';

  @override
  String get deleteWallet => 'ウォレットを削除';

  @override
  String get deleteWalletReqDesc =>
      'アプリパスワードと確認テキストが必要です。システム認証が有効な場合はその認証も必要です';

  @override
  String get destroyAllData => 'すべてのウォレットデータを破棄';

  @override
  String get destroyAllDataDesc => '復元不可。端末の処分前にのみ使用してください';

  @override
  String get securitySettingsTitle => 'セキュリティ設定';

  @override
  String get verificationPolicy => '認証ポリシー';

  @override
  String get biometricUsageDesc => 'ロック解除と署名にFace IDを使用';

  @override
  String get verifyEverySign => '署名ごとに認証';

  @override
  String get verifyEverySignDesc => '無効にできません（V1で強制）';

  @override
  String get accessSection => 'アクセス';

  @override
  String get changeAppPassword => 'アプリのパスワードを変更';

  @override
  String get screenCaptureProtection => 'スクリーンショット安全通知';

  @override
  String get screenCaptureBlocked => '画面収録・ミラーリングを検出しました';

  @override
  String get screenCaptureBlockedHint =>
      '収録・ミラーリング中はリカバリーフレーズを非表示にします。停止すると自動的に戻ります。';

  @override
  String get permanentlyDeleteWallet => 'ウォレットを完全に削除';

  @override
  String get stepPassword => 'パスワード';

  @override
  String get stepConfirmText => '確認テキスト';

  @override
  String get irreversibleAction => 'この操作は取り消せません';

  @override
  String get deleteWalletWarningDesc =>
      '削除後、本端末はこのウォレットの全ての鍵データを消去します。リカバリーフレーズが未バックアップまたは紛失している場合、資産は永久に復元できません。';

  @override
  String get typeToConfirmDelete => '続けるには「ウォレットを削除」と入力してください';

  @override
  String get deleteWalletConfirmationPhrase => 'ウォレットを削除';

  @override
  String get verifyToDeleteWallet => 'このウォレットを完全に削除するために認証';

  @override
  String get deleteAuthenticationFailed => '認証に失敗しました。ウォレットは削除されていません。';

  @override
  String get deleteWalletFailed =>
      'ウォレットを安全に削除できませんでした。現在のウォレットは削除されていません。もう一度お試しください。';

  @override
  String get displayLanguage => '表示言語';

  @override
  String get settingsTitle => '設定';

  @override
  String get fiatUnit => '法定通貨';

  @override
  String get languageSystem => 'システムに従う';

  @override
  String get settingsSaveFailed => '設定を保存できませんでした。内容は変更されていません。もう一度お試しください。';

  @override
  String get pinKeyDelete => '最後の桁を削除';
}
