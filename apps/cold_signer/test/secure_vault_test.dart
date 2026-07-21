import 'package:cold_signer/src/security/mnemonic_wordlist.dart';
import 'package:cold_signer/src/security/secure_vault.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:math';

/// Vault + wordlist behavior over the in-memory fake. MethodChannel plugins
/// (the real Keychain/Keystore backend) are unavailable in widget tests, so
/// every test runs against [InMemoryVaultStorage].
void main() {
  group('SecureVault', () {
    test('stores and reads back mnemonic + metadata', () async {
      final storage = InMemoryVaultStorage();
      final vault = SecureVault(storage);
      expect(await vault.hasWallet(), isFalse);
      expect(await vault.readMnemonic(), isNull);
      expect(await vault.readMetadata(), isNull);

      final words = generateMnemonic(random: Random(7));
      await vault.storeWallet(
        mnemonic: words,
        metadata: const WalletMetadata(
            walletId: 'WLT-A1B2C3D4', name: '主钱包', createdAt: 1786000000),
      );

      expect(await vault.hasWallet(), isTrue);
      expect(await vault.readMnemonic(), words);
      final meta = await vault.readMetadata();
      expect(meta!.walletId, 'WLT-A1B2C3D4');
      expect(meta.name, '主钱包');
      expect(meta.createdAt, 1786000000);
    });

    test('wipe erases mnemonic, metadata AND the PIN keys', () async {
      final storage = InMemoryVaultStorage();
      final vault = SecureVault(storage);
      await vault.storeWallet(
        mnemonic: generateMnemonic(random: Random(7)),
        metadata: const WalletMetadata(
            walletId: 'WLT-A1B2C3D4', name: '主钱包', createdAt: 1786000000),
      );
      // Simulate PinLock's footprint under the same storage.
      await storage.write(SecureVault.pinKey, '{"hash":"x"}');
      await storage.write(SecureVault.pinLockoutKey, '{"fails":3}');

      await vault.wipe();
      expect(await vault.hasWallet(), isFalse);
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
