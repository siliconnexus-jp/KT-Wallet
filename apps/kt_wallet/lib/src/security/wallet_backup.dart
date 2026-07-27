import 'dart:convert';
import 'dart:typed_data';

/// A backup file that is not ours, or is ours but damaged. Distinct from a
/// wrong password (which surfaces from the native seal as
/// `StoreCorruptedException`) so the UI can tell the user which mistake they
/// made — "that isn't a KT Wallet backup" and "wrong password" are very
/// different things to be told at 2am.
class BackupFormatException implements Exception {
  const BackupFormatException(this.reason);

  final String reason;

  @override
  String toString() => 'BackupFormatException: $reason';
}

/// The on-disk envelope for an encrypted wallet backup.
///
/// The payload is whatever [CoreCrypto.createBackup] sealed; everything else
/// here is metadata chosen so that a leaked file says as little as possible.
/// Deliberately absent: wallet name, addresses, balances, device identifiers —
/// the file discloses only that someone uses this app, and the KDF parameters
/// an attacker would learn from the ciphertext anyway.
///
/// JSON rather than a packed binary because a backup outlives the build that
/// wrote it: a support engineer three years from now can open it in a text
/// editor and see the version and cipher, instead of guessing at bytes.
abstract final class WalletBackupFile {
  static const format = 'kt-wallet-backup';
  static const version = 1;
  static const fileExtension = 'ktbak';

  /// Mirrors the native seal; recorded so a future format change can be
  /// detected on read rather than producing a mystery decryption failure.
  static const kdfAlgorithm = 'PBKDF2-HMAC-SHA256';
  static const kdfRounds = 210000;
  static const cipher = 'AES-256-GCM';

  static Uint8List encode({
    required Uint8List sealed,
    required DateTime createdAt,
  }) {
    if (sealed.isEmpty) {
      throw const BackupFormatException('nothing to write');
    }
    return Uint8List.fromList(
      utf8.encode(
        const JsonEncoder.withIndent('  ').convert({
          'format': format,
          'version': version,
          'kdf': {'alg': kdfAlgorithm, 'rounds': kdfRounds},
          'cipher': cipher,
          'createdAt': createdAt.toUtc().toIso8601String(),
          'payload': base64Encode(sealed),
        }),
      ),
    );
  }

  /// Returns the sealed payload, or throws [BackupFormatException].
  static Uint8List decode(Uint8List bytes) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      throw const BackupFormatException('not a KT Wallet backup file');
    }
    if (decoded is! Map || decoded['format'] != format) {
      throw const BackupFormatException('not a KT Wallet backup file');
    }
    final fileVersion = decoded['version'];
    if (fileVersion is! int || fileVersion > version) {
      // Written by a newer app. Say so rather than failing to decrypt: the fix
      // is to update, not to try another password.
      throw BackupFormatException('backup version $fileVersion is too new');
    }
    final payload = decoded['payload'];
    if (payload is! String || payload.isEmpty) {
      throw const BackupFormatException('backup file has no payload');
    }
    try {
      return base64Decode(payload);
    } catch (_) {
      throw const BackupFormatException('backup payload is damaged');
    }
  }

  /// Timestamped so a user with several backups can tell them apart in the
  /// Files app without opening them.
  static String suggestedFileName(DateTime at) {
    final t = at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'KT-Wallet-${t.year}${two(t.month)}${two(t.day)}'
        '-${two(t.hour)}${two(t.minute)}.$fileExtension';
  }

  /// The `createdAt` recorded in [bytes], or null when it is absent or
  /// unparsable. Display only — never a trust signal.
  static DateTime? createdAtOf(Uint8List bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) return null;
      final raw = decoded['createdAt'];
      return raw is String ? DateTime.tryParse(raw) : null;
    } catch (_) {
      return null;
    }
  }
}
