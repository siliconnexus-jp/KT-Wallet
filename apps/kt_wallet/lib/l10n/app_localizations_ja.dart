// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get signResultSaveFailed =>
      '署名結果を安全に保存できませんでした。送信はしていません。再スキャンしてください。';

  @override
  String get settingsGeneral => '一般';

  @override
  String get generalSettingsDescription =>
      '言語と表示通貨はアプリ全体に適用されます。ウォレットやオンチェーン資産には影響しません。';

  @override
  String get backupThisWallet => 'このウォレットをバックアップ';

  @override
  String get backupScopeDescription =>
      'このウォレットの復元情報のみを保存します。他のウォレット、連絡先、アプリ設定は含まれません。';

  @override
  String get backupEncryptedOptions => '暗号化ファイル・QRコード';

  @override
  String get backupTargetLabel => 'バックアップ対象';

  @override
  String get backupWalletUnavailable =>
      'このウォレットはバックアップできません。ウォレット管理に戻って選び直してください。';

  @override
  String get backupQrTitle => '暗号化QR';

  @override
  String get backupFileFormat => 'バックアップファイル';

  @override
  String get backupQrIntro =>
      'この端末で独自の強いパスワードを使ってリカバリーフレーズを暗号化し、KT WalletのQR画像を作成します。画像に平文のフレーズやパスワードは含まれません。';

  @override
  String get backupQrWarning =>
      '画像の保有者はオフラインでパスワードを推測できます。忘れたパスワードは復元できません。画像とパスワードは別々に保管し、手書きのフレーズも残してください。保存先がクラウドと同期する場合があります。';

  @override
  String get backupQrImageInstruction =>
      'パスワードが必要 · 受取用QRではありません\nKT Walletの「バックアップから復元」で「暗号化QRをスキャン」または「QR画像を選択」を使用してください。画像を公開せず、パスワードは別に保管してください。';

  @override
  String get backupQrGenerate => '暗号化QRを作成';

  @override
  String get backupQrSave => 'QR画像を端末に保存';

  @override
  String get backupQrScan => '暗号化QRをスキャン';

  @override
  String get backupQrPickImage => 'QR画像を選択';

  @override
  String get backupQrScanHint =>
      'KT Walletの暗号化バックアップQRをスキャンしてください。次の画面でパスワードを入力します。';

  @override
  String get backupQrInvalid =>
      '有効な暗号化バックアップQRがありません。QRが1つだけ含まれる元のPNG/JPEG画像を選択してください。';

  @override
  String get backupQrRestoreIntro =>
      '暗号化ファイル、QRスキャン、保存済みQR画像から復元できます。復号はこの端末で行い、バックアップのパスワードが必要です。';

  @override
  String get secretAccessRiskTitle => '表示する前に';

  @override
  String get secretAccessContinue => 'リスクを理解して続ける';

  @override
  String get mnemonicAccessRisk =>
      'リカバリーフレーズでウォレット全体を復元できます。他人に知られると、資産を移動されるおそれがあります。\n\n周囲に人がいない場所で確認し、スクリーンショット・録画・共有はしないでください。';

  @override
  String get privateKeyAccessRisk =>
      '秘密鍵で対応するアカウントを操作できます。他人に知られると、そのアカウントの資産を移動されるおそれがあります。\n\n周囲に人がいない場所で確認し、スクリーンショット・録画・共有はしないでください。';

  @override
  String get tabWallet => 'ウォレット';

  @override
  String get tabActivity => '履歴';

  @override
  String get scanSignedResultNext => 'オフラインで署名済み：結果をスキャン';

  @override
  String backupCheckProgress(int current, int total) {
    return 'バックアップ確認 $current / $total';
  }

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
  String get introRole => '独立したオンラインウォレット';

  @override
  String get introSecurityDescription =>
      '1台で使う場合は、本機に秘密鍵を保管し署名するウォレットを作成できます。送金前にネットワーク・宛先・金額を確認してください。';

  @override
  String get introSecurityNote =>
      '復元フレーズはオフラインで安全に保管。撮影・共有せず、誰に求められても渡さないでください。';

  @override
  String get introPairTitle => 'オンラインで管理。\nオフラインで署名。';

  @override
  String get introPairDescription =>
      '2台で使う場合は、オフライン端末に KT Cold Signer をインストールし、公開アカウントをここに接続します。本機は照会と送信、オフライン端末は確認と署名を担当します。';

  @override
  String get introPairNote =>
      '独立した 2 つのアプリが QR コードで連携。オフライン側の秘密鍵はオンライン端末に入れません。';

  @override
  String get introStart => 'KT Wallet を始める';

  @override
  String get appName => 'KT Wallet';

  @override
  String get appTagline => '二台構成のコールドウォレット・オンライン監視端末';

  @override
  String get actionConfirm => '確認';

  @override
  String get actionCancel => 'キャンセル';

  @override
  String get actionClose => '閉じる';

  @override
  String get actionDelete => '削除';

  @override
  String get pinKeyDelete => '最後の桁を削除';

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
  String get homeSearchHint => '銘柄・アドレス・ネットワークを検索';

  @override
  String get homeCategoryCoins => '銘柄';

  @override
  String get homeCategoryNetworks => 'ネットワーク';

  @override
  String get homeCategoryCustom => 'カスタム';

  @override
  String get homeNoMatchingAssets => '該当する資産がありません';

  @override
  String get homeNoMatchingNetworks => '該当するネットワークがありません';

  @override
  String get walletKindHot => '本機で署名';

  @override
  String get walletKindWatch => 'オフライン署名';

  @override
  String get walletStateBackedUp => 'バックアップ済み';

  @override
  String get walletStateNotBackedUp => '未バックアップ';

  @override
  String get walletStateColdSigner => 'KT Cold Signer';

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
  String get backupBannerText => 'リカバリーフレーズは未バックアップです';

  @override
  String get backupNow => '今すぐバックアップ';

  @override
  String get walletAddressesTitle => 'アカウントアドレス';

  @override
  String get walletAddressSearchHint => 'ネットワークまたはアドレスを検索';

  @override
  String get balanceChangePeriod => '1日';

  @override
  String get marketUpdating => '残高を更新中…';

  @override
  String get marketCachedJustNow => 'たった今確認済み';

  @override
  String marketCachedMinutes(int count) {
    return '$count 分前に確認済み';
  }

  @override
  String marketCachedHours(int count) {
    return '$count 時間前に確認済み';
  }

  @override
  String get marketCachedStale => '一部の資産データを更新できませんでした。保存済みの値がある項目は前回の値を表示します。';

  @override
  String get marketRefreshing => 'このウォレットの資産を更新中…';

  @override
  String get marketBalancesIncomplete =>
      '一部の残高を更新できませんでした。保存済みの残高がある項目は前回の値を表示します。';

  @override
  String get marketPricesIncomplete =>
      '一部の相場を更新できませんでした。評価額に前回の価格を使用している場合があります。';

  @override
  String get historyRefreshing => 'このウォレットの取引履歴を更新中…';

  @override
  String get historyCachedStale => '一部の取引履歴を更新できませんでした。前回保存した履歴を含んでいます。';

  @override
  String get actionReceive => '受取';

  @override
  String get actionSend => '送金';

  @override
  String get actionMore => 'その他';

  @override
  String get actionShare => '共有';

  @override
  String get actionScanSign => '署名スキャン';

  @override
  String get assetsSortByValue => '保有額の高い順';

  @override
  String get assetsHideZero => '残高ゼロを非表示';

  @override
  String get assetsFavoritesOnly => 'お気に入り';

  @override
  String assetAddFavorite(Object symbol) {
    return '$symbolをお気に入りに追加';
  }

  @override
  String assetRemoveFavorite(Object symbol) {
    return '$symbolをお気に入りから削除';
  }

  @override
  String get recordsTitle => '取引履歴';

  @override
  String get recordsWalletTab => 'ウォレット';

  @override
  String get historyTypeFilterTitle => 'タイプで絞り込み';

  @override
  String get historyTypeAll => '全タイプ';

  @override
  String get historyTypeTransfers => '送信/受信';

  @override
  String get historyTypeOther => 'その他';

  @override
  String get historyNetworkFilterTitle => 'ネットワークで絞り込み';

  @override
  String get historyAllNetworks => '全ネットワーク';

  @override
  String get historySent => '送信';

  @override
  String get historyReceived => '受信';

  @override
  String historyFromAddress(String address) {
    return '$address から';
  }

  @override
  String historyToAddress(String address) {
    return '$address へ';
  }

  @override
  String get historyAddressUnavailable => 'アドレスを取得できません';

  @override
  String get historyUnverifiedTokenBadge => '未確認';

  @override
  String get historyLoadMore => 'さらに読み込む';

  @override
  String get historyLoadingMore => '読み込み中…';

  @override
  String get historyNoRecognizedTransactions => '確認済み資産の取引履歴はまだありません';

  @override
  String get historyUnverifiedRecordsTitle => '未検証・リスクトークンの履歴';

  @override
  String get historyUnverifiedRecordsDescription =>
      'メイン履歴から非表示です。操作前にネットワークとコントラクトを確認してください。';

  @override
  String get historyCustomTokenBadge => 'カスタム';

  @override
  String get historyRiskTokenBadge => 'リスク';

  @override
  String get transactionConfirmedNotice => '取引がオンチェーンで確認されました';

  @override
  String get transactionFailedNotice => '取引がオンチェーンで失敗しました';

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
  String get addWalletStandardSection => '本機で署名 · スマートフォン1台';

  @override
  String get createNewWallet => '新規ウォレットを作成';

  @override
  String get createNewWalletDesc => '本機でフレーズを生成し、バックアップ後に使用';

  @override
  String get importMnemonic => 'リカバリーフレーズをインポート';

  @override
  String get importMnemonicDesc => '12 / 18 / 24 単語の既存フレーズ';

  @override
  String get coldWalletSection => 'オフライン署名 · スマートフォン2台';

  @override
  String get connectColdWallet => 'オフラインウォレットを接続';

  @override
  String get connectColdWalletDesc => '公開アカウント情報を取り込み、送金時はオフライン端末で署名';

  @override
  String get createWalletTitle => '本機で署名するウォレットを作成';

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
  String get mnemonicChallengeHint =>
      '手書きの控えを確認してください。抜き取り確認はバックアップ全体の正しさを保証しません。';

  @override
  String get verifyWrong => '選択が違います。手書きバックアップを確認して再試行してください';

  @override
  String walletCreateAuthLocked(int seconds) {
    return 'セキュリティ認証は一時的にロックされています。$seconds 秒後に再試行してください。';
  }

  @override
  String get walletCreateFailed => 'ウォレットの作成を完了できませんでした。もう一度お試しください。';

  @override
  String get walletDeviceAuthUnavailable =>
      'システム認証を利用できません。システム設定で画面ロックの PIN またはパスワードを設定してから再試行してください。設定済みの場合は生体認証を確認するか、しばらくして再試行してください。';

  @override
  String get walletCreatedBackedUp => '作成と抜き取り確認が完了しました。フレーズ全体を安全に保管してください。';

  @override
  String get backupVerified =>
      'バックアップの確認を記録しました。フレーズ全体が順番どおり保存されていることを確認してください。';

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
  String get connectColdSafety =>
      'この監視専用アカウントは公開情報のみを取り込み、オフラインウォレットのフレーズ・秘密鍵・シードを取り込みません。他の本機署名ウォレットは本機に秘密鍵を保管します。';

  @override
  String get scanAccountHint => 'KT Cold SignerのアドレスQRに合わせてください';

  @override
  String get importConfirmTitle => 'インポートを確認';

  @override
  String get createWatchWallet => '監視ウォレットを作成';

  @override
  String get invalidOfflineWalletExport => 'オフラインウォレットのエクスポートデータが無効です';

  @override
  String get offlineWalletAlreadyPaired => 'このオフラインウォレットはすでにペアリングされています';

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
  String get walletDeleteFailed =>
      'ウォレットを安全に削除できませんでした。内容は削除されていません。もう一度お試しください。';

  @override
  String get walletUpdateFailed => '変更を保存できませんでした。内容は変更されていません。もう一度お試しください。';

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
  String get walletIdLabel => 'ウォレット ID';

  @override
  String get coldSignerWalletIdLabel => 'KT Cold Signer ウォレット ID';

  @override
  String get standardWallet => '通常ウォレット';

  @override
  String get backupNotYet => 'リカバリーフレーズが未バックアップです';

  @override
  String get viewMnemonic => 'リカバリーフレーズを表示';

  @override
  String get viewMnemonicDesc => '生体認証またはパスコードが必要です';

  @override
  String get viewPrivateKey => '秘密鍵を表示';

  @override
  String privateKeyWarningProgress(int current, int total) {
    return 'ご注意 $current/$total';
  }

  @override
  String get privateKeyWarningOneTitle =>
      '周囲に人がおらず、カメラや画面収録が動作していないことを確認してください';

  @override
  String get privateKeyWarningOneBody =>
      '秘密鍵を表示する操作を他人に見せないでください。撮影や録画をされると、ウォレットの管理権を永久に失うおそれがあります。';

  @override
  String get privateKeyWarningTwoTitle => 'スクリーンショットや通常のコピーで秘密鍵を保存しないでください';

  @override
  String get privateKeyWarningTwoBody =>
      'コピーすると秘密鍵が一時的にクリップボードへ保存されます。クラウドやメッセージアプリへ送ると盗まれる危険があります。';

  @override
  String get privateKeyWarningThreeTitle => '秘密鍵を持つ人がウォレットを管理できます';

  @override
  String get privateKeyWarningThreeBody =>
      '秘密鍵が漏れると資産を盗まれる可能性があります。秘密鍵を持つ人はウォレットを完全に操作できます。';

  @override
  String get privateKeyAcknowledge => '理解しました';

  @override
  String get privateKeyBackupNow => '今すぐバックアップ';

  @override
  String get privateKeyNotNow => '今回はしない';

  @override
  String privateKeyCountdownButton(String label, int seconds) {
    return '$label（$seconds秒）';
  }

  @override
  String get privateKeyAuthFailed => '認証が完了しなかったため、秘密鍵は表示もコピーもされていません。';

  @override
  String get privateKeyRetryAuth => 'もう一度認証';

  @override
  String get privateKeyEvmNetworks => 'EVM ネットワーク';

  @override
  String get privateKeyPrivacyHint => '周囲の人やカメラから画面が見えないことを確認してください';

  @override
  String get privateKeySecureCopy => '安全にコピー';

  @override
  String get privateKeyFullCopy => 'すべてコピー';

  @override
  String get privateKeySecureCopyTitle => '安全にコピー';

  @override
  String get privateKeySecureCopyBody =>
      '安全のため、末尾6文字を除いた秘密鍵をコピーしました。使用する前に、以下の文字を手動で追加してください。';

  @override
  String get privateKeySecureCopyConfirm => '確認';

  @override
  String get privateKeyFullCopyTitle => 'すべてコピー';

  @override
  String get privateKeyFullCopyBody =>
      '秘密鍵全体がクリップボードに入り、他のアプリに読み取られたり、誤って貼り付けたりするリスクがあります。コピーを続けますか？';

  @override
  String get privateKeyCopyAction => 'コピー';

  @override
  String get privateKeyCopiedSecurely => '安全にコピーしました';

  @override
  String get privateKeyCopiedFully => '秘密鍵全体をコピーしました。60秒後にクリップボードを消去します';

  @override
  String get privateKeySessionExpired => '秘密鍵の表示セッションが期限切れです。もう一度認証してください。';

  @override
  String get privateKeyNoAccounts => 'このウォレットにはエクスポート可能な秘密鍵がありません';

  @override
  String get deleteWalletDesc => '認証が必要です。削除前にバックアップ状態を再確認します';

  @override
  String get amountMustBePositive => '金額は0より大きくしてください';

  @override
  String get insufficientBalance => '残高不足';

  @override
  String insufficientAssetBalance(String symbol) {
    return '残高不足です。$symbol が十分か確認してください';
  }

  @override
  String get amountFormatInvalid => '金額の形式が正しくありません';

  @override
  String get recipientAddress => '受取アドレス';

  @override
  String get pasteOrEnterAddress => 'アドレスを貼り付けまたは入力';

  @override
  String compatibleContactsHint(String network) {
    return '$networkで使用できる連絡先のみ表示しています';
  }

  @override
  String noCompatibleContacts(String network) {
    return '$networkで使用できる連絡先はありません';
  }

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
  String recipientLookalikeWarning(String label) {
    return 'このアドレスは「$label」と先頭・末尾が酷似していますが、同一ではありません。クリップボード汚染の可能性があります。';
  }

  @override
  String get recipientLookalikeReview => 'アドレス全体を確認しました';

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
  String get expectedAssetChanges => '予想される資産変動';

  @override
  String outgoingAsset(String symbol) {
    return '$symbol を送信';
  }

  @override
  String get maximumNetworkFee => 'ネットワーク手数料の上限';

  @override
  String get networkFeeEstimate => 'ネットワーク手数料の見積もり';

  @override
  String upToNegativeAmount(String amount) {
    return '最大 -$amount';
  }

  @override
  String get solanaRentReserve => '回収可能なアカウント準備金';

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
  String get transactionSourceAddress => '送信元アドレス';

  @override
  String get transactionDestinationAccount => '受取アカウント';

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
  String get transactionNotSubmitted => '取引は送信されませんでした。もう一度お試しください。';

  @override
  String get broadcastUnsupported => '選択したネットワークでは、この署名済み取引を送信できません。';

  @override
  String get rpcRejectInsufficientFunds => '送金額と最大ネットワーク手数料を支払うための残高が不足しています。';

  @override
  String get rpcRejectNonceTooLow => '取引nonceが低すぎます。更新してからもう一度お試しください。';

  @override
  String get rpcRejectNonceTooHigh => '取引nonceが高すぎます。更新してからもう一度お試しください。';

  @override
  String get rpcRejectReplacementFeeTooLow => '置換取引のネットワーク手数料が低すぎます。';

  @override
  String get rpcRejectFeeTooLow => 'ネットワーク手数料が低すぎます。';

  @override
  String get rpcRejectGasLimitTooLow => '取引のGas Limitが低すぎます。';

  @override
  String get rpcRejectBlockGasLimit => '取引がネットワークのブロックGas上限を超えています。';

  @override
  String get rpcRejectFeeCapBelowBase => '手数料上限が現在のネットワーク基本手数料を下回っています。';

  @override
  String get rpcRejectAlreadyKnown => 'ネットワークはこの取引をすでに認識しています。再送せず状態を確認してください。';

  @override
  String get rpcRejectExecutionReverted => '取引は実行中にコントラクトによって取り消されました。';

  @override
  String get rpcRejectInvalidSender => '取引の送信元が無効です。';

  @override
  String get rpcRejectExpiredReference => '取引のブロック参照が期限切れです。取引を作り直してください。';

  @override
  String get rpcRejectAccountInUse => '必要なアカウントが使用中です。しばらく待ってからお試しください。';

  @override
  String get rpcRejectSimulationFailed => 'ネットワークが取引シミュレーションを拒否しました。';

  @override
  String get rpcRejectInvalidSignature => '取引署名が無効です。';

  @override
  String get rpcRejectGeneric => 'ネットワークが取引を拒否しました。';

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
  String get txSubmissionUnknown => '送信結果を確認中';

  @override
  String get txSubmissionUnknownMessage =>
      '署名済み取引がネットワークに到達している可能性があります。再送信しないでください。KT Wallet はローカルで算出した取引ハッシュを引き続き確認します。';

  @override
  String transferBroadcastInProgress(String amount, String symbol) {
    return '$amount $symbol を送金中';
  }

  @override
  String transferBroadcastCompleted(String amount, String symbol) {
    return '$amount $symbol を送金済み';
  }

  @override
  String transferBroadcastFailed(String amount, String symbol) {
    return '$amount $symbol の送金に失敗';
  }

  @override
  String get transferProcessingState => '処理中';

  @override
  String get transferCompletedState => '完了';

  @override
  String get transferStageProcessing => '処理中';

  @override
  String get transferStageBroadcasting => 'ブロードキャスト中';

  @override
  String get transferStageAwaitingConfirmation => '確認待ち';

  @override
  String get transferStageConfirming => '確認中';

  @override
  String get networkCost => 'ネットワーク手数料';

  @override
  String get submissionTime => '送信日時';

  @override
  String get viewOnBlockchainExplorer => 'ブロックチェーンエクスプローラーで表示';

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
  String get txStatusUnknown => 'ステータスを確認できません';

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
  String get feeAwaitingInput => '未見積もり';

  @override
  String get feeWaitingBalance => '残高不足のため、手数料を見積もれません。';

  @override
  String get feeWaitingRecipient => '有効な受取アドレスを入力すると手数料を見積もります。';

  @override
  String get feeWaitingAmount => '有効な送金額を入力すると手数料を見積もります。';

  @override
  String get feeUnavailable => 'ネットワーク手数料を取得できません';

  @override
  String get feeRateLimited => '手数料サービスが混み合っています。しばらくしてから再試行してください。';

  @override
  String get feeNetworkUnavailable => '手数料サービスに接続できません。通信環境を確認して再試行してください。';

  @override
  String get feeUnavailableHint => 'ネットワーク手数料を見積もれないため、送信できません。';

  @override
  String get tokenRiskChecking => 'トークンの識別情報を確認中…';

  @override
  String get tokenRiskCheckingBody =>
      '署名前に、検証済み一覧と独立した脅威情報を使用して、現在のネットワークと完全なコントラクトアドレスを確認しています。';

  @override
  String get tokenRiskVerifiedTitle => '公式トークンの識別情報を確認済み';

  @override
  String get tokenRiskVerifiedBody =>
      'ネットワークとコントラクトアドレスが運営者の検証済み一覧と一致します。これは識別情報の確認であり、投資の安全性を保証するものではありません。';

  @override
  String get tokenRiskUnsafeTitle => '危険なトークンコントラクトを検出';

  @override
  String get tokenRiskUnsafeBody =>
      '設定済みのセキュリティ情報源が、この完全なコントラクトに明確な悪意の証拠を検出しました。ウォレットを保護するため署名をブロックしました。';

  @override
  String get tokenRiskUnknownTitle => 'トークンのリスクを確認できません';

  @override
  String get tokenRiskUnknownBody =>
      '設定済みの情報源では、このコントラクトの識別情報や安全性を確認できません。続行前に公式情報で完全なアドレスを確認してください。';

  @override
  String get tokenRiskUnavailableTitle => 'トークンのリスクを確認できません';

  @override
  String get tokenRiskUnavailableBody =>
      'リスクサービスを利用できません。KT Wallet はこのコントラクトの安全性を確認できないため、続行前に別の方法で確認してください。';

  @override
  String get tokenRiskBlockedHint => 'このトークンコントラクトは危険と判定されたため送信できません。';

  @override
  String get signRequestBuildFailed => 'オンチェーンの取引パラメータを検証できません。署名は無効です。';

  @override
  String get signRequestSaveFailed =>
      '署名待ち取引を安全に保存できなかったため、署名QRコードは生成されませんでした。戻って再試行してください。';

  @override
  String get transactionSimulationFailed =>
      '取引シミュレーションに失敗したため署名されませんでした。残高、金額、受取先、またはトークンコントラクトを確認してください。';

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
  String get txReplacementPendingLabel => '競合中の置換取引';

  @override
  String get txNotFound => 'ローカル取引記録が見つかりません';

  @override
  String confirming(int received, int total) {
    return '確認中 ($received/$total)';
  }

  @override
  String get txDetailTitle => '取引詳細';

  @override
  String get txBroadcastTime => 'ブロードキャスト時刻';

  @override
  String get txLastStatusCheck => '最終ステータス確認';

  @override
  String get txNotCheckedYet => '未確認';

  @override
  String get txCopyHash => '取引ハッシュをコピー';

  @override
  String get txHashCopied => '取引ハッシュをコピーしました';

  @override
  String get txViewInExplorer => 'ブロックエクスプローラーで表示';

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
  String tokenImpersonationWarning(String symbol) {
    return '⚠️ この資産は $symbol と表示されていますが、コントラクトは KT Wallet が検証した公式 $symbol アドレス一覧にありません。同名またはブリッジ資産の可能性があるため、名前だけで送金しないでください。';
  }

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
  String get multiChainBadge => 'マルチチェーン';

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
  String get receiveExportSubtitle => 'アドレス、ネットワーク、読取可能な受取QRを含みます';

  @override
  String get exportTransactionReceipt => '取引証明をエクスポート';

  @override
  String get exportTransactionReceiptSubtitle => '取引明細とオンチェーン確認用QRを含みます';

  @override
  String get transactionReceiptTitle => 'オンチェーン取引証明';

  @override
  String get transactionReceiptTimeLabel => '取引日時';

  @override
  String get saveReceiptToPhotos => '写真に保存';

  @override
  String get shareReceiptImage => '取引証明画像を共有';

  @override
  String get transactionReceiptSaved => '取引証明を写真に保存しました';

  @override
  String get transactionReceiptDenied => '写真ライブラリへのアクセスが拒否されました';

  @override
  String get transactionReceiptUseShare => 'このOSでは直接保存できません。共有をご利用ください';

  @override
  String get transactionReceiptFailed => '取引証明を作成できませんでした';

  @override
  String get scanToVerifyOnChain => 'スキャンしてブロックエクスプローラーで確認';

  @override
  String get transactionReceiptFooter => 'KT Wallet が生成 · オンチェーンデータが正です';

  @override
  String transactionReceiptSubject(String network) {
    return '$network 取引証明';
  }

  @override
  String get actionCopy => 'アドレスをコピー';

  @override
  String get addressBookTitle => 'アドレス帳';

  @override
  String get localWalletAddresses => 'ローカルウォレットアドレス';

  @override
  String get savedContacts => '保存済みの連絡先';

  @override
  String get localWalletLabel => 'ローカルウォレット';

  @override
  String get currentWalletLabel => '現在のウォレット';

  @override
  String evmNetworksLabel(int count) {
    return 'EVM · $count ネットワーク';
  }

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
  String get searchTokenHint => '名前、シンボル、コントラクトアドレスを検索';

  @override
  String get myTokens => 'マイトークン';

  @override
  String get addedTokenSearchResults => '追加済み';

  @override
  String get popularOfficialTokens => '人気の公式トークン';

  @override
  String get officialTokenSearchResults => '公式トークン';

  @override
  String get officialTokenVerified => 'KT Wallet 公式認証';

  @override
  String get noMatchingTokens => '該当するトークンがありません\\n右上の + からコントラクトで追加できます';

  @override
  String addOfficialToken(String symbol) {
    return '公式 $symbol を追加';
  }

  @override
  String officialTokenAdded(String symbol) {
    return '公式 $symbol を追加しました';
  }

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
  String get fiatUnit => '表示通貨';

  @override
  String get displayLanguage => '表示言語';

  @override
  String get deleteWatchWallet => '監視ウォレットを削除';

  @override
  String get deleteWatchWalletDesc => '公開アドレスとローカル記録のみ削除。資産に影響はありません';

  @override
  String get languageSystem => 'システムに従う';

  @override
  String get walletLoadErrorTitle => 'ウォレットを読み込めませんでした';

  @override
  String get walletLoadErrorDesc =>
      '端末内のウォレットデータを読み取れませんでした。もう一度お試しください。問題が続く場合も、未バックアップのウォレットを失わないよう、アプリとデータを削除しないでください。';

  @override
  String get pendingDeletionAuthTitle => '削除が完了していません';

  @override
  String get pendingDeletionAuthDesc =>
      '前回のウォレット削除には端末の本人認証が必要です。未完了の削除は保留されており、安全なストレージの破損を示すものではありません。準備ができたら認証して削除を続けてください。認証が利用できない、またはロックされている場合は、しばらく待つか端末の画面ロック設定をご確認ください。';

  @override
  String get pendingDeletionAuthAction => '認証して削除を続ける';

  @override
  String get walletPersistenceFailed =>
      'ウォレットを安全に保存できなかったため、追加されませんでした。もう一度お試しください。';

  @override
  String get walletAlreadyExists => 'このウォレットはすでにこの端末にあります。';

  @override
  String get cryptoUnavailableTitle => 'ウォレットエンジンを利用できません';

  @override
  String get cryptoUnavailableDesc =>
      'この Android ビルドには Trust Wallet Core が含まれていません。Wallet Core 対応ビルドをインストールしてください。模擬鍵へ自動的に切り替わることはありません。';

  @override
  String get secureStorageUnavailableTitle => 'セキュアストレージを利用できません';

  @override
  String get secureStorageUnavailableDesc =>
      'KT WalletはPINとロック状態を安全に読み取れないため、ウォレットをロックしたままにします。アプリを再起動するか、信頼できる配布元から再インストールしてください。';

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
  String get marketOfflineDemo => '資産データを一時的に取得できません。しばらくしてから再試行してください。';

  @override
  String get actionDone => '完了';

  @override
  String get historyUnsupportedChain => 'このチェーンでは履歴照会はまだ利用できません';

  @override
  String get historyEmpty => '取引履歴はまだありません';

  @override
  String get historyEmptyDescription =>
      '取引履歴がここに表示されます。\n下に引いて更新するか、絞り込みを変更してください。';

  @override
  String get transferPaste => '貼り付け';

  @override
  String get transferScan => 'スキャン';

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
  String get changeWalletPin => 'ウォレットPINを変更';

  @override
  String get changeWalletPinDesc => '6桁のPINを変更する前に現在の本人確認が必要です';

  @override
  String get enterCurrentPin => '現在のウォレットPINを入力';

  @override
  String get walletPinChanged => 'ウォレットPINを変更しました';

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
  String get endpointUrlInvalid =>
      '認証情報を含まない有効な HTTPS URL を入力してください。HTTP は localhost のみ使用できます。';

  @override
  String chainIdMismatch(Object actual) {
    return 'Chain ID が一致しません：ノードは $actual を返しました';
  }

  @override
  String transferNetworkUnavailable(String network) {
    return '$network で使用できるアクティブなネットワークがありません。';
  }

  @override
  String get transferChainIdUnavailable => '選択した EVM ネットワークに Chain ID がありません。';

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
    return 'エアドロップ失敗：$message';
  }

  @override
  String get airdropRateLimited => 'リクエストが多すぎます。しばらくしてから再試行してください';

  @override
  String get airdropUnavailable => 'テストコインサービスは一時的に利用できません';

  @override
  String get airdropInvalidRequest => 'フォーセットがこのアドレスまたはリクエストを拒否しました';

  @override
  String get airdropInsufficientFunds => 'フォーセットのテストコイン残高が不足しています';

  @override
  String get airdropRejected => 'フォーセットがリクエストを拒否しました';

  @override
  String get airdropMalformedResponse => 'テストコインサービスから無効な応答が返されました';

  @override
  String get fiatHiddenTestnet => 'テストネット資産には市場価格がありません';

  @override
  String get backupEncryptedTitle => '暗号化バックアップ';

  @override
  String get backupEncryptedRow => '暗号化バックアップ';

  @override
  String get backupEncryptedRowDesc => '強いパスワードで暗号化ファイルやQR画像を保存';

  @override
  String get backupIntro =>
      'バックアップは設定したパスワードで暗号化されます。ファイルとパスワードの両方を持つ人はこのウォレットを操作できます。';

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
  String get backupPasswordWarning =>
      '他で使っていない長いパスフレーズを設定してください。このパスワードは復元できず、失うとバックアップを開けません。手書きのリカバリーフレーズも保管してください。';

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
  String get restoreFromBackupDesc => 'ファイル、QRスキャン、QR画像から復元';

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
  String get restoreFileTooLarge => 'このファイルは KT ウォレットのバックアップとして大きすぎます';

  @override
  String get restoreFileUnavailable => 'この端末ではバックアップファイルを開けません';

  @override
  String get restoreFileReadFailed => '選択したファイルを読み込めませんでした。もう一度お試しください';

  @override
  String get restoreSelectedFileFallback => 'バックアップファイル';

  @override
  String get restoreRestored => 'ウォレットを復元しました';

  @override
  String get restoreAction => '復元';

  @override
  String backupFileChosen(String name) {
    return '選択済み：$name';
  }

  @override
  String get settingsAbout => 'このアプリについて';

  @override
  String get aboutTitle => 'このアプリについて';

  @override
  String get aboutVersion => 'バージョン';

  @override
  String get aboutOpenSource => 'ソースコード';

  @override
  String get aboutOpenSourceDesc => '鍵を預けるコードは検証できます';

  @override
  String get aboutTagline => 'エアギャップウォレット。鍵が端末を離れることはありません。';

  @override
  String get aboutCopiedLink => 'リンクをコピーしました';

  @override
  String get aboutTrustTitle => '信頼と法的情報';

  @override
  String get aboutPrivacyPolicy => 'プライバシーポリシー';

  @override
  String get aboutPrivacyPolicyDesc => 'アプリが処理・送信するデータを確認';

  @override
  String get aboutSecurityRisk => 'セキュリティとリスク';

  @override
  String get aboutSecurityRiskDesc => '現在の保証、既知の制限、利用範囲';

  @override
  String get aboutSecurityPolicy => 'セキュリティポリシー';

  @override
  String get aboutSecurityPolicyDesc => '対象範囲、安全な調査、対応目標';

  @override
  String get aboutThirdPartyNotices => 'オープンソース通知';

  @override
  String get aboutThirdPartyNoticesDesc => '同梱する依存関係のライセンス';

  @override
  String get aboutReportSecurity => 'セキュリティ問題を報告';

  @override
  String get aboutReportSecurityDesc => '非公開報告の手順と機密情報の扱いを確認';

  @override
  String get aboutNeverShareSecrets => 'KT Wallet がリカバリーフレーズや秘密鍵を求めることはありません。';

  @override
  String get diagnosticsTitle => 'サポート診断';

  @override
  String get diagnosticsSubtitle => '問題調査用のプライバシー保護 JSON を書き出します';

  @override
  String get diagnosticsConfirmTitle => '診断パッケージを書き出しますか？';

  @override
  String get diagnosticsConfirmBody => '共有前に、含まれる情報と除外される情報を確認してください。';

  @override
  String get diagnosticsIncludesTitle => '含まれる情報';

  @override
  String get diagnosticsIncludesBody => 'App とビルド、ネットワークモード、サービス状態、集計パフォーマンス';

  @override
  String get diagnosticsExcludesTitle => '含まれない情報';

  @override
  String get diagnosticsExcludesBody =>
      'アドレス、残高、金額、取引、鍵、署名、リカバリーフレーズ、エンドポイント URL';

  @override
  String get diagnosticsExportAction => '書き出して共有';

  @override
  String get diagnosticsShareSubject => 'KT Wallet サポート診断';

  @override
  String get diagnosticsShareText =>
      '匿名化された KT Wallet の診断情報です。共有前にファイルを確認してください。';

  @override
  String get diagnosticsReady => '診断パッケージを準備しました';

  @override
  String get diagnosticsFailed => '診断パッケージを作成できませんでした';

  @override
  String get diagnosticsUploadTitle => '匿名パフォーマンスレポートを送信';

  @override
  String get diagnosticsUploadSubtitle =>
      '確認後に固定集計指標を一度だけ送信します。バックグラウンド送信は行いません';

  @override
  String get diagnosticsUploadConfirmTitle => '匿名パフォーマンスレポートを送信しますか？';

  @override
  String get diagnosticsUploadConfirmBody =>
      'ユーザーが開始する一回限りの送信です。バックグラウンドで自動送信せず、自動再試行も行いません。サーバーには匿名集計のみを 7 日間保持します。';

  @override
  String get diagnosticsUploadIncludesBody =>
      'App バージョン、プラットフォーム、おおまかな言語、ビルドモード、固定性能項目の件数・成否・P50/P95';

  @override
  String get diagnosticsUploadExcludesBody =>
      'ウォレット・端末 ID、アドレス、残高、金額、取引、txHash、時刻、エラー本文、スタック、鍵、署名、リカバリーフレーズ、エンドポイント URL';

  @override
  String get diagnosticsUploadAction => '同意して送信';

  @override
  String get diagnosticsUploadSent => '匿名パフォーマンスレポートを送信しました';

  @override
  String get diagnosticsUploadAlreadySent => '同じ匿名レポートは送信済みです';

  @override
  String get diagnosticsUploadNoSamples => '送信できるパフォーマンスサンプルはまだありません';

  @override
  String get diagnosticsUploadFailed => '匿名レポートを送信できませんでした。自動再試行はしていません';

  @override
  String get diagnosticsUploadGatewayRequired =>
      'ダイレクトモードでは診断を送信しません。先に KT Gateway を有効にしてください';

  @override
  String get settingsApprovals => 'トークン承認';

  @override
  String get approvalsTitle => 'トークン承認';

  @override
  String get approvalsSubtitle => 'ERC-20 トークンを使用できるコントラクトを確認します';

  @override
  String get approvalPrivacyTitle => '外部承認スキャン';

  @override
  String get approvalPrivacyBody =>
      '未解除の承認を調べるため、KT Wallet は設定済み Gateway を通じて、このウォレットの公開アドレスと選択中のメインネットを GoPlus に送信します。鍵、残高、取引内容は送信しません。いつでも無効にできます。';

  @override
  String get approvalEnableAndScan => '許可してスキャン';

  @override
  String get approvalDisableScan => '外部スキャンを無効化';

  @override
  String get approvalScanAgain => '再スキャン';

  @override
  String get approvalLoading => '未解除の承認を確認中…';

  @override
  String get approvalEmptyTitle => '未解除の承認は見つかりませんでした';

  @override
  String get approvalEmptyBody =>
      'プロバイダーはスキャンを完了し、選択したネットワークでこのウォレットの ERC-20 allowance はありませんでした。';

  @override
  String get approvalUnavailableTitle => '承認状態を取得できません';

  @override
  String get approvalUnavailableBody =>
      'スキャンが完了しませんでした。承認一覧は不明であり、空という意味ではありません。';

  @override
  String get approvalUnsupportedTitle => 'このネットワークは未対応です';

  @override
  String get approvalUnsupportedBody =>
      '承認スキャンは現在、Ethereum、Polygon、Base、Arbitrum、BNB Smart Chain のメインネットのみ対応しています。';

  @override
  String get approvalUnlimited => '無制限の承認';

  @override
  String approvalAmount(String amount) {
    return '承認額：$amount';
  }

  @override
  String get approvalSpender => '使用権限を持つコントラクト';

  @override
  String get approvalTokenContract => 'トークンコントラクト';

  @override
  String get approvalApprovedAt => '最終変更';

  @override
  String get approvalRisky => 'リスク信号を検出';

  @override
  String get approvalIdentityUnknown => '安全性は未確認';

  @override
  String get approvalKnownSpender => 'プロバイダー既知タグ';

  @override
  String get approvalReadOnlyNotice =>
      'ホットウォレットは厳密なゼロ allowance 取引を端末内で送信します。監視ウォレットはペアリング済み KT Cold Signer との QR 往復署名を使用します。';

  @override
  String get approvalPrivacyEnabled => 'この端末では外部承認スキャンが有効です';

  @override
  String get approvalNoWallet => 'ウォレットを選択して承認を確認してください';

  @override
  String get approvalRevoke => '承認を解除';

  @override
  String get approvalRevokeTitle => 'このトークン承認を解除しますか？';

  @override
  String get approvalRevokeBody =>
      'KT Wallet はトークンコントラクトへ approve(spender, 0) を送信します。allowance のみを変更し、トークンは送金しません。';

  @override
  String get approvalRevokeConfirm => '認証して解除';

  @override
  String get approvalRevokePreparing => '正確な解除取引をシミュレーションし、最大手数料を見積もっています…';

  @override
  String approvalRevokeMaximumFee(String fee) {
    return '最大ネットワーク手数料：$fee';
  }

  @override
  String get approvalRevokeSubmitted =>
      '解除取引を送信しました。チェーンで確認されるまで Pending のままです。';

  @override
  String get approvalRevokePending => '承認解除は確認待ちです';

  @override
  String get approvalRevokeFailed => '解除取引は送信されませんでした。解除済みとして表示しません。';

  @override
  String get approvalRevokeAuthFailed => '認証が完了しなかったため、署名していません。';

  @override
  String get approvalRevokeHotOnly => 'この承認解除に使用できる署名対応ウォレットがありません。';

  @override
  String get tronAccountStatus => 'TRON アカウント状態';

  @override
  String get tronActivationChecking => '確認中';

  @override
  String get tronActivated => '有効化済み';

  @override
  String get tronUnactivated => '未有効化';

  @override
  String get tronActivationUnknown => '状態不明';

  @override
  String get tronActivationRequiredHint =>
      'この TRON アドレスはまだ有効化されていません。TRC-20 資産の受取・表示はできますが、取引は開始できません。まずこのアドレスへ TRX を送ってオンチェーンで有効化し、ネットワーク手数料分の TRX も確保してください。';
}
