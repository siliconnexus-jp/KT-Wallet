// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'KT Wallet';

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
      'Pair KT Wallet Cold Signer by QR; private keys never touch this device';

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
  String get mnemonicUnavailableTitle => 'Recovery phrase unavailable';

  @override
  String get mnemonicUnavailableBackup =>
      'This backup flow only applies to a newly created wallet. To back up this wallet, open Wallet details → View recovery phrase.';

  @override
  String get mnemonicAuthRequired =>
      'Authentication is required to show the recovery phrase. Please try again.';

  @override
  String get mnemonicNoKeyMaterial =>
      'No recovery phrase for this wallet is stored on this device.';

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
  String get scanAccountHint => 'Aim at the KT Wallet Cold Signer address QR';

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
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count wallets',
      one: '$count wallet',
    );
    return '$_temp0 · limit $max';
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
  String get viewMnemonicDesc => 'Requires biometrics or passcode';

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
  String get chainParamsFallback =>
      'Couldn\'t fetch on-chain parameters — using preset nonce and fee values';

  @override
  String broadcastFailedMessage(String message) {
    return 'Broadcast failed: $message';
  }

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
  String get txTimeLabel => 'Time';

  @override
  String get txHash => 'Tx hash';

  @override
  String get statusLabel => 'Status';

  @override
  String get txStatusSubmitted => 'Submitted';

  @override
  String get txStatusPending => 'Pending';

  @override
  String get txStatusConfirmed => 'Confirmed';

  @override
  String get txStatusFailed => 'Failed';

  @override
  String get txStatusDropped => 'Dropped';

  @override
  String get txStatusReplaced => 'Replaced';

  @override
  String get nonceConflict =>
      'This nonce is already reserved by another pending transaction. Refresh and try again.';

  @override
  String get txSpeedUp => 'Speed up';

  @override
  String get txCancelTransaction => 'Cancel transaction';

  @override
  String get txReplacementConfirmTitle => 'Confirm replacement';

  @override
  String get txSpeedUpConfirm =>
      'Resend with the same nonce and a higher network fee. The recipient and amount will not change.';

  @override
  String get txCancelConfirm =>
      'Send a zero-value transaction to yourself with the same nonce. The original is cancelled only if this replacement confirms first.';

  @override
  String get txReplacementSubmitted => 'Replacement transaction submitted';

  @override
  String get txReplacementRace =>
      'The replacement was submitted while the original status changed. Wait for the final on-chain result.';

  @override
  String get txNonceAlreadyUsed =>
      'This nonce has already been consumed on-chain and can no longer be replaced.';

  @override
  String get txReplacementUnavailable =>
      'This transaction is missing the chain parameters required for speed-up or cancellation.';

  @override
  String txReplacementWrongNetwork(String network) {
    return 'This transaction belongs to $network. Switch back to that network before speeding it up or cancelling.';
  }

  @override
  String get feeEstimating => 'Estimating…';

  @override
  String get feeUnavailable => 'Network fee unavailable';

  @override
  String get feeUnavailableHint =>
      'The network fee could not be estimated, so sending is disabled.';

  @override
  String get txNonceLabel => 'Nonce';

  @override
  String get txMaxFeeLabel => 'Maximum fee (raw unit)';

  @override
  String get txRawAmountLabel => 'Amount (raw unit)';

  @override
  String get txReplacesLabel => 'Replaces transaction';

  @override
  String get txReplacedByLabel => 'Replaced by transaction';

  @override
  String get txNotFound => 'Local transaction record not found';

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
      'Every transfer requires biometrics or a passcode';

  @override
  String get useFaceId => 'Use biometrics';

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
  String get unverifiedToken => 'Unverified token — check the contract address';

  @override
  String get receiveWarning =>
      'Only TRON network (TRC-20) assets are supported. Sending from other networks will lose funds.';

  @override
  String get explorerLinkCopied => 'Block explorer link copied';

  @override
  String get addressCopied => 'Address copied';

  @override
  String get saveReceiveImage => 'Save receive image';

  @override
  String get privacyOverlayActive => 'KT Wallet Protection is active';

  @override
  String get privacyOverlayHidden => 'Your wallet content is hidden';

  @override
  String get chooseNetwork => 'Choose a network';

  @override
  String assetOnChains(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count chains',
      one: '$count chain',
    );
    return '$_temp0';
  }

  @override
  String get receiveCardTitle => 'Receiving address';

  @override
  String get receiveCardNetwork => 'Network';

  @override
  String get receiveCardGenerated => 'Generated';

  @override
  String get receiveImageSaved => 'Saved to your photos';

  @override
  String get receiveImageDenied => 'Photo library access was declined';

  @override
  String get receiveImageUseShare =>
      'This OS version cannot save directly — use share instead';

  @override
  String get receiveImageFailed => 'Could not create the receive image';

  @override
  String get actionCopy => 'Copy address';

  @override
  String get addressBookTitle => 'Address book';

  @override
  String get searchNameOrAddress => 'Search name or address';

  @override
  String get assetUnavailable => 'This asset is no longer available';

  @override
  String get noMatchingContacts => 'No matching contacts';

  @override
  String get contactsEmpty => 'No contacts yet — tap + to add one';

  @override
  String get tokensEmpty => 'No custom tokens yet — tap + to add one';

  @override
  String get contactBobExchange => 'Bob Exchange';

  @override
  String get contactColdBackup => 'Cold wallet backup';

  @override
  String get editContactTitle => 'Edit contact';

  @override
  String get actionEdit => 'Edit';

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
  String get screenCaptureBlocked => 'Screen recording detected';

  @override
  String get screenCaptureBlockedHint =>
      'Content is hidden to protect your recovery phrase. It returns when the recording or mirroring stops.';

  @override
  String get screenshotWarning =>
      'You just screenshotted your recovery phrase. It is now in your photo library, and anyone who can see that library can take your assets — move them to a new wallet now.';

  @override
  String get rpcMeasuring => 'Measuring…';

  @override
  String get rpcUnreachable => 'Unreachable';

  @override
  String get rpcNotMeasured => '—';

  @override
  String get rpcTimeout => 'Timeout';

  @override
  String get rpcNode => 'RPC node';

  @override
  String get networkResetDefault => 'Reset to default';

  @override
  String get gatewayTitle => 'Gateway';

  @override
  String get gatewayDesc =>
      'Unified query gateway; leave blank to connect directly to each chain\'s node';

  @override
  String get gatewayNotSet => 'Not set';

  @override
  String get gatewayTest => 'Test connection';

  @override
  String get gatewayTestOk => 'Gateway connection succeeded';

  @override
  String get gatewayTestFail => 'Gateway connection failed';

  @override
  String get accessControl => 'Access control';

  @override
  String get appLock => 'App lock';

  @override
  String get appLockDesc => 'Require biometrics to open the app';

  @override
  String get authMethod => 'Authentication method';

  @override
  String get authMethodDesc => 'Used to unlock the app and approve transfers';

  @override
  String get authBiometrics => 'Face ID / Biometrics';

  @override
  String get authBiometricsDesc => 'Fast approval using this device';

  @override
  String get authPassword => 'Wallet password';

  @override
  String get authPasswordDesc => 'Enter your 6-digit wallet password';

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
  String get cryptoUnavailableTitle => 'Wallet engine unavailable';

  @override
  String get cryptoUnavailableDesc =>
      'This Android build does not include Trust Wallet Core. Install a wallet-core-enabled build; simulated keys are never used automatically.';

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
  String get marketOfflineDemo =>
      'Network unavailable — live data could not be loaded';

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

  @override
  String get networkEnvironment => 'Network environment';

  @override
  String get envMainnet => 'Mainnet';

  @override
  String get envTestnet => 'Testnet';

  @override
  String get testnetBadge => 'TESTNET';

  @override
  String get perChainNetwork => 'Per-chain network';

  @override
  String get addNetwork => 'Add network';

  @override
  String get networkNameLabel => 'Network name';

  @override
  String get chainFamilyLabel => 'Chain family';

  @override
  String get chainIdLabel => 'Chain ID';

  @override
  String get explorerLabel => 'Explorer URL (optional)';

  @override
  String get symbolLabel => 'Symbol';

  @override
  String get probeChecking => 'Probing RPC…';

  @override
  String get probeOkSave => 'Probe passed, saved';

  @override
  String get rpcProbeFailed => 'RPC probe failed — check the URL';

  @override
  String chainIdMismatch(Object actual) {
    return 'Chain ID mismatch: node returned $actual';
  }

  @override
  String get deleteNetwork => 'Delete network';

  @override
  String get networkInUse => 'This network is currently in use';

  @override
  String get faucetAction => 'Get test funds';

  @override
  String get faucetOpened => 'Testnet faucet opened';

  @override
  String get externalActionFailed =>
      'Unable to open the external app. Try again.';

  @override
  String shareAddressSubject(String network) {
    return '$network receive address';
  }

  @override
  String get cameraUnavailable =>
      'Camera unavailable. Check permission and try again.';

  @override
  String get biometricUnavailable =>
      'Biometrics unavailable. Use your wallet PIN.';

  @override
  String get airdropRequesting => 'Requesting airdrop…';

  @override
  String get airdropOk => 'Airdrop sent — balance will refresh shortly';

  @override
  String airdropFailed(Object message) {
    return 'Airdrop failed: $message';
  }

  @override
  String get fiatHiddenTestnet => 'Testnet assets have no market price';

  @override
  String get backupEncryptedTitle => 'Encrypted backup';

  @override
  String get backupEncryptedRow => 'Encrypted backup';

  @override
  String get backupEncryptedRowDesc =>
      'Save an encrypted copy to iCloud Drive or Files';

  @override
  String get backupIntro =>
      'The file is encrypted with a password you choose. Anyone who has both the file and the password controls this wallet.';

  @override
  String get backupPasswordLabel => 'Backup password';

  @override
  String get backupPasswordConfirm => 'Repeat the password';

  @override
  String get backupPasswordTooShort => 'At least 8 characters';

  @override
  String get backupPasswordMismatch => 'The two passwords do not match';

  @override
  String get backupPasswordWarning =>
      'There is no way to recover this password. Lose it and the backup is unopenable — keep your written recovery phrase as well.';

  @override
  String get backupCreate => 'Create backup';

  @override
  String get backupSaved => 'Backup saved';

  @override
  String backupSavedTo(String location) {
    return 'Backup saved to $location';
  }

  @override
  String get backupCancelled => 'Backup cancelled';

  @override
  String get backupFailed => 'Could not create the backup';

  @override
  String get backupUnsupported => 'This device cannot save files';

  @override
  String get restoreFromBackup => 'Restore from backup';

  @override
  String get restoreFromBackupDesc => 'Open an encrypted .ktbak file';

  @override
  String get restorePickFile => 'Choose backup file';

  @override
  String get restoreEnterPassword => 'Enter the backup password';

  @override
  String get restoreWrongPassword => 'Wrong password, or the file is damaged';

  @override
  String get restoreNotABackup => 'That is not a KT Wallet backup file';

  @override
  String get restoreTooNew =>
      'This backup was written by a newer version of the app';

  @override
  String get restoreRestored => 'Wallet restored';

  @override
  String get restoreAction => 'Restore';

  @override
  String backupFileChosen(String name) {
    return 'Selected: $name';
  }
}
