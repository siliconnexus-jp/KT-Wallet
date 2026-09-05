import 'package:cold_signer/l10n/app_localizations.dart';
import 'package:cold_signer/src/screens/signer_onboarding_screens.dart';
import 'package:cold_signer/src/security/secure_vault.dart';
import 'package:cold_signer/src/state/signer_wallet_controller.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:core_crypto/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

class _PreflightCrypto extends MockCoreCrypto {
  bool available = false;
  int generated = 0;
  int writes = 0;
  @override
  Future<void> checkWalletCreationReady() async {
    if (!available) throw const AuthUnavailableException();
  }

  @override
  Future<String> generateMnemonic({int strength = 128}) {
    generated++;
    return super.generateMnemonic(strength: strength);
  }

  @override
  Future<void> storeWallet({
    required String walletId,
    required String mnemonic,
    bool requireAuth = true,
    String? kdfPassword,
  }) {
    writes++;
    return super.storeWallet(
      walletId: walletId,
      mnemonic: mnemonic,
      requireAuth: requireAuth,
      kdfPassword: kdfPassword,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'missing system authentication blocks before generation and can retry',
    () async {
      final crypto = _PreflightCrypto();
      final wallet = SignerWalletController(
        crypto: crypto,
        storage: InMemoryVaultStorage(),
      );
      addTearDown(wallet.dispose);
      await expectLater(
        wallet.beginCreate(),
        throwsA(isA<AuthUnavailableException>()),
      );
      expect(crypto.generated, 0);
      expect(crypto.writes, 0);
      expect(wallet.pendingMnemonic, isNull);
      crypto.available = true;
      expect(await wallet.beginCreate(), isNotEmpty);
      expect(crypto.generated, 1);
    },
  );

  test(
    'unavailable authentication on import does not stage or persist the phrase',
    () async {
      final crypto = _PreflightCrypto();
      final wallet = SignerWalletController(
        crypto: crypto,
        storage: InMemoryVaultStorage(),
      );
      addTearDown(wallet.dispose);
      final phrase = await crypto.generateMnemonic();
      await expectLater(
        wallet.beginImport(phrase),
        throwsA(isA<AuthUnavailableException>()),
      );
      expect(wallet.pendingMnemonic, isNull);
      expect(crypto.writes, 0);
    },
  );

  test(
    'late preflight failure preserves onboarding for retry without vault writes',
    () async {
      final crypto = _PreflightCrypto()..available = true;
      final wallet = SignerWalletController(
        crypto: crypto,
        storage: InMemoryVaultStorage(),
        pinIterations: 10,
      );
      addTearDown(wallet.dispose);
      final words = await wallet.beginCreate();
      wallet.markMnemonicVerified(words);
      await wallet.setPin('123456');
      crypto.available = false;
      await expectLater(
        wallet.completeOnboarding(),
        throwsA(isA<AuthUnavailableException>()),
      );
      expect(wallet.pendingMnemonic, words);
      expect(wallet.hasWallet, isFalse);
      expect(crypto.writes, 0);
      crypto.available = true;
      await wallet.completeOnboarding();
      expect(wallet.hasWallet, isTrue);
      expect(crypto.writes, 1);
    },
  );

  for (final locale in ['zh', 'en', 'ja']) {
    testWidgets(
      'welcome explains system authentication before create/import in $locale',
      (tester) async {
        final crypto = _PreflightCrypto();
        final wallet = SignerWalletController(
          crypto: crypto,
          storage: InMemoryVaultStorage(),
        );
        addTearDown(wallet.dispose);
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ktSignerTheme(),
            home: SignerWalletScope(
              controller: wallet,
              child: const SignerWelcomeScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(SignerWelcomeScreen)),
        );
        for (final label in [l10n.createNewWallet, l10n.importExistingWallet]) {
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
          expect(find.text(l10n.walletDeviceAuthRequired), findsOneWidget);
          expect(crypto.generated, 0);
          expect(crypto.writes, 0);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
}
