import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';

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

/// A validated envelope plus the exact native payload format it declares.
/// Keeping these together prevents callers from stripping the version and
/// accidentally invoking a legacy KDF fallback for a new backup.
class DecodedWalletBackup {
  const DecodedWalletBackup({
    required this.envelopeVersion,
    required this.cryptoFormat,
    required this.sealed,
  });

  final int envelopeVersion;
  final BackupCipherFormat cryptoFormat;
  final Uint8List sealed;
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
  static const version = 2;
  static const legacyVersion = 1;
  static const fileExtension = 'ktbak';

  /// A mnemonic backup is only a few hundred bytes. Keep a generous ceiling
  /// for future envelope versions, but reject an arbitrary document before it
  /// can be decoded, copied again over a platform channel, or handed to the
  /// native crypto layer.
  static const maxFileBytes = 256 * 1024;

  /// Mirrors the native seal; recorded so a future format change can be
  /// detected on read rather than producing a mystery decryption failure.
  static const kdfAlgorithm = 'PBKDF2-HMAC-SHA256';
  static const kdfRounds = 210000;
  static const cipher = 'AES-256-GCM';
  static const payloadFormat = 'salt16-nonce12-aes256gcm-v1';

  static Uint8List encode({
    required Uint8List sealed,
    required DateTime createdAt,
  }) {
    if (sealed.isEmpty) {
      throw const BackupFormatException('nothing to write');
    }
    final bytes = Uint8List.fromList(
      utf8.encode(
        const JsonEncoder.withIndent('  ').convert({
          'format': format,
          'version': version,
          'kdf': {'alg': kdfAlgorithm, 'rounds': kdfRounds},
          'cipher': cipher,
          'payloadFormat': payloadFormat,
          'createdAt': createdAt.toUtc().toIso8601String(),
          'payload': base64Encode(sealed),
        }),
      ),
    );
    if (bytes.length > maxFileBytes) {
      throw const BackupFormatException('backup file size is invalid');
    }
    return bytes;
  }

  /// Returns the sealed payload, or throws [BackupFormatException].
  static Uint8List decode(Uint8List bytes) => decodeEnvelope(bytes).sealed;

  /// Validates the closed schema and preserves the payload version for native
  /// decryption. Version 1 remains readable for existing users; only version 2
  /// is ever written by current builds.
  static DecodedWalletBackup decodeEnvelope(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxFileBytes) {
      throw const BackupFormatException('backup file size is invalid');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      throw const BackupFormatException('not a KT Wallet backup file');
    }
    if (decoded is! Map<String, dynamic> || decoded['format'] != format) {
      throw const BackupFormatException('not a KT Wallet backup file');
    }
    final fileVersion = decoded['version'];
    if (fileVersion is int && fileVersion > version) {
      // A newer envelope may legitimately have a different closed schema. Say
      // "update the app" before validating fields this build cannot know.
      throw BackupFormatException('backup version $fileVersion is too new');
    }
    const v1Keys = {
      'format',
      'version',
      'kdf',
      'cipher',
      'createdAt',
      'payload',
    };
    const v2Keys = {...v1Keys, 'payloadFormat'};
    final expectedKeys = switch (fileVersion) {
      legacyVersion => v1Keys,
      version => v2Keys,
      _ => const <String>{},
    };
    if (expectedKeys.isEmpty) {
      throw const BackupFormatException('backup version is unsupported');
    }
    if (decoded.keys.toSet().difference(expectedKeys).isNotEmpty ||
        expectedKeys.difference(decoded.keys.toSet()).isNotEmpty) {
      throw const BackupFormatException('backup envelope is damaged');
    }
    final kdf = decoded['kdf'];
    if (kdf is! Map<String, dynamic> ||
        kdf.keys.toSet().difference(const {'alg', 'rounds'}).isNotEmpty ||
        const {'alg', 'rounds'}.difference(kdf.keys.toSet()).isNotEmpty ||
        kdf['alg'] != kdfAlgorithm ||
        kdf['rounds'] != kdfRounds ||
        decoded['cipher'] != cipher) {
      throw const BackupFormatException(
        'backup crypto metadata is unsupported',
      );
    }
    if (fileVersion == version && decoded['payloadFormat'] != payloadFormat) {
      throw const BackupFormatException('backup payload format is unsupported');
    }
    final createdAt = decoded['createdAt'];
    final parsedCreatedAt = createdAt is String
        ? DateTime.tryParse(createdAt)
        : null;
    if (parsedCreatedAt == null || !parsedCreatedAt.isUtc) {
      throw const BackupFormatException('backup timestamp is damaged');
    }
    final payload = decoded['payload'];
    if (payload is! String || payload.isEmpty) {
      throw const BackupFormatException('backup file has no payload');
    }
    try {
      final sealed = base64Decode(payload);
      if (sealed.isEmpty) {
        throw const BackupFormatException('backup payload is damaged');
      }
      return DecodedWalletBackup(
        envelopeVersion: fileVersion as int,
        cryptoFormat: fileVersion == legacyVersion
            ? BackupCipherFormat.legacyV1
            : BackupCipherFormat.portableV2,
        sealed: sealed,
      );
    } on BackupFormatException {
      rethrow;
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
    if (bytes.isEmpty || bytes.length > maxFileBytes) return null;
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
