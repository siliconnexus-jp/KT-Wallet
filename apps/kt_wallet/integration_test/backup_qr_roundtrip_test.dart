import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/src/security/backup_qr_image.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native QR image decoding and portable authenticated decryption round-trip',
    (tester) async {
      // Public vector from PortableBackupCipherTest; no user wallet is read,
      // created, imported or deleted. This uses only native stateless readBackup.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Encrypted backup QR verification')),
        ),
      );
      const hex =
          '000102030405060708090a0b0c0d0e0f101112131415161718191a1b'
          '364a29004ca61dca69b29ce63afbfa7315822fc380f858634e289bbb5b33dd43'
          'bf50be31944b5e4d9f6bbd81f23c53bc';
      final sealed = Uint8List.fromList([
        for (var i = 0; i < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ]);
      const password = 'Correct horse 電池🔐';
      final crypto = MethodChannelCoreCrypto();
      final original = await crypto.readBackup(
        blob: sealed,
        password: password,
        format: BackupCipherFormat.portableV2,
      );
      final payload = WalletBackupQr.encode(sealed);
      final png = await renderBackupQrPng(
        payload: payload,
        title: 'Encrypted QR',
        instruction: 'Password required. Not a receiving address.',
      );
      final scanned = await const BackupQrImageReader().read(png);
      expect(scanned, payload);
      final decoded = WalletBackupQr.decode(scanned);
      expect(
        await crypto.readBackup(
          blob: decoded.sealed,
          password: password,
          format: decoded.cryptoFormat,
        ),
        original,
      );
      await expectLater(
        crypto.readBackup(
          blob: decoded.sealed,
          password: 'wrong password',
          format: decoded.cryptoFormat,
        ),
        throwsA(isA<CoreCryptoException>()),
      );
      final tampered = Uint8List.fromList(decoded.sealed)..[40] ^= 1;
      await expectLater(
        crypto.readBackup(
          blob: tampered,
          password: password,
          format: decoded.cryptoFormat,
        ),
        throwsA(isA<CoreCryptoException>()),
      );
    },
  );
}
