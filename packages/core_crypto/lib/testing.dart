/// Deterministic in-memory [CoreCrypto] for app-layer tests (no real crypto).
///
/// Addresses/signatures are hash-derived pseudo values — stable across runs
/// but intentionally NOT real derivations. Real-vector verification happens in
/// the native instrumented tests (todolist.md P1-2/P1-3).
library;

import 'dart:typed_data';

import 'core_crypto.dart';

/// Small embedded BIP-39-style wordlist (first 64 real BIP-39 words) used for
/// deterministic generation and word validation in tests.
const mockWordlist = [
  'abandon', 'ability', 'able', 'about', 'above', 'absent', 'absorb',
  'abstract', 'absurd', 'abuse', 'access', 'accident', 'account', 'accuse',
  'achieve', 'acid', 'acoustic', 'acquire', 'across', 'act', 'action',
  'actor', 'actress', 'actual', 'adapt', 'add', 'addict', 'address',
  'adjust', 'admit', 'adult', 'advance', 'advice', 'aerobic', 'affair',
  'afford', 'afraid', 'again', 'age', 'agent', 'agree', 'ahead', 'aim',
  'air', 'airport', 'aisle', 'alarm', 'album', 'alcohol', 'alert', 'alien',
  'all', 'alley', 'allow', 'almost', 'alone', 'alpha', 'already', 'also',
  'alter', 'always', 'amateur', 'amazing', 'among',
];

class _StoredWallet {
  _StoredWallet(this.mnemonic, {required this.requireAuth, this.kdfPassword});

  final String mnemonic;
  final bool requireAuth;
  final String? kdfPassword;
}

/// Mirrors the native lockout ladder (detailed-design.md §2.4) so app-layer
/// lockout UI can be tested without native code.
class MockCoreCrypto implements CoreCrypto {
  MockCoreCrypto({
    Future<bool> Function()? authenticator,
    DateTime Function()? clock,
  })  : _authenticate = authenticator ?? (() async => true),
        _now = clock ?? DateTime.now;

  final Future<bool> Function() _authenticate;
  final DateTime Function() _now;
  final _wallets = <String, _StoredWallet>{};

  int _generateCounter = 0;
  int _failCount = 0;
  DateTime? _lockedUntil;

  int get storedWalletCount => _wallets.length;

  // ---- auth ladder -------------------------------------------------------

  int _cooldownForFailCount(int fails) {
    if (fails >= 15) return 900;
    if (fails >= 10) return 300;
    if (fails >= 5) return 60;
    return 0;
  }

  int get _remainingCooldown {
    final until = _lockedUntil;
    if (until == null) return 0;
    final remaining = until.difference(_now()).inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  Future<void> _requireAuth() async {
    if (_remainingCooldown > 0) {
      throw AuthLockedException(_remainingCooldown);
    }
    if (await _authenticate()) {
      _failCount = 0;
      _lockedUntil = null;
      return;
    }
    _failCount += 1;
    final cooldown = _cooldownForFailCount(_failCount);
    if (cooldown > 0) {
      _lockedUntil = _now().add(Duration(seconds: cooldown));
      throw AuthLockedException(cooldown);
    }
    throw const AuthFailedException();
  }

  // ---- deterministic helpers --------------------------------------------

  /// FNV-1a variant kept non-negative (Dart ints are signed 64-bit; a plain
  /// 64-bit mask can yield negatives, breaking radix/modulo math).
  static int _fnv1a(String input, [int seed = 0xcbf29ce484222325]) {
    var hash = seed & 0x7FFFFFFFFFFFFFFF;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0x7FFFFFFFFFFFFFFF;
    }
    return hash;
  }

  static String _hexStream(String input, int hexChars) {
    final buffer = StringBuffer();
    var round = 0;
    while (buffer.length < hexChars) {
      buffer.write(_fnv1a('$input:$round').toRadixString(16).padLeft(16, '0'));
      round++;
    }
    return buffer.toString().substring(0, hexChars);
  }

  static const _base58 =
      '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

  static String _base58Stream(String input, int chars) {
    final buffer = StringBuffer();
    var round = 0;
    while (buffer.length < chars) {
      var hash = _fnv1a('$input:$round');
      while (hash > 0 && buffer.length < chars) {
        buffer.write(_base58[hash % 58]);
        hash ~/= 58;
      }
      round++;
    }
    return buffer.toString();
  }

  // ---- CoreCrypto --------------------------------------------------------

  @override
  Future<String> generateMnemonic({int strength = 128}) async {
    CoreCryptoValidation.checkStrength(strength);
    final wordCount = strength ~/ 32 * 3;
    final seed = _generateCounter++;
    return List.generate(
      wordCount,
      (i) => mockWordlist[_fnv1a('gen:$seed:$i') % mockWordlist.length],
    ).join(' ');
  }

  @override
  Future<bool> validateMnemonic(String mnemonic) async {
    CoreCryptoValidation.checkMnemonicNotEmpty(mnemonic);
    final words = mnemonic.trim().split(RegExp(r'\s+'));
    if (!{12, 18, 24}.contains(words.length)) return false;
    return words.every(mockWordlist.contains);
  }

  @override
  Future<bool> validateWord(String word) async => mockWordlist.contains(word);

  @override
  Future<List<String>> suggestWords(String prefix, {int limit = 3}) async {
    if (prefix.trim().isEmpty) return const [];
    return mockWordlist.where((w) => w.startsWith(prefix)).take(limit).toList();
  }

  @override
  Future<void> storeWallet({
    required String walletId,
    required String mnemonic,
    bool requireAuth = true,
    String? kdfPassword,
  }) async {
    CoreCryptoValidation.checkWalletId(walletId);
    if (!await validateMnemonic(mnemonic)) {
      throw const InvalidMnemonicException();
    }
    _wallets[walletId] = _StoredWallet(
      mnemonic,
      requireAuth: requireAuth,
      kdfPassword: kdfPassword,
    );
  }

  _StoredWallet _walletOrThrow(String walletId) {
    final wallet = _wallets[walletId];
    if (wallet == null) throw WalletNotFoundException(walletId);
    return wallet;
  }

  @override
  Future<ChainAddresses> deriveAddresses(String walletId) async {
    CoreCryptoValidation.checkWalletId(walletId);
    final wallet = _walletOrThrow(walletId);
    final m = wallet.mnemonic;
    final evm = '0x${_hexStream('$m:evm', 40)}';
    return ChainAddresses(
      eth: evm,
      polygon: evm,
      tron: 'T${_base58Stream('$m:tron', 33)}',
      solana: _base58Stream('$m:solana', 44),
    );
  }

  @override
  Future<SignedTransaction> signTransaction({
    required String walletId,
    required Coin coin,
    required Uint8List signingInput,
  }) async {
    CoreCryptoValidation.checkWalletId(walletId);
    CoreCryptoValidation.checkSigningInput(signingInput);
    final wallet = _walletOrThrow(walletId);
    if (wallet.requireAuth) await _requireAuth();

    final seed = '${wallet.mnemonic}:${coin.name}:${signingInput.join(",")}';
    final hex = _hexStream(seed, 128);
    final bytes = Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
    return SignedTransaction(
      signedTx: bytes,
      txHash: '0x${_hexStream('$seed:hash', 64)}',
    );
  }

  @override
  Future<String> exportMnemonic(String walletId) async {
    CoreCryptoValidation.checkWalletId(walletId);
    final wallet = _walletOrThrow(walletId);
    await _requireAuth();
    return wallet.mnemonic;
  }

  @override
  Future<void> deleteWallet(String walletId) async {
    CoreCryptoValidation.checkWalletId(walletId);
    _walletOrThrow(walletId);
    await _requireAuth();
    _wallets.remove(walletId);
  }

  @override
  Future<AuthState> getAuthState() async {
    final cooldown = _remainingCooldown;
    return AuthState(
      locked: cooldown > 0,
      failCount: _failCount,
      cooldownSec: cooldown,
    );
  }
}
