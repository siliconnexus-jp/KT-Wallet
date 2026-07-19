import 'dart:typed_data';

import 'types.dart';

/// Key management and signing API. All key material lives on the native side;
/// mnemonics only cross this boundary during onboarding/backup/export flows
/// (detailed-design.md §2).
abstract class CoreCrypto {
  /// Generates a BIP-39 mnemonic (128/192/256 bits → 12/18/24 words).
  Future<String> generateMnemonic({int strength = 128});

  Future<bool> validateMnemonic(String mnemonic);

  /// Validates a single word against the BIP-39 wordlist.
  Future<bool> validateWord(String word);

  /// Wordlist completions for [prefix] (import flow suggestions).
  Future<List<String>> suggestWords(String prefix, {int limit = 3});

  /// Persists a wallet into native secure storage. After this call the Dart
  /// side must drop its mnemonic reference.
  ///
  /// [kdfPassword] enables the Cold Signer double-encryption layer.
  Future<void> storeWallet({
    required String walletId,
    required String mnemonic,
    bool requireAuth = true,
    String? kdfPassword,
  });

  /// Derives public addresses for all supported chains.
  Future<ChainAddresses> deriveAddresses(String walletId);

  /// Signs a wallet-core SigningInput. Triggers native authentication.
  Future<SignedTransaction> signTransaction({
    required String walletId,
    required Coin coin,
    required Uint8List signingInput,
  });

  /// Returns the mnemonic for backup review. Strong auth enforced natively.
  Future<String> exportMnemonic(String walletId);

  /// Removes the wallet and securely erases its key material.
  Future<void> deleteWallet(String walletId);

  Future<AuthState> getAuthState();
}

/// Shared request validation used by every [CoreCrypto] implementation, so
/// invalid requests fail fast and identically on real and mock backends.
abstract final class CoreCryptoValidation {
  static final _walletIdRe = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  static void checkStrength(int strength) {
    if (!allowedMnemonicStrengths.contains(strength)) {
      throw ArgumentError.value(
        strength,
        'strength',
        'must be one of $allowedMnemonicStrengths',
      );
    }
  }

  static void checkWalletId(String walletId) {
    if (!_walletIdRe.hasMatch(walletId)) {
      throw ArgumentError.value(walletId, 'walletId', 'invalid wallet id');
    }
  }

  static void checkMnemonicNotEmpty(String mnemonic) {
    if (mnemonic.trim().isEmpty) {
      throw ArgumentError('mnemonic must not be empty');
    }
  }

  static void checkSigningInput(Uint8List input) {
    if (input.isEmpty) {
      throw ArgumentError('signingInput must not be empty');
    }
  }
}
