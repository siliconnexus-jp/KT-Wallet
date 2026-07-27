import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:core_crypto/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/platform/file_exchange.dart';
import 'package:kt_wallet/src/screens/backup_screens.dart';
import 'package:kt_wallet/src/security/wallet_backup.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/state/wallet_scope.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';

const _phrase =
    'abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon about';

/// A router, not a plain `home:`, because a successful restore navigates to
/// /home — and a screen that cannot navigate is not one this test has proven.
Widget _app(Widget home, WalletController controller) => MaterialApp.router(
  debugShowCheckedModeBanner: false,
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  routerConfig: GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (c, s) => WalletScope(controller: controller, child: home),
      ),
      GoRoute(
        path: '/home',
        builder: (c, s) => const Scaffold(body: Text('home')),
      ),
    ],
  ),
);

Future<WalletController> _controllerWithWallet(MockCoreCrypto crypto) async {
  final controller = WalletController(WalletManager(), crypto: crypto);
  await controller.importWallet(_phrase, name: 'Wallet 1');
  return controller;
}

void main() {
  group('envelope', () {
    test('round-trips the sealed payload', () {
      final sealed = Uint8List.fromList([1, 2, 3, 4, 250]);
      final file = WalletBackupFile.encode(
        sealed: sealed,
        createdAt: DateTime.utc(2026, 7, 27, 22, 15),
      );
      expect(WalletBackupFile.decode(file), sealed);
      expect(
        WalletBackupFile.createdAtOf(file),
        DateTime.utc(2026, 7, 27, 22, 15),
      );
    });

    test('carries no wallet identity in cleartext', () {
      final text = utf8.decode(
        WalletBackupFile.encode(
          sealed: Uint8List.fromList([9, 9, 9]),
          createdAt: DateTime.utc(2026),
        ),
      );
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      // Anything beyond these keys is a disclosure the file did not need.
      expect(decoded.keys.toSet(), {
        'format',
        'version',
        'kdf',
        'cipher',
        'createdAt',
        'payload',
      });
    });

    test('rejects a file that is not ours', () {
      expect(
        () => WalletBackupFile.decode(
          Uint8List.fromList(utf8.encode('{"format":"someone-else"}')),
        ),
        throwsA(isA<BackupFormatException>()),
      );
      expect(
        () => WalletBackupFile.decode(Uint8List.fromList([0, 1, 2])),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('names a version from the future rather than failing to decrypt', () {
      final future = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'format': WalletBackupFile.format,
            'version': WalletBackupFile.version + 1,
            'payload': base64Encode([1, 2, 3]),
          }),
        ),
      );
      expect(
        () => WalletBackupFile.decode(future),
        throwsA(
          isA<BackupFormatException>().having(
            (e) => e.reason,
            'reason',
            contains('too new'),
          ),
        ),
      );
    });

    test('file name is timestamped and carries the extension', () {
      expect(
        WalletBackupFile.suggestedFileName(DateTime(2026, 7, 27, 9, 5)),
        'KT-Wallet-20260727-0905.ktbak',
      );
    });
  });

  group('seal', () {
    test(
      'the right password recovers the phrase, a wrong one does not',
      () async {
        final crypto = MockCoreCrypto();
        final controller = await _controllerWithWallet(crypto);
        final id = controller.current!.id;

        final sealed = await crypto.createBackup(
          walletId: id,
          password: 'correct horse',
        );
        expect(
          await crypto.readBackup(blob: sealed, password: 'correct horse'),
          _phrase,
        );
        await expectLater(
          crypto.readBackup(blob: sealed, password: 'correct hors'),
          throwsA(isA<StoreCorruptedException>()),
        );
      },
    );

    test(
      'a too-short password is refused before any sealing happens',
      () async {
        final crypto = MockCoreCrypto();
        final controller = await _controllerWithWallet(crypto);
        expect(
          () => crypto.createBackup(
            walletId: controller.current!.id,
            password: 'short',
          ),
          throwsArgumentError,
        );
      },
    );
  });

  group('export screen', () {
    testWidgets('seals and hands the envelope to the file picker', (
      tester,
    ) async {
      final crypto = MockCoreCrypto();
      final controller = await _controllerWithWallet(crypto);
      final files = FakeFileExchange();

      await tester.pumpWidget(
        _app(
          BackupExportScreen(
            files: files,
            clock: () => DateTime.utc(2026, 7, 27, 22, 30),
          ),
          controller,
        ),
      );
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'a good long password');
      await tester.enterText(fields.at(1), 'a good long password');
      await tester.pumpAndSettle();
      await tester.tap(find.text('生成备份'));
      await tester.pumpAndSettle();

      expect(files.saved, hasLength(1));
      expect(files.saved.single.name, endsWith('.ktbak'));
      // What was written must open again with the same password.
      final sealed = WalletBackupFile.decode(files.saved.single.bytes);
      expect(
        await crypto.readBackup(blob: sealed, password: 'a good long password'),
        _phrase,
      );
    });

    testWidgets('mismatched passwords never reach the crypto layer', (
      tester,
    ) async {
      final crypto = MockCoreCrypto();
      final controller = await _controllerWithWallet(crypto);
      final files = FakeFileExchange();

      await tester.pumpWidget(
        _app(BackupExportScreen(files: files), controller),
      );
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'a good long password');
      await tester.enterText(fields.at(1), 'a good long passwork');
      await tester.pumpAndSettle();
      await tester.tap(find.text('生成备份'));
      await tester.pumpAndSettle();

      expect(files.saved, isEmpty);
      expect(find.text('两次输入的密码不一致'), findsOneWidget);
    });

    testWidgets('a short password leaves the button disabled', (tester) async {
      final crypto = MockCoreCrypto();
      final controller = await _controllerWithWallet(crypto);
      final files = FakeFileExchange();

      await tester.pumpWidget(
        _app(BackupExportScreen(files: files), controller),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'short');
      await tester.enterText(find.byType(TextField).at(1), 'short');
      await tester.pumpAndSettle();
      expect(find.text('至少 8 位'), findsOneWidget);

      await tester.tap(find.text('生成备份'));
      await tester.pumpAndSettle();
      expect(files.saved, isEmpty);
    });
  });

  group('restore screen', () {
    Future<Uint8List> backupFile(MockCoreCrypto crypto, String walletId) async {
      final sealed = await crypto.createBackup(
        walletId: walletId,
        password: 'a good long password',
      );
      return WalletBackupFile.encode(
        sealed: sealed,
        createdAt: DateTime.utc(2026),
      );
    }

    testWidgets('restores the wallet from a file plus its password', (
      tester,
    ) async {
      final source = MockCoreCrypto();
      final sourceController = await _controllerWithWallet(source);
      final bytes = await backupFile(source, sourceController.current!.id);

      // A fresh device: new crypto backend, no wallets.
      final crypto = MockCoreCrypto();
      final controller = WalletController(WalletManager(), crypto: crypto);
      final files = FakeFileExchange(
        pick: PickedFile(name: 'KT-Wallet.ktbak', bytes: bytes),
      );

      await tester.pumpWidget(
        _app(BackupRestoreScreen(files: files), controller),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('选择备份文件'));
      await tester.pumpAndSettle();
      expect(find.textContaining('KT-Wallet.ktbak'), findsOneWidget);

      await tester.enterText(
        find.byType(TextField).first,
        'a good long password',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复'));
      await tester.pumpAndSettle();

      expect(find.text('home'), findsOneWidget, reason: 'lands on /home');
      expect(controller.count, 1);
      expect(controller.current, isA<HotWallet>());
      // Same key material: the restored wallet derives the same addresses.
      expect(
        controller.current!.addresses.eth,
        sourceController.current!.addresses.eth,
      );
    });

    testWidgets('a wrong password reports itself and imports nothing', (
      tester,
    ) async {
      final source = MockCoreCrypto();
      final sourceController = await _controllerWithWallet(source);
      final bytes = await backupFile(source, sourceController.current!.id);

      final controller = WalletController(
        WalletManager(),
        crypto: MockCoreCrypto(),
      );
      final files = FakeFileExchange(
        pick: PickedFile(name: 'KT-Wallet.ktbak', bytes: bytes),
      );

      await tester.pumpWidget(
        _app(BackupRestoreScreen(files: files), controller),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择备份文件'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'not the password');
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复'));
      await tester.pumpAndSettle();

      expect(find.text('密码错误，或文件已损坏'), findsOneWidget);
      expect(controller.count, 0);
    });

    testWidgets('a foreign file is rejected at pick time', (tester) async {
      final controller = WalletController(
        WalletManager(),
        crypto: MockCoreCrypto(),
      );
      final files = FakeFileExchange(
        pick: PickedFile(
          name: 'holiday.jpg',
          bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF]),
        ),
      );

      await tester.pumpWidget(
        _app(BackupRestoreScreen(files: files), controller),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择备份文件'));
      await tester.pumpAndSettle();

      expect(find.text('这不是 KT 钱包的备份文件'), findsOneWidget);
      // Still asking for a file, not for a password to a file it never took.
      expect(find.text('选择备份文件'), findsOneWidget);
    });
  });
}
