// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get qrImportTitle => 'Import encrypted QR';

  @override
  String get qrImportDescription =>
      'Scan a KT Wallet encrypted backup or choose its image from this device. Decryption happens entirely offline.';

  @override
  String get qrImportScan => 'Scan backup QR';

  @override
  String get qrImportImage => 'Choose local QR image';

  @override
  String get qrImportReady => 'Encrypted backup recognized';

  @override
  String get qrImportPassword => 'Backup encryption password';

  @override
  String get qrImportContinue => 'Decrypt and continue';

  @override
  String get qrImportInvalid =>
      'Unable to read this backup. Choose a local PNG/JPEG under 8 MB containing one KT Wallet encrypted backup QR.';

  @override
  String get qrImportWrongPassword =>
      'Incorrect password or damaged backup. Check the password and try again.';

  @override
  String get qrImportSafety =>
      'Keep this device offline. Use the password chosen when exporting the backup, not your wallet PIN. If this phrase has been used on an online device, importing it here does not make it a never-online cold wallet.';

  @override
  String get walletDeviceAuthRequired =>
      'Set up a device screen-lock passcode or biometrics in system settings, then retry. A wallet PIN does not replace device authentication; emulators need this setup too.';

  @override
  String get walletCreationAuthRequired =>
      'Device authentication was not completed. The wallet has not been created. Retry and complete the system prompt.';

  @override
  String get introOpenTitle => '100% open source.\nFront to back.';

  @override
  String get introOpenDescription =>
      'Wallet apps, offline signing and the backend gateway. All source code is open, so trust can be built on what you can inspect.';

  @override
  String get introOpenNote =>
      'Explore the complete source and see how your assets are protected. Open to review. Open to improvement.';

  @override
  String get introSecurityTitle => 'Security first.\nControl stays yours.';

  @override
  String get introFrontend => 'Wallet apps';

  @override
  String get introBackend => 'Backend';

  @override
  String get introOnline => 'Online wallet';

  @override
  String get introOffline => 'Offline signer';

  @override
  String get introNext => 'Continue';

  @override
  String get introSkip => 'Skip intro';

  @override
  String get introBack => 'Back';

  @override
  String get introSource => 'Explore the source code';

  @override
  String get introSourceHint =>
      'Scan with a connected device to explore the full source. This screen makes no network requests.';

  @override
  String get introCopyLink => 'Copy source address';

  @override
  String get introCopied => 'Source address copied';

  @override
  String get introSaveFailed =>
      'Couldn\'t save your progress. Please try again.';

  @override
  String get introRole => 'Independent offline signer';

  @override
  String get introSecurityDescription =>
      'Private keys stay on this offline device. Review transaction details and authenticate for every signature. Keep your recovery phrase backed up offline.';

  @override
  String get introSecurityNote =>
      'Enable airplane mode and turn off Wi-Fi and Bluetooth. Dedicate this phone to signing and keep it offline.';

  @override
  String get introPairTitle => 'Built to sign.\nKept offline.';

  @override
  String get introPairDescription =>
      'Use KT Wallet on a connected phone to prepare a transaction. Scan, review and sign here, then return the signed QR to the online wallet for broadcast.';

  @override
  String get introPairNote =>
      'QR codes carry transactions and signatures, never keys or recovery phrases. This app doesn\'t query balances or broadcast.';

  @override
  String get introStart => 'Set up offline signing';

  @override
  String get appName => 'KT Cold Signer';

  @override
  String get actionConfirm => 'Confirm';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionSave => 'Save';

  @override
  String get actionImport => 'Import';

  @override
  String get actionValidating => 'Validating…';

  @override
  String get cameraUnavailable => 'Camera unavailable';

  @override
  String get done => 'Done';

  @override
  String get later => 'Maybe later';

  @override
  String get splashTagline => 'Dual-device cold wallet · offline signer';

  @override
  String get welcomeSubtitle =>
      'Offline signing · the recovery phrase never goes online';

  @override
  String get welcomeFeatOfflineTitle => 'Fully offline';

  @override
  String get welcomeFeatOfflineDesc =>
      'This device makes no network requests; keep airplane mode on throughout';

  @override
  String get welcomeFeatLocalTitle =>
      'The recovery phrase stays on this device';

  @override
  String get welcomeFeatLocalDesc =>
      'Generated and encrypted on this device; it never reaches the online phone';

  @override
  String get createNewWallet => 'Create new wallet';

  @override
  String get importExistingWallet => 'Import existing wallet';

  @override
  String get securityNoticeTitle => 'Security notice';

  @override
  String get showMnemonic => 'Show recovery phrase';

  @override
  String get mnemonicWillGenerate => 'A recovery phrase will be generated next';

  @override
  String get ruleFullControlTitle =>
      'The phrase is full control of your assets';

  @override
  String get ruleFullControlDesc =>
      'Anyone with these 12 words can restore your wallet on any device and move all your assets';

  @override
  String get ruleHandwriteTitle => 'Back up by hand on paper only';

  @override
  String get ruleHandwriteDesc =>
      'Write two copies and store them separately in safe physical locations';

  @override
  String get ruleNoCaptureTitle =>
      'Never photograph, screenshot, or type it into an online device';

  @override
  String get ruleNoCaptureDesc =>
      'Don\'t save it to photos, cloud, or chat apps; iOS warns after a screenshot, while Android blocks screenshots on recovery-phrase screens';

  @override
  String get backupMnemonicTitle => 'Back up recovery phrase';

  @override
  String get mnemonicShowConfirmBtn => 'I\'ve written it down — verify';

  @override
  String get mnemonicShowInstruction =>
      'Copy the 12 words below by hand in order and store them in a safe physical location.';

  @override
  String get mnemonicShowWarning =>
      'Don\'t screenshot, photograph, or copy it to any online device.';

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
  String get importWalletTitle => 'Import wallet';

  @override
  String get mnemonicInvalidChecksum =>
      'Invalid recovery phrase. Check every word, the word count, and the BIP-39 checksum.';

  @override
  String wordCountOption(int count) {
    return '$count words';
  }

  @override
  String get setPasswordTitle => 'Set unlock password';

  @override
  String get setPasswordPrompt => 'Set a 6-digit password';

  @override
  String get setPasswordConfirmPrompt => 'Enter again to confirm';

  @override
  String get setPasswordDesc =>
      'Used to unlock the app and confirm signing. The password is stored only in this device\'s secure area.';

  @override
  String get passwordMismatch => 'The two entries don\'t match — set it again';

  @override
  String get biometricTitle => 'Biometrics';

  @override
  String get enableFaceId => 'Enable Face ID';

  @override
  String get biometricUnavailable =>
      'No usable biometric or device authentication is set up.';

  @override
  String get walletSecureStorageFailed =>
      'Secure wallet storage failed. No key was saved.';

  @override
  String get secureStorageUnavailableTitle => 'Secure storage unavailable';

  @override
  String get secureStorageUnavailableDesc =>
      'KT Cold Signer cannot safely read wallet, password, or lockout state. Signing remains locked. Restart the app or reinstall it from a trusted source.';

  @override
  String get actionRetry => 'Retry';

  @override
  String get biometricSkip => 'Not now — use password only';

  @override
  String get biometricDesc =>
      'Every signature requires authentication. Face ID makes it faster, and you can switch to the device passcode anytime.';

  @override
  String get exportPublicAddress => 'Export public addresses';

  @override
  String get walletCreated => 'Wallet created';

  @override
  String get mnemonicBackedUpVerified =>
      'Recovery phrase backed up and verified';

  @override
  String get walletNameLabel => 'Wallet name';

  @override
  String get walletMainName => 'Main Wallet';

  @override
  String get mnemonicBackupLabel => 'Phrase backup';

  @override
  String get verified => 'Verified';

  @override
  String get supportedNetworks => 'Supported networks';

  @override
  String offlineForDays(int days) {
    return 'Offline for $days days';
  }

  @override
  String get securityCheckPassed => 'Security check passed · airplane mode on';

  @override
  String get offlineStatusConfirmed => 'Network offline';

  @override
  String get offlineStatusConnected => 'Network connection detected';

  @override
  String get offlineStatusUnknown => 'Network status unavailable';

  @override
  String get scanPendingTx => 'Scan pending transaction';

  @override
  String get scanPendingTxDesc => 'Scan the dynamic QR from the online wallet';

  @override
  String get exportAddress => 'Address QR';

  @override
  String get signRecords => 'Signing records';

  @override
  String get securityCheck => 'Security check';

  @override
  String get walletManage => 'Wallet management';

  @override
  String get offlineSecurityCheck => 'Offline security check';

  @override
  String get checkAirplaneMode => 'Airplane mode';

  @override
  String get checkCellular => 'Cellular';

  @override
  String get checkBluetooth => 'Bluetooth';

  @override
  String get checkDevicePasscode => 'Device passcode';

  @override
  String get checkBiometric => 'Biometrics';

  @override
  String get checkScreenRecording => 'Screen recording';

  @override
  String get statusOn => 'On';

  @override
  String get statusOff => 'Off';

  @override
  String get statusDetectedOn => 'Detected on';

  @override
  String get statusEnabled => 'Enabled';

  @override
  String get statusNotDetected => 'Not detected';

  @override
  String get riskCannotSign => 'Risk detected · signing unavailable';

  @override
  String get bluetoothWarning => 'Bluetooth is on — turn it off and re-check.';

  @override
  String get checkNetwork => 'Network connection';

  @override
  String get checkIntegrity => 'System integrity';

  @override
  String get checkLevelPass => 'Pass';

  @override
  String get checkLevelWarn => 'Warning';

  @override
  String get checkLevelBlock => 'Blocked';

  @override
  String get checkDetailUnknown => 'Status unavailable';

  @override
  String get checkDetailNetworkSafe => 'No network connection detected';

  @override
  String get checkDetailNetworkUnsafe => 'Network connection detected';

  @override
  String get checkDetailAirplaneSafe => 'Airplane mode is on';

  @override
  String get checkDetailAirplaneUnsafe => 'Airplane mode is off';

  @override
  String get checkDetailBluetoothSafe => 'Bluetooth is off';

  @override
  String get checkDetailBluetoothUnsafe => 'Bluetooth is on';

  @override
  String get checkDetailPasscodeSafe => 'Device passcode is set';

  @override
  String get checkDetailPasscodeUnsafe => 'Device passcode is not set';

  @override
  String get checkDetailBiometricSafe => 'Biometrics are available';

  @override
  String get checkDetailBiometricUnsafe => 'Biometrics are unavailable';

  @override
  String get checkDetailScreenCaptureSafe => 'No screen recording detected';

  @override
  String get checkDetailScreenCaptureUnsafe => 'Screen recording detected';

  @override
  String get checkDetailIntegritySafe => 'System integrity check passed';

  @override
  String get checkDetailIntegrityUnsafe => 'Root or jailbreak detected';

  @override
  String get securityChecking => 'Checking device status…';

  @override
  String get securityOverallPass => 'All checks passed · Ready to sign';

  @override
  String get securityOverallWarn => 'Risks detected · Proceed with caution';

  @override
  String get securityOverallBlock => 'Critical risk · Signing disabled';

  @override
  String get securityRecheck => 'Re-run checks';

  @override
  String receivingShard(int received, int total) {
    return 'Receiving shard $received / $total';
  }

  @override
  String get confirmTxContent => 'Confirm transaction';

  @override
  String get reject => 'Reject';

  @override
  String get confirmSign => 'Confirm signing';

  @override
  String rawAmountPrecision(String amount, int precision) {
    return 'Raw amount $amount (precision $precision)';
  }

  @override
  String get fromAccount => 'From account';

  @override
  String get toAddress => 'Recipient address';

  @override
  String get spenderAddress => 'Authorized spender';

  @override
  String get nativeTransferOperation => 'Native transfer';

  @override
  String get tokenTransferOperation => 'Token transfer';

  @override
  String get approvalRevokeOperation => 'Revoke token approval';

  @override
  String get approvalRevokeZeroAllowance => 'Set allowance to zero';

  @override
  String get approvalRevokeSignerNotice =>
      'This is the exact ERC-20 approve(spender, 0) call. It revokes allowance and does not transfer tokens.';

  @override
  String get tokenContractLabel => 'Token contract';

  @override
  String get chainIdLabel => 'Chain ID';

  @override
  String get maximumFeeBaseUnits => 'Maximum fee (base units)';

  @override
  String get walletIdLabel => 'Wallet ID';

  @override
  String get createdAtLabel => 'Created at';

  @override
  String get expiresAtLabel => 'Valid until';

  @override
  String get riskWarningTitle => 'Risk warning';

  @override
  String get backToHome => 'Back to home';

  @override
  String get viewRawTxData => 'View raw transaction data';

  @override
  String get signingBlocked => 'Signing blocked';

  @override
  String get signingBlockedDesc =>
      'This transaction contains content that can\'t be safely parsed. KT Cold Signer refused to sign to protect your assets.';

  @override
  String get transactionParseFailed => 'Unable to parse safely';

  @override
  String get signingFailed =>
      'Signing failed. The transaction, wallet, or authentication did not pass validation.';

  @override
  String unknownContractCallDetected(String method) {
    return 'Unknown contract call detected: $method';
  }

  @override
  String get unknownContractCallDesc =>
      'Only native transfers, token transfers, and the exact approve(spender, 0) revocation are supported. Non-zero approve, permit, and unknown calls are rejected.';

  @override
  String get authTitle => 'Authentication';

  @override
  String get useFaceIdVerify => 'Verify with Face ID';

  @override
  String get useDevicePasscode => 'Use device passcode';

  @override
  String get biometricFailedRetry => 'Authentication failed. Try again.';

  @override
  String get verifyToSign => 'Verify to complete signing';

  @override
  String get verifyToSignDesc =>
      'Every signature requires Face ID or the device passcode';

  @override
  String get amountLabel => 'Amount';

  @override
  String get requestId => 'Request ID';

  @override
  String get enterPinToSign => 'Enter app PIN to complete signing';

  @override
  String get enterPinToDelete => 'Enter app PIN to continue deletion';

  @override
  String get pinIncorrect => 'Incorrect PIN, try again';

  @override
  String pinLockedRetry(int seconds) {
    return 'Too many attempts. Retry in ${seconds}s';
  }

  @override
  String get signComplete => 'Signing complete';

  @override
  String get voidThisSignature => 'Close signature QR';

  @override
  String get voidSignatureTitle => 'Close signature QR?';

  @override
  String get voidSignatureDesc =>
      'This only closes the QR on this device. A signature already scanned or saved elsewhere is not revoked and may still be broadcast. Closing this page does not cancel the transaction.';

  @override
  String get signatureVoided => 'QR closed. Signature not revoked.';

  @override
  String get signResultUnavailable => 'Signing result unavailable';

  @override
  String dynamicShard(int received, int total) {
    return 'Dynamic shard $received / $total';
  }

  @override
  String get scanResultInstruction =>
      'On the online wallet’s current transaction, tap “Signed offline? Scan the result” to read this QR.';

  @override
  String get allAddresses => 'All addresses';

  @override
  String exportQrCaption(int count) {
    return 'Includes public addresses for $count chains · no private data';
  }

  @override
  String get filterAll => 'All';

  @override
  String get stateSigned => 'Signed';

  @override
  String get stateRejected => 'Rejected';

  @override
  String get stateExpired => 'Expired';

  @override
  String get unknownContractCallLabel => 'Unknown contract call';

  @override
  String walletCreatedOn(String date) {
    return 'Created $date';
  }

  @override
  String get backedUp => 'Backed up';

  @override
  String get editWalletName => 'Edit wallet name';

  @override
  String get mnemonicBackupCheck => 'Verify phrase backup';

  @override
  String get mnemonicBackupCheckDesc =>
      'Periodically spot-check that the phrase still transcribes correctly';

  @override
  String get mnemonicReviewFailed =>
      'Authentication or phrase validation failed. No recovery phrase was shown.';

  @override
  String get deleteWallet => 'Delete wallet';

  @override
  String get deleteWalletReqDesc =>
      'Requires the app PIN and confirmation text; system authentication is also required when enabled';

  @override
  String get destroyAllData => 'Destroy all wallet data';

  @override
  String get destroyAllDataDesc =>
      'Irreversible; use only before disposing of the device';

  @override
  String get securitySettingsTitle => 'Security settings';

  @override
  String get verificationPolicy => 'Verification policy';

  @override
  String get biometricUsageDesc => 'Face ID for unlock and signing';

  @override
  String get verifyEverySign => 'Verify every signature';

  @override
  String get verifyEverySignDesc => 'Can\'t be disabled (enforced in V1)';

  @override
  String get accessSection => 'Access';

  @override
  String get changeAppPassword => 'Change app password';

  @override
  String get screenCaptureProtection => 'Screenshot safety alerts';

  @override
  String get screenCaptureBlocked => 'Screen recording detected';

  @override
  String get screenCaptureBlockedHint =>
      'The recovery phrase is hidden while recording or mirroring is active. Stop capture to restore it.';

  @override
  String get permanentlyDeleteWallet => 'Permanently delete wallet';

  @override
  String get stepPassword => 'Password';

  @override
  String get stepConfirmText => 'Confirm text';

  @override
  String get irreversibleAction => 'This action is irreversible';

  @override
  String get deleteWalletWarningDesc =>
      'After deletion, this device erases all of the wallet\'s key data. If the recovery phrase isn\'t backed up or the backup is lost, the assets can never be recovered.';

  @override
  String get typeToConfirmDelete => 'Type “Delete wallet” to continue';

  @override
  String get deleteWalletConfirmationPhrase => 'Delete wallet';

  @override
  String get verifyToDeleteWallet => 'Verify to permanently delete this wallet';

  @override
  String get deleteAuthenticationFailed =>
      'Authentication failed. The wallet was not deleted.';

  @override
  String get deleteWalletFailed =>
      'The wallet could not be deleted safely. Nothing was removed; try again.';

  @override
  String get displayLanguage => 'Language';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get fiatUnit => 'Fiat currency';

  @override
  String get languageSystem => 'System default';

  @override
  String get settingsSaveFailed =>
      'The setting could not be saved. Nothing was changed; try again.';

  @override
  String get pinKeyDelete => 'Delete last digit';
}
