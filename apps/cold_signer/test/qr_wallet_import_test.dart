import 'dart:async';

import 'package:cold_signer/l10n/app_localizations.dart';
import 'package:cold_signer/src/screens/signer_qr_import_screen.dart';
import 'package:cold_signer/src/screens/signer_signing_screens.dart';
import 'package:cold_signer/src/security/backup_qr_image.dart';
import 'package:cold_signer/src/security/secure_vault.dart';
import 'package:cold_signer/src/security/security_check.dart';
import 'package:cold_signer/src/signer_router.dart';
import 'package:cold_signer/src/state/signer_wallet_controller.dart';
import 'package:cold_signer/src/widgets/scan_viewfinder.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:core_crypto/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

const _password = 'Offline-test-password-482!';
const _phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

class _Crypto extends MockCoreCrypto {
  int writes = 0;
  int reads = 0;
  BackupCipherFormat? format;
  bool available = true;
  Completer<void>? pause;
  @override
  Future<void> checkWalletCreationReady() async {
    if (!available) throw const AuthUnavailableException();
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

  @override
  Future<String> readBackup({
    required Uint8List blob,
    required String password,
    required BackupCipherFormat format,
  }) async {
    reads++;
    this.format = format;
    await pause?.future;
    return super.readBackup(blob: blob, password: password, format: format);
  }
}

class _Picker extends SignerBackupImagePicker {
  bool cancel = false;
  bool fail = false;
  @override
  Future<Uint8List?> pick() async {
    if (fail) throw PlatformException(code: 'READ_FAILED');
    return cancel ? null : Uint8List.fromList([1]);
  }
}

class _Reader extends BackupQrImageReader {
  _Reader(this.payload);
  final String payload;
  @override
  Future<String> read(Uint8List bytes) async => payload;
}

Future<String> _backup() async {
  final online = MockCoreCrypto();
  await online.storeWallet(walletId: 'online-test', mnemonic: _phrase);
  return WalletBackupQr.encode(
    await online.createBackup(walletId: 'online-test', password: _password),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'image reader rejects oversized, empty and corrupt files locally',
    () async {
      const reader = BackupQrImageReader();
      for (final bytes in [
        Uint8List(0),
        Uint8List(BackupQrImageReader.maxFileBytes + 1),
        Uint8List.fromList([1, 2, 3]),
      ]) {
        await expectLater(reader.read(bytes), throwsA(anything));
      }
    },
  );

  testWidgets(
    'camera rejects a plaintext QR and returns only a valid encrypted backup',
    (tester) async {
      final payload = await _backup();
      final crypto = _Crypto();
      final wallet = SignerWalletController(
        crypto: crypto,
        storage: InMemoryVaultStorage(),
      );
      addTearDown(wallet.dispose);
      final router = buildSignerRouter(initialLocation: '/qr-import');
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          locale: const Locale('en'),
          theme: ktSignerTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (c, child) =>
              SignerWalletScope(controller: wallet, child: child!),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('qr-import-scan')));
      await tester.pumpAndSettle();
      final scanner = tester.widget<ScanViewfinder>(
        find.byType(ScanViewfinder),
      );
      scanner.onScanned!(_phrase);
      await tester.pumpAndSettle();
      expect(find.byType(SignerBackupScanScreen), findsOneWidget);
      expect(crypto.reads, 0);
      scanner.onScanned!(payload);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('qr-import-password')), findsOneWidget);
      expect(crypto.reads, 0);
      expect(find.text(_phrase), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'online QR restores into offline PIN flow without an early vault write',
    () async {
      final crypto = _Crypto();
      final wallet = SignerWalletController(
        crypto: crypto,
        storage: InMemoryVaultStorage(),
        pinIterations: 10,
      );
      addTearDown(wallet.dispose);
      expect(await wallet.beginQrImport(await _backup(), _password), isTrue);
      expect(crypto.format, BackupCipherFormat.portableV2);
      expect(wallet.onboardingStage, SignerOnboardingStage.pinSetup);
      expect(wallet.hasWallet, isFalse);
      expect(crypto.writes, 0);
      await wallet.setPin('482961');
      await wallet.completeOnboarding();
      expect(wallet.hasWallet, isTrue);
      expect(crypto.writes, 1);
    },
  );

  test(
    'wrong password leaves no pending phrase or vault writes and can retry',
    () async {
      final crypto = _Crypto();
      final wallet = SignerWalletController(
        crypto: crypto,
        storage: InMemoryVaultStorage(),
      );
      addTearDown(wallet.dispose);
      final payload = await _backup();
      await expectLater(
        wallet.beginQrImport(payload, 'wrong'),
        throwsA(isA<StoreCorruptedException>()),
      );
      expect(wallet.pendingMnemonic, isNull);
      expect(crypto.writes, 0);
      expect(await wallet.beginQrImport(payload, _password), isTrue);
    },
  );

  test(
    'invalid transport and unavailable authentication never decrypt',
    () async {
      final crypto = _Crypto()..available = false;
      final wallet = SignerWalletController(
        crypto: crypto,
        storage: InMemoryVaultStorage(),
      );
      addTearDown(wallet.dispose);
      for (final payload in [
        _phrase,
        'https://example.com',
        'KTWALLET:BACKUP:1:AA==',
        'KTWALLET:BACKUP:2:AA==',
      ]) {
        await expectLater(
          wallet.beginQrImport(payload, _password),
          throwsA(isA<BackupFormatException>()),
        );
      }
      await expectLater(
        wallet.beginQrImport(await _backup(), _password),
        throwsA(isA<AuthUnavailableException>()),
      );
      expect(crypto.reads, 0);
      expect(wallet.pendingMnemonic, isNull);
    },
  );

  test('cancelled in-flight decryption cannot stage a phrase', () async {
    final crypto = _Crypto()..pause = Completer<void>();
    final wallet = SignerWalletController(
      crypto: crypto,
      storage: InMemoryVaultStorage(),
    );
    addTearDown(wallet.dispose);
    var active = true;
    final task = wallet.beginQrImport(
      await _backup(),
      _password,
      isActive: () => active,
    );
    await Future<void>.delayed(Duration.zero);
    active = false;
    crypto.pause!.complete();
    expect(await task, isFalse);
    expect(wallet.pendingMnemonic, isNull);
    expect(crypto.writes, 0);
  });

  test('QR routes never overwrite a wallet or interrupt PIN enrollment', () {
    for (final path in ['/qr-import', '/qr-import/scan']) {
      expect(
        signerProductionRouteRedirect(
          galleryMode: false,
          uri: Uri.parse(path),
          hasWallet: true,
        ),
        '/home',
      );
      expect(
        signerProductionRouteRedirect(
          galleryMode: false,
          uri: Uri.parse(path),
          onboardingStage: SignerOnboardingStage.pinSetup,
        ),
        '/set-password',
      );
    }
  });

  for (final locale in ['en', 'zh', 'ja']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('QR import is accessible in $locale at ${scale}x text', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(locale),
              theme: ktSignerTheme(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (c, child) => MediaQuery(
                data: MediaQuery.of(
                  c,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const SignerQrImportScreen(),
            ),
          );
          await tester.pumpAndSettle();
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          if (scale == 1) {
            await expectLater(tester, meetsGuideline(textContrastGuideline));
          }
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      });
    }
    testWidgets('local QR image, password failure and retry in $locale', (
      tester,
    ) async {
      final crypto = _Crypto();
      final wallet = SignerWalletController(
        crypto: crypto,
        storage: InMemoryVaultStorage(),
      );
      addTearDown(wallet.dispose);
      final picker = _Picker();
      final reader = _Reader(await _backup());
      final router = GoRouter(
        initialLocation: '/qr-import',
        routes: [
          GoRoute(
            path: '/qr-import',
            builder: (c, s) =>
                SignerQrImportScreen(picker: picker, reader: reader),
          ),
          GoRoute(
            path: '/set-password',
            builder: (c, s) => const Scaffold(body: Text('PIN SETUP')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          locale: Locale(locale),
          theme: ktSignerTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (c, child) =>
              SignerWalletScope(controller: wallet, child: child!),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(SignerQrImportScreen)),
      );
      picker.cancel = true;
      await tester.tap(find.byKey(const ValueKey('qr-import-image')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.qrImportInvalid), findsNothing);
      picker.cancel = false;
      await tester.tap(find.byKey(const ValueKey('qr-import-image')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('qr-import-password')),
        'wrong',
      );
      await tester.pump();
      await tester.tap(find.text(l10n.qrImportContinue));
      await tester.pumpAndSettle();
      expect(find.text(l10n.qrImportWrongPassword), findsOneWidget);
      expect(wallet.pendingMnemonic, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('qr-import-password')),
        _password,
      );
      await tester.pump();
      await tester.tap(find.text(l10n.qrImportContinue));
      await tester.pumpAndSettle();
      expect(find.text('PIN SETUP'), findsOneWidget);
      expect(crypto.writes, 0);
      expect(find.text(_phrase), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('home actions have equal-height two-column layout in $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          theme: ktSignerTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SignerHomeScreen(
            probe: () async => const DeviceState.unknown(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final left = tester.getRect(find.byKey(const ValueKey('home-action-0')));
      final right = tester.getRect(find.byKey(const ValueKey('home-action-1')));
      final next = tester.getRect(find.byKey(const ValueKey('home-action-2')));
      expect(left.height, right.height);
      expect(left.top, right.top);
      expect(next.top, greaterThan(left.bottom));
      expect(tester.takeException(), isNull);
    });
  }
}
