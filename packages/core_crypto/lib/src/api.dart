import 'dart:typed_data';
import 'dart:convert';

import 'types.dart';

/// Native payload formats accepted by [CoreCrypto.readBackup].
///
/// Version 1 is the legacy envelope: iOS wrote PBKDF2 while older Android
/// builds wrote Argon2id despite declaring PBKDF2 in the outer metadata.
/// Android therefore keeps a narrowly-scoped legacy fallback. Version 2 is
/// the portable PBKDF2-HMAC-SHA256/AES-GCM format emitted by every platform.
enum BackupCipherFormat {
  legacyV1(1),
  portableV2(2);

  const BackupCipherFormat(this.wireVersion);

  final int wireVersion;
}

/// Why a password cannot be used for a newly-created portable backup.
///
/// Restore deliberately does not apply this policy: older files may have been
/// created before the current floor and must not be stranded.
enum BackupPasswordIssue { tooShort, tooLong, predictable }

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

  /// Reports whether native secure storage contains this wallet without
  /// opening its secret or showing a system-authentication prompt.
  ///
  /// This is suitable for startup presence checks. It deliberately does not
  /// prove that persisted public addresses match the secret; callers that
  /// need that stronger guarantee must use [deriveAddresses] from an
  /// explicitly authenticated flow.
  Future<bool> walletExists(String walletId);

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
    required BackupCipherFormat format,
  });

  /// Removes the wallet and securely erases its key material.
  Future<void> deleteWallet(String walletId);

  Future<AuthState> getAuthState();
}

/// Shared request validation used by every [CoreCrypto] implementation, so
/// invalid requests fail fast and identically on real and mock backends.
abstract final class CoreCryptoValidation {
  static final _walletIdRe = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
  static const maxMnemonicUtf8Bytes = 512;
  static const maxWordUtf8Bytes = 64;
  static const maxKdfPasswordUtf8Bytes = 1024;
  static const maxBackupPasswordUtf8Bytes = 4096;
  static const maxSigningInputBytes = 1024 * 1024;
  static const maxBackupBlobBytes = 1024 * 1024;

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
    if (mnemonic.trim().isEmpty ||
        utf8.encode(mnemonic).length > maxMnemonicUtf8Bytes) {
      throw ArgumentError('mnemonic must not be empty');
    }
  }

  static void checkWord(String word) {
    if (utf8.encode(word).length > maxWordUtf8Bytes) {
      throw ArgumentError('word is too long');
    }
  }

  static void checkSuggestionPrefix(String prefix) => checkWord(prefix);

  static void checkKdfPassword(String? password) {
    if (password != null &&
        utf8.encode(password).length > maxKdfPasswordUtf8Bytes) {
      throw ArgumentError.value('<redacted>', 'kdfPassword', 'is too long');
    }
  }

  static void checkRestorePassword(String password) {
    if (password.isEmpty ||
        utf8.encode(password).length > maxBackupPasswordUtf8Bytes) {
      throw ArgumentError.value('<redacted>', 'password', 'invalid length');
    }
  }

  static void checkSuggestionLimit(int limit) {
    if (limit < 1 || limit > 20) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 20');
    }
  }

  /// Shortest password the backup KDF is allowed to stretch for a new file.
  ///
  /// A backup file is offline and unthrottled: an attacker who takes it can
  /// grind guesses at whatever rate their hardware allows, and 210k PBKDF2
  /// rounds cannot turn a common password into a secret. Fourteen Unicode
  /// scalar values permits a short multi-word passphrase while rejecting the
  /// password-manager/UI defaults that are most dangerous for an offline
  /// wallet backup.
  static const minBackupPasswordLength = 14;

  /// Bounds KDF input and catches accidental paste of unrelated documents.
  /// This is a creation rule only; restore accepts historical longer values.
  static const maxBackupPasswordLength = 128;

  static BackupPasswordIssue? backupPasswordIssue(String password) {
    final runes = password.runes.toList(growable: false);
    if (runes.length < minBackupPasswordLength) {
      return BackupPasswordIssue.tooShort;
    }
    if (runes.length > maxBackupPasswordLength) {
      return BackupPasswordIssue.tooLong;
    }

    // Reject very low-diversity and short-period repeats such as aaaaa...,
    // ababab..., or 12341234.... These have negligible entropy despite
    // satisfying a length-only rule.
    if (runes.toSet().length < 6 || _isShortPeriodRepeat(runes)) {
      return BackupPasswordIssue.predictable;
    }

    final compact = password.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
    const predictableAscii = <String>{
      'abcdefghijklmn',
      'zyxwvutsrqponm',
      '12345678901234',
      '98765432109876',
      'password123456',
      'qwertyuiopasdf',
      'asdfghjklqwerty',
      'letmein12345678',
      'iloveyou1234567',
      'admin123456789',
    };
    if (predictableAscii.contains(compact) || _isMonotonicAscii(runes)) {
      return BackupPasswordIssue.predictable;
    }
    return null;
  }

  static void checkBackupPassword(String password) {
    final issue = backupPasswordIssue(password);
    if (issue == null) return;
    final reason = switch (issue) {
      BackupPasswordIssue.tooShort =>
        'must be at least $minBackupPasswordLength characters',
      BackupPasswordIssue.tooLong =>
        'must be at most $maxBackupPasswordLength characters',
      BackupPasswordIssue.predictable => 'must not be predictable',
    };
    throw ArgumentError.value('<redacted>', 'password', reason);
  }

  static bool _isShortPeriodRepeat(List<int> runes) {
    for (var period = 1; period <= 4; period++) {
      if (runes.length % period != 0) continue;
      var repeated = true;
      for (var index = period; index < runes.length; index++) {
        if (runes[index] != runes[index % period]) {
          repeated = false;
          break;
        }
      }
      if (repeated) return true;
    }
    return false;
  }

  static bool _isMonotonicAscii(List<int> runes) {
    if (runes.length < minBackupPasswordLength) return false;
    final allDigits = runes.every((rune) => rune >= 0x30 && rune <= 0x39);
    final allLower = runes.every((rune) => rune >= 0x61 && rune <= 0x7a);
    final allUpper = runes.every((rune) => rune >= 0x41 && rune <= 0x5a);
    if (!allDigits && !allLower && !allUpper) return false;
    final delta = runes[1] - runes[0];
    if (delta != 1 && delta != -1) return false;
    for (var index = 2; index < runes.length; index++) {
      if (runes[index] - runes[index - 1] != delta) return false;
    }
    return true;
  }

  static void checkBackupBlobNotEmpty(Uint8List blob) {
    if (blob.isEmpty || blob.length > maxBackupBlobBytes) {
      throw ArgumentError('backup blob has an invalid size');
    }
  }

  static void checkSigningInput(Uint8List input) {
    if (input.isEmpty || input.length > maxSigningInputBytes) {
      throw ArgumentError('signingInput has an invalid size');
    }
  }
}
