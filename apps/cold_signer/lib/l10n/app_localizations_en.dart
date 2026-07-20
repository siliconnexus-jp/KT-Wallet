// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get actionConfirm => 'Confirm';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionSave => 'Save';

  @override
  String get actionImport => 'Import';

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
      'Don\'t save it to photos, cloud, or chat apps; this app blocks screenshots';

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
  String get scanPendingTx => 'Scan pending transaction';

  @override
  String get scanPendingTxDesc => 'Scan the dynamic QR from the online wallet';

  @override
  String get exportAddress => 'Export addresses';

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
  String get riskWarningTitle => 'Risk warning';

  @override
  String get backToHome => 'Back to home';

  @override
  String get viewRawTxData => 'View raw transaction data';

  @override
  String get signingBlocked => 'Signing blocked';

  @override
  String get signingBlockedDesc =>
      'This transaction contains content that can\'t be safely parsed. Cold Signer refused to sign to protect your assets.';

  @override
  String unknownContractCallDetected(String method) {
    return 'Unknown contract call detected: $method';
  }

  @override
  String get unknownContractCallDesc =>
      'V1 supports only native-coin and token transfers. Authorization calls like approve and permit are always rejected.';

  @override
  String get authTitle => 'Authentication';

  @override
  String get useFaceIdVerify => 'Verify with Face ID';

  @override
  String get useDevicePasscode => 'Use device passcode';

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
  String get signComplete => 'Signing complete';

  @override
  String get voidThisSignature => 'Void this signature';

  @override
  String get voidSignatureTitle => 'Void this signature?';

  @override
  String get voidSignatureDesc =>
      'Once voided, this signature QR code becomes invalid and the online wallet cannot broadcast the transaction.';

  @override
  String get signatureVoided => 'Signature voided';

  @override
  String dynamicShard(int received, int total) {
    return 'Dynamic shard $received / $total';
  }

  @override
  String get scanResultInstruction =>
      'Read this QR with the online wallet\'s “Scan signing result”';

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
  String get deleteWallet => 'Delete wallet';

  @override
  String get deleteWalletReqDesc =>
      'Requires password, biometrics, and confirmation text';

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
  String get screenCaptureProtection => 'Screenshot & recording protection';

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
  String get displayLanguage => 'Language';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get fiatUnit => 'Fiat currency';

  @override
  String get languageSystem => 'System default';

  @override
  String get deviceMode => 'Device mode';

  @override
  String get deviceModeSigner => 'Offline Signer';

  @override
  String get deviceModeSwitchTitle => 'Switch device mode';

  @override
  String get deviceModeSwitchDesc =>
      'Before switching, make sure this device is no longer used as a signer. You will return to the mode selection screen.';
}
