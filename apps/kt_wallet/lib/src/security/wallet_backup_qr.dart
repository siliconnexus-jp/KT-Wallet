import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';

import 'wallet_backup.dart';

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
        envelopeVersion: WalletBackupFile.version,
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
