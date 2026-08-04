import 'package:cold_signer/main.dart';
import 'package:cold_signer/src/security/secure_vault.dart';
import 'package:cold_signer/src/state/locale_controller.dart';
import 'package:cold_signer/src/state/signer_wallet_controller.dart';
import 'package:core_crypto/testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _UnavailableVaultStorage implements VaultStorage {
  const _UnavailableVaultStorage();

  @override
  Future<void> delete(String key) =>
      Future<void>.error(StateError('secure storage unavailable'));

  @override
  Future<String?> read(String key) =>
      Future<String?>.error(StateError('secure storage unavailable'));

  @override
  Future<void> write(String key, String value) =>
      Future<void>.error(StateError('secure storage unavailable'));
}

void main() {
  testWidgets('secure storage failure blocks onboarding and signing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final wallet = SignerWalletController(
      storage: const _UnavailableVaultStorage(),
    );

    await tester.pumpWidget(
      ColdSignerApp(
        localeController: LocaleController(initial: const Locale('en')),
        walletController: wallet,
        initialLocation: '/welcome',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Secure storage unavailable'), findsOneWidget);
    expect(find.text('Create new wallet'), findsNothing);
    expect(find.text('Import existing wallet'), findsNothing);
    await expectLater(
      find.byType(ColdSignerApp),
      matchesGoldenFile('goldens/screens/secure-storage-unavailable.png'),
    );

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Secure storage unavailable'), findsOneWidget);
    expect(find.text('Create new wallet'), findsNothing);
  });

  testWidgets('corrupt enrolled PIN blocks startup before biometric signing', (
    tester,
  ) async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('fonts/Inter.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = InMemoryVaultStorage();
    final crypto = MockCoreCrypto();
    const walletId = 'cold-wallet-corrupt-pin';
    await crypto.storeWallet(
      walletId: walletId,
      mnemonic:
          'abandon ability able about above absent absorb abstract absurd abuse access accident',
      requireAuth: false,
    );
    await SecureVault(storage).storeMetadata(
      const WalletMetadata(
        walletId: walletId,
        name: 'KT Cold Signer',
        createdAt: 1785888000,
        biometricEnabled: true,
      ),
    );
    storage.values[SecureVault.pinKey] = '{"iterations":500}';
    final wallet = SignerWalletController(storage: storage, crypto: crypto);

    await tester.pumpWidget(
      ColdSignerApp(
        localeController: LocaleController(initial: const Locale('en')),
        walletController: wallet,
        initialLocation: '/home',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Secure storage unavailable'), findsOneWidget);
    expect(find.text('Use Face ID'), findsNothing);
    expect(wallet.hasWallet, isFalse);
    await expectLater(
      find.byType(ColdSignerApp),
      matchesGoldenFile('goldens/screens/pin-state-corrupted-en.png'),
    );
  });

  testWidgets(
    'ambiguous wallet metadata blocks startup before native wallet access',
    (tester) async {
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('fonts/Inter.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final storage = InMemoryVaultStorage();
      final crypto = MockCoreCrypto();
      const walletId = 'cold-wallet-corrupt-metadata';
      await crypto.storeWallet(
        walletId: walletId,
        mnemonic:
            'abandon ability able about above absent absorb abstract absurd abuse access accident',
        requireAuth: false,
      );
      storage.values[SecureVault.metadataKey] =
          '{"walletId":"$walletId","walletId":"other-wallet",'
          '"name":"KT Cold Signer","createdAt":1785888000,'
          '"version":2,"addresses":{},"publicKeys":{},'
          '"biometricEnabled":false}';
      final wallet = SignerWalletController(storage: storage, crypto: crypto);

      await tester.pumpWidget(
        ColdSignerApp(
          localeController: LocaleController(initial: const Locale('en')),
          walletController: wallet,
          initialLocation: '/home',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Secure storage unavailable'), findsOneWidget);
      expect(find.text('Scan transaction to sign'), findsNothing);
      expect(wallet.hasWallet, isFalse);
      expect(crypto.storedWalletCount, 1);
      await expectLater(
        find.byType(ColdSignerApp),
        matchesGoldenFile('goldens/screens/vault-state-corrupted-en.png'),
      );
    },
  );
}
