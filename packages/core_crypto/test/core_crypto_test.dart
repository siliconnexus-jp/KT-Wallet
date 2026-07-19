import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:core_crypto/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MockCoreCrypto deterministic behavior', () {
    test('generateMnemonic is deterministic per instance sequence', () async {
      final a = MockCoreCrypto();
      final b = MockCoreCrypto();
      expect(await a.generateMnemonic(), await b.generateMnemonic());
      expect(
        await a.generateMnemonic(),
        isNot(await b.generateMnemonic(strength: 192)),
      );
    });

    test('strength maps to word count 12/18/24', () async {
      final mock = MockCoreCrypto();
      expect((await mock.generateMnemonic()).split(' ').length, 12);
      expect((await mock.generateMnemonic(strength: 192)).split(' ').length, 18);
      expect((await mock.generateMnemonic(strength: 256)).split(' ').length, 24);
    });

    test('same mnemonic derives same addresses; eth == polygon', () async {
      final mock = MockCoreCrypto();
      final mnemonic = await mock.generateMnemonic();
      await mock.storeWallet(walletId: 'w1', mnemonic: mnemonic);
      await mock.storeWallet(walletId: 'w2', mnemonic: mnemonic);
      final a1 = await mock.deriveAddresses('w1');
      final a2 = await mock.deriveAddresses('w2');
      expect(a1.toMap(), a2.toMap());
      expect(a1.eth, a1.polygon);
      expect(a1.eth, startsWith('0x'));
      expect(a1.eth.length, 42);
      expect(a1.tron, startsWith('T'));
      expect(a1.tron.length, 34);
      expect(a1.solana.length, 44);
    });

    test('different mnemonics derive different addresses', () async {
      final mock = MockCoreCrypto();
      final m1 = await mock.generateMnemonic();
      final m2 = await mock.generateMnemonic();
      await mock.storeWallet(walletId: 'w1', mnemonic: m1);
      await mock.storeWallet(walletId: 'w2', mnemonic: m2);
      expect(
        (await mock.deriveAddresses('w1')).eth,
        isNot((await mock.deriveAddresses('w2')).eth),
      );
    });

    test('sign is deterministic and depends on coin + input', () async {
      final mock = MockCoreCrypto();
      await mock.storeWallet(
        walletId: 'w1',
        mnemonic: await mock.generateMnemonic(),
      );
      final input = Uint8List.fromList([1, 2, 3]);
      final s1 = await mock.signTransaction(
          walletId: 'w1', coin: Coin.eth, signingInput: input);
      final s2 = await mock.signTransaction(
          walletId: 'w1', coin: Coin.eth, signingInput: input);
      final s3 = await mock.signTransaction(
          walletId: 'w1', coin: Coin.tron, signingInput: input);
      expect(s1.signedTx, s2.signedTx);
      expect(s1.txHash, s2.txHash);
      expect(s1.txHash, isNot(s3.txHash));
    });
  });

  group('MockCoreCrypto lifecycle and errors', () {
    test('unknown wallet throws WalletNotFoundException', () async {
      final mock = MockCoreCrypto();
      expect(
        () => mock.deriveAddresses('missing'),
        throwsA(isA<WalletNotFoundException>()),
      );
    });

    test('invalid mnemonic rejected on store', () async {
      final mock = MockCoreCrypto();
      expect(
        () => mock.storeWallet(walletId: 'w1', mnemonic: 'not a mnemonic'),
        throwsA(isA<InvalidMnemonicException>()),
      );
    });

    test('export returns stored mnemonic; delete removes wallet', () async {
      final mock = MockCoreCrypto();
      final mnemonic = await mock.generateMnemonic();
      await mock.storeWallet(walletId: 'w1', mnemonic: mnemonic);
      expect(await mock.exportMnemonic('w1'), mnemonic);
      await mock.deleteWallet('w1');
      expect(mock.storedWalletCount, 0);
      expect(
        () => mock.exportMnemonic('w1'),
        throwsA(isA<WalletNotFoundException>()),
      );
    });

    test('word validation and suggestions use wordlist', () async {
      final mock = MockCoreCrypto();
      expect(await mock.validateWord('abandon'), isTrue);
      expect(await mock.validateWord('zzz'), isFalse);
      expect(await mock.suggestWords('ab'), ['abandon', 'ability', 'able']);
      expect(await mock.suggestWords(''), isEmpty);
    });
  });

  group('MockCoreCrypto auth lockout ladder (DD §2.4)', () {
    late DateTime now;
    late MockCoreCrypto mock;

    setUp(() async {
      now = DateTime(2026, 1, 1);
      mock = MockCoreCrypto(
        authenticator: () async => false,
        clock: () => now,
      );
      final seeded = MockCoreCrypto();
      final mnemonic = await seeded.generateMnemonic();
      await mock.storeWallet(walletId: 'w1', mnemonic: mnemonic);
    });

    Future<Object?> attempt() async {
      try {
        await mock.exportMnemonic('w1');
        return null;
      } catch (e) {
        return e;
      }
    }

    test('first 4 failures are AUTH_FAILED, 5th locks for 60s', () async {
      for (var i = 0; i < 4; i++) {
        expect(await attempt(), isA<AuthFailedException>());
      }
      final fifth = await attempt();
      expect(fifth, isA<AuthLockedException>());
      expect((fifth! as AuthLockedException).cooldownSec, 60);

      final state = await mock.getAuthState();
      expect(state.locked, isTrue);
      expect(state.failCount, 5);
      expect(state.cooldownSec, 60);
    });

    test('operations during cooldown throw AUTH_LOCKED with countdown',
        () async {
      for (var i = 0; i < 5; i++) {
        await attempt();
      }
      now = now.add(const Duration(seconds: 30));
      final during = await attempt();
      expect(during, isA<AuthLockedException>());
      expect((during! as AuthLockedException).cooldownSec, 30);
    });

    test('ladder escalates 60 → 300 → 900', () async {
      // Attempts during cooldown are rejected WITHOUT counting (by design),
      // so the clock must pass each cooldown for the next failure to count.
      Future<void> failOnceAfterCooldown() async {
        now = now.add(const Duration(hours: 1));
        await attempt();
      }

      for (var i = 0; i < 5; i++) {
        await failOnceAfterCooldown();
      }
      expect((await mock.getAuthState()).failCount, 5);
      expect((await mock.getAuthState()).cooldownSec, 60);

      for (var i = 0; i < 5; i++) {
        await failOnceAfterCooldown();
      }
      expect((await mock.getAuthState()).failCount, 10);
      expect((await mock.getAuthState()).cooldownSec, 300);

      for (var i = 0; i < 5; i++) {
        await failOnceAfterCooldown();
      }
      expect((await mock.getAuthState()).failCount, 15);
      expect((await mock.getAuthState()).cooldownSec, 900);
    });

    test('successful auth resets the counter', () async {
      var allow = false;
      final resettable = MockCoreCrypto(
        authenticator: () async => allow,
        clock: () => now,
      );
      final seeded = MockCoreCrypto();
      await resettable.storeWallet(
        walletId: 'w1',
        mnemonic: await seeded.generateMnemonic(),
      );
      for (var i = 0; i < 3; i++) {
        try {
          await resettable.exportMnemonic('w1');
        } catch (_) {}
      }
      expect((await resettable.getAuthState()).failCount, 3);
      allow = true;
      await resettable.exportMnemonic('w1');
      final state = await resettable.getAuthState();
      expect(state.failCount, 0);
      expect(state.locked, isFalse);
    });
  });

  group('validation (shared across implementations)', () {
    test('bad strength rejected before any backend call', () {
      final mock = MockCoreCrypto();
      expect(() => mock.generateMnemonic(strength: 160), throwsArgumentError);
    });

    test('bad walletId rejected', () {
      final mock = MockCoreCrypto();
      expect(
        () => mock.deriveAddresses('bad wallet id!'),
        throwsArgumentError,
      );
      expect(() => mock.deriveAddresses(''), throwsArgumentError);
    });

    test('empty signing input rejected', () async {
      final mock = MockCoreCrypto();
      await mock.storeWallet(
        walletId: 'w1',
        mnemonic: await mock.generateMnemonic(),
      );
      expect(
        () => mock.signTransaction(
          walletId: 'w1',
          coin: Coin.eth,
          signingInput: Uint8List(0),
        ),
        throwsArgumentError,
      );
    });
  });
}
