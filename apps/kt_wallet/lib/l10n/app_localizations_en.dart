// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTagline => 'Dual-device cold wallet · online watch client';

  @override
  String get actionConfirm => 'Confirm';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionNext => 'Next';

  @override
  String get actionImport => 'Import';

  @override
  String get manage => 'Manage';

  @override
  String get viewAll => 'All';

  @override
  String get max => 'Max';

  @override
  String get tabHome => 'Home';

  @override
  String get tabAssets => 'Assets';

  @override
  String get tabRecords => 'Activity';

  @override
  String get tabSettings => 'Settings';

  @override
  String get walletKindHot => 'Standard';

  @override
  String get walletKindWatch => 'Watch';

  @override
  String get walletStateBackedUp => 'Backed up';

  @override
  String get walletStateNotBackedUp => 'Not backed up';

  @override
  String get walletSeedDaily => 'Daily Wallet';

  @override
  String get walletSeedMain => 'Main Wallet';

  @override
  String walletDefaultName(int index) {
    return 'Wallet $index';
  }

  @override
  String walletImportedName(int index) {
    return 'Imported Wallet $index';
  }

  @override
  String get backupBannerText => 'Recovery phrase not backed up — risk of loss';

  @override
  String get backupNow => 'Back up now';

  @override
  String get balanceTitle => 'Total value (USD)';

  @override
  String get balanceChangePeriod => 'past 24h';

  @override
  String get actionReceive => 'Receive';

  @override
  String get actionSend => 'Send';

  @override
  String get actionMore => 'More';

  @override
  String get actionScanSign => 'Scan signature';

  @override
  String get assetsSortByValue => 'Sorted by holding value';

  @override
  String get recordsTitle => 'Transactions';

  @override
  String get txSent => 'Sent';

  @override
  String get txReceived => 'Received';

  @override
  String get dateToday => 'Today';

  @override
  String get dateYesterday => 'Yesterday';

  @override
  String monthDay(int month, int day) {
    return '$month/$day';
  }

  @override
  String get settingsWalletManage => 'Wallet management';

  @override
  String get settingsSecurity => 'Security';

  @override
  String get settingsAddressBook => 'Address book';

  @override
  String get settingsNetwork => 'Networks';

  @override
  String get settingsTokenManage => 'Token management';

  @override
  String get addWalletTitle => 'Add wallet';

  @override
  String get addWalletStandardSection => 'Standard wallet · convenient';

  @override
  String get createNewWallet => 'Create new wallet';

  @override
  String get createNewWalletDesc =>
      'Generate a new recovery phrase on this device, ready to use';

  @override
  String get importMnemonic => 'Import recovery phrase';

  @override
  String get importMnemonicDesc => 'An existing 12 / 18 / 24-word phrase';

  @override
  String get coldWalletSection => 'Offline wallet pair · high security';

  @override
  String get connectColdWallet => 'Connect offline wallet';

  @override
  String get connectColdWalletDesc =>
      'Pair Cold Signer by QR; private keys never touch this device';

  @override
  String get createWalletTitle => 'Create standard wallet';

  @override
  String get showMnemonic => 'Show recovery phrase';

  @override
  String get mnemonicWillGenerate => 'A recovery phrase will be generated next';

  @override
  String get hotWalletNotice =>
      'This is a hot wallet: the recovery phrase is stored in this device\'s secure enclave. Good for small daily amounts; use an offline wallet pair for larger holdings.';

  @override
  String get ruleFullControlTitle =>
      'The phrase is full control of your assets';

  @override
  String get ruleFullControlDesc =>
      'Anyone with these 12 words can move all your assets';

  @override
  String get ruleHandwriteTitle => 'Back up by hand on paper only';

  @override
  String get ruleHandwriteDesc =>
      'Don\'t save it to photos, cloud, notes, or chat apps';

  @override
  String get backupMnemonicTitle => 'Back up recovery phrase';

  @override
  String get mnemonicShowConfirmBtn => 'I\'ve written it down — verify';

  @override
  String get mnemonicShowWarning =>
      'Copy it by hand in order. Don\'t screenshot or photograph it. Anyone with the phrase controls your assets.';

  @override
  String get verifyBackupTitle => 'Verify backup';

  @override
  String mnemonicWordChallenge(int position) {
    return 'What is word $position?';
  }

  @override
  String get mnemonicChallengeHint => 'Pick the correct word below';

  @override
  String get verifyWrong =>
      'Wrong choice — check your written backup and try again';

  @override
  String get walletCreatedBackedUp => 'Wallet created and backed up';

  @override
  String get backupVerified => 'Backup verified — your phrase is correct';

  @override
  String get mnemonicInvalid =>
      'Invalid recovery phrase — check each word and try again';

  @override
  String get mnemonicImported => 'Recovery phrase imported';

  @override
  String wordsCount(int count) {
    return '$count words';
  }

  @override
  String get pasteMnemonic => 'Paste phrase (clipboard cleared after parsing)';

  @override
  String get scanAccountQr => 'Scan account QR';

  @override
  String get connectColdSubtitle =>
      'Import public addresses from the offline phone to create a watch wallet';

  @override
  String get connectColdSafety =>
      'This device never receives or stores a phrase, private key, or seed.';

  @override
  String get scanAccountHint => 'Aim at the Cold Signer address QR';

  @override
  String get importConfirmTitle => 'Confirm import';

  @override
  String get createWatchWallet => 'Create watch wallet';

  @override
  String walletIdProtocol(String id, int version) {
    return 'Wallet ID: $id · protocol v$version';
  }

  @override
  String get walletsTitle => 'Wallets';

  @override
  String get deleteWalletTitle => 'Delete wallet';

  @override
  String deleteWalletConfirm(String name) {
    return 'Delete “$name”? This only removes the local record; on-chain assets are unaffected.';
  }

  @override
  String deletedWallet(String name) {
    return 'Deleted “$name”';
  }

  @override
  String get sortAction => 'Reorder';

  @override
  String walletCountLimit(int count, int max) {
    return '$count wallets · limit $max';
  }

  @override
  String get walletDetailTitle => 'Wallet details';

  @override
  String get walletTypeLabel => 'Wallet type';

  @override
  String get standardWallet => 'Standard wallet';

  @override
  String get backupNotYet => 'Recovery phrase not backed up yet';

  @override
  String get viewMnemonic => 'View recovery phrase';

  @override
  String get viewMnemonicDesc => 'Requires Face ID or passcode';

  @override
  String get deleteWalletDesc =>
      'Requires authentication; backup status is reconfirmed before deletion';

  @override
  String get amountMustBePositive => 'Amount must be greater than 0';

  @override
  String get insufficientBalance => 'Insufficient balance';

  @override
  String get amountFormatInvalid => 'Invalid amount format';

  @override
  String get recipientAddress => 'Recipient address';

  @override
  String get pasteOrEnterAddress => 'Paste or enter address';

  @override
  String enterChainAddress(String network) {
    return 'Enter a $network network recipient address';
  }

  @override
  String addressValidOn(String network) {
    return 'Valid address · $network network';
  }

  @override
  String get addressInvalid => 'Invalid address';

  @override
  String get amountLabel => 'Amount';

  @override
  String availableBalance(String amount, String symbol) {
    return '$amount $symbol available';
  }

  @override
  String get selectAsset => 'Select asset';

  @override
  String get scanAddressTitle => 'Scan address QR';

  @override
  String get scanAddressHint => 'Aim at the recipient address QR';

  @override
  String get networkFee => 'Network fee';

  @override
  String get feeCustom => 'Custom';

  @override
  String get feeSlow => 'Slow';

  @override
  String get feeStandard => 'Standard';

  @override
  String get feeFast => 'Fast';

  @override
  String get confirmFee => 'Confirm fee';

  @override
  String get feeExplainer =>
      'Higher fees confirm faster. Fees go to the network, not this app.';

  @override
  String get feeEtaSlow => '≈ 3–5 min';

  @override
  String get feeEtaStandard => '≈ 1 min';

  @override
  String get feeEtaFast => '≈ 15 sec';

  @override
  String get feeLowWarning =>
      'A fee that\'s too low may leave the transaction unconfirmed for a long time or fail. When TRON Energy is insufficient, TRX is burned to cover it.';

  @override
  String get confirmTransactionTitle => 'Confirm transaction';

  @override
  String get confirmTransfer => 'Confirm transfer';

  @override
  String get generateSignQr => 'Generate signing QR';

  @override
  String get hotConfirmHint =>
      'After authentication, this device signs and broadcasts automatically';

  @override
  String get watchConfirmHint => 'The QR contains no phrase or private key';

  @override
  String get fromAddress => 'From';

  @override
  String get totalSpend => 'Total spend';

  @override
  String get unbackedTransferWarning =>
      'This wallet\'s recovery phrase isn\'t backed up. Back it up before sending.';

  @override
  String get pendingSignTitle => 'Pending signature';

  @override
  String dynamicShard(int received, int total) {
    return 'Dynamic shard $received / $total';
  }

  @override
  String get networkRow => 'Network';

  @override
  String get requestId => 'Request ID';

  @override
  String get scanWithOfflinePhone =>
      'Scan this QR with the offline signing phone';

  @override
  String get scanSignResultTitle => 'Scan signing result';

  @override
  String recognizedShard(int received, int total) {
    return 'Recognized shard $received / $total';
  }

  @override
  String get broadcastTitle => 'Broadcast transaction';

  @override
  String get dontBroadcastYet => 'Not yet';

  @override
  String get signatureVerified =>
      'Signature verified · signer matches the wallet address; contents untampered';

  @override
  String get signerAddress => 'Signer address';

  @override
  String get txHashPreview => 'Tx hash preview';

  @override
  String get backToHome => 'Back to home';

  @override
  String get txSubmitted => 'Transaction submitted';

  @override
  String get txHash => 'Tx hash';

  @override
  String get statusLabel => 'Status';

  @override
  String confirming(int received, int total) {
    return 'Confirming ($received/$total)';
  }

  @override
  String get txDetailTitle => 'Transaction details';

  @override
  String get confirmedPrefix => 'Confirmed';

  @override
  String get confirmations => 'Confirmations';

  @override
  String get authToConfirmTransfer => 'Authenticate to confirm';

  @override
  String get authEveryTransfer =>
      'Every transfer requires Face ID or a passcode';

  @override
  String get useFaceId => 'Use Face ID';

  @override
  String get usePasscode => 'Use passcode instead';

  @override
  String get biometricFailedRetry => 'Authentication failed. Try again.';

  @override
  String get searchAssetHint => 'Search name / symbol / contract';

  @override
  String get price => 'Price';

  @override
  String get change24h => '24h change';

  @override
  String get contractAddress => 'Contract';

  @override
  String get receiveWarning =>
      'Only TRON network (TRC-20) assets are supported. Sending from other networks will lose funds.';

  @override
  String get explorerLinkCopied => 'Block explorer link copied';

  @override
  String get addressCopied => 'Address copied';

  @override
  String get addressBookTitle => 'Address book';

  @override
  String get searchNameOrAddress => 'Search name or address';

  @override
  String get noMatchingContacts => 'No matching contacts';

  @override
  String get contactBobExchange => 'Bob Exchange';

  @override
  String get contactColdBackup => 'Cold wallet backup';

  @override
  String get addContactTitle => 'Add contact';

  @override
  String get nameLabel => 'Name';

  @override
  String get addressLabel => 'Address';

  @override
  String get invalidChainAddress => 'Not a valid chain address';

  @override
  String get actionSave => 'Save';

  @override
  String get tokenManageTitle => 'Token management';

  @override
  String get addTokenTitle => 'Add token';

  @override
  String get tokenSymbolLabel => 'Symbol';

  @override
  String get networkSettingsTitle => 'Network settings';

  @override
  String get rpcTimeout => 'Timeout';

  @override
  String get rpcNode => 'RPC node';

  @override
  String get networkResetDefault => 'Reset to default';

  @override
  String get accessControl => 'Access control';

  @override
  String get appLock => 'App lock';

  @override
  String get appLockDesc => 'Require Face ID to open the app';

  @override
  String get autoLock => 'Auto-lock';

  @override
  String get autoLockDesc => 'Re-lock after a background timeout';

  @override
  String get autoLockValue => '1 min';

  @override
  String get privacyMode => 'Privacy mode';

  @override
  String get privacyModeDesc => 'Hide balances on home by default';

  @override
  String get dataSection => 'Data';

  @override
  String get fiatUnit => 'Fiat currency';

  @override
  String get displayLanguage => 'Language';

  @override
  String get deleteWatchWallet => 'Delete watch wallet';

  @override
  String get deleteWatchWalletDesc =>
      'Removes only public addresses and local records; assets unaffected';

  @override
  String get languageSystem => 'System default';

  @override
  String get modeSelectTitle => 'Choose device mode';

  @override
  String get modeSelectSubtitle =>
      'Before first use, decide this phone\'s role';

  @override
  String get modeWalletTitle => 'Online Wallet';

  @override
  String get modeWalletDesc =>
      'Everyday use: check balances and send transfers';

  @override
  String get modeSignerTitle => 'Offline Signer';

  @override
  String get modeSignerDesc =>
      'Install on a phone that never goes online; keeps keys offline and signs transactions';

  @override
  String get modeSignerConfirmTitle => 'Enable offline signer';

  @override
  String get modeSignerConfirmBody =>
      'This mode is for an offline device. Turn on airplane mode and keep this device permanently offline.';

  @override
  String get deviceMode => 'Device mode';

  @override
  String get deviceModeSwitchTitle => 'Switch device mode';

  @override
  String get deviceModeSwitchDesc =>
      'You will return to the mode selection screen.';

  @override
  String get walletLoadErrorTitle => 'Couldn\'t load wallets';

  @override
  String get walletLoadErrorDesc =>
      'Your on-device wallet data couldn\'t be read. Try again; if the problem persists, reinstall the app.';

  @override
  String get actionRetry => 'Retry';

  @override
  String get renameWallet => 'Rename wallet';

  @override
  String get backupTranscribed => 'I have written it down';

  @override
  String receiveWarningFor(String network) {
    return 'Only $network network assets are supported. Sending from other networks will lose funds.';
  }

  @override
  String get autoLockImmediate => 'Immediately';

  @override
  String autoLockMinutesLabel(int minutes) {
    return '$minutes min';
  }

  @override
  String get copyAddress => 'Copy address';

  @override
  String get noMatchingAssets => 'No matching assets';

  @override
  String get noWatchWallet => 'No watch wallet on this device';

  @override
  String get watchWalletCreated => 'Watch wallet created';

  @override
  String get marketOfflineDemo => 'Offline — showing demo data';

  @override
  String get actionDone => 'Done';

  @override
  String get historyUnsupportedChain =>
      'History lookup isn\'t available on this chain yet';

  @override
  String get historyEmpty => 'No transactions yet';

  @override
  String get setPinTitle => 'Set unlock PIN';

  @override
  String get setPinPrompt => 'Set a 6-digit PIN';

  @override
  String get setPinConfirmPrompt => 'Enter again to confirm';

  @override
  String get setPinDesc =>
      'Unlocks the app when biometrics are unavailable. The PIN is stored only in this device\'s secure area.';

  @override
  String get pinMismatch => 'The two entries don\'t match — set it again';

  @override
  String get enterPinToUnlock => 'Enter PIN to unlock';

  @override
  String get enterPinToDisable => 'Enter PIN to turn off app lock';

  @override
  String get pinIncorrect => 'Incorrect PIN, try again';

  @override
  String pinLockedRetry(int seconds) {
    return 'Too many attempts. Retry in ${seconds}s';
  }

  @override
  String get usePinUnlock => 'Unlock with PIN';
}
