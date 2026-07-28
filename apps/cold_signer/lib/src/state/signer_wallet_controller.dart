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
import '../signing/sign_record_store.dart';

/// The signer's persistent wallet state: mnemonic + metadata in the secure
/// vault, PIN via [PinLock], and the drift-backed anti-replay ledger.
///
/// Every live screen reads this through [SignerWalletScope.maybeOf] and MUST
/// fall back to the original design-snapshot rendering when the scope (or the
/// state it would provide) is absent — the dev gallery and the golden tests
/// run without any wallet state and must stay byte-identical.
class SignerWalletController extends ChangeNotifier {
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

  /// Whether a wallet is stored on this device (valid after [load]).
  bool get hasWallet => _hasWallet;

  WalletMetadata? get metadata => _metadata;
  bool get biometricEnabled => _metadata?.biometricEnabled ?? false;

  /// The freshly generated mnemonic of an onboarding session in progress
  /// (create flow, between C1 and C16); null otherwise. Cleared as soon as
  /// the wallet is persisted — key material must not linger in Dart memory.
  List<String>? get pendingMnemonic => _pendingMnemonic;

  String? get localWalletId => _metadata?.walletId;

  /// Loads vault state. Called once at startup (and safe to call again).
  Future<void> load() async {
    await _vault.removeLegacyMnemonic();
    _hasWallet = await _vault.hasWallet();
    _metadata = await _vault.readMetadata();
    if (_metadata != null) {
      try {
        final addresses = await _crypto.deriveAddresses(_metadata!.walletId);
        final publicKeys = await _crypto.derivePublicKeys(_metadata!.walletId);
        _metadata = _metadata!.copyWith(
          addresses: addresses.toMap(),
          publicKeys: publicKeys.toMap().map(
            (key, value) => MapEntry(key, base64Encode(value)),
          ),
        );
        await _vault.storeMetadata(_metadata!);
      } catch (_) {
        // Metadata without its native key is not a wallet. Fail closed instead
        // of booting a signer that can export fake accounts but cannot sign.
        await _vault.wipe();
        _metadata = null;
        _hasWallet = false;
      }
    }
    notifyListeners();
  }

  /// Starts the create-wallet flow: generates the real mnemonic that C3 will
  /// display and C4 will challenge.
  Future<List<String>> beginCreate() async {
    if (isFlutterTestEnv && _crypto is MethodChannelCoreCrypto) {
      _pendingMnemonic = generateMnemonic(random: _random);
      notifyListeners();
      return _pendingMnemonic!;
    }
    try {
      _pendingMnemonic = (await _crypto.generateMnemonic(
        strength: 128,
      )).trim().split(' ');
    } catch (_) {
      if (!isFlutterTestEnv) rethrow;
      _pendingMnemonic = generateMnemonic(random: _random);
    }
    notifyListeners();
    return _pendingMnemonic!;
  }

  /// Validates a complete BIP-39 phrase, including its checksum, without
  /// persisting anything. The native wallet is created only after PIN setup.
  Future<bool> beginImport(String mnemonic) async {
    final normalized = mnemonic.trim().toLowerCase().split(RegExp(r'\s+'));
    if (!const {12, 18, 24}.contains(normalized.length)) return false;
    if (!await _crypto.validateMnemonic(normalized.join(' '))) return false;
    if (_hasWallet) return false;
    _pendingMnemonic = normalized;
    notifyListeners();
    return true;
  }

  /// Builds C4's verification challenge over the pending mnemonic, or null
  /// when no create flow is in progress (gallery → canned demo challenge).
  QuizQuestion? buildVerifyChallenge() {
    final words = _pendingMnemonic;
    if (words == null) return null;
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

  /// Stores the app PIN (C14). PBKDF2 parameters live in [PinLock].
  Future<void> setPin(String pin) => _pinLock.setPin(pin);

  Future<bool> setBiometricEnabled(bool enabled) async {
    final metadata = _metadata;
    if (metadata == null) return false;
    if (enabled && !await BiometricAuth.instance.canAuthenticate()) {
      return false;
    }
    _metadata = metadata.copyWith(biometricEnabled: enabled);
    await _vault.storeMetadata(_metadata!);
    notifyListeners();
    return true;
  }

  /// Persists the pending wallet in the native crypto vault and drops the
  /// in-memory mnemonic. No-op when neither a create nor import flow is active.
  Future<void> completeOnboarding() async {
    final words = _pendingMnemonic;
    if (words == null) return;
    final walletId = _newWalletId();
    final metadata = WalletMetadata(
      walletId: walletId,
      name: '主钱包',
      createdAt: _now().millisecondsSinceEpoch ~/ 1000,
    );
    try {
      await _crypto.storeWallet(
        walletId: walletId,
        mnemonic: words.join(' '),
        requireAuth: true,
      );
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
      _hasWallet = true;
      _metadata = completed;
      notifyListeners();
    } catch (_) {
      // PIN is enrolled before this step. Roll it back with the metadata so a
      // failed native import never leaves a half-created wallet.
      await _vault.wipe();
      try {
        await _crypto.deleteWallet(walletId);
      } catch (_) {}
      rethrow;
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
        account(60, 'eth', "m/44'/60'/0'/0/0"),
        account(966, 'polygon', "m/44'/60'/0'/0/0"),
        account(8453, 'base', "m/44'/60'/0'/0/0"),
        account(42161, 'arbitrum', "m/44'/60'/0'/0/0"),
        account(9000, 'avalanche', "m/44'/60'/0'/0/0"),
        account(714, 'bnb', "m/44'/60'/0'/0/0"),
        account(195, 'tron', "m/44'/195'/0'/0/0"),
        account(501, 'solana', "m/44'/501'/0'/0'"),
      ],
    );
  }

  Future<SignResult> signRequest(SignRequest request) async {
    final metadata = _metadata;
    if (!_hasWallet ||
        metadata == null ||
        request.walletId != metadata.walletId) {
      throw StateError('request does not belong to this wallet');
    }
    final coin = switch (request.coin) {
      60 => Coin.eth,
      966 => Coin.polygon,
      8453 => Coin.base,
      42161 => Coin.arbitrum,
      9000 => Coin.avalanche,
      714 => Coin.bnb,
      195 => Coin.tron,
      501 => Coin.solana,
      _ => throw StateError('unsupported coin ${request.coin}'),
    };
    ParsedUnsignedTransfer parsed;
    try {
      parsed = parseUnsignedTransfer(_chainForCoin(coin), request.rawTx);
    } on Object {
      if (!isFlutterTestEnv) rethrow;
      parsed = _testOnlyParsedRequest(request, coin);
    }
    if (request.chainId != null &&
        parsed.networkId != BigInt.from(request.chainId!)) {
      throw StateError('transaction chainId does not match request');
    }
    final security = SecurityChecks.verdict(await _deviceProbe());
    if (!security.canSign) {
      throw StateError(
        'device security check blocked signing: '
        '${security.blocking.map((e) => e.id).join(',')}',
      );
    }
    final signed = await _crypto.signTransaction(
      walletId: metadata.walletId,
      coin: coin,
      signingInput: request.rawTx,
    );
    final signer = metadata.addresses[coin.name]!;
    final result = SignResult(
      reqId: request.reqId,
      walletId: request.walletId,
      coin: request.coin,
      signedTx: signed.signedTx,
      signer: signer,
      txHash: signed.txHash,
    );
    await recordSigned(request, parsed: parsed, txHash: signed.txHash);
    return result;
  }

  /// Point-in-time snapshot of the anti-replay ledger for the C6 validator.
  Future<SignRecordStore> loadRecordStore() async =>
      CachedSignRecordStore.load(await _openRecords());

  /// Commits a signed request's reqId to the durable ledger. Called BEFORE
  /// the result QR is shown (crash-safety ordering, DD §3.4): once recorded,
  /// re-scanning the same request routes to /risk as a duplicate.
  Future<void> recordSigned(
    SignRequest request, {
    ParsedUnsignedTransfer? parsed,
    String? txHash,
  }) async {
    final transaction =
        parsed ??
        parseUnsignedTransfer(
          _chainForCoin(
            switch (request.coin) {
              60 => Coin.eth,
              966 => Coin.polygon,
              8453 => Coin.base,
              42161 => Coin.arbitrum,
              9000 => Coin.avalanche,
              714 => Coin.bnb,
              195 => Coin.tron,
              501 => Coin.solana,
              _ => throw StateError('unsupported coin ${request.coin}'),
            },
          ),
          request.rawTx,
        );
    await (await _openRecords()).put(
      SignatureRecord(
        reqId: request.reqIdHex,
        walletId: request.walletId,
        date: _now().millisecondsSinceEpoch ~/ 1000,
        coin: 'slip44:${request.coin}',
        operation: transaction.operation.name,
        toAddress: transaction.to,
        amount: '${transaction.amountRaw} base units',
        txHash: txHash,
        status: RequestStatus.signed,
      ),
    );
  }

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
      await _crypto.deleteWallet(walletId);
    }
    await _vault.wipe();
    try {
      await (await _openRecords()).clear();
    } catch (_) {
      // Records live in a separate store; a failed clear must not block the
      // key-material wipe that already happened above.
    }
    _pendingMnemonic = null;
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
    try {
      final drift = DriftSignRecordPersistence(openSignerDatabase());
      await drift.all(); // force the lazy open so open errors surface here
      return _records = drift;
    } catch (_) {
      return _pluginlessRecords = InMemorySignRecordPersistence();
    }
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
