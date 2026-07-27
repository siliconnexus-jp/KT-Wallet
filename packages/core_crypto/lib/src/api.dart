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

  /// Derives the public keys used by those accounts. No private material
  /// crosses the native boundary.
  Future<ChainPublicKeys> derivePublicKeys(String walletId);

  /// Signs a wallet-core SigningInput. Triggers native authentication.
  Future<SignedTransaction> signTransaction({
    required String walletId,
    required Coin coin,
    required Uint8List signingInput,
  });

  /// Returns the mnemonic for backup review. Strong auth enforced natively.
  Future<String> exportMnemonic(String walletId);

  /// Seals the wallet's entropy under [password] for off-device backup.
  ///
  /// Strong auth is enforced natively, exactly as for [exportMnemonic] — the
  /// two disclose the same secret, one to the screen and one to a file. The
  /// plaintext entropy never crosses this boundary: the returned bytes are
  /// `salt(16) || nonce || ciphertext || tag`, PBKDF2-HMAC-SHA256 (210k) into
  /// AES-256-GCM. Losing [password] loses the backup; there is no recovery
  /// path, by construction.
  Future<Uint8List> createBackup({
    required String walletId,
    required String password,
  });

  /// Opens a blob from [createBackup] and returns the mnemonic, for the normal
  /// import path to store as a wallet.
  ///
  /// No biometric prompt: the file is already off-device, so [password] is the
  /// only thing standing between the holder and the secret. A wrong password
  /// is indistinguishable from a corrupt file (GCM tells you no more than
  /// "this did not authenticate") and surfaces as [StoreCorruptedException].
  Future<String> readBackup({
    required Uint8List blob,
    required String password,
  });

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

  /// Shortest password the backup KDF is allowed to stretch.
  ///
  /// A backup file is offline and unthrottled: an attacker who takes it can
  /// grind guesses at whatever rate their hardware allows, and 210k PBKDF2
  /// rounds buy roughly a millisecond each. The floor is a blunt instrument —
  /// it stops "1234", not a determined bad choice — so the UI states the
  /// stakes rather than relying on this alone.
  static const minBackupPasswordLength = 8;

  static void checkBackupPassword(String password) {
    if (password.length < minBackupPasswordLength) {
      throw ArgumentError.value(
        '<redacted>',
        'password',
        'must be at least $minBackupPasswordLength characters',
      );
    }
  }

  static void checkBackupBlobNotEmpty(Uint8List blob) {
    if (blob.isEmpty) throw ArgumentError('backup blob must not be empty');
  }

  static void checkSigningInput(Uint8List input) {
    if (input.isEmpty) {
      throw ArgumentError('signingInput must not be empty');
    }
  }
}
