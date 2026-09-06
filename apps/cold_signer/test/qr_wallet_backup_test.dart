import 'dart:async';
import 'dart:convert';

import 'package:core_crypto/core_crypto.dart';
import 'package:core_crypto/testing.dart';
import 'package:cold_signer/l10n/app_localizations.dart';
import 'package:cold_signer/src/screens/signer_qr_backup_screen.dart';
import 'package:cold_signer/src/security/backup_qr_image.dart';
import 'package:cold_signer/src/security/secure_vault.dart';
import 'package:cold_signer/src/state/signer_wallet_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

const password = 'harbor velvet copper comet 27';
const phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Zl1sAAAAASUVORK5CYII=',
);

class _Crypto extends MockCoreCrypto {
  bool cancel = false;
  int calls = 0;
  Completer<void>? pause;
  @override
  Future<Uint8List> createBackup({
    required String walletId,
    required String password,
  }) async {
    calls++;
    await pause?.future;
    if (cancel) throw const AuthCancelledException();
    return super.createBackup(walletId: walletId, password: password);
  }
}

class _Files extends SignerBackupImagePicker {
  int saves = 0;
  bool fail = false;
  @override
  Future<bool> save(Uint8List bytes) async {
    saves++;
    expect(bytes, png);
    if (fail) throw PlatformException(code: 'WRITE_FAILED');
    return true;
  }
}

Future<SignerWalletController> _wallet(_Crypto crypto) async {
  final controller = SignerWalletController(
    crypto: crypto,
    storage: InMemoryVaultStorage(),
    pinIterations: 10,
  );
  expect(await controller.beginImport(phrase), isTrue);
  await controller.setPin('482961');
  await controller.completeOnboarding();
  return controller;
}

Widget host(
  SignerWalletController wallet,
  Widget child, {
  String locale = 'en',
}) => MaterialApp(
  locale: Locale(locale),
  theme: ktSignerTheme(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: SignerWalletScope(controller: wallet, child: child),
);

Future<void> fill(WidgetTester tester, {String value = password}) async {
  await tester.enterText(find.byType(TextField).at(0), value);
  await tester.enterText(find.byType(TextField).at(1), value);
  final risk = find.byKey(const ValueKey('signer-backup-risk'));
  await tester.ensureVisible(risk);
  if (!tester.widget<CheckboxListTile>(risk).value!) await tester.tap(risk);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('encrypted backup form visual review', (tester) async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('fonts/Inter.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = await _wallet(_Crypto());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        controller,
        SignerQrBackupScreen(walletId: controller.localWalletId!),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/backup/qr-export-en.png'),
    );
  });

  testWidgets(
    'weak password never exports; native ciphertext QR can restore and save retries',
    (tester) async {
      final crypto = _Crypto();
      final controller = await _wallet(crypto);
      addTearDown(controller.dispose);
      final files = _Files();
      String? payload;
      await tester.pumpWidget(
        host(
          controller,
          SignerQrBackupScreen(
            walletId: controller.localWalletId!,
            files: files,
            renderer: (value) async {
              payload = value;
              return png;
            },
          ),
        ),
      );
      await fill(tester, value: '123');
      expect(
        tester
            .widget<KtPrimaryButton>(
              find.byKey(const ValueKey('signer-backup-submit')),
            )
            .onPressed,
        isNull,
      );
      expect(crypto.calls, 0);
      await fill(tester);
      await tester.tap(find.byKey(const ValueKey('signer-backup-submit')));
      await tester.pumpAndSettle();
      expect(crypto.calls, 1);
      expect(find.byType(TextField), findsNothing);
      expect(find.text(phrase), findsNothing);
      final decoded = WalletBackupQr.decode(payload!);
      expect(decoded.cryptoFormat, BackupCipherFormat.portableV2);
      // App-level transport round trip; real encryption vectors live in native tests.
      expect(
        await crypto.readBackup(
          blob: decoded.sealed,
          password: password,
          format: decoded.cryptoFormat,
        ),
        phrase,
      );
      await expectLater(
        crypto.readBackup(
          blob: decoded.sealed,
          password: 'incorrect',
          format: decoded.cryptoFormat,
        ),
        throwsA(isA<StoreCorruptedException>()),
      );
      files.fail = true;
      await tester.tap(find.byKey(const ValueKey('signer-backup-submit')));
      await tester.pumpAndSettle();
      expect(files.saves, 1);
      files.fail = false;
      await tester.tap(find.byKey(const ValueKey('signer-backup-submit')));
      await tester.pumpAndSettle();
      expect(files.saves, 2);
      expect(crypto.calls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancelled native authentication exports nothing and clears password',
    (tester) async {
      final crypto = _Crypto()..cancel = true;
      final controller = await _wallet(crypto);
      addTearDown(controller.dispose);
      var rendered = false;
      await tester.pumpWidget(
        host(
          controller,
          SignerQrBackupScreen(
            walletId: controller.localWalletId!,
            renderer: (_) async {
              rendered = true;
              return png;
            },
          ),
        ),
      );
      await fill(tester);
      await tester.tap(find.byKey(const ValueKey('signer-backup-submit')));
      await tester.pumpAndSettle();
      expect(rendered, false);
      for (final field in tester.widgetList<TextField>(
        find.byType(TextField),
      )) {
        expect(field.controller!.text, isEmpty);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('wrong wallet ID cannot export even via direct route', (
    tester,
  ) async {
    final crypto = _Crypto();
    final controller = await _wallet(crypto);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        controller,
        const SignerQrBackupScreen(walletId: 'different-wallet'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('signer-backup-submit')), findsNothing);
    expect(crypto.calls, 0);
    await expectLater(
      controller.createEncryptedBackup(
        walletId: 'different-wallet',
        password: password,
      ),
      throwsStateError,
    );
  });

  for (final locale in ['zh', 'en', 'ja']) {
    testWidgets('backup form $locale supports narrow screens and large text', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = await _wallet(_Crypto());
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(
          controller,
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: SignerQrBackupScreen(walletId: controller.localWalletId!),
          ),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  test(
    'save adapter rejects unbounded files before platform channel',
    () async {
      const files = SignerBackupImagePicker();
      await expectLater(
        files.save(Uint8List(0)),
        throwsA(isA<BackupFormatException>()),
      );
      await expectLater(
        files.save(Uint8List(BackupQrImageReader.maxFileBytes + 1)),
        throwsA(isA<BackupFormatException>()),
      );
    },
  );
}
