import 'dart:convert';
import 'dart:typed_data';

import 'api.dart';

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

/// A closed, bounded transport for the existing native portable-v2 cipher.
/// Never accepts URLs, plaintext mnemonics, KDF parameters, or legacy fallback.
abstract final class WalletBackupQr {
  static const prefix = 'KTWALLET:BACKUP:2:';
  static const maxSealedBytes = 512;
  static const maxTextLength = 704;

  static String encode(Uint8List sealed) {
    // salt16 + nonce12 + entropy16..32 + GCM tag16; a bounded allowance
    // above that also supports test backends without enlarging QR capacity.
    if (sealed.length < 60 || sealed.length > maxSealedBytes) {
      throw const BackupFormatException('invalid QR backup size');
    }
    return '$prefix${base64UrlEncode(sealed)}';
  }

  static DecodedWalletBackup decode(String text) {
    if (text.length > maxTextLength || !text.startsWith(prefix)) {
      throw const BackupFormatException('not a supported encrypted backup QR');
    }
    try {
      final encoded = text.substring(prefix.length);
      final sealed = base64Url.decode(encoded);
      if (encode(sealed) != text) {
        throw const BackupFormatException('non-canonical backup QR');
      }
      return DecodedWalletBackup(
        envelopeVersion: 2,
        cryptoFormat: BackupCipherFormat.portableV2,
        sealed: sealed,
      );
    } on BackupFormatException {
      rethrow;
    } catch (_) {
      throw const BackupFormatException('invalid encrypted backup QR');
    }
  }
}
