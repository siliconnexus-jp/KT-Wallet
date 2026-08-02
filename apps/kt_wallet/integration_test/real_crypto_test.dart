import 'package:chains/chains.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/e2e_wallet_cleanup.dart';

/// On-device proof that the REAL Trust Wallet Core bridge works end to end on
/// iOS: mnemonic generation, Keychain-backed storage, and BIP-44 derivation —
/// with every derived address validated by our own chain validators
/// (EIP-55 checksum, TRON base58check, Solana base58). Run on a simulator or
/// device:
///   flutter test integration_test/real_crypto_test.dart -d `<ios-device>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final crypto = MethodChannelCoreCrypto();
  const walletId = 'itest-real-crypto';

  test(
    'real wallet-core: generate → store → derive, all addresses validate',
    () async {
      final mnemonic = await crypto.generateMnemonic();
      final words = mnemonic.trim().split(RegExp(r'\s+'));
      expect(words.length, anyOf(12, 24), reason: 'BIP-39 mnemonic length');
      expect(await crypto.validateMnemonic(mnemonic), isTrue);

      await crypto.storeWallet(
        walletId: walletId,
        mnemonic: mnemonic,
        requireAuth: false,
      );
      registerE2eWalletCleanup(crypto, walletId);
      final addrs = await crypto.deriveAddresses(walletId);

      // Our own validators must accept what wallet-core derived.
      expect(
        Addresses.validate(Chain.ethereum, addrs.eth).isValid,
        isTrue,
        reason: 'ETH ${addrs.eth}',
      );
      expect(
        Addresses.validate(Chain.polygon, addrs.polygon).isValid,
        isTrue,
        reason: 'POL ${addrs.polygon}',
      );
      expect(
        Addresses.validate(Chain.tron, addrs.tron).isValid,
        isTrue,
        reason: 'TRON ${addrs.tron}',
      );
      expect(
        Addresses.validate(Chain.solana, addrs.solana).isValid,
        isTrue,
        reason: 'SOL ${addrs.solana}',
      );

      // EVM chains share the same derivation path in this design.
      expect(addrs.polygon, addrs.eth);

      // Deterministic: deriving again yields identical addresses.
      final again = await crypto.deriveAddresses(walletId);
      expect(again.eth, addrs.eth);
      expect(again.tron, addrs.tron);
      expect(again.solana, addrs.solana);

      // Surface the real addresses in the run log for the session report.
      // ignore: avoid_print
      print(
        'REAL-DERIVED eth=${addrs.eth} tron=${addrs.tron} sol=${addrs.solana}',
      );
    },
  );

  test(
    'same mnemonic imported under two ids derives identical addresses',
    () async {
      // Deliberately avoids exportMnemonic (biometric AuthGate can't be
      // satisfied headlessly) — determinism is proven with a fresh mnemonic
      // stored under two independent wallet ids.
      final mnemonic = await crypto.generateMnemonic();
      await crypto.storeWallet(
        walletId: 'itest-det-a',
        mnemonic: mnemonic,
        requireAuth: false,
      );
      registerE2eWalletCleanup(crypto, 'itest-det-a');
      await crypto.storeWallet(
        walletId: 'itest-det-b',
        mnemonic: mnemonic,
        requireAuth: false,
      );
      registerE2eWalletCleanup(crypto, 'itest-det-b');
      final a = await crypto.deriveAddresses('itest-det-a');
      final b = await crypto.deriveAddresses('itest-det-b');
      expect(b.eth, a.eth);
      expect(b.tron, a.tron);
      expect(b.solana, a.solana);
    },
  );
}
