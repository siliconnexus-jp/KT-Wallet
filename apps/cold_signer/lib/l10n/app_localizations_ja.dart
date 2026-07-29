// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

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
      '写真・クラウド・チャットアプリに保存しないでください。スクリーンショットを検出すると、復元フレーズをすぐに隠して警告します';

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
  String get scanPendingTx => '署名待ち取引をスキャン';

  @override
  String get scanPendingTxDesc => 'オンラインウォレットが生成した動的QRをスキャン';

  @override
  String get exportAddress => 'アドレスをエクスポート';

  @override
  String get signRecords => '署名記録';

  @override
  String get securityCheck => 'セキュリティチェック';

  @override
  String get walletManage => 'ウォレット管理';

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
  String unknownContractCallDetected(String method) {
    return '未知のコントラクト呼び出しを検出：$method';
  }

  @override
  String get unknownContractCallDesc =>
      'V1はネイティブ通貨とトークンの送金のみ対応します。approve・permit などの承認系呼び出しはすべて拒否します。';

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
  String get pinIncorrect => 'パスワードが違います。再試行してください';

  @override
  String pinLockedRetry(int seconds) {
    return '試行回数が上限に達しました。$seconds 秒後に再試行してください';
  }

  @override
  String get signComplete => '署名完了';

  @override
  String get voidThisSignature => 'この署名を無効化';

  @override
  String get voidSignatureTitle => 'この署名を無効にしますか？';

  @override
  String get voidSignatureDesc =>
      '無効にすると、この署名結果のQRコードは使用できなくなり、オンラインウォレットはこの取引をブロードキャストできません。';

  @override
  String get signatureVoided => '署名を無効にしました';

  @override
  String dynamicShard(int received, int total) {
    return '動的シャード $received / $total';
  }

  @override
  String get scanResultInstruction => 'オンラインウォレットの「署名結果をスキャン」でこのQRを読み取ってください';

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
  String get deleteWallet => 'ウォレットを削除';

  @override
  String get deleteWalletReqDesc => 'パスワード・生体認証・確認テキストが必要です';

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
  String get displayLanguage => '表示言語';

  @override
  String get settingsTitle => '設定';

  @override
  String get fiatUnit => '法定通貨';

  @override
  String get languageSystem => 'システムに従う';

  @override
  String get deviceMode => 'デバイスモード';

  @override
  String get deviceModeSigner => 'オフライン署名機';

  @override
  String get deviceModeSwitchTitle => 'デバイスモードを切り替え';

  @override
  String get deviceModeSwitchDesc =>
      '切り替える前に、この端末を署名機として使用しないことを確認してください。切り替えるとモード選択画面に戻ります。';
}
