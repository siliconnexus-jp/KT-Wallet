// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appName => 'KT Wallet';

  @override
  String get appTagline => '二台構成のコールドウォレット・オンライン監視端末';

  @override
  String get actionConfirm => '確認';

  @override
  String get actionCancel => 'キャンセル';

  @override
  String get actionDelete => '削除';

  @override
  String get actionNext => '次へ';

  @override
  String get actionImport => 'インポート';

  @override
  String get manage => '管理';

  @override
  String get viewAll => 'すべて';

  @override
  String get max => '最大';

  @override
  String get tabHome => 'ホーム';

  @override
  String get tabAssets => '資産';

  @override
  String get tabRecords => '履歴';

  @override
  String get tabSettings => '設定';

  @override
  String get walletKindHot => '通常';

  @override
  String get walletKindWatch => '監視';

  @override
  String get walletStateBackedUp => 'バックアップ済み';

  @override
  String get walletStateNotBackedUp => '未バックアップ';

  @override
  String get walletSeedDaily => '日常ウォレット';

  @override
  String get walletSeedMain => 'メインウォレット';

  @override
  String walletDefaultName(int index) {
    return 'ウォレット $index';
  }

  @override
  String walletImportedName(int index) {
    return 'インポートウォレット $index';
  }

  @override
  String get backupBannerText => 'リカバリーフレーズが未バックアップ — 紛失の恐れがあります';

  @override
  String get backupNow => '今すぐバックアップ';

  @override
  String get balanceTitle => '総資産評価額 (USD)';

  @override
  String get balanceChangePeriod => '過去24時間';

  @override
  String get actionReceive => '受取';

  @override
  String get actionSend => '送金';

  @override
  String get actionMore => 'その他';

  @override
  String get actionScanSign => '署名スキャン';

  @override
  String get assetsSortByValue => '保有額の高い順';

  @override
  String get recordsTitle => '取引履歴';

  @override
  String get txSent => '送信';

  @override
  String get txReceived => '受取';

  @override
  String get dateToday => '今日';

  @override
  String get dateYesterday => '昨日';

  @override
  String monthDay(int month, int day) {
    return '$month月$day日';
  }

  @override
  String get settingsWalletManage => 'ウォレット管理';

  @override
  String get settingsSecurity => 'セキュリティ設定';

  @override
  String get settingsAddressBook => 'アドレス帳';

  @override
  String get settingsNetwork => 'ネットワーク';

  @override
  String get settingsTokenManage => 'トークン管理';

  @override
  String get addWalletTitle => 'ウォレットを追加';

  @override
  String get addWalletStandardSection => '通常ウォレット・手軽';

  @override
  String get createNewWallet => '新規ウォレットを作成';

  @override
  String get createNewWalletDesc => '端末で新しいリカバリーフレーズを生成し、すぐに使えます';

  @override
  String get importMnemonic => 'リカバリーフレーズをインポート';

  @override
  String get importMnemonicDesc => '12 / 18 / 24 単語の既存フレーズ';

  @override
  String get coldWalletSection => 'オフラインウォレット構成・高セキュリティ';

  @override
  String get connectColdWallet => 'オフラインウォレットを接続';

  @override
  String get connectColdWalletDesc =>
      'QRでKT Wallet Cold Signerとペアリング。秘密鍵は端末に入りません';

  @override
  String get createWalletTitle => '通常ウォレットを作成';

  @override
  String get showMnemonic => 'リカバリーフレーズを表示';

  @override
  String get mnemonicWillGenerate => '次にリカバリーフレーズを生成します';

  @override
  String get hotWalletNotice =>
      'これはホットウォレットです。リカバリーフレーズは端末のセキュアエリアに保存されます。少額の日常利用に適しており、多額の資産にはオフラインウォレット構成を推奨します。';

  @override
  String get ruleFullControlTitle => 'リカバリーフレーズは資産の完全な管理権です';

  @override
  String get ruleFullControlDesc => 'この12単語を得た者は、あなたの全資産を送金できます';

  @override
  String get ruleHandwriteTitle => '紙とペンで手書きバックアップのみ';

  @override
  String get ruleHandwriteDesc => '写真・クラウド・メモ・チャットアプリに保存しないでください';

  @override
  String get backupMnemonicTitle => 'リカバリーフレーズをバックアップ';

  @override
  String get mnemonicShowConfirmBtn => '手書きしました — 確認へ';

  @override
  String get mnemonicShowWarning =>
      '順番通りに手書きしてください。スクリーンショットや撮影は禁止です。フレーズを得た者が資産を管理できます。';

  @override
  String get mnemonicUnavailableTitle => 'リカバリーフレーズを表示できません';

  @override
  String get mnemonicUnavailableBackup =>
      'このバックアップ手順は新規作成したウォレット専用です。現在のウォレットをバックアップするには「ウォレット詳細 → リカバリーフレーズを表示」を開いてください。';

  @override
  String get mnemonicAuthRequired => 'リカバリーフレーズを表示するには認証が必要です。もう一度お試しください。';

  @override
  String get mnemonicNoKeyMaterial => 'この端末にはこのウォレットのリカバリーフレーズが保存されていません。';

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
  String get walletCreatedBackedUp => 'ウォレットを作成しバックアップしました';

  @override
  String get backupVerified => 'バックアップを確認しました — フレーズは正しいです';

  @override
  String get mnemonicInvalid => 'リカバリーフレーズが無効です。各単語を確認して再試行してください';

  @override
  String get mnemonicImported => 'リカバリーフレーズをインポートしました';

  @override
  String wordsCount(int count) {
    return '$count 単語';
  }

  @override
  String get pasteMnemonic => 'フレーズを貼り付け（解析後クリップボードを消去）';

  @override
  String get scanAccountQr => 'アカウントQRをスキャン';

  @override
  String get connectColdSubtitle => 'オフライン端末から公開アドレスをインポートして監視ウォレットを作成';

  @override
  String get connectColdSafety => '端末はフレーズ・秘密鍵・シードを一切受信・保存しません。';

  @override
  String get scanAccountHint => 'KT Wallet Cold SignerのアドレスQRに合わせてください';

  @override
  String get importConfirmTitle => 'インポートを確認';

  @override
  String get createWatchWallet => '監視ウォレットを作成';

  @override
  String walletIdProtocol(String id, int version) {
    return 'Wallet ID: $id · プロトコル v$version';
  }

  @override
  String get walletsTitle => 'ウォレット';

  @override
  String get deleteWalletTitle => 'ウォレットを削除';

  @override
  String deleteWalletConfirm(String name) {
    return '「$name」を削除しますか？端末の記録のみ削除され、オンチェーン資産には影響しません。';
  }

  @override
  String deletedWallet(String name) {
    return '「$name」を削除しました';
  }

  @override
  String get sortAction => '並べ替え';

  @override
  String walletCountLimit(int count, int max) {
    return 'ウォレット $count 個 · 上限 $max 個';
  }

  @override
  String get walletDetailTitle => 'ウォレット詳細';

  @override
  String get walletTypeLabel => 'ウォレット種別';

  @override
  String get standardWallet => '通常ウォレット';

  @override
  String get backupNotYet => 'リカバリーフレーズが未バックアップです';

  @override
  String get viewMnemonic => 'リカバリーフレーズを表示';

  @override
  String get viewMnemonicDesc => '生体認証またはパスコードが必要です';

  @override
  String get deleteWalletDesc => '認証が必要です。削除前にバックアップ状態を再確認します';

  @override
  String get amountMustBePositive => '金額は0より大きくしてください';

  @override
  String get insufficientBalance => '残高不足';

  @override
  String get amountFormatInvalid => '金額の形式が正しくありません';

  @override
  String get recipientAddress => '受取アドレス';

  @override
  String get pasteOrEnterAddress => 'アドレスを貼り付けまたは入力';

  @override
  String enterChainAddress(String network) {
    return '$networkネットワークの受取アドレスを入力してください';
  }

  @override
  String addressValidOn(String network) {
    return 'アドレス形式は正しい · $networkネットワーク';
  }

  @override
  String get addressInvalid => '無効なアドレス';

  @override
  String get amountLabel => '金額';

  @override
  String availableBalance(String amount, String symbol) {
    return '利用可能 $amount $symbol';
  }

  @override
  String get selectAsset => '資産を選択';

  @override
  String get scanAddressTitle => 'アドレスQRをスキャン';

  @override
  String get scanAddressHint => '受取アドレスのQRコードに合わせてください';

  @override
  String get networkFee => 'ネットワーク手数料';

  @override
  String get feeCustom => 'カスタム';

  @override
  String get feeSlow => '低速';

  @override
  String get feeStandard => '標準';

  @override
  String get feeFast => '高速';

  @override
  String get confirmFee => '手数料を確認';

  @override
  String get feeExplainer => '手数料が高いほど確認が早くなります。手数料はネットワークに支払われ、アプリには入りません。';

  @override
  String get feeEtaSlow => '≈ 3〜5分';

  @override
  String get feeEtaStandard => '≈ 1分';

  @override
  String get feeEtaFast => '≈ 15秒';

  @override
  String get feeLowWarning =>
      '手数料が低すぎると、取引が長時間未確認のままになったり失敗したりする場合があります。TRON Energyが不足するとTRXを消費して補います。';

  @override
  String get confirmTransactionTitle => '取引を確認';

  @override
  String get confirmTransfer => '送金を確認';

  @override
  String get generateSignQr => '署名用QRを生成';

  @override
  String get hotConfirmHint => '認証後、この端末が署名し自動で送信します';

  @override
  String get watchConfirmHint => 'QRにフレーズや秘密鍵は含まれません';

  @override
  String get fromAddress => '送信元';

  @override
  String get totalSpend => '合計支出';

  @override
  String get unbackedTransferWarning =>
      'このウォレットはリカバリーフレーズが未バックアップです。送金前にバックアップを推奨します。';

  @override
  String get pendingSignTitle => '署名待ち取引';

  @override
  String dynamicShard(int received, int total) {
    return '動的シャード $received / $total';
  }

  @override
  String get networkRow => 'ネットワーク';

  @override
  String get requestId => 'リクエストID';

  @override
  String get scanWithOfflinePhone => 'このQRをオフライン署名端末でスキャンしてください';

  @override
  String get scanSignResultTitle => '署名結果をスキャン';

  @override
  String recognizedShard(int received, int total) {
    return '認識済みシャード $received / $total';
  }

  @override
  String get broadcastTitle => '取引をブロードキャスト';

  @override
  String get dontBroadcastYet => 'まだ送信しない';

  @override
  String get chainParamsFallback => 'チェーン上のパラメータを取得できないため、既定のnonceと手数料を使用します';

  @override
  String broadcastFailedMessage(String message) {
    return 'ブロードキャストに失敗しました：$message';
  }

  @override
  String get signatureVerified => '署名を確認 · 署名者はウォレットアドレスと一致し、内容は改ざんされていません';

  @override
  String get signerAddress => '署名アドレス';

  @override
  String get txHashPreview => '取引ハッシュのプレビュー';

  @override
  String get backToHome => 'ホームへ戻る';

  @override
  String get txSubmitted => '取引を送信しました';

  @override
  String get txTimeLabel => '日時';

  @override
  String get txHash => '取引ハッシュ';

  @override
  String get statusLabel => 'ステータス';

  @override
  String get txStatusSubmitted => '送信済み';

  @override
  String get txStatusPending => '確認待ち';

  @override
  String get txStatusConfirmed => '確認済み';

  @override
  String get txStatusFailed => '失敗';

  @override
  String get txStatusDropped => '破棄済み';

  @override
  String get txStatusReplaced => '置換済み';

  @override
  String get nonceConflict => 'この nonce は別の保留中取引で使用されています。更新して再試行してください。';

  @override
  String get txSpeedUp => '取引を高速化';

  @override
  String get txCancelTransaction => '取引をキャンセル';

  @override
  String get txReplacementConfirmTitle => '置換取引を確認';

  @override
  String get txSpeedUpConfirm =>
      '同じ nonce とより高いネットワーク手数料で再送信します。送金先と金額は変更されません。';

  @override
  String get txCancelConfirm =>
      '同じ nonce で自分宛てに 0 金額の取引を送信します。この置換取引が先に確認された場合のみ元の取引がキャンセルされます。';

  @override
  String get txReplacementSubmitted => '置換取引を送信しました';

  @override
  String get txReplacementRace => '置換取引の送信中に元の取引状態が変わりました。チェーン上の最終結果をお待ちください。';

  @override
  String get txNonceAlreadyUsed => 'この nonce はすでにチェーン上で使用されているため置換できません。';

  @override
  String get txReplacementUnavailable =>
      'この取引には高速化またはキャンセルに必要なチェーンパラメータがありません。';

  @override
  String txReplacementWrongNetwork(String network) {
    return 'この取引は $network のものです。高速化やキャンセルの前に、そのネットワークに切り替えてください。';
  }

  @override
  String get feeEstimating => '見積もり中…';

  @override
  String get feeUnavailable => 'ネットワーク手数料を取得できません';

  @override
  String get feeUnavailableHint => 'ネットワーク手数料を見積もれないため、送信できません。';

  @override
  String get txNonceLabel => 'Nonce';

  @override
  String get txMaxFeeLabel => '最大手数料（最小単位）';

  @override
  String get txRawAmountLabel => '金額（最小単位）';

  @override
  String get txReplacesLabel => '置換元の取引';

  @override
  String get txReplacedByLabel => '置換先の取引';

  @override
  String get txNotFound => 'ローカル取引記録が見つかりません';

  @override
  String confirming(int received, int total) {
    return '確認中 ($received/$total)';
  }

  @override
  String get txDetailTitle => '取引詳細';

  @override
  String get confirmedPrefix => '確認済み';

  @override
  String get confirmations => '確認数';

  @override
  String get authToConfirmTransfer => '認証して送金を確認';

  @override
  String get authEveryTransfer => '送金ごとに生体認証またはパスコードが必要です';

  @override
  String get useFaceId => '生体認証を使用';

  @override
  String get usePasscode => 'パスコードを使う';

  @override
  String get biometricFailedRetry => '認証に失敗しました。もう一度お試しください';

  @override
  String get searchAssetHint => '名称 / シンボル / コントラクトを検索';

  @override
  String get price => '価格';

  @override
  String get change24h => '24時間変動';

  @override
  String get contractAddress => 'コントラクトアドレス';

  @override
  String get unverifiedToken => '未確認トークン — コントラクトアドレスを確認してください';

  @override
  String get receiveWarning =>
      'TRONネットワーク（TRC-20）資産のみ対応。他のネットワークからの送金は資産の損失につながります。';

  @override
  String get explorerLinkCopied => 'ブロックエクスプローラーのリンクをコピーしました';

  @override
  String get addressCopied => 'アドレスをコピーしました';

  @override
  String get saveReceiveImage => '受取画像を保存';

  @override
  String get privacyOverlayActive => 'KT Wallet 保護が有効です';

  @override
  String get privacyOverlayHidden => 'ウォレットの内容は非表示です';

  @override
  String get chooseNetwork => 'ネットワークを選択';

  @override
  String assetOnChains(int count) {
    return '$count チェーン';
  }

  @override
  String get receiveCardTitle => '受取アドレス';

  @override
  String get receiveCardNetwork => 'ネットワーク';

  @override
  String get receiveCardGenerated => '生成日時';

  @override
  String get receiveImageSaved => '写真に保存しました';

  @override
  String get receiveImageDenied => '写真ライブラリへのアクセスが拒否されました';

  @override
  String get receiveImageUseShare => 'このOSでは直接保存できません。共有をご利用ください';

  @override
  String get receiveImageFailed => '受取画像を作成できませんでした';

  @override
  String get actionCopy => 'アドレスをコピー';

  @override
  String get addressBookTitle => 'アドレス帳';

  @override
  String get searchNameOrAddress => '名称またはアドレスを検索';

  @override
  String get assetUnavailable => 'この資産は利用できません';

  @override
  String get noMatchingContacts => '一致する連絡先がありません';

  @override
  String get contactsEmpty => '連絡先がまだありません。右上の + から追加できます';

  @override
  String get tokensEmpty => 'カスタムトークンがまだありません。右上の + から追加できます';

  @override
  String get contactBobExchange => 'Bob 取引所';

  @override
  String get contactColdBackup => 'コールドウォレットのバックアップ';

  @override
  String get editContactTitle => '連絡先を編集';

  @override
  String get actionEdit => '編集';

  @override
  String get addContactTitle => '連絡先を追加';

  @override
  String get nameLabel => '名前';

  @override
  String get addressLabel => 'アドレス';

  @override
  String get invalidChainAddress => '有効なチェーンアドレスではありません';

  @override
  String get actionSave => '保存';

  @override
  String get tokenManageTitle => 'トークン管理';

  @override
  String get addTokenTitle => 'トークンを追加';

  @override
  String get tokenSymbolLabel => 'シンボル';

  @override
  String get networkSettingsTitle => 'ネットワーク設定';

  @override
  String get screenCaptureBlocked => '画面収録・ミラーリングを検出しました';

  @override
  String get screenCaptureBlockedHint =>
      'リカバリーフレーズを保護するため内容を隠しています。収録・ミラーリングを停止すると復帰します。';

  @override
  String get screenshotWarning =>
      'リカバリーフレーズのスクリーンショットが撮影されました。写真ライブラリに保存されており、閲覧できる人は誰でも資産を移動できます。直ちに新しいウォレットへ資産を移してください。';

  @override
  String get rpcMeasuring => '測定中…';

  @override
  String get rpcUnreachable => '接続できません';

  @override
  String get rpcNotMeasured => '—';

  @override
  String get rpcTimeout => 'タイムアウト';

  @override
  String get rpcNode => 'RPCノード';

  @override
  String get networkResetDefault => 'デフォルトに戻す';

  @override
  String get gatewayTitle => 'ゲートウェイ';

  @override
  String get gatewayDesc => '統合クエリゲートウェイ。空欄の場合は各チェーンのノードに直接接続します';

  @override
  String get gatewayNotSet => '未設定';

  @override
  String get gatewayTest => '接続テスト';

  @override
  String get gatewayTestOk => 'ゲートウェイ接続に成功しました';

  @override
  String get gatewayTestFail => 'ゲートウェイ接続に失敗しました';

  @override
  String get accessControl => 'アクセス制御';

  @override
  String get appLock => 'アプリロック';

  @override
  String get appLockDesc => 'アプリ起動時に安全認証を要求';

  @override
  String get authMethod => '認証方法';

  @override
  String get authMethodDesc => 'アプリのロック解除と送金承認に使用します';

  @override
  String get authBiometrics => 'Face ID / 生体認証';

  @override
  String get authBiometricsDesc => 'このデバイスの生体認証ですばやく承認';

  @override
  String get authPassword => 'ウォレットパスワード';

  @override
  String get authPasswordDesc => '6桁のウォレットパスワードを入力';

  @override
  String get autoLock => '自動ロック';

  @override
  String get autoLockDesc => 'バックグラウンドで一定時間後に再ロック';

  @override
  String get autoLockValue => '1分';

  @override
  String get privacyMode => 'プライバシーモード';

  @override
  String get privacyModeDesc => 'ホームで残高を既定で非表示';

  @override
  String get dataSection => 'データ';

  @override
  String get fiatUnit => '法定通貨';

  @override
  String get displayLanguage => '表示言語';

  @override
  String get deleteWatchWallet => '監視ウォレットを削除';

  @override
  String get deleteWatchWalletDesc => '公開アドレスとローカル記録のみ削除。資産に影響はありません';

  @override
  String get languageSystem => 'システムに従う';

  @override
  String get modeSelectTitle => 'デバイスモードを選択';

  @override
  String get modeSelectSubtitle => 'はじめに、この端末の役割を選んでください';

  @override
  String get modeWalletTitle => 'オンラインウォレット';

  @override
  String get modeWalletDesc => '日常利用・残高の確認・送金の実行';

  @override
  String get modeSignerTitle => 'オフライン署名機';

  @override
  String get modeSignerDesc => 'ネットに一切接続しない端末にインストールし、秘密鍵をオフラインで保管して署名します';

  @override
  String get modeSignerConfirmTitle => 'オフライン署名機を有効化';

  @override
  String get modeSignerConfirmBody =>
      'このモードはオフライン端末専用です。機内モードをオンにし、この端末を絶対にネットへ接続しないでください。';

  @override
  String get deviceMode => 'デバイスモード';

  @override
  String get deviceModeSwitchTitle => 'デバイスモードを切り替え';

  @override
  String get deviceModeSwitchDesc => '切り替えると、モード選択画面に戻ります。';

  @override
  String get walletLoadErrorTitle => 'ウォレットを読み込めませんでした';

  @override
  String get walletLoadErrorDesc =>
      '端末内のウォレットデータを読み取れませんでした。もう一度お試しください。問題が続く場合はアプリを再インストールしてください。';

  @override
  String get cryptoUnavailableTitle => 'ウォレットエンジンを利用できません';

  @override
  String get cryptoUnavailableDesc =>
      'この Android ビルドには Trust Wallet Core が含まれていません。Wallet Core 対応ビルドをインストールしてください。模擬鍵へ自動的に切り替わることはありません。';

  @override
  String get actionRetry => '再試行';

  @override
  String get renameWallet => 'ウォレット名を変更';

  @override
  String get backupTranscribed => '書き写しました';

  @override
  String receiveWarningFor(String network) {
    return '$networkネットワークの資産のみ対応。他のネットワークからの送金は資産の損失につながります。';
  }

  @override
  String get autoLockImmediate => 'すぐに';

  @override
  String autoLockMinutesLabel(int minutes) {
    return '$minutes分';
  }

  @override
  String get copyAddress => 'アドレスをコピー';

  @override
  String get noMatchingAssets => '一致する資産はありません';

  @override
  String get noWatchWallet => 'ウォッチウォレットはありません';

  @override
  String get watchWalletCreated => 'ウォッチウォレットを作成しました';

  @override
  String get marketOfflineDemo => 'ネットワークに接続できず、ライブデータを取得できません';

  @override
  String get actionDone => '完了';

  @override
  String get historyUnsupportedChain => 'このチェーンでは履歴照会はまだ利用できません';

  @override
  String get historyEmpty => '取引履歴はまだありません';

  @override
  String get setPinTitle => 'ロック解除パスワードを設定';

  @override
  String get setPinPrompt => '6桁のパスワードを設定';

  @override
  String get setPinConfirmPrompt => '確認のため再入力';

  @override
  String get setPinDesc =>
      '生体認証が使えないときにパスワードでアプリを解除します。パスワードは本端末のセキュアエリアにのみ保存されます。';

  @override
  String get pinMismatch => '2回の入力が一致しません。もう一度設定してください';

  @override
  String get enterPinToUnlock => 'パスワードを入力してロック解除';

  @override
  String get enterPinToDisable => 'アプリロックをオフにするにはパスワードを入力';

  @override
  String get pinIncorrect => 'パスワードが違います。再試行してください';

  @override
  String pinLockedRetry(int seconds) {
    return '試行回数が上限に達しました。$seconds 秒後に再試行してください';
  }

  @override
  String get usePinUnlock => 'パスワードで解除';

  @override
  String get networkEnvironment => 'ネットワーク環境';

  @override
  String get envMainnet => 'メインネット';

  @override
  String get envTestnet => 'テストネット';

  @override
  String get testnetBadge => 'テストネット';

  @override
  String get perChainNetwork => 'チェーン別ネットワーク';

  @override
  String get addNetwork => 'ネットワークを追加';

  @override
  String get networkNameLabel => 'ネットワーク名';

  @override
  String get chainFamilyLabel => 'チェーン系統';

  @override
  String get chainIdLabel => 'Chain ID';

  @override
  String get explorerLabel => 'エクスプローラー URL(任意)';

  @override
  String get symbolLabel => 'シンボル';

  @override
  String get probeChecking => 'RPC を確認中…';

  @override
  String get probeOkSave => '確認に成功し、保存しました';

  @override
  String get rpcProbeFailed => 'RPC の確認に失敗しました。URL を確認してください';

  @override
  String chainIdMismatch(Object actual) {
    return 'Chain ID が一致しません:ノードは $actual を返しました';
  }

  @override
  String get deleteNetwork => 'ネットワークを削除';

  @override
  String get networkInUse => 'このネットワークは使用中です';

  @override
  String get faucetAction => 'テストコインを取得';

  @override
  String get faucetOpened => 'テストネットのフォーセットを開きました';

  @override
  String get externalActionFailed => '外部アプリを開けません。もう一度お試しください';

  @override
  String shareAddressSubject(String network) {
    return '$network 受取アドレス';
  }

  @override
  String get cameraUnavailable => 'カメラを利用できません。権限を確認して再試行してください';

  @override
  String get biometricUnavailable => '生体認証を利用できません。ウォレットPINを使用してください';

  @override
  String get airdropRequesting => 'エアドロップを要求中…';

  @override
  String get airdropOk => 'エアドロップ完了 — まもなく残高が更新されます';

  @override
  String airdropFailed(Object message) {
    return 'エアドロップ失敗:$message';
  }

  @override
  String get fiatHiddenTestnet => 'テストネット資産には市場価格がありません';

  @override
  String get backupEncryptedTitle => '暗号化バックアップ';

  @override
  String get backupEncryptedRow => '暗号化バックアップ';

  @override
  String get backupEncryptedRowDesc => '暗号化したコピーを iCloud Drive やファイルに保存';

  @override
  String get backupIntro =>
      'バックアップは設定したパスワードで暗号化されます。ファイルとパスワードの両方を持つ人はこのウォレットを操作できます。';

  @override
  String get backupPasswordLabel => 'バックアップパスワード';

  @override
  String get backupPasswordConfirm => 'パスワードを再入力';

  @override
  String get backupPasswordTooShort => '8 文字以上';

  @override
  String get backupPasswordMismatch => 'パスワードが一致しません';

  @override
  String get backupPasswordWarning =>
      'このパスワードは復元できません。失うとバックアップは開けません。手書きのリカバリーフレーズも保管してください。';

  @override
  String get backupCreate => 'バックアップを作成';

  @override
  String get backupSaved => 'バックアップを保存しました';

  @override
  String get backupCancelled => 'バックアップをキャンセルしました';

  @override
  String get backupFailed => 'バックアップを作成できませんでした';

  @override
  String get backupUnsupported => 'この端末ではファイルを保存できません';

  @override
  String get restoreFromBackup => 'バックアップから復元';

  @override
  String get restoreFromBackupDesc => '暗号化された .ktbak ファイルを開く';

  @override
  String get restorePickFile => 'バックアップファイルを選択';

  @override
  String get restoreEnterPassword => 'バックアップパスワードを入力';

  @override
  String get restoreWrongPassword => 'パスワードが違うか、ファイルが壊れています';

  @override
  String get restoreNotABackup => 'KT ウォレットのバックアップファイルではありません';

  @override
  String get restoreTooNew => 'このバックアップは新しいバージョンで作成されています';

  @override
  String get restoreRestored => 'ウォレットを復元しました';

  @override
  String get restoreAction => '復元';

  @override
  String backupFileChosen(String name) {
    return '選択済み：$name';
  }
}
