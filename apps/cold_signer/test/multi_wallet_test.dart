import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:cold_signer/src/security/secure_vault.dart';
import 'package:cold_signer/src/signing/sign_record_store.dart';
import 'package:cold_signer/src/state/signer_wallet_controller.dart';
import 'package:cold_signer/src/signer_router.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:core_crypto/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:cold_signer/l10n/app_localizations.dart';
import 'package:cold_signer/src/screens/signer_onboarding_screens.dart';
import 'package:cold_signer/src/screens/signer_settings_screens.dart';
import 'package:cold_signer/src/screens/signer_signing_screens.dart';

class _Storage extends InMemoryVaultStorage {
  bool failMetadata = false;
  @override
  Future<void> write(String key, String value) async {
    if (failMetadata && key == SecureVault.metadataKey) {
      throw StateError('disk');
    }
    await super.write(key, value);
  }
}

class _Crypto extends MockCoreCrypto {
  bool failDerive = false;
  Completer<void>? exportGate;
  @override
  Future<String> exportMnemonic(String walletId) async {
    await exportGate?.future;
    return super.exportMnemonic(walletId);
  }

  @override
  Future<ChainAddresses> deriveAddresses(String walletId) async {
    if (failDerive) throw const AuthCancelledException();
    return super.deriveAddresses(walletId);
  }
}

Future<WalletMetadata> _create(SignerWalletController c, String name) async {
  if (c.hasWallet) c.beginAddWallet();
  final words = await c.beginCreate();
  c.markMnemonicVerified(words);
  if (!c.hasWallet) await c.setPin('135790');
  return c.completeOnboarding(walletName: name);
}

SignatureRecord _record(String id, String wallet) => SignatureRecord(
  reqId: id,
  date: 1,
  coin: 'ETH',
  operation: 'transfer',
  toAddress: 'public',
  amount: '1',
  status: RequestStatus.scanned,
  walletId: wallet,
);

void main() {
  testWidgets(
    'production QR is high contrast and changes identity with the selected wallet',
    (tester) async {
      final c = SignerWalletController(
        storage: _Storage(),
        crypto: _Crypto(),
        pinIterations: 10,
      );
      addTearDown(c.dispose);
      final a = await _create(c, 'A');
      final b = await _create(c, 'B');
      await tester.pumpWidget(
        SignerWalletScope(
          controller: c,
          child: MaterialApp(
            theme: ktSignerTheme(),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SignerAddressExportScreen(),
          ),
        ),
      );
      await tester.pump();
      Future<AccountExport> readQr() async {
        final aggregator = FrameAggregator();
        final qr = tester.widget<KtQrCode>(find.byType(KtQrCode));
        expect(qr.dark, isFalse);
        expect(qr.quietZone, 4);
        expect(qr.size, 240);
        final total = AirgapFrame.decode(
          Uint8List.fromList(base64Url.decode(qr.data)),
        ).total;
        for (var i = 0; i < total; i++) {
          final data = tester.widget<KtQrCode>(find.byType(KtQrCode)).data;
          aggregator.addFrame(
            AirgapFrame.decode(Uint8List.fromList(base64Url.decode(data))),
          );
          await tester.pump(const Duration(milliseconds: 600));
        }
        return AirgapPayload.decode(aggregator.payload!) as AccountExport;
      }

      expect((await readQr()).walletId, b.walletId);
      await c.selectWallet(a.walletId);
      await tester.pump();
      expect((await readQr()).walletId, a.walletId);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'wallet list switches selection and add flow keeps the existing PIN',
    (tester) async {
      final c = SignerWalletController(
        storage: _Storage(),
        crypto: _Crypto(),
        pinIterations: 10,
      );
      addTearDown(c.dispose);
      final a = await _create(c, 'First');
      await _create(c, 'Second');
      final router = buildSignerRouter(initialLocation: '/wallets');
      addTearDown(router.dispose);
      await tester.pumpWidget(
        SignerWalletScope(
          controller: c,
          child: MaterialApp.router(
            routerConfig: router,
            theme: ktSignerTheme(),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('First'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
      await tester.tap(find.text('First'));
      await tester.pumpAndSettle();
      expect(c.localWalletId, a.walletId);
      router.go('/wallets');
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(SignerWalletListScreen)),
      );
      await tester.tap(find.text(l10n.addWallet));
      await tester.pumpAndSettle();
      expect(find.byType(SignerWelcomeScreen), findsOneWidget);
      expect(c.addingWallet, isTrue);
      await c.beginImport(
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
      );
      router.go('/set-password');
      await tester.pumpAndSettle();
      expect(find.byType(SignerBiometricScreen), findsOneWidget);
      expect(find.byType(SignerSetPasswordScreen), findsNothing);
      c.cancelAddWallet();
      router.go('/wallets');
      await tester.pumpAndSettle();
      expect(c.wallets.length, 2);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'encrypted backup and signing stay bound to selected wallet; exports cancel on switching',
    () async {
      final crypto = _Crypto();
      final c = SignerWalletController(
        storage: _Storage(),
        crypto: crypto,
        pinIterations: 10,
      );
      final a = await _create(c, 'A');
      final b = await _create(c, 'B');
      const password = 'harbor velvet copper comet 27';
      await expectLater(
        c.createEncryptedBackup(walletId: a.walletId, password: password),
        throwsStateError,
      );
      final blob = await c.createEncryptedBackup(
        walletId: b.walletId,
        password: password,
      );
      expect(
        await crypto.readBackup(
          blob: blob,
          password: password,
          format: BackupCipherFormat.portableV2,
        ),
        await crypto.exportMnemonic(b.walletId),
      );
      await expectLater(
        c.signRequest(
          SignRequest(
            reqId: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
            walletId: a.walletId,
            coin: 60,
            rawTx: Uint8List.fromList([1]),
            createdAt: 1,
            expiresAt: 2,
          ),
        ),
        throwsStateError,
      );
      crypto.exportGate = Completer<void>();
      final export = c.exportMnemonicForReview();
      final rejected = expectLater(export, throwsStateError);
      await c.selectWallet(a.walletId);
      crypto.exportGate!.complete();
      await rejected;
    },
  );

  test(
    'concurrent metadata updates retain every wallet and deleting last wallet clears PIN',
    () async {
      final storage = _Storage();
      final vault = SecureVault(storage);
      await Future.wait([
        for (var i = 0; i < 4; i++)
          vault.storeMetadata(
            WalletMetadata(
              walletId: 'wallet_$i',
              name: 'Wallet $i',
              createdAt: 1,
            ),
          ),
      ]);
      expect((await vault.readWallets()).length, 4);
      final c = SignerWalletController(
        storage: _Storage(),
        crypto: _Crypto(),
        pinIterations: 10,
      );
      await _create(c, 'A');
      final b = await _create(c, 'B');
      await c.deleteWallet(expectedWalletId: b.walletId);
      expect(c.wallets.length, 1);
      expect(await c.pinLock.isSet(), isTrue);
      await c.deleteWallet();
      expect(c.wallets, isEmpty);
      expect(c.hasWallet, isFalse);
      expect(await c.pinLock.isSet(), isFalse);
    },
  );

  test(
    'legacy wallet migrates without replacing keys or app PIN; selected wallet survives restart',
    () async {
      final storage = _Storage();
      final crypto = _Crypto();
      final c = SignerWalletController(
        storage: storage,
        crypto: crypto,
        pinIterations: 500,
      );
      final a = await _create(c, 'A');
      final pin = storage.values[SecureVault.pinKey];
      final phrase = await crypto.exportMnemonic(a.walletId);
      final b = await _create(c, 'B');
      expect(c.wallets.map((w) => w.name), ['A', 'B']);
      expect(c.localWalletId, b.walletId);
      expect(storage.values[SecureVault.pinKey], pin);
      expect(await crypto.exportMnemonic(a.walletId), phrase);
      expect(crypto.storedWalletCount, 2);
      await c.selectWallet(a.walletId);
      expect(c.buildAccountExport().walletId, a.walletId);
      final restarted = SignerWalletController(
        storage: storage,
        crypto: crypto,
        pinIterations: 500,
      );
      await restarted.load();
      expect(restarted.localWalletId, a.walletId);
      expect(restarted.wallets.length, 2);
    },
  );

  test(
    'new wallet failure preserves old metadata, PIN and native wallet',
    () async {
      final storage = _Storage();
      final crypto = _Crypto();
      final c = SignerWalletController(
        storage: storage,
        crypto: crypto,
        pinIterations: 500,
      );
      final a = await _create(c, 'A');
      final old = Map.of(storage.values);
      c.beginAddWallet();
      final words = await c.beginCreate();
      c.markMnemonicVerified(words);
      storage.failMetadata = true;
      await expectLater(
        c.completeOnboarding(walletName: 'B'),
        throwsStateError,
      );
      expect(c.localWalletId, a.walletId);
      expect(c.hasWallet, isTrue);
      expect(storage.values, old);
      expect(crypto.storedWalletCount, 1);
    },
  );

  test(
    'switch cancellation preserves selection and failed delete resumes only its target',
    () async {
      final storage = _Storage();
      final crypto = _Crypto();
      final records = InMemorySignRecordPersistence();
      final c = SignerWalletController(
        storage: storage,
        crypto: crypto,
        records: records,
        pinIterations: 500,
      );
      final a = await _create(c, 'A');
      final b = await _create(c, 'B');
      await records.reserve(_record('a', a.walletId));
      await records.reserve(_record('b', b.walletId));
      crypto.failDerive = true;
      await expectLater(
        c.selectWallet(a.walletId),
        throwsA(isA<AuthCancelledException>()),
      );
      expect(c.localWalletId, b.walletId);
      crypto.failDerive = false;
      storage.failMetadata = true;
      await expectLater(c.deleteWallet(), throwsStateError);
      expect(crypto.storedWalletCount, 1);
      expect(c.canAddWallet, isFalse);
      expect(c.beginAddWallet, throwsStateError);
      await expectLater(c.selectWallet(a.walletId), throwsStateError);
      storage.failMetadata = false;
      final restored = SignerWalletController(
        storage: storage,
        crypto: crypto,
        records: records,
        pinIterations: 500,
      );
      await restored.load();
      expect(restored.localWalletId, a.walletId);
      expect(restored.wallets.length, 1);
      expect((await restored.recordsForCurrentWallet()).single.reqId, 'a');
      expect(await records.get('b'), isNull);
      expect(await restored.pinLock.isSet(), isTrue);
      expect(await restored.vault.pendingDeletionWalletId(), isNull);
    },
  );

  test(
    'cancel addition keeps existing wallet and import uses the shared PIN',
    () async {
      final c = SignerWalletController(
        storage: _Storage(),
        crypto: _Crypto(),
        pinIterations: 500,
      );
      final a = await _create(c, 'A');
      c.beginAddWallet();
      await c.beginCreate();
      c.cancelAddWallet();
      expect(c.pendingMnemonic, isNull);
      expect(c.localWalletId, a.walletId);
      c.beginAddWallet();
      expect(
        await c.beginImport(
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
        ),
        isTrue,
      );
      expect(c.onboardingStage, SignerOnboardingStage.biometricSetup);
      expect(
        signerProductionRouteRedirect(
          galleryMode: false,
          uri: Uri.parse('/set-password'),
          hasWallet: true,
          addingWallet: true,
          hasPendingMnemonic: true,
          onboardingStage: c.onboardingStage,
        ),
        '/biometric',
      );
      await c.completeOnboarding(walletName: 'Imported');
      expect(c.wallets.length, 2);
    },
  );

  test(
    'collection rejects duplicate identities and unknown selected wallet',
    () async {
      final storage = _Storage();
      final vault = SecureVault(storage);
      final a = const WalletMetadata(
        walletId: 'wallet_a',
        name: 'A',
        createdAt: 1,
      ).toJson();
      for (final value in [
        {
          'v': 3,
          'selected': 'wallet_a',
          'wallets': [a, a],
        },
        {
          'v': 3,
          'selected': 'unknown',
          'wallets': [a],
        },
      ]) {
        storage.values[SecureVault.metadataKey] = jsonEncode(value);
        await expectLater(
          vault.readWallets(),
          throwsA(isA<VaultStateCorruptedException>()),
        );
      }
    },
  );
}
