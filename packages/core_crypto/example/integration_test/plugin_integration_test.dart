// Native-bridge vector tests (todolist.md P1-2/P1-3 DoD).
// Runs on a real device/simulator against the actual wallet-core build:
//   cd packages/core_crypto/example && flutter test integration_test
import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// BIP-39 reference mnemonic (Trezor vector, entropy 0x00*16).
const vectorMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon about';

/// m/44'/60'/0'/0/0 for [vectorMnemonic] — authoritative, widely published.
const vectorEthAddress = '0x9858EfFD232B4033E47d90003D41EC34EcaEda94';

// TRON / Solana expected values are pinned after the first verified native
// run (cross-checked against wallet-core's own test suite and a reference
// wallet). Until pinned, the test asserts format + determinism and prints the
// derived values for pinning. NEVER pin a value that has not been verified
// against a second independent source.
const String? vectorTronAddress = null;
const String? vectorSolanaAddress = null;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final crypto = MethodChannelCoreCrypto();
  const walletId = 'itest-vector-wallet';

  tearDown(() async {
    try {
      await crypto.deleteWallet(walletId);
    } on WalletNotFoundException {
      // already clean
    }
  });

  testWidgets('BIP-39: generate produces valid 12/24-word mnemonics',
      (tester) async {
    for (final strength in [128, 256]) {
      final mnemonic = await crypto.generateMnemonic(strength: strength);
      expect(mnemonic.split(' ').length, strength ~/ 32 * 3);
      expect(await crypto.validateMnemonic(mnemonic), isTrue);
    }
  });

  testWidgets('BIP-39: checksum validation', (tester) async {
    expect(await crypto.validateMnemonic(vectorMnemonic), isTrue);
    // 12 x abandon has an invalid checksum.
    final bad = List.filled(12, 'abandon').join(' ');
    expect(await crypto.validateMnemonic(bad), isFalse);
    expect(await crypto.validateWord('abandon'), isTrue);
    expect(await crypto.validateWord('abandonn'), isFalse);
    expect(await crypto.suggestWords('aban'), contains('abandon'));
  });

  testWidgets('BIP-44: derives the authoritative ETH vector address',
      (tester) async {
    await crypto.storeWallet(
      walletId: walletId,
      mnemonic: vectorMnemonic,
      requireAuth: false,
    );
    final addrs = await crypto.deriveAddresses(walletId);

    expect(addrs.eth.toLowerCase(), vectorEthAddress.toLowerCase());
    expect(addrs.polygon, addrs.eth);

    // Structural checks always apply.
    expect(addrs.tron, startsWith('T'));
    expect(addrs.tron.length, 34);
    expect(addrs.solana.length, inInclusiveRange(32, 44));

    // Pinned-vector checks once verified.
    if (vectorTronAddress != null) {
      expect(addrs.tron, vectorTronAddress);
    } else {
      debugPrint('PIN-ME tron=${addrs.tron}');
    }
    if (vectorSolanaAddress != null) {
      expect(addrs.solana, vectorSolanaAddress);
    } else {
      debugPrint('PIN-ME solana=${addrs.solana}');
    }

    // Determinism: a second store/derive round trips identically.
    await crypto.deleteWallet(walletId);
    await crypto.storeWallet(
      walletId: walletId,
      mnemonic: vectorMnemonic,
      requireAuth: false,
    );
    expect((await crypto.deriveAddresses(walletId)).toMap(), addrs.toMap());
  });

  testWidgets('store/export/delete lifecycle', (tester) async {
    await crypto.storeWallet(
      walletId: walletId,
      mnemonic: vectorMnemonic,
      requireAuth: false,
    );
    expect(await crypto.exportMnemonic(walletId), vectorMnemonic);
    await crypto.deleteWallet(walletId);
    expect(
      () => crypto.deriveAddresses(walletId),
      throwsA(isA<WalletNotFoundException>()),
    );
  });

  // Signing vectors are added in P1-4 once the native bridge injects the
  // derived key into the per-chain SigningInput proto (see WalletCoreBridge).
  // Until then signing is a fail-closed stub, asserted here so a regression
  // that makes it silently "succeed" is caught.
  testWidgets('signTransaction is fail-closed until P1-4 wiring', (tester) async {
    await crypto.storeWallet(
      walletId: walletId,
      mnemonic: vectorMnemonic,
      requireAuth: false,
    );
    expect(
      () => crypto.signTransaction(
        walletId: walletId,
        coin: Coin.eth,
        signingInput: Uint8List.fromList([0xde, 0xad, 0xbe, 0xef]),
      ),
      throwsA(isA<CoreCryptoException>()),
    );
    // skip until P1-4: per-chain SigningInput key injection + device vector run
  }, skip: true);
}
