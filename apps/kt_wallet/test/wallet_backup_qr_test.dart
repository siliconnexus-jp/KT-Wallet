import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:core_crypto/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, ByteData;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/platform/file_exchange.dart';
import 'package:kt_wallet/src/screens/backup_screens.dart';
import 'package:kt_wallet/src/security/backup_qr_image.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/state/wallet_scope.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/widgets/scan_viewfinder.dart';
import 'package:ui_kit/ui_kit.dart';

// Public test-only phrase. No production wallet is accessed by this suite.
const phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const password = 'harbor velvet copper comet 27';
final onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Zl1sAAAAASUVORK5CYII=',
);

class _Reader extends BackupQrImageReader {
  _Reader(this.text);
  final String text;
  @override
  Future<String> read(Uint8List bytes) async => text;
}

Widget host(Widget page, WalletController wallets) => MaterialApp.router(
  locale: const Locale('zh'),
  theme: ktWalletTheme(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  routerConfig: GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => WalletScope(controller: wallets, child: page),
      ),
      GoRoute(
        path: '/home',
        builder: (_, _) => const Scaffold(body: Text('restored-home')),
      ),
    ],
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = Platform.environment['KT_BACKUP_QR_FONT'];
    if (font != null) {
      await (FontLoader(
        KtFonts.ui,
      )..addFont(File(font).readAsBytes().then(ByteData.sublistView))).load();
    }
  });
  test('QR codec is bounded, canonical, and pinned to portable-v2', () {
    for (final length in [60, 68, 76, 512]) {
      final sealed = Uint8List.fromList(List.generate(length, (i) => i % 256));
      final decoded = WalletBackupQr.decode(WalletBackupQr.encode(sealed));
      expect(decoded.sealed, sealed);
      expect(decoded.cryptoFormat, BackupCipherFormat.portableV2);
    }
    for (final text in [
      '',
      phrase,
      'https://example.com',
      'KTWALLET:BACKUP:1:AAAA',
      'KTWALLET:BACKUP:3:AAAA',
      '${WalletBackupQr.prefix}AAAA',
      '${WalletBackupQr.prefix}${'A' * 10000}',
      '${WalletBackupQr.encode(Uint8List(60))}\n',
    ]) {
      expect(
        () => WalletBackupQr.decode(text),
        throwsA(isA<BackupFormatException>()),
      );
    }
    expect(
      () => WalletBackupQr.encode(Uint8List(59)),
      throwsA(isA<BackupFormatException>()),
    );
    expect(
      () => WalletBackupQr.encode(Uint8List(513)),
      throwsA(isA<BackupFormatException>()),
    );
  });

  test('branded PNG renders a real QR at maximum supported size', () async {
    final png = await renderBackupQrPng(
      payload: WalletBackupQr.encode(Uint8List(512)),
      title: 'Encrypted recovery backup',
      instruction:
          'Password required. Not a payment QR. Keep the password separately.',
    );
    expect(png.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(png.length, greaterThan(5000));
    final output = Platform.environment['KT_BACKUP_QR_PREVIEW'];
    if (output != null) {
      final preview = await renderBackupQrPng(
        payload: WalletBackupQr.encode(Uint8List(76)),
        title: '加密助记词备份',
        instruction:
            '示例图片 · 不含真实钱包\n需要密码，不是收款码。请在 KT Wallet 中选择「从备份恢复」，密码与图片须分开保管。',
      );
      await File(output).writeAsBytes(preview);
    }
  });

  testWidgets(
    'QR export requires strength, confirmation and explicit risk acceptance',
    (tester) async {
      final crypto = MockCoreCrypto();
      final wallets = WalletController(WalletManager(), crypto: crypto);
      addTearDown(wallets.dispose);
      await wallets.importWallet(phrase, name: 'Test wallet');
      final files = FakeFileExchange(
        saveOutcome: FileExchangeOutcome.cancelled,
      );
      String? payload;
      await tester.pumpWidget(
        host(
          BackupExportScreen(
            files: files,
            qrRenderer: (value) async {
              payload = value;
              return onePixelPng;
            },
          ),
          wallets,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('加密二维码'));
      await tester.pumpAndSettle();
      bool enabled() =>
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, '生成加密二维码'),
              )
              .onPressed !=
          null;
      await tester.enterText(find.byType(TextField).first, 'short');
      await tester.enterText(find.byType(TextField).last, 'short');
      await tester.pumpAndSettle();
      expect(enabled(), false);
      await tester.enterText(find.byType(TextField).first, password);
      await tester.enterText(find.byType(TextField).last, password);
      await tester.pumpAndSettle();
      expect(enabled(), false);
      await tester.ensureVisible(find.byKey(const ValueKey('backup-qr-risk')));
      await tester.tap(find.byKey(const ValueKey('backup-qr-risk')));
      await tester.pumpAndSettle();
      expect(enabled(), true);
      await tester.tap(find.text('生成加密二维码'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('backup-qr-preview')), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      final decoded = WalletBackupQr.decode(payload!);
      expect(
        await crypto.readBackup(
          blob: decoded.sealed,
          password: password,
          format: decoded.cryptoFormat,
        ),
        phrase,
      );
      await tester.tap(find.text('保存二维码图片到本地'));
      await tester.pumpAndSettle();
      expect(files.saved.single.name, endsWith('-encrypted.png'));
      expect(files.saved.single.bytes, onePixelPng);
      expect(find.byKey(const ValueKey('backup-qr-preview')), findsOneWidget);
    },
  );

  testWidgets(
    'image import requires password and does not create a wallet on failure',
    (tester) async {
      final crypto = MockCoreCrypto();
      final source = WalletController(WalletManager(), crypto: crypto);
      addTearDown(source.dispose);
      await source.importWallet(phrase, name: 'Source');
      final payload = WalletBackupQr.encode(
        await crypto.createBackup(
          walletId: source.current!.id,
          password: password,
        ),
      );
      final target = WalletController(WalletManager(), crypto: crypto);
      addTearDown(target.dispose);
      final files = FakeFileExchange(
        pick: PickedFile(name: 'encrypted.png', bytes: onePixelPng),
      );
      await tester.pumpWidget(
        host(
          BackupRestoreScreen(files: files, qrImages: _Reader(payload)),
          target,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('backup-qr-pick-image')));
      await tester.pumpAndSettle();
      expect(target.count, 0);
      await tester.enterText(find.byType(TextField), 'wrong password');
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(BackupRestoreScreen)),
      );
      await tester.tap(find.text(l10n.restoreAction));
      await tester.pumpAndSettle();
      expect(find.text(l10n.restoreWrongPassword), findsOneWidget);
      expect(target.count, 0);
      await tester.enterText(find.byType(TextField), password);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.restoreAction));
      await tester.pumpAndSettle();
      expect(target.count, 1);
      expect(find.text('restored-home'), findsOneWidget);
    },
  );

  testWidgets(
    'scanner rejects payment codes and accepts only encrypted backups',
    (tester) async {
      final wallets = WalletController(
        WalletManager(),
        crypto: MockCoreCrypto(),
      );
      addTearDown(wallets.dispose);
      await tester.pumpWidget(
        host(BackupRestoreScreen(files: FakeFileExchange()), wallets),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('backup-qr-scan')));
      await tester.pumpAndSettle();
      tester.widget<ScanViewfinder>(find.byType(ScanViewfinder)).onScanned!(
        'ethereum:0x123',
      );
      await tester.pumpAndSettle();
      expect(find.byType(BackupQrScanScreen), findsOneWidget);
      tester.widget<ScanViewfinder>(find.byType(ScanViewfinder)).onScanned!(
        WalletBackupQr.encode(Uint8List(76)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BackupQrScanScreen), findsNothing);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, true);
      expect(wallets.count, 0);
    },
  );
}
