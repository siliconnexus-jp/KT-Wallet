import 'package:cold_signer/src/security/pin_lock.dart';
import 'package:cold_signer/src/security/secure_vault.dart';
import 'package:cold_signer/src/signing/sign_record_store.dart';
import 'package:cold_signer/src/state/signer_wallet_controller.dart';
import 'package:core_crypto/testing.dart';
import 'package:flutter_test/flutter_test.dart';

class _DeleteTrackingCrypto extends MockCoreCrypto {
  final deletedWalletIds = <String>[];

  @override
  Future<void> deleteWallet(String walletId) async {
    deletedWalletIds.add(walletId);
    await super.deleteWallet(walletId);
  }
}

const _mnemonic =
    'abandon ability able about above absent absorb abstract absurd abuse access accident';

void main() {
  test(
    'metadata rejects ambiguous, open, invalid, and oversized records',
    () async {
      final storage = InMemoryVaultStorage();
      final vault = SecureVault(storage);
      await vault.storeMetadata(
        const WalletMetadata(
          walletId: 'wallet_a',
          name: 'KT Cold Signer',
          createdAt: 1785888000,
        ),
      );
      final valid = storage.values[SecureVault.metadataKey]!;

      for (final malformed in [
        valid.replaceFirst(
          '"walletId":"wallet_a"',
          '"walletId":"wallet_a","walletId":"wallet_b"',
        ),
        valid.replaceFirst(
          '"walletId":"wallet_a"',
          '"walletId":"wallet_a","wallet\\u0049d":"wallet_b"',
        ),
        '${valid.substring(0, valid.length - 1)},"memo":"ignored"}',
        valid.replaceFirst('"version":2', '"version":3'),
        valid.replaceFirst('"version":2', '"version":null'),
        valid.replaceFirst('"walletId":"wallet_a"', '"walletId":"../wallet"'),
        valid.replaceFirst('"name":"KT Cold Signer"', '"name":""'),
        valid.replaceFirst('"createdAt":1785888000', '"createdAt":-1'),
        valid.replaceFirst('"addresses":{}', '"addresses":[]'),
        valid.replaceFirst(
          '"biometricEnabled":false',
          '"biometricEnabled":null',
        ),
        ' ' * 16385,
      ]) {
        storage.values[SecureVault.metadataKey] = malformed;
        expect(
          () => vault.readMetadata(),
          throwsA(isA<VaultStateCorruptedException>()),
        );
        expect(
          () => vault.hasWallet(),
          throwsA(isA<VaultStateCorruptedException>()),
        );
      }
    },
  );

  test('deletion marker rejects malformed wallet identity', () async {
    final storage = InMemoryVaultStorage();
    final vault = SecureVault(storage);
    for (final malformed in ['../wallet', '', 'x' * 65]) {
      storage.values[SecureVault.deletionPendingKey] = malformed;
      expect(
        () => vault.pendingDeletionWalletId(),
        throwsA(isA<VaultStateCorruptedException>()),
      );
    }
  });

  test(
    'mismatched deletion marker never deletes either native wallet',
    () async {
      final storage = InMemoryVaultStorage();
      final crypto = _DeleteTrackingCrypto();
      await crypto.storeWallet(walletId: 'wallet_a', mnemonic: _mnemonic);
      await crypto.storeWallet(walletId: 'wallet_b', mnemonic: _mnemonic);
      await SecureVault(storage).storeMetadata(
        const WalletMetadata(
          walletId: 'wallet_a',
          name: 'Wallet A',
          createdAt: 1785888000,
        ),
      );
      await PinLock(storage, iterations: 500).setPin('135790');
      storage.values[SecureVault.deletionPendingKey] = 'wallet_b';
      final controller = SignerWalletController(
        storage: storage,
        crypto: crypto,
        records: InMemorySignRecordPersistence(),
        pinIterations: 500,
      );

      await expectLater(
        controller.load(),
        throwsA(isA<VaultStateCorruptedException>()),
      );
      expect(crypto.deletedWalletIds, isEmpty);
      expect(crypto.storedWalletCount, 2);
      expect(storage.values[SecureVault.metadataKey], isNotNull);
    },
  );

  test(
    'marker without metadata cleans residue without deleting arbitrary key',
    () async {
      final storage = InMemoryVaultStorage()
        ..values[SecureVault.deletionPendingKey] = 'wallet_b';
      final crypto = _DeleteTrackingCrypto();
      await crypto.storeWallet(walletId: 'wallet_b', mnemonic: _mnemonic);
      final controller = SignerWalletController(
        storage: storage,
        crypto: crypto,
        records: InMemorySignRecordPersistence(),
      );

      await controller.load();

      expect(crypto.deletedWalletIds, isEmpty);
      expect(crypto.storedWalletCount, 1);
      expect(storage.values, isEmpty);
      expect(controller.hasWallet, isFalse);
    },
  );
}
