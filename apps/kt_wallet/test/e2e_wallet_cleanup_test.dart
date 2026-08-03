import 'package:core_crypto/core_crypto.dart';
import 'package:core_crypto/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/e2e_wallet_cleanup.dart';

void main() {
  test('creates and registers cleanup for a reserved E2E wallet', () async {
    final crypto = MockCoreCrypto();
    final mnemonic = await crypto.generateMnemonic();

    await storeE2eWallet(crypto, walletId: 'kt-e2e-create', mnemonic: mnemonic);

    expect(crypto.storedWalletCount, 1);
    expect(await crypto.deriveAddresses('kt-e2e-create'), isNotNull);
  });

  test('authenticated stale cleanup replaces only the reserved slot', () async {
    final crypto = MockCoreCrypto();
    final oldMnemonic = await crypto.generateMnemonic();
    final newMnemonic = await crypto.generateMnemonic();
    await crypto.storeWallet(
      walletId: 'kt-e2e-stale',
      mnemonic: oldMnemonic,
      requireAuth: false,
    );
    final oldAddress = (await crypto.deriveAddresses('kt-e2e-stale')).eth;

    await storeE2eWallet(
      crypto,
      walletId: 'kt-e2e-stale',
      mnemonic: newMnemonic,
    );

    expect(crypto.storedWalletCount, 1);
    expect(
      (await crypto.deriveAddresses('kt-e2e-stale')).eth,
      isNot(oldAddress),
    );
  });

  test('rejects a non-E2E wallet ID before touching native storage', () async {
    final crypto = MockCoreCrypto();
    final mnemonic = await crypto.generateMnemonic();

    await expectLater(
      storeE2eWallet(crypto, walletId: 'production-wallet', mnemonic: mnemonic),
      throwsArgumentError,
    );
    expect(crypto.storedWalletCount, 0);
  });

  test('failed stale authentication preserves the existing key', () async {
    final crypto = MockCoreCrypto(authenticator: () async => false);
    final oldMnemonic = await crypto.generateMnemonic();
    final newMnemonic = await crypto.generateMnemonic();
    await crypto.storeWallet(
      walletId: 'kt-e2e-auth-failure',
      mnemonic: oldMnemonic,
      requireAuth: false,
    );
    final oldAddress = (await crypto.deriveAddresses(
      'kt-e2e-auth-failure',
    )).eth;

    await expectLater(
      storeE2eWallet(
        crypto,
        walletId: 'kt-e2e-auth-failure',
        mnemonic: newMnemonic,
      ),
      throwsA(isA<AuthFailedException>()),
    );

    expect(crypto.storedWalletCount, 1);
    expect(
      (await crypto.deriveAddresses('kt-e2e-auth-failure')).eth,
      oldAddress,
    );
  });
}
