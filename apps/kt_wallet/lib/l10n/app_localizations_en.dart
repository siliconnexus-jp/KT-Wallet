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
  String get actionClose => 'Close';

  @override
  String get actionDelete => 'Delete';

  @override
  String get pinKeyDelete => 'Delete last digit';

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
  String get homeSearchHint => 'Search assets, addresses, or networks';

  @override
  String get homeCategoryCoins => 'Coins';

  @override
  String get homeCategoryNetworks => 'Networks';

  @override
  String get homeCategoryCustom => 'Custom';

  @override
  String get homeNoMatchingAssets => 'No matching assets';

  @override
  String get homeNoMatchingNetworks => 'No matching networks';

  @override
  String get walletKindHot => 'Standard';

  @override
  String get walletKindWatch => 'Watch';

  @override
  String get walletStateBackedUp => 'Backed up';

  @override
  String get walletStateNotBackedUp => 'Not backed up';

  @override
  String get walletStateColdSigner => 'KT Cold Signer';

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
  String get backupBannerText => 'Recovery phrase not backed up';

  @override
  String get backupNow => 'Back up now';

  @override
  String get walletAddressesTitle => 'Account addresses';

  @override
  String get walletAddressSearchHint => 'Search network or address';

  @override
  String get balanceChangePeriod => '1D';

  @override
  String get marketUpdating => 'Updating balances…';

  @override
  String get marketCachedJustNow => 'Last verified just now';

  @override
  String marketCachedMinutes(int count) {
    return 'Last verified $count min ago';
  }

  @override
  String marketCachedHours(int count) {
    return 'Last verified $count hr ago';
  }

  @override
  String get marketCachedStale =>
      'Saved balances are shown while the network reconnects';

  @override
  String get actionReceive => 'Receive';

  @override
  String get actionSend => 'Send';

  @override
  String get actionMore => 'More';

  @override
  String get actionShare => 'Share';

  @override
  String get actionScanSign => 'Scan signature';

  @override
  String get assetsSortByValue => 'Sorted by holding value';

  @override
  String get assetsHideZero => 'Hide zero balances';

  @override
  String get assetsFavoritesOnly => 'Favorites';

  @override
  String assetAddFavorite(Object symbol) {
    return 'Add $symbol to favorites';
  }

  @override
  String assetRemoveFavorite(Object symbol) {
    return 'Remove $symbol from favorites';
  }

  @override
  String get recordsTitle => 'Transactions';

  @override
  String get historyLoadMore => 'Load more';

  @override
  String get historyLoadingMore => 'Loading more…';

  @override
  String get transactionConfirmedNotice => 'Transaction confirmed on-chain';

  @override
  String get transactionFailedNotice => 'Transaction failed on-chain';

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
      'Pair KT Cold Signer by QR; private keys never touch this device';

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
  String walletCreateAuthLocked(int seconds) {
    return 'Security verification is temporarily locked. Try again in $seconds seconds.';
  }

  @override
  String get walletCreateFailed =>
      'Wallet creation could not be completed. Please try again.';

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
  String get scanAccountHint => 'Aim at the KT Cold Signer address QR';

  @override
  String get importConfirmTitle => 'Confirm import';

  @override
  String get createWatchWallet => 'Create watch wallet';

  @override
  String get invalidOfflineWalletExport => 'Invalid offline wallet export';

  @override
  String get offlineWalletAlreadyPaired =>
      'This offline wallet is already paired';

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
  String get walletDeleteFailed =>
      'The wallet could not be deleted safely. Nothing was removed; try again.';

  @override
  String get walletUpdateFailed =>
      'Changes could not be saved. Nothing was changed; try again.';

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
  String get walletIdLabel => 'Wallet ID';

  @override
  String get coldSignerWalletIdLabel => 'KT Cold Signer wallet ID';

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
  String compatibleContactsHint(String network) {
    return 'Only contacts compatible with $network are shown';
  }

  @override
  String noCompatibleContacts(String network) {
    return 'No contacts are compatible with $network';
  }

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
  String recipientLookalikeWarning(String label) {
    return 'This address closely resembles $label, but is not identical. It may be a clipboard-poisoning address.';
  }

  @override
  String get recipientLookalikeReview => 'I verified the full address';

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
  String get expectedAssetChanges => 'Expected asset changes';

  @override
  String outgoingAsset(String symbol) {
    return '$symbol sent';
  }

  @override
  String get maximumNetworkFee => 'Maximum network fee';

  @override
  String upToNegativeAmount(String amount) {
    return 'Up to -$amount';
  }

  @override
  String get solanaRentReserve => 'Recoverable account reserve';

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
  String get transactionSourceAddress => 'Source address';

  @override
  String get transactionDestinationAccount => 'Received by';

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
  String get transactionNotSubmitted =>
      'The transaction was not submitted. Try again.';

  @override
  String get broadcastUnsupported =>
      'This signed transaction can\'t be broadcast on the selected network.';

  @override
  String get rpcRejectInsufficientFunds =>
      'Insufficient balance for the amount and maximum network fee.';

  @override
  String get rpcRejectNonceTooLow =>
      'The transaction nonce is too low. Refresh and try again.';

  @override
  String get rpcRejectNonceTooHigh =>
      'The transaction nonce is too high. Refresh and try again.';

  @override
  String get rpcRejectReplacementFeeTooLow =>
      'The replacement network fee is too low.';

  @override
  String get rpcRejectFeeTooLow => 'The network fee is too low.';

  @override
  String get rpcRejectGasLimitTooLow => 'The transaction gas limit is too low.';

  @override
  String get rpcRejectBlockGasLimit =>
      'The transaction exceeds the network block gas limit.';

  @override
  String get rpcRejectFeeCapBelowBase =>
      'The fee cap is below the current network base fee.';

  @override
  String get rpcRejectAlreadyKnown =>
      'The network already knows this transaction. Check its status instead of sending again.';

  @override
  String get rpcRejectExecutionReverted =>
      'The transaction was reverted during execution.';

  @override
  String get rpcRejectInvalidSender => 'The transaction sender is invalid.';

  @override
  String get rpcRejectExpiredReference =>
      'The transaction\'s block reference has expired. Rebuild the transaction.';

  @override
  String get rpcRejectAccountInUse =>
      'A required account is currently in use. Wait and try again.';

  @override
  String get rpcRejectSimulationFailed =>
      'The network rejected the transaction simulation.';

  @override
  String get rpcRejectInvalidSignature =>
      'The transaction signature is invalid.';

  @override
  String get rpcRejectGeneric => 'The network rejected the transaction.';

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
  String get txSubmissionUnknown => 'Broadcast result unknown';

  @override
  String get txSubmissionUnknownMessage =>
      'The signed transaction may have reached the network. Do not send it again. KT Wallet will keep checking its locally derived transaction hash.';

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
  String get txStatusUnknown => 'Status unavailable';

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
  String get tokenRiskChecking => 'Checking token identity…';

  @override
  String get tokenRiskCheckingBody =>
      'KT Wallet is checking this exact network and contract against the verified catalog and independent threat intelligence before signing.';

  @override
  String get tokenRiskVerifiedTitle => 'Official token identity confirmed';

  @override
  String get tokenRiskVerifiedBody =>
      'The network and contract address match the operator-verified token catalog. This verifies identity, not investment safety.';

  @override
  String get tokenRiskUnsafeTitle => 'Risky token contract detected';

  @override
  String get tokenRiskUnsafeBody =>
      'A configured security source found explicit malicious evidence for this exact contract. Signing is blocked to protect your wallet.';

  @override
  String get tokenRiskUnknownTitle => 'Token risk is unknown';

  @override
  String get tokenRiskUnknownBody =>
      'No configured source can confirm this contract\'s identity or safety. Check the full contract address with an official source before continuing.';

  @override
  String get tokenRiskUnavailableTitle => 'Unable to check token risk';

  @override
  String get tokenRiskUnavailableBody =>
      'The risk service is unavailable. KT Wallet cannot confirm that this contract is safe; verify it independently before continuing.';

  @override
  String get tokenRiskBlockedHint =>
      'Sending is disabled because this token contract is marked as risky.';

  @override
  String get signRequestBuildFailed =>
      'The on-chain transaction parameters could not be verified. Signing is disabled.';

  @override
  String get signRequestSaveFailed =>
      'The pending transaction could not be saved safely. No signing QR was created; go back and try again.';

  @override
  String get transactionSimulationFailed =>
      'Transaction simulation failed and nothing was signed. Check the balance, amount, recipient, or token contract.';

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
  String get txReplacementPendingLabel => 'Competing replacement';

  @override
  String get txNotFound => 'Local transaction record not found';

  @override
  String confirming(int received, int total) {
    return 'Confirming ($received/$total)';
  }

  @override
  String get txDetailTitle => 'Transaction details';

  @override
  String get txBroadcastTime => 'Broadcast time';

  @override
  String get txLastStatusCheck => 'Last status check';

  @override
  String get txNotCheckedYet => 'Not checked yet';

  @override
  String get txCopyHash => 'Copy transaction hash';

  @override
  String get txHashCopied => 'Transaction hash copied';

  @override
  String get txViewInExplorer => 'View in block explorer';

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
  String tokenImpersonationWarning(String symbol) {
    return '⚠️ This asset is named $symbol, but its contract is not in KT Wallet\'s verified official $symbol address list. It may be a lookalike or bridged asset; never transfer based on the name alone.';
  }

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
  String get receiveExportSubtitle =>
      'Includes the address, network, and a scannable payment QR';

  @override
  String get exportTransactionReceipt => 'Export transaction receipt';

  @override
  String get exportTransactionReceiptSubtitle =>
      'Includes transaction details and an on-chain verification QR';

  @override
  String get transactionReceiptTitle => 'On-chain transaction receipt';

  @override
  String get transactionReceiptTimeLabel => 'Transaction time';

  @override
  String get saveReceiptToPhotos => 'Save to photos';

  @override
  String get shareReceiptImage => 'Share receipt image';

  @override
  String get transactionReceiptSaved =>
      'Transaction receipt saved to your photos';

  @override
  String get transactionReceiptDenied => 'Photo library access was declined';

  @override
  String get transactionReceiptUseShare =>
      'This OS version cannot save directly — use share instead';

  @override
  String get transactionReceiptFailed =>
      'Could not create the transaction receipt';

  @override
  String get scanToVerifyOnChain => 'Scan to verify in a block explorer';

  @override
  String get transactionReceiptFooter =>
      'Generated by KT Wallet · On-chain data is authoritative';

  @override
  String transactionReceiptSubject(String network) {
    return '$network transaction receipt';
  }

  @override
  String get actionCopy => 'Copy address';

  @override
  String get addressBookTitle => 'Address book';

  @override
  String get localWalletAddresses => 'Local wallet addresses';

  @override
  String get savedContacts => 'Saved contacts';

  @override
  String get localWalletLabel => 'Local wallet';

  @override
  String get currentWalletLabel => 'Current wallet';

  @override
  String evmNetworksLabel(int count) {
    return 'EVM · $count networks';
  }

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
  String get searchTokenHint => 'Search name, symbol, or contract address';

  @override
  String get myTokens => 'My tokens';

  @override
  String get addedTokenSearchResults => 'Added';

  @override
  String get popularOfficialTokens => 'Popular verified tokens';

  @override
  String get officialTokenSearchResults => 'Verified tokens';

  @override
  String get officialTokenVerified => 'Verified by KT Wallet';

  @override
  String get noMatchingTokens =>
      'No matching token found\\nTap + to add one by contract address';

  @override
  String addOfficialToken(String symbol) {
    return 'Add verified $symbol';
  }

  @override
  String officialTokenAdded(String symbol) {
    return 'Added verified $symbol';
  }

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
  String get walletPersistenceFailed =>
      'The wallet couldn\'t be saved securely. Nothing was added. Please try again.';

  @override
  String get walletAlreadyExists => 'This wallet is already on this device.';

  @override
  String get cryptoUnavailableTitle => 'Wallet engine unavailable';

  @override
  String get cryptoUnavailableDesc =>
      'This Android build does not include Trust Wallet Core. Install a wallet-core-enabled build; simulated keys are never used automatically.';

  @override
  String get secureStorageUnavailableTitle => 'Secure storage unavailable';

  @override
  String get secureStorageUnavailableDesc =>
      'KT Wallet cannot safely read your PIN and lockout state. Your wallet remains locked. Restart the app or reinstall it from a trusted source.';

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
  String get changeWalletPin => 'Change wallet PIN';

  @override
  String get changeWalletPinDesc =>
      'Verify your current identity before replacing the 6-digit PIN';

  @override
  String get enterCurrentPin => 'Enter your current wallet PIN';

  @override
  String get walletPinChanged => 'Wallet PIN changed';

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
  String get endpointUrlInvalid =>
      'Enter a valid HTTPS URL without embedded credentials. HTTP is allowed only for localhost.';

  @override
  String chainIdMismatch(Object actual) {
    return 'Chain ID mismatch: node returned $actual';
  }

  @override
  String transferNetworkUnavailable(String network) {
    return 'No active network is available for $network.';
  }

  @override
  String get transferChainIdUnavailable =>
      'The selected EVM network has no Chain ID.';

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
  String get airdropRateLimited => 'Too many requests. Try again later.';

  @override
  String get airdropUnavailable => 'Test funds are temporarily unavailable';

  @override
  String get airdropInvalidRequest =>
      'The faucet rejected this address or request';

  @override
  String get airdropInsufficientFunds =>
      'The faucet does not have enough test funds';

  @override
  String get airdropRejected => 'The faucet rejected the request';

  @override
  String get airdropMalformedResponse =>
      'The faucet returned an invalid response';

  @override
  String get fiatHiddenTestnet => 'Testnet assets have no market price';

  @override
  String get backupEncryptedTitle => 'Encrypted backup';

  @override
  String get backupEncryptedRow => 'Encrypted backup';

  @override
  String get backupEncryptedRowDesc =>
      'Save an encrypted copy with the system file picker';

  @override
  String get backupIntro =>
      'The file is encrypted with a password you choose. Anyone who has both the file and the password controls this wallet.';

  @override
  String get backupPasswordLabel => 'Backup password';

  @override
  String get backupPasswordConfirm => 'Repeat the password';

  @override
  String get backupPasswordTooShort => 'Use at least 14 characters';

  @override
  String get backupPasswordTooLong => 'Use no more than 128 characters';

  @override
  String get backupPasswordTooWeak =>
      'Avoid repeated, sequential, or common passwords';

  @override
  String get backupPasswordMismatch => 'The two passwords do not match';

  @override
  String get backupPasswordWarning =>
      'Use a unique long passphrase. It cannot be recovered; if you lose it, the backup cannot be opened. Keep your written recovery phrase as well.';

  @override
  String get backupCreate => 'Create backup';

  @override
  String get backupSaved => 'Backup saved';

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
  String get restoreFileTooLarge =>
      'This file is too large to be a KT Wallet backup';

  @override
  String get restoreFileUnavailable => 'This device cannot open backup files';

  @override
  String get restoreFileReadFailed =>
      'Could not read the selected file. Try again';

  @override
  String get restoreSelectedFileFallback => 'Backup file';

  @override
  String get restoreRestored => 'Wallet restored';

  @override
  String get restoreAction => 'Restore';

  @override
  String backupFileChosen(String name) {
    return 'Selected: $name';
  }

  @override
  String get settingsAbout => 'About';

  @override
  String get aboutTitle => 'About';

  @override
  String get aboutVersion => 'Version';

  @override
  String get aboutOpenSource => 'Open source';

  @override
  String get aboutOpenSourceDesc => 'Read the code that holds your keys';

  @override
  String get aboutTagline => 'Air-gapped wallet. Keys never leave your device.';

  @override
  String get aboutCopiedLink => 'Link copied';

  @override
  String get aboutTrustTitle => 'Trust & legal';

  @override
  String get aboutPrivacyPolicy => 'Privacy policy';

  @override
  String get aboutPrivacyPolicyDesc => 'What the apps process and send';

  @override
  String get aboutSecurityRisk => 'Security & risk notice';

  @override
  String get aboutSecurityRiskDesc =>
      'Current guarantees and known limitations';

  @override
  String get aboutSecurityPolicy => 'Security policy';

  @override
  String get aboutSecurityPolicyDesc =>
      'Scope, safe research, and response targets';

  @override
  String get aboutThirdPartyNotices => 'Open-source notices';

  @override
  String get aboutThirdPartyNoticesDesc => 'Licenses for bundled dependencies';

  @override
  String get aboutReportSecurity => 'Report a security issue';

  @override
  String get aboutReportSecurityDesc =>
      'Read the private reporting process first';

  @override
  String get aboutNeverShareSecrets =>
      'KT Wallet will never ask for your recovery phrase or private key.';

  @override
  String get diagnosticsTitle => 'Support diagnostics';

  @override
  String get diagnosticsSubtitle =>
      'Export a privacy-safe JSON package for troubleshooting';

  @override
  String get diagnosticsConfirmTitle => 'Export diagnostics?';

  @override
  String get diagnosticsConfirmBody =>
      'Review what is and is not included before sharing.';

  @override
  String get diagnosticsIncludesTitle => 'Included';

  @override
  String get diagnosticsIncludesBody =>
      'App and build details, network modes, service state, and aggregate performance';

  @override
  String get diagnosticsExcludesTitle => 'Never included';

  @override
  String get diagnosticsExcludesBody =>
      'Addresses, balances, amounts, transactions, keys, signatures, recovery phrases, or endpoint URLs';

  @override
  String get diagnosticsExportAction => 'Export and share';

  @override
  String get diagnosticsShareSubject => 'KT Wallet support diagnostics';

  @override
  String get diagnosticsShareText =>
      'Redacted KT Wallet diagnostics. Review the file before sharing.';

  @override
  String get diagnosticsReady => 'Diagnostic package ready';

  @override
  String get diagnosticsFailed => 'Could not create the diagnostic package';

  @override
  String get diagnosticsUploadTitle => 'Send anonymous performance report';

  @override
  String get diagnosticsUploadSubtitle =>
      'Review and send fixed aggregate metrics once; never uploads in the background';

  @override
  String get diagnosticsUploadConfirmTitle =>
      'Send an anonymous performance report?';

  @override
  String get diagnosticsUploadConfirmBody =>
      'This is a one-time upload you initiate. It does not upload in the background or retry automatically. The server retains only anonymous aggregates for 7 days.';

  @override
  String get diagnosticsUploadIncludesBody =>
      'App version, platform, broad language, build mode, and counts, outcomes, P50/P95 for fixed performance metrics';

  @override
  String get diagnosticsUploadExcludesBody =>
      'Wallet or device IDs, addresses, balances, amounts, transactions, tx hashes, timestamps, error text, stacks, keys, signatures, recovery phrases, or endpoint URLs';

  @override
  String get diagnosticsUploadAction => 'Agree and send';

  @override
  String get diagnosticsUploadSent => 'Anonymous performance report sent';

  @override
  String get diagnosticsUploadAlreadySent =>
      'The same anonymous report was already sent';

  @override
  String get diagnosticsUploadNoSamples =>
      'There are no performance samples to send yet';

  @override
  String get diagnosticsUploadFailed =>
      'Could not send the anonymous report; it was not retried';

  @override
  String get diagnosticsUploadGatewayRequired =>
      'Direct mode does not upload diagnostics; enable KT Gateway first';

  @override
  String get settingsApprovals => 'Token approvals';

  @override
  String get approvalsTitle => 'Token approvals';

  @override
  String get approvalsSubtitle =>
      'Review contracts that can spend your ERC-20 tokens';

  @override
  String get approvalPrivacyTitle => 'External approval scan';

  @override
  String get approvalPrivacyBody =>
      'To find outstanding approvals, KT Wallet sends this wallet\'s public address and selected mainnet to GoPlus through the configured Gateway. Keys, balances and transaction contents are not sent. You can turn this off at any time.';

  @override
  String get approvalEnableAndScan => 'Allow and scan';

  @override
  String get approvalDisableScan => 'Turn off external scan';

  @override
  String get approvalScanAgain => 'Scan again';

  @override
  String get approvalLoading => 'Checking outstanding approvals…';

  @override
  String get approvalEmptyTitle => 'No outstanding approvals found';

  @override
  String get approvalEmptyBody =>
      'The provider completed this scan and returned no ERC-20 allowances for this wallet on the selected network.';

  @override
  String get approvalUnavailableTitle => 'Approval status unavailable';

  @override
  String get approvalUnavailableBody =>
      'The provider did not complete the scan. Your approval list is unknown — this is not an empty result.';

  @override
  String get approvalUnsupportedTitle => 'This network is not covered';

  @override
  String get approvalUnsupportedBody =>
      'Approval scanning currently supports Ethereum, Polygon, Base, Arbitrum and BNB Smart Chain mainnets only.';

  @override
  String get approvalUnlimited => 'Unlimited allowance';

  @override
  String approvalAmount(String amount) {
    return 'Allowance: $amount';
  }

  @override
  String get approvalSpender => 'Spender';

  @override
  String get approvalTokenContract => 'Token contract';

  @override
  String get approvalApprovedAt => 'Last changed';

  @override
  String get approvalRisky => 'Risk signal found';

  @override
  String get approvalIdentityUnknown => 'Safety not confirmed';

  @override
  String get approvalKnownSpender => 'Known provider tag';

  @override
  String get approvalReadOnlyNotice =>
      'Hot wallets revoke locally with an exact zero-allowance transaction. Watch wallets use the paired KT Cold Signer QR round trip.';

  @override
  String get approvalPrivacyEnabled =>
      'External scan is enabled for this device';

  @override
  String get approvalNoWallet => 'Select a wallet to review approvals';

  @override
  String get approvalRevoke => 'Revoke approval';

  @override
  String get approvalRevokeTitle => 'Revoke this token approval?';

  @override
  String get approvalRevokeBody =>
      'KT Wallet will send approve(spender, 0) to the token contract. This changes the allowance only; it does not transfer tokens.';

  @override
  String get approvalRevokeConfirm => 'Authenticate and revoke';

  @override
  String get approvalRevokePreparing =>
      'Simulating the exact revocation and estimating its maximum fee…';

  @override
  String approvalRevokeMaximumFee(String fee) {
    return 'Maximum network fee: $fee';
  }

  @override
  String get approvalRevokeSubmitted =>
      'Revocation submitted. It remains pending until the chain confirms it.';

  @override
  String get approvalRevokePending => 'Revocation pending';

  @override
  String get approvalRevokeFailed =>
      'The revocation was not submitted. Nothing is shown as revoked.';

  @override
  String get approvalRevokeAuthFailed =>
      'Authentication was not completed. Nothing was signed.';

  @override
  String get approvalRevokeHotOnly =>
      'No signing-capable wallet is available for this revocation.';
}
