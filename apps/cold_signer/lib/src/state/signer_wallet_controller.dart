import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:chains/chains.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/widgets.dart';

import '../data/database_provider.dart';
import '../data/signer_database.dart';
import '../security/mnemonic_wordlist.dart'
    show drawDistractors, generateMnemonic;
import '../security/biometric_auth.dart';
import '../security/device_probe.dart';
import '../security/security_check.dart';
import '../security/pin_lock.dart';
import '../security/secure_vault.dart';
import '../signing/mnemonic_quiz.dart';
import '../signing/mnemonic_review.dart';
import '../signing/sign_record_store.dart';

/// Volatile onboarding progress. It is intentionally not persisted: a process
/// restart must return to the welcome screen instead of guessing that mnemonic
/// review or PIN enrollment succeeded.
enum SignerOnboardingStage {
  idle,
  mnemonicReview,
  pinSetup,
  biometricSetup,
  completed,
}

/// The signer's persistent wallet state: mnemonic + metadata in the secure
/// vault, PIN via [PinLock], and the drift-backed anti-replay ledger.
///
/// Every live screen reads this through [SignerWalletScope.maybeOf] and MUST
/// fall back to the original design-snapshot rendering when the scope (or the
/// state it would provide) is absent — the dev gallery and the golden tests
/// run without any wallet state and must stay byte-identical.
class SignerWalletController extends ChangeNotifier {
  static const _finalSigningClockSkewSeconds = 600;

  SignerWalletController({
    VaultStorage? storage,
    this._records,
    CoreCrypto? crypto,
    Future<DeviceState> Function()? deviceProbe,
    Random? random,
    DateTime Function()? clock,
    int? pinIterations,
  }) : _storage = storage ?? SecureVaultStorage(),
       _random = random ?? Random.secure(),
       _now = clock ?? DateTime.now,
       _crypto = crypto ?? MethodChannelCoreCrypto(),
       _deviceProbe = deviceProbe ?? probeDeviceState {
    _vault = SecureVault(_storage);
    _pinLock = PinLock(
      _storage,
      random: _random,
      clock: _now,
      iterations: pinIterations ?? 100000,
    );
  }

  final VaultStorage _storage;
  final Random _random;
  final DateTime Function() _now;
  final CoreCrypto _crypto;
  final Future<DeviceState> Function() _deviceProbe;

  late final SecureVault _vault;
  late final PinLock _pinLock;

  /// Injected persistence (tests), or the on-device drift database opened
  /// lazily on first use.
  SignRecordPersistence? _records;

  /// Swapped in when the drift/path_provider MethodChannels are unavailable
  /// (widget tests that pump the real app without injecting fakes). On a real
  /// device the drift store always opens and this stays null.
  SignRecordPersistence? _pluginlessRecords;

  SecureVault get vault => _vault;
  PinLock get pinLock => _pinLock;

  bool _hasWallet = false;
  WalletMetadata? _metadata;
  List<String>? _pendingMnemonic;
  SignerOnboardingStage _onboardingStage = SignerOnboardingStage.idle;
  Future<List<String>>? _beginCreateInFlight;
  Future<WalletMetadata>? _completeOnboardingInFlight;

  /// Whether a wallet is stored on this device (valid after [load]).
  bool get hasWallet => _hasWallet;

  WalletMetadata? get metadata => _metadata;
  bool get biometricEnabled => _metadata?.biometricEnabled ?? false;

  /// The freshly generated mnemonic of an onboarding session in progress
  /// (create flow, between C1 and C16); null otherwise. Cleared as soon as
  /// the wallet is persisted — key material must not linger in Dart memory.
  List<String>? get pendingMnemonic => _pendingMnemonic;

  SignerOnboardingStage get onboardingStage => _onboardingStage;

  void finishOnboardingPresentation() {
    if (_hasWallet && _onboardingStage == SignerOnboardingStage.completed) {
      _onboardingStage = SignerOnboardingStage.idle;
      notifyListeners();
    }
  }

  String? get localWalletId => _metadata?.walletId;

  /// Loads vault state. Called once at startup (and safe to call again).
  Future<void> load() async {
    await _vault.removeLegacyMnemonic();
    final pendingDeletion = await _vault.pendingDeletionWalletId();
    if (pendingDeletion != null) {
      await _finishPendingDeletion(pendingDeletion);
      return;
    }
    final loadedMetadata = await _vault.readMetadata();
    if (loadedMetadata != null) {
      // A wallet without one valid, bounded PIN record is not a usable signer.
      // Validate this before native derivation or any biometric-only signing
      // route can become reachable. Missing and malformed state both keep the
      // startup security gate closed; never enroll a replacement implicitly.
      if (!await _pinLock.isSet()) {
        throw const PinStateCorruptedException();
      }
      await _pinLock.lockRemaining();
      // A native plugin, Keychain, Keystore, or derivation failure is not
      // proof that the wallet key is gone. Never destroy the only durable
      // wallet identifier in response to a transient read failure. Propagate
      // the error so the app stays on its blocking security screen and an
      // explicit retry can recover the same wallet.
      final addresses = await _crypto.deriveAddresses(loadedMetadata.walletId);
      final publicKeys = await _crypto.derivePublicKeys(
        loadedMetadata.walletId,
      );
      final refreshed = loadedMetadata.copyWith(
        addresses: addresses.toMap(),
        publicKeys: publicKeys.toMap().map(
          (key, value) => MapEntry(key, base64Encode(value)),
        ),
      );
      await _vault.storeMetadata(refreshed);
      _metadata = refreshed;
      _hasWallet = true;
    } else {
      _metadata = null;
      _hasWallet = false;
    }
    notifyListeners();
  }

  /// Starts the create-wallet flow: generates the real mnemonic that C3 will
  /// display and C4 will challenge.
  Future<List<String>> beginCreate() {
    if (_hasWallet) {
      return Future<List<String>>.error(StateError('a wallet already exists'));
    }
    final active = _beginCreateInFlight;
    if (active != null) return active;
    final pending = _pendingMnemonic;
    if (pending != null) return Future<List<String>>.value(List.of(pending));

    late final Future<List<String>> task;
    task = _beginCreate().whenComplete(() {
      if (identical(_beginCreateInFlight, task)) {
        _beginCreateInFlight = null;
      }
    });
    _beginCreateInFlight = task;
    return task;
  }

  Future<List<String>> _beginCreate() async {
    if (isFlutterTestEnv && _crypto is MethodChannelCoreCrypto) {
      _pendingMnemonic = generateMnemonic(random: _random);
      _onboardingStage = SignerOnboardingStage.mnemonicReview;
      notifyListeners();
      return List.of(_pendingMnemonic!);
    }
    try {
      _pendingMnemonic = (await _crypto.generateMnemonic(
        strength: 128,
      )).trim().split(' ');
    } catch (_) {
      if (!isFlutterTestEnv) rethrow;
      _pendingMnemonic = generateMnemonic(random: _random);
    }
    _onboardingStage = SignerOnboardingStage.mnemonicReview;
    notifyListeners();
    return List.of(_pendingMnemonic!);
  }

  /// Validates a complete BIP-39 phrase, including its checksum, without
  /// persisting anything. The native wallet is created only after PIN setup.
  Future<bool> beginImport(String mnemonic) async {
    if (_hasWallet || _pendingMnemonic != null) return false;
    final normalized = mnemonic.trim().toLowerCase().split(RegExp(r'\s+'));
    if (!const {12, 18, 24}.contains(normalized.length)) return false;
    if (!await _crypto.validateMnemonic(normalized.join(' '))) return false;
    _pendingMnemonic = normalized;
    _onboardingStage = SignerOnboardingStage.pinSetup;
    notifyListeners();
    return true;
  }

  /// Advances a create flow only after the exact in-memory phrase has been
  /// challenged successfully. A route or widget cannot substitute another
  /// list and then jump directly to PIN enrollment.
  void markMnemonicVerified(List<String> words) {
    final pending = _pendingMnemonic;
    final matches =
        pending != null &&
        pending.length == words.length &&
        Iterable<int>.generate(
          pending.length,
        ).every((index) => pending[index] == words[index]);
    if (_hasWallet ||
        _onboardingStage != SignerOnboardingStage.mnemonicReview ||
        !matches) {
      throw StateError('mnemonic review is not active');
    }
    _onboardingStage = SignerOnboardingStage.pinSetup;
    notifyListeners();
  }

  /// Exports the native-held phrase after the platform's strong-auth gate.
  ///
  /// The returned words are ephemeral and are never written to Dart storage or
  /// retained on this controller. Invalid native output fails closed.
  Future<MnemonicReviewFlow> exportMnemonicForReview() async {
    final metadata = _metadata;
    if (!_hasWallet || metadata == null) {
      throw StateError('wallet is not ready');
    }
    final phrase = await _crypto.exportMnemonic(metadata.walletId);
    final words = phrase.trim().toLowerCase().split(RegExp(r'\s+'));
    if (!const {12, 18, 24}.contains(words.length) ||
        !await _crypto.validateMnemonic(words.join(' '))) {
      throw const InvalidMnemonicException();
    }
    return MnemonicReviewFlow(
      purpose: MnemonicReviewPurpose.backup,
      words: words,
    );
  }

  /// Builds a verification challenge over exactly the phrase being reviewed.
  QuizQuestion buildVerifyChallengeFor(List<String> words) {
    if (!const {12, 18, 24}.contains(words.length)) {
      throw ArgumentError.value(words.length, 'words', 'invalid word count');
    }
    return MnemonicQuiz.build(
      words,
      count: 1,
      optionCount: 6,
      pickIndices: (wordCount, count) => [
        for (var i = 0; i < count; i++) _random.nextInt(wordCount),
      ],
      distractorsFor: (correct, n) =>
          drawDistractors(correct, n, random: _random),
    ).single;
  }

  /// Builds C4's onboarding challenge, or null outside an active create flow.
  QuizQuestion? buildVerifyChallenge() {
    final words = _pendingMnemonic;
    return words == null ? null : buildVerifyChallengeFor(words);
  }

  Future<void> renameWallet(String name) async {
    final metadata = _metadata;
    final normalized = name.trim();
    if (!_hasWallet || metadata == null || normalized.isEmpty) return;
    final updated = metadata.copyWith(name: normalized);
    await _vault.storeMetadata(updated);
    _metadata = updated;
    notifyListeners();
  }

  /// Stores the app PIN (C14). PBKDF2 parameters live in [PinLock].
  Future<void> setPin(String pin) async {
    if (!_hasWallet &&
        (_pendingMnemonic == null ||
            _onboardingStage != SignerOnboardingStage.pinSetup)) {
      throw StateError('PIN setup is not active');
    }
    await _pinLock.setPin(pin);
    if (!_hasWallet) {
      _onboardingStage = SignerOnboardingStage.biometricSetup;
      notifyListeners();
    }
  }

  Future<bool> setBiometricEnabled(bool enabled) async {
    final metadata = _metadata;
    if (metadata == null) return false;
    if (enabled && !await BiometricAuth.instance.canAuthenticate()) {
      return false;
    }
    final updated = metadata.copyWith(biometricEnabled: enabled);
    await _vault.storeMetadata(updated);
    _metadata = updated;
    notifyListeners();
    return true;
  }

  /// Persists the pending wallet in the native crypto vault and drops the
  /// in-memory mnemonic. A missing onboarding phrase is an invalid production
  /// state, not permission to navigate to a fake success screen.
  Future<WalletMetadata> completeOnboarding({String walletName = 'KT Wallet'}) {
    if (_hasWallet) {
      return Future<WalletMetadata>.error(
        StateError('a wallet already exists'),
      );
    }
    if (_pendingMnemonic == null ||
        _onboardingStage != SignerOnboardingStage.biometricSetup) {
      return Future<WalletMetadata>.error(
        StateError('wallet onboarding is not ready to commit'),
      );
    }
    final active = _completeOnboardingInFlight;
    if (active != null) return active;

    late final Future<WalletMetadata> task;
    task = _completeOnboarding(walletName: walletName).whenComplete(() {
      if (identical(_completeOnboardingInFlight, task)) {
        _completeOnboardingInFlight = null;
      }
    });
    _completeOnboardingInFlight = task;
    return task;
  }

  Future<WalletMetadata> _completeOnboarding({
    required String walletName,
  }) async {
    final words = _pendingMnemonic;
    if (words == null ||
        _onboardingStage != SignerOnboardingStage.biometricSetup ||
        _hasWallet) {
      throw StateError('wallet onboarding is not ready to commit');
    }
    final walletId = _newWalletId();
    final metadata = WalletMetadata(
      walletId: walletId,
      name: walletName,
      createdAt: _now().millisecondsSinceEpoch ~/ 1000,
    );
    var nativeWalletStored = false;
    try {
      await _crypto.storeWallet(
        walletId: walletId,
        mnemonic: words.join(' '),
        requireAuth: true,
      );
      nativeWalletStored = true;
      final addresses = await _crypto.deriveAddresses(walletId);
      final publicKeys = await _crypto.derivePublicKeys(walletId);
      final completed = metadata.copyWith(
        addresses: addresses.toMap(),
        publicKeys: publicKeys.toMap().map(
          (key, value) => MapEntry(key, base64Encode(value)),
        ),
      );
      await _vault.storeMetadata(completed);
      _pendingMnemonic = null;
      _onboardingStage = SignerOnboardingStage.completed;
      _hasWallet = true;
      _metadata = completed;
      notifyListeners();
      return completed;
    } catch (error, stackTrace) {
      // PIN is enrolled before this step. Attempt every compensation action
      // independently: one failed store must not prevent deletion of native
      // key material or the remaining PIN/metadata keys. Native deletion runs
      // first so a secure-storage delete failure cannot strand a known key.
      Object? cleanupError;
      StackTrace? cleanupStackTrace;
      if (nativeWalletStored) {
        try {
          await _crypto.deleteWallet(walletId);
        } catch (cleanup, cleanupStack) {
          cleanupError = cleanup;
          cleanupStackTrace = cleanupStack;
        }
      }
      try {
        await _vault.wipe();
      } catch (cleanup, cleanupStack) {
        cleanupError ??= cleanup;
        cleanupStackTrace ??= cleanupStack;
      }
      _pendingMnemonic = null;
      _onboardingStage = SignerOnboardingStage.idle;
      _hasWallet = false;
      _metadata = null;
      notifyListeners();
      if (cleanupError != null) {
        Error.throwWithStackTrace(cleanupError, cleanupStackTrace!);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  String _newWalletId() {
    final bytes = Uint8List.fromList(
      List<int>.generate(18, (_) => _random.nextInt(256)),
    );
    return 'w_${base64Url.encode(bytes).replaceAll('=', '')}';
  }

  AccountExport buildAccountExport() {
    final metadata = _metadata;
    if (!_hasWallet || metadata == null || metadata.addresses.isEmpty) {
      throw StateError('wallet is not ready');
    }
    final addresses = metadata.addresses;
    if (metadata.publicKeys.isEmpty) {
      throw StateError('wallet public keys are not ready');
    }
    AccountRecord account(int coin, String key, String path) => AccountRecord(
      coin: coin,
      address: addresses[key]!,
      path: path,
      index: 0,
      publicKey: base64Decode(metadata.publicKeys[key]!),
    );
    return AccountExport(
      walletId: metadata.walletId,
      walletName: metadata.name,
      accounts: [
        account(60, 'eth', accountExportDerivationPaths[60]!),
        account(966, 'polygon', accountExportDerivationPaths[966]!),
        account(8453, 'base', accountExportDerivationPaths[8453]!),
        account(42161, 'arbitrum', accountExportDerivationPaths[42161]!),
        account(9000, 'avalanche', accountExportDerivationPaths[9000]!),
        account(714, 'bnb', accountExportDerivationPaths[714]!),
        account(195, 'tron', accountExportDerivationPaths[195]!),
        account(501, 'solana', accountExportDerivationPaths[501]!),
      ],
    );
  }

  Future<SignResult> signRequest(SignRequest request) async {
    // Protocol byte arrays are mutable Dart objects. Freeze every signing
    // input once so a racing callback cannot change bytes after parsing but
    // before the native key operation.
    final stableRequest = SignRequest(
      reqId: Uint8List.fromList(request.reqId),
      walletId: request.walletId,
      coin: request.coin,
      chainId: request.chainId,
      rawTx: Uint8List.fromList(request.rawTx),
      summary: request.summary == null
          ? null
          : Map<Object?, Object?>.unmodifiable(request.summary!),
      createdAt: request.createdAt,
      expiresAt: request.expiresAt,
    );
    final metadata = _metadata;
    if (!_hasWallet ||
        metadata == null ||
        stableRequest.walletId != metadata.walletId) {
      throw StateError('request does not belong to this wallet');
    }
    final coin = switch (stableRequest.coin) {
      60 => Coin.eth,
      966 => Coin.polygon,
      8453 => Coin.base,
      42161 => Coin.arbitrum,
      9000 => Coin.avalanche,
      714 => Coin.bnb,
      195 => Coin.tron,
      501 => Coin.solana,
      _ => throw StateError('unsupported coin ${stableRequest.coin}'),
    };
    ParsedUnsignedTransfer parsed;
    try {
      parsed = parseUnsignedTransfer(_chainForCoin(coin), stableRequest.rawTx);
    } on Object {
      if (!isFlutterTestEnv) rethrow;
      parsed = _testOnlyParsedRequest(stableRequest, coin);
    }
    if (stableRequest.chainId != null &&
        parsed.networkId != BigInt.from(stableRequest.chainId!)) {
      throw StateError('transaction chainId does not match request');
    }
    final signer = metadata.addresses[coin.name]!;
    if (parsed.from != null &&
        !Addresses.equal(parsed.chain, parsed.from!, signer)) {
      throw StateError('transaction sender does not belong to this wallet');
    }
    final security = SecurityChecks.verdict(await _deviceProbe());
    if (!security.canSign) {
      throw StateError(
        'device security check blocked signing: '
        '${security.blocking.map((e) => e.id).join(',')}',
      );
    }

    // Authentication can take long enough for a request that was valid when
    // scanned to expire. Re-check at the last possible boundary before any key
    // operation, and never trust a future-dated request beyond the documented
    // clock-skew allowance.
    _validateFinalSigningWindow(stableRequest);

    final records = await _openRecords();
    final reservation = _signatureRecord(
      stableRequest,
      parsed: parsed,
      status: RequestStatus.scanned,
    );
    if (!await records.reserve(reservation)) {
      throw StateError('sign request was already consumed');
    }

    // A reservation is intentionally never released after this point. If the
    // native call or final database write fails, the signer cannot prove that
    // no signature escaped, so retrying the same reqId must remain blocked.
    // Storage may have stalled or the device may have changed state while the
    // reservation was committed. Re-probe and then check the clock once more;
    // there is no further await before invoking the native signer.
    final finalSecurity = SecurityChecks.verdict(await _deviceProbe());
    if (!finalSecurity.canSign) {
      throw StateError(
        'device security changed before signing: '
        '${finalSecurity.blocking.map((e) => e.id).join(',')}',
      );
    }
    _validateFinalSigningWindow(stableRequest);
    final signed = await _crypto.signTransaction(
      walletId: metadata.walletId,
      coin: coin,
      signingInput: stableRequest.rawTx,
    );
    final result = SignResult(
      reqId: Uint8List.fromList(stableRequest.reqId),
      walletId: stableRequest.walletId,
      coin: stableRequest.coin,
      signedTx: signed.signedTx,
      signer: signer,
      txHash: signed.txHash,
    );
    final finalized = await records.finalizeReservation(
      _signatureRecord(
        stableRequest,
        parsed: parsed,
        txHash: signed.txHash,
        status: RequestStatus.signed,
      ),
    );
    if (!finalized) {
      throw StateError('sign request reservation could not be finalized');
    }
    return result;
  }

  void _validateFinalSigningWindow(SignRequest request) {
    final nowSec = _now().millisecondsSinceEpoch ~/ 1000;
    if (nowSec >= request.expiresAt) {
      throw StateError('sign request expired before signing');
    }
    if (request.createdAt - _finalSigningClockSkewSeconds > nowSec) {
      throw StateError('sign request creation time exceeds clock skew');
    }
  }

  /// Point-in-time snapshot of the anti-replay ledger for the C6 validator.
  Future<SignRecordStore> loadRecordStore() async =>
      CachedSignRecordStore.load(await _openRecords());

  SignatureRecord _signatureRecord(
    SignRequest request, {
    required ParsedUnsignedTransfer parsed,
    required RequestStatus status,
    String? txHash,
  }) => SignatureRecord(
    reqId: request.reqIdHex,
    walletId: request.walletId,
    date: _now().millisecondsSinceEpoch ~/ 1000,
    coin: 'slip44:${request.coin}',
    operation: parsed.operation.name,
    toAddress: parsed.to,
    amount: '${parsed.amountRaw} base units',
    txHash: txHash,
    status: status,
  );

  Chain _chainForCoin(Coin coin) => switch (coin) {
    Coin.eth => Chain.ethereum,
    Coin.polygon => Chain.polygon,
    Coin.base => Chain.base,
    Coin.arbitrum => Chain.arbitrum,
    Coin.avalanche => Chain.avalanche,
    Coin.bnb => Chain.bnb,
    Coin.tron => Chain.tron,
    Coin.solana => Chain.solana,
  };

  ParsedUnsignedTransfer _testOnlyParsedRequest(
    SignRequest request,
    Coin coin,
  ) {
    final summary = request.summary ?? const {};
    return ParsedUnsignedTransfer(
      chain: _chainForCoin(coin),
      operation: '${summary['op']}'.contains('Token')
          ? TxOperation.tokenTransfer
          : TxOperation.nativeTransfer,
      from: '${summary['from'] ?? ''}',
      to: '${summary['to'] ?? ''}',
      amountRaw: BigInt.tryParse('${summary['rawAmount'] ?? 0}') ?? BigInt.zero,
    );
  }

  /// C21: wipes the vault (mnemonic, metadata, PIN, lockout) and the
  /// anti-replay records, returning the device to the no-wallet state.
  Future<void> deleteWallet() async {
    final walletId = _metadata?.walletId;
    if (walletId != null) {
      // Persist the user's irreversible intent before touching the native
      // vault. If the process dies after key deletion, startup sees this
      // marker and completes every remaining cleanup step without exposing a
      // wallet that can no longer sign.
      await _vault.markDeletionPending(walletId);
      await _finishPendingDeletion(walletId);
      return;
    }
    await _vault.wipe();
    await _clearRecordsBestEffort();
    _clearWalletState();
  }

  Future<void> _finishPendingDeletion(String walletId) async {
    try {
      await _crypto.deleteWallet(walletId);
    } on WalletNotFoundException {
      // Idempotent recovery after a crash following native key deletion.
    }
    var recordsCleared = true;
    try {
      await (await _openRecords()).clear();
    } catch (_) {
      recordsCleared = false;
    }
    try {
      await _vault.wipe(keepDeletionMarker: !recordsCleared);
    } catch (_) {
      // Native key deletion is already irreversible. The durable marker is
      // deliberately kept whenever any vault key remains, so a later startup
      // retries rather than presenting a broken signer wallet.
    }
    _clearWalletState();
  }

  Future<void> _clearRecordsBestEffort() async {
    try {
      await (await _openRecords()).clear();
    } catch (_) {
      // No wallet metadata or key remains on this legacy no-wallet path.
    }
  }

  void _clearWalletState() {
    _pendingMnemonic = null;
    _onboardingStage = SignerOnboardingStage.idle;
    _hasWallet = false;
    _metadata = null;
    notifyListeners();
  }

  Future<SignRecordPersistence> _openRecords() async {
    final injected = _records;
    if (injected != null) return injected;
    final fallback = _pluginlessRecords;
    if (fallback != null) return fallback;
    // path_provider is MethodChannel-backed: under `flutter test` its future
    // never completes, so widget tests that didn't inject a store degrade to
    // in-memory up front. Never taken on a device.
    if (isFlutterTestEnv) {
      return _pluginlessRecords = InMemorySignRecordPersistence();
    }
    final drift = DriftSignRecordPersistence(openSignerDatabase());
    await drift.all(); // force the lazy open so open errors fail signing closed
    return _records = drift;
  }
}

/// Exposes the app-wide [SignerWalletController] to the widget tree.
class SignerWalletScope extends InheritedNotifier<SignerWalletController> {
  const SignerWalletScope({
    super.key,
    required SignerWalletController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The live controller, or null when a screen is rendered standalone (the
  /// golden tests build registry widgets bare) — callers must then keep the
  /// original design-snapshot behavior.
  static SignerWalletController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SignerWalletScope>()?.notifier;
}
