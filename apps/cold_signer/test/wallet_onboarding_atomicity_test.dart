import 'package:cold_signer/src/security/pin_lock.dart';
import 'package:cold_signer/src/security/secure_vault.dart';
import 'package:cold_signer/src/signing/sign_record_store.dart';
import 'package:cold_signer/src/state/signer_wallet_controller.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:core_crypto/testing.dart';
import 'package:flutter_test/flutter_test.dart';

class _FailingDeriveCrypto extends MockCoreCrypto {
  @override
  Future<ChainAddresses> deriveAddresses(String walletId) =>
      Future<ChainAddresses>.error(StateError('native derive unavailable'));
}

class _TrackingCrypto extends MockCoreCrypto {
  int deleteCalls = 0;

  @override
  Future<void> deleteWallet(String walletId) async {
    deleteCalls += 1;
    await super.deleteWallet(walletId);
  }
}

class _MetadataWriteFailureStorage extends InMemoryVaultStorage {
  final List<String> deletedKeys = <String>[];
  bool failFirstDelete = false;

  @override
  Future<void> write(String key, String value) async {
    if (key == SecureVault.metadataKey) {
      throw StateError('metadata store unavailable');
    }
    await super.write(key, value);
  }

  @override
  Future<void> delete(String key) async {
    deletedKeys.add(key);
    if (failFirstDelete && key == SecureVault.mnemonicKey) {
      throw StateError('legacy key deletion unavailable');
    }
    await super.delete(key);
  }
}

class _ToggleMetadataWriteStorage extends InMemoryVaultStorage {
  bool failMetadataWrites = false;

  @override
  Future<void> write(String key, String value) async {
    if (failMetadataWrites && key == SecureVault.metadataKey) {
      throw StateError('metadata store unavailable');
    }
    await super.write(key, value);
  }
}

class _ToggleDeleteStorage extends InMemoryVaultStorage {
  String? failingKey;

  @override
  Future<void> delete(String key) async {
    if (key == failingKey) throw StateError('vault delete unavailable: $key');
    await super.delete(key);
  }
}

class _ToggleDeleteCrypto extends MockCoreCrypto {
  bool failDelete = true;

  @override
  Future<void> deleteWallet(String walletId) async {
    if (failDelete) throw const AuthFailedException();
    await super.deleteWallet(walletId);
  }
}

Future<List<String>> _advanceToBiometricSetup(
  SignerWalletController controller,
) async {
  final words = List<String>.of(await controller.beginCreate());
  controller.markMnemonicVerified(words);
  await controller.setPin('135790');
  return words;
}

void main() {
  test(
    'transient native startup failure preserves wallet metadata and key',
    () async {
      final storage = InMemoryVaultStorage();
      final crypto = _FailingDeriveCrypto();
      const walletId = 'w_existing_secure_wallet';
      final mnemonic = await crypto.generateMnemonic();
      await crypto.storeWallet(walletId: walletId, mnemonic: mnemonic);
      await SecureVault(storage).storeMetadata(
        const WalletMetadata(
          walletId: walletId,
          name: 'Existing wallet',
          createdAt: 1,
        ),
      );
      await PinLock(storage, iterations: 500).setPin('135790');
      final durablePinRecord = await storage.read(SecureVault.pinKey);

      final controller = SignerWalletController(
        storage: storage,
        crypto: crypto,
      );
      await expectLater(controller.load(), throwsStateError);

      expect((await SecureVault(storage).readMetadata())?.walletId, walletId);
      expect(await storage.read(SecureVault.pinKey), durablePinRecord);
      expect(crypto.storedWalletCount, 1);
    },
  );

  test(
    'metadata commit failure removes native key and all PIN state',
    () async {
      final storage = _MetadataWriteFailureStorage();
      final crypto = _TrackingCrypto();
      final controller = SignerWalletController(
        storage: storage,
        crypto: crypto,
        pinIterations: 1000,
      );
      await _advanceToBiometricSetup(controller);

      await expectLater(controller.completeOnboarding(), throwsStateError);

      expect(crypto.deleteCalls, 1);
      expect(crypto.storedWalletCount, 0);
      expect(await storage.read(SecureVault.pinKey), isNull);
      expect(await storage.read(SecureVault.pinLockoutKey), isNull);
      expect(controller.pendingMnemonic, isNull);
      expect(controller.hasWallet, isFalse);
      expect(controller.metadata, isNull);
    },
  );

  test(
    'cleanup still deletes native key and later vault keys if one delete fails',
    () async {
      final storage = _MetadataWriteFailureStorage()..failFirstDelete = true;
      final crypto = _TrackingCrypto();
      final controller = SignerWalletController(
        storage: storage,
        crypto: crypto,
        pinIterations: 1000,
      );
      await _advanceToBiometricSetup(controller);

      await expectLater(controller.completeOnboarding(), throwsStateError);

      expect(crypto.deleteCalls, 1);
      expect(crypto.storedWalletCount, 0);
      expect(
        storage.deletedKeys,
        containsAll(<String>[
          SecureVault.mnemonicKey,
          SecureVault.metadataKey,
          SecureVault.pinKey,
          SecureVault.pinLockoutKey,
        ]),
      );
      expect(await storage.read(SecureVault.pinKey), isNull);
      expect(controller.pendingMnemonic, isNull);
      expect(controller.hasWallet, isFalse);
    },
  );

  test(
    'complete onboarding cannot report success without an active phrase',
    () async {
      final crypto = _TrackingCrypto();
      final controller = SignerWalletController(
        storage: InMemoryVaultStorage(),
        crypto: crypto,
      );

      await expectLater(controller.completeOnboarding(), throwsStateError);
      expect(crypto.storedWalletCount, 0);
      expect(controller.hasWallet, isFalse);
    },
  );

  test('create and commit calls are idempotent while in flight', () async {
    final crypto = _TrackingCrypto();
    final controller = SignerWalletController(
      storage: InMemoryVaultStorage(),
      crypto: crypto,
      pinIterations: 1000,
    );

    final firstCreate = controller.beginCreate();
    final secondCreate = controller.beginCreate();
    expect(identical(firstCreate, secondCreate), isTrue);
    final words = await firstCreate;
    expect(await secondCreate, words);
    controller.markMnemonicVerified(words);
    await controller.setPin('135790');

    final firstCommit = controller.completeOnboarding();
    final secondCommit = controller.completeOnboarding();
    expect(identical(firstCommit, secondCommit), isTrue);
    final metadata = await firstCommit;
    expect((await secondCommit).walletId, metadata.walletId);
    expect(controller.hasWallet, isTrue);
    expect(crypto.storedWalletCount, 1);
  });

  test('mnemonic review and PIN enrollment cannot be skipped', () async {
    final controller = SignerWalletController(
      storage: InMemoryVaultStorage(),
      crypto: MockCoreCrypto(),
      pinIterations: 1000,
    );
    final words = await controller.beginCreate();

    await expectLater(controller.setPin('135790'), throwsStateError);
    await expectLater(controller.completeOnboarding(), throwsStateError);
    expect(
      () => controller.markMnemonicVerified(<String>[
        ...words.take(words.length - 1),
        'wrong',
      ]),
      throwsStateError,
    );

    controller.markMnemonicVerified(words);
    await expectLater(controller.completeOnboarding(), throwsStateError);
    await controller.setPin('135790');
    expect(controller.onboardingStage, SignerOnboardingStage.biometricSetup);
    await controller.completeOnboarding();
    expect(controller.onboardingStage, SignerOnboardingStage.completed);
    controller.finishOnboardingPresentation();
    expect(controller.onboardingStage, SignerOnboardingStage.idle);
  });

  test('an existing wallet rejects every new onboarding entry', () async {
    final storage = InMemoryVaultStorage();
    final crypto = _TrackingCrypto();
    final controller = SignerWalletController(
      storage: storage,
      crypto: crypto,
      pinIterations: 1000,
    );
    await _advanceToBiometricSetup(controller);
    final original = await controller.completeOnboarding();

    await expectLater(controller.beginCreate(), throwsStateError);
    expect(
      await controller.beginImport(await crypto.generateMnemonic()),
      false,
    );
    await expectLater(controller.completeOnboarding(), throwsStateError);
    expect(controller.metadata?.walletId, original.walletId);
    expect(crypto.storedWalletCount, 1);
  });

  test('failed metadata updates never mutate the live wallet state', () async {
    final storage = _ToggleMetadataWriteStorage();
    final crypto = MockCoreCrypto();
    const walletId = 'w_metadata_commit_guard';
    final mnemonic = await crypto.generateMnemonic();
    await crypto.storeWallet(walletId: walletId, mnemonic: mnemonic);
    await SecureVault(storage).storeMetadata(
      const WalletMetadata(
        walletId: walletId,
        name: 'Committed name',
        createdAt: 1,
        biometricEnabled: true,
      ),
    );
    await PinLock(storage, iterations: 500).setPin('135790');
    final controller = SignerWalletController(storage: storage, crypto: crypto);
    await controller.load();
    storage.failMetadataWrites = true;

    await expectLater(
      controller.renameWallet('Uncommitted name'),
      throwsStateError,
    );
    expect(controller.metadata?.name, 'Committed name');

    await expectLater(controller.setBiometricEnabled(false), throwsStateError);
    expect(controller.biometricEnabled, isTrue);
  });

  test(
    'delete crash window keeps a tombstone and startup finishes vault cleanup',
    () async {
      final storage = _ToggleDeleteStorage();
      final crypto = MockCoreCrypto();
      final records = InMemorySignRecordPersistence();
      const walletId = 'w_delete_recovery';
      final mnemonic = await crypto.generateMnemonic();
      await crypto.storeWallet(walletId: walletId, mnemonic: mnemonic);
      final addresses = await crypto.deriveAddresses(walletId);
      await SecureVault(storage).storeMetadata(
        WalletMetadata(
          walletId: walletId,
          name: 'Delete recovery',
          createdAt: 1,
          addresses: addresses.toMap(),
        ),
      );
      await PinLock(storage, iterations: 500).setPin('135790');
      final controller = SignerWalletController(
        storage: storage,
        crypto: crypto,
        records: records,
      );
      await controller.load();
      storage.failingKey = SecureVault.metadataKey;

      await controller.deleteWallet();

      expect(controller.hasWallet, isFalse);
      expect(crypto.storedWalletCount, 0);
      expect(await storage.read(SecureVault.deletionPendingKey), walletId);
      expect(await storage.read(SecureVault.metadataKey), isNotNull);

      storage.failingKey = null;
      final restarted = SignerWalletController(
        storage: storage,
        crypto: crypto,
        records: records,
      );
      await restarted.load();

      expect(restarted.hasWallet, isFalse);
      expect(storage.values, isEmpty);
    },
  );

  test(
    'native delete failure preserves wallet and durable intent for retry',
    () async {
      final storage = InMemoryVaultStorage();
      final crypto = _ToggleDeleteCrypto();
      const walletId = 'w_native_delete_retry';
      final mnemonic = await crypto.generateMnemonic();
      await crypto.storeWallet(walletId: walletId, mnemonic: mnemonic);
      final addresses = await crypto.deriveAddresses(walletId);
      await SecureVault(storage).storeMetadata(
        WalletMetadata(
          walletId: walletId,
          name: 'Native retry',
          createdAt: 1,
          addresses: addresses.toMap(),
        ),
      );
      await PinLock(storage, iterations: 500).setPin('135790');
      final controller = SignerWalletController(
        storage: storage,
        crypto: crypto,
        records: InMemorySignRecordPersistence(),
      );
      await controller.load();

      await expectLater(
        controller.deleteWallet(),
        throwsA(isA<AuthFailedException>()),
      );

      expect(controller.hasWallet, isTrue);
      expect(crypto.storedWalletCount, 1);
      expect(await storage.read(SecureVault.deletionPendingKey), walletId);

      crypto.failDelete = false;
      final restarted = SignerWalletController(
        storage: storage,
        crypto: crypto,
        records: InMemorySignRecordPersistence(),
      );
      await restarted.load();

      expect(restarted.hasWallet, isFalse);
      expect(crypto.storedWalletCount, 0);
      expect(storage.values, isEmpty);
    },
  );
}
