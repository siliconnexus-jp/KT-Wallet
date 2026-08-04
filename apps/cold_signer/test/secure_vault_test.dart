import 'package:cold_signer/src/security/mnemonic_wordlist.dart';
import 'package:cold_signer/src/security/secure_vault.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:convert';
import 'dart:math';

/// Vault + wordlist behavior over the in-memory fake. MethodChannel plugins
/// (the real Keychain/Keystore backend) are unavailable in widget tests, so
/// every test runs against [InMemoryVaultStorage].
void main() {
  group('SecureVault', () {
    test('stores public metadata without any mnemonic', () async {
      final storage = InMemoryVaultStorage();
      final vault = SecureVault(storage);
      expect(await vault.hasWallet(), isFalse);
      expect(await vault.readMetadata(), isNull);

      await vault.storeMetadata(
        const WalletMetadata(
          walletId: 'WLT-A1B2C3D4',
          name: '主钱包',
          createdAt: 1786000000,
          addresses: {'eth': '0x123'},
        ),
      );

      expect(await vault.hasWallet(), isTrue);
      expect(storage.values.containsKey(SecureVault.mnemonicKey), isFalse);
      final meta = await vault.readMetadata();
      expect(meta!.walletId, 'WLT-A1B2C3D4');
      expect(meta.name, '主钱包');
      expect(meta.createdAt, 1786000000);
      expect(meta.addresses['eth'], '0x123');
    });

    test('wipe erases mnemonic, metadata AND the PIN keys', () async {
      final storage = InMemoryVaultStorage();
      final vault = SecureVault(storage);
      await vault.storeMetadata(
        const WalletMetadata(
          walletId: 'WLT-A1B2C3D4',
          name: '主钱包',
          createdAt: 1786000000,
        ),
      );
      // Simulate an upgrade from the legacy Dart-mnemonic build.
      await storage.write(SecureVault.mnemonicKey, 'legacy secret words');
      // Simulate PinLock's footprint under the same storage.
      await storage.write(SecureVault.pinKey, '{"hash":"x"}');
      await storage.write(SecureVault.pinLockoutKey, '{"fails":3}');

      await vault.wipe();
      expect(await vault.hasWallet(), isFalse);
      expect(storage.values, isEmpty);
    });

    test(
      'reads the closed legacy v1 descriptor without inventing fields',
      () async {
        final storage = InMemoryVaultStorage();
        storage.values[SecureVault.metadataKey] = jsonEncode({
          'walletId': 'legacy_wallet',
          'name': 'Legacy wallet',
          'createdAt': 1,
        });

        final metadata = await SecureVault(storage).readMetadata();

        expect(metadata?.version, 1);
        expect(metadata?.addresses, isEmpty);
        expect(metadata?.publicKeys, isEmpty);
        expect(metadata?.biometricEnabled, isFalse);
      },
    );

    test('refuses to persist invalid metadata', () async {
      final storage = InMemoryVaultStorage();
      await expectLater(
        SecureVault(storage).storeMetadata(
          const WalletMetadata(
            walletId: '../wallet',
            name: 'Invalid',
            createdAt: 1,
          ),
        ),
        throwsA(isA<VaultStateCorruptedException>()),
      );
      expect(storage.values, isEmpty);
    });
  });

  group('signer wordlist', () {
    test('has 256 unique lowercase words', () {
      expect(signerWordlist.length, 256);
      expect(signerWordlist.toSet().length, 256);
      for (final w in signerWordlist) {
        expect(RegExp(r'^[a-z]{3,9}$').hasMatch(w), isTrue, reason: w);
      }
    });

    test('generateMnemonic draws 12 wordlist words, seed-deterministic', () {
      final a = generateMnemonic(random: Random(42));
      final b = generateMnemonic(random: Random(42));
      expect(a.length, 12);
      expect(a, b); // same seed → same words
      for (final w in a) {
        expect(signerWordlist, contains(w));
      }
      expect(generateMnemonic(random: Random(43)), isNot(a));
    });

    test('drawDistractors never yields the correct word or duplicates', () {
      final rng = Random(1);
      for (var i = 0; i < 50; i++) {
        final correct = signerWordlist[rng.nextInt(signerWordlist.length)];
        final d = drawDistractors(correct, 5, random: rng);
        expect(d.length, 5);
        expect(d.toSet().length, 5);
        expect(d, isNot(contains(correct)));
      }
    });
  });
}
