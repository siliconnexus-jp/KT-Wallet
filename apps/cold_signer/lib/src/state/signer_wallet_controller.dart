import 'dart:math';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:flutter/widgets.dart';

import '../data/database_provider.dart';
import '../data/signer_database.dart';
import '../security/mnemonic_wordlist.dart';
import '../security/pin_lock.dart';
import '../security/secure_vault.dart';
import '../signing/demo_airgap.dart';
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
    Random? random,
    DateTime Function()? clock,
    int? pinIterations,
  })  : _storage = storage ?? SecureVaultStorage(),
        _random = random ?? Random.secure(),
        _now = clock ?? DateTime.now {
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

  /// The freshly generated mnemonic of an onboarding session in progress
  /// (create flow, between C1 and C16); null otherwise. Cleared as soon as
  /// the wallet is persisted — key material must not linger in Dart memory.
  List<String>? get pendingMnemonic => _pendingMnemonic;

  /// The wallet id incoming sign-requests must carry. The demo hot wallet
  /// addresses its traffic to [demoWalletId], so a wallet created on this
  /// device enrolls under that id (a production signer would generate a
  /// random id and hand it to the hot wallet via the account-export QR).
  String get localWalletId => _metadata?.walletId ?? demoWalletId;

  /// Loads vault state. Called once at startup (and safe to call again).
  Future<void> load() async {
    _hasWallet = await _vault.hasWallet();
    _metadata = await _vault.readMetadata();
    notifyListeners();
  }

  /// Starts the create-wallet flow: generates the real mnemonic that C3 will
  /// display and C4 will challenge.
  List<String> beginCreate() {
    _pendingMnemonic = generateMnemonic(random: _random);
    notifyListeners();
    return _pendingMnemonic!;
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
      pickIndices: (wordCount, count) =>
          [for (var i = 0; i < count; i++) _random.nextInt(wordCount)],
      distractorsFor: (correct, n) =>
          drawDistractors(correct, n, random: _random),
    ).single;
  }

  /// Stores the app PIN (C14). PBKDF2 parameters live in [PinLock].
  Future<void> setPin(String pin) => _pinLock.setPin(pin);

  /// Persists the pending wallet to the vault (C16 completion) and drops the
  /// in-memory mnemonic. No-op when no create flow is in progress (the
  /// import flow is still a design mock and never reaches here with state).
  Future<void> completeOnboarding() async {
    final words = _pendingMnemonic;
    if (words == null) return;
    final metadata = WalletMetadata(
      walletId: demoWalletId, // see [localWalletId]
      name: '主钱包',
      createdAt: _now().millisecondsSinceEpoch ~/ 1000,
    );
    await _vault.storeWallet(mnemonic: words, metadata: metadata);
    _pendingMnemonic = null;
    _hasWallet = true;
    _metadata = metadata;
    notifyListeners();
  }

  /// Point-in-time snapshot of the anti-replay ledger for the C6 validator.
  Future<SignRecordStore> loadRecordStore() async =>
      CachedSignRecordStore.load(await _openRecords());

  /// Commits a signed request's reqId to the durable ledger. Called BEFORE
  /// the result QR is shown (crash-safety ordering, DD §3.4): once recorded,
  /// re-scanning the same request routes to /risk as a duplicate.
  Future<void> recordSigned(SignRequest request, {String? txHash}) async {
    final summary = request.summary ?? const {};
    await (await _openRecords()).put(SignatureRecord(
      reqId: request.reqIdHex,
      walletId: request.walletId,
      date: _now().millisecondsSinceEpoch ~/ 1000,
      coin: 'slip44:${request.coin}',
      operation: '${summary['op'] ?? 'transfer'}',
      toAddress: '${summary['to'] ?? ''}',
      amount: '${summary['amount'] ?? ''} ${summary['token'] ?? ''}'.trim(),
      txHash: txHash,
      status: RequestStatus.signed,
    ));
  }

  /// C21: wipes the vault (mnemonic, metadata, PIN, lockout) and the
  /// anti-replay records, returning the device to the no-wallet state.
  Future<void> deleteWallet() async {
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
  const SignerWalletScope(
      {super.key, required SignerWalletController controller, required super.child})
      : super(notifier: controller);

  /// The live controller, or null when a screen is rendered standalone (the
  /// golden tests build registry widgets bare) — callers must then keep the
  /// original design-snapshot behavior.
  static SignerWalletController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SignerWalletScope>()?.notifier;
}
