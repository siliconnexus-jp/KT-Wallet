import 'dart:convert';

import 'package:core_crypto/core_crypto.dart';
import 'package:core_crypto/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _RecordingBackupCrypto extends MockCoreCrypto {
  BackupCipherFormat? lastReadFormat;

  @override
  Future<String> readBackup({
    required Uint8List blob,
    required String password,
    required BackupCipherFormat format,
  }) {
    lastReadFormat = format;
    return super.readBackup(blob: blob, password: password, format: format);
  }
}

/// A router, not a plain `home:`, because a successful restore navigates to
/// /home — and a screen that cannot navigate is not one this test has proven.
Widget _app(
  Widget home,
  WalletController controller, {
  Locale locale = const Locale('zh'),
}) => MaterialApp.router(
  debugShowCheckedModeBanner: false,
  locale: locale,
  theme: ThemeData(fontFamily: 'Inter'),
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
  test('provider file names are reduced to safe bounded display text', () {
    expect(
      sanitizePickedFileName('/private/provider/\u202Eevil.exe\nwallet.ktbak'),
      'evil.exewallet.ktbak',
    );
    expect(
      sanitizePickedFileName(r'C:\provider\folder\wallet.ktbak'),
      'wallet.ktbak',
    );
    expect(
      sanitizePickedFileName('  KT\u00A0\u3000Wallet.ktbak  '),
      'KT Wallet.ktbak',
    );
    expect(sanitizePickedFileName('\u2066\u2069\n'), isEmpty);
    expect(sanitizePickedFileName(null), isEmpty);

    final long = sanitizePickedFileName(
      '${List.filled(120, 'a').join()}.ktbak',
    );
    expect(long.runes.length, pickedFileDisplayNameMaxRunes);
    expect(long, contains('…'));
    expect(long, endsWith('.ktbak'));
  });

  testWidgets('platform file exchange enforces and transmits the read limit', (
    tester,
  ) async {
    MethodCall? observed;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      FileExchange.channel,
      (call) async {
        observed = call;
        return <String, Object?>{
          'cancelled': false,
          'name': 'oversized.ktbak',
          'bytes': Uint8List(5),
        };
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        FileExchange.channel,
        null,
      ),
    );

    await expectLater(
      const FileExchange().pickFile(maxBytes: 4),
      throwsA(isA<FileTooLargeException>()),
    );
    expect(observed?.method, 'pickFile');
    expect((observed?.arguments as Map<Object?, Object?>)['maxBytes'], 4);
  });

  testWidgets('platform file exchange never exposes a provider path as name', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      FileExchange.channel,
      (_) async => <String, Object?>{
        'cancelled': false,
        'name': '/private/provider/\u202Ewallet.ktbak',
        'bytes': Uint8List.fromList([1, 2]),
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        FileExchange.channel,
        null,
      ),
    );

    final picked = await const FileExchange().pickFile(maxBytes: 4);
    expect(picked?.name, 'wallet.ktbak');
    expect(picked?.name, isNot(contains('/private/')));
  });

  testWidgets('native too-large result remains distinct from cancellation', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      FileExchange.channel,
      (_) => throw PlatformException(code: 'FILE_TOO_LARGE'),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        FileExchange.channel,
        null,
      ),
    );

    await expectLater(
      const FileExchange().pickFile(maxBytes: 4),
      throwsA(isA<FileTooLargeException>()),
    );
  });

  testWidgets('native picker failure is not misreported as cancellation', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      FileExchange.channel,
      (_) => throw PlatformException(
        code: 'FAILED',
        message: '/private/provider/path must not cross the boundary',
      ),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        FileExchange.channel,
        null,
      ),
    );

    await expectLater(
      const FileExchange().pickFile(maxBytes: 4),
      throwsA(
        isA<FilePickException>().having(
          (error) => error.failure,
          'failure',
          FilePickFailure.failed,
        ),
      ),
    );
  });

  testWidgets('native cancellation remains a quiet null result', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      FileExchange.channel,
      (_) async => <String, Object?>{'cancelled': true},
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        FileExchange.channel,
        null,
      ),
    );

    expect(await const FileExchange().pickFile(maxBytes: 4), isNull);
  });

  testWidgets('malformed native picker replies are visible failures', (
    tester,
  ) async {
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        FileExchange.channel,
        null,
      ),
    );

    for (final reply in <Object?>[
      null,
      <String, Object?>{'cancelled': false},
      'not-a-map',
    ]) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        FileExchange.channel,
        (_) async => reply,
      );
      await expectLater(
        const FileExchange().pickFile(maxBytes: 4),
        throwsA(isA<FilePickException>()),
      );
    }
  });

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
      final decoded = WalletBackupFile.decodeEnvelope(file);
      expect(decoded.envelopeVersion, 2);
      expect(decoded.cryptoFormat, BackupCipherFormat.portableV2);
      expect(decoded.sealed, sealed);
    });

    test('accepts the closed legacy v1 envelope without rewriting it', () {
      final legacy = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'format': WalletBackupFile.format,
            'version': WalletBackupFile.legacyVersion,
            'kdf': {
              'alg': WalletBackupFile.kdfAlgorithm,
              'rounds': WalletBackupFile.kdfRounds,
            },
            'cipher': WalletBackupFile.cipher,
            'createdAt': '2026-08-02T00:00:00.000Z',
            'payload': base64Encode([1, 2, 3]),
          }),
        ),
      );

      final decoded = WalletBackupFile.decodeEnvelope(legacy);
      expect(decoded.envelopeVersion, 1);
      expect(decoded.cryptoFormat, BackupCipherFormat.legacyV1);
      expect(decoded.sealed, [1, 2, 3]);
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
        'payloadFormat',
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

    test('rejects oversized files before JSON or crypto parsing', () {
      final oversized = Uint8List(WalletBackupFile.maxFileBytes + 1);
      expect(
        () => WalletBackupFile.decode(oversized),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('fails closed on envelope and crypto metadata drift', () {
      final valid =
          jsonDecode(
                utf8.decode(
                  WalletBackupFile.encode(
                    sealed: Uint8List.fromList([1, 2, 3]),
                    createdAt: DateTime.utc(2026, 8, 2),
                  ),
                ),
              )
              as Map<String, dynamic>;

      Uint8List encoded(Map<String, dynamic> value) =>
          Uint8List.fromList(utf8.encode(jsonEncode(value)));

      for (final corrupted in <Map<String, dynamic>>[
        {...valid, 'unexpected': true},
        {...valid}..remove('cipher'),
        {...valid, 'version': 0},
        {...valid, 'cipher': 'AES-256-CBC'},
        {...valid, 'payloadFormat': 'argon2id-aes256gcm'},
        {...valid}..remove('payloadFormat'),
        {
          ...valid,
          'kdf': {'alg': WalletBackupFile.kdfAlgorithm, 'rounds': 1},
        },
        {...valid, 'createdAt': '2026-08-02T00:00:00'},
        {...valid, 'payload': ''},
      ]) {
        expect(
          () => WalletBackupFile.decode(encoded(corrupted)),
          throwsA(isA<BackupFormatException>()),
        );
      }
    });

    test('rejects duplicate backup identities before choosing a value', () {
      final payload = base64Encode([1, 2, 3]);
      Uint8List bytes(String body) => Uint8List.fromList(utf8.encode(body));
      final prefix =
          '{"format":"${WalletBackupFile.format}",'
          '"version":${WalletBackupFile.version},'
          '"kdf":{"alg":"${WalletBackupFile.kdfAlgorithm}",'
          '"rounds":${WalletBackupFile.kdfRounds}},'
          '"cipher":"${WalletBackupFile.cipher}",'
          '"payloadFormat":"${WalletBackupFile.payloadFormat}",'
          '"createdAt":"2026-08-05T00:00:00.000Z",';

      for (final ambiguous in [
        '$prefix"payload":"bad","payload":"$payload"}',
        '$prefix"payload":"bad","pay\\u006coad":"$payload"}',
        '{"format":"wrong","format":"${WalletBackupFile.format}",'
            '"version":${WalletBackupFile.version},'
            '"kdf":{"alg":"${WalletBackupFile.kdfAlgorithm}",'
            '"rounds":1,"rounds":${WalletBackupFile.kdfRounds}},'
            '"cipher":"${WalletBackupFile.cipher}",'
            '"payloadFormat":"${WalletBackupFile.payloadFormat}",'
            '"createdAt":"2026-08-05T00:00:00.000Z",'
            '"payload":"$payload"}',
      ]) {
        expect(
          () => WalletBackupFile.decodeEnvelope(bytes(ambiguous)),
          throwsA(isA<BackupFormatException>()),
        );
      }

      expect(
        WalletBackupFile.createdAtOf(
          bytes(
            '$prefix"createdAt":"2026-08-06T00:00:00.000Z",'
            '"payload":"$payload"}',
          ),
        ),
        isNull,
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

    test('refuses to create a file this reader cannot restore', () {
      expect(
        () => WalletBackupFile.encode(
          sealed: Uint8List(WalletBackupFile.maxFileBytes),
          createdAt: DateTime.utc(2026),
        ),
        throwsA(isA<BackupFormatException>()),
      );
      expect(
        WalletBackupFile.createdAtOf(
          Uint8List(WalletBackupFile.maxFileBytes + 1),
        ),
        isNull,
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
          password: 'correct horse battery',
        );
        expect(
          await crypto.readBackup(
            blob: sealed,
            password: 'correct horse battery',
            format: BackupCipherFormat.portableV2,
          ),
          _phrase,
        );
        await expectLater(
          crypto.readBackup(
            blob: sealed,
            password: 'correct horse batterx',
            format: BackupCipherFormat.portableV2,
          ),
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

    test('predictable and oversized passwords are refused for new files', () {
      expect(
        CoreCryptoValidation.backupPasswordIssue('abababababababab'),
        BackupPasswordIssue.predictable,
      );
      expect(
        CoreCryptoValidation.backupPasswordIssue('abcdefghijklmn'),
        BackupPasswordIssue.predictable,
      );
      expect(
        CoreCryptoValidation.backupPasswordIssue('独立备份密码短语甲乙丙丁戊己庚辛'),
        isNull,
      );
      expect(
        CoreCryptoValidation.backupPasswordIssue(List.filled(129, 'x').join()),
        BackupPasswordIssue.tooLong,
      );
    });
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
        await crypto.readBackup(
          blob: sealed,
          password: 'a good long password',
          format: BackupCipherFormat.portableV2,
        ),
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
      expect(find.text('请至少输入 14 个字符'), findsOneWidget);

      await tester.tap(find.text('生成备份'));
      await tester.pumpAndSettle();
      expect(files.saved, isEmpty);
    });

    testWidgets('a predictable password is explained and cannot be submitted', (
      tester,
    ) async {
      final crypto = MockCoreCrypto();
      final controller = await _controllerWithWallet(crypto);
      final files = FakeFileExchange();

      await tester.pumpWidget(
        _app(BackupExportScreen(files: files), controller),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'abababababababab');
      await tester.enterText(find.byType(TextField).at(1), 'abababababababab');
      await tester.pumpAndSettle();

      expect(find.text('请勿使用重复、连续或常见密码'), findsOneWidget);
      await tester.tap(find.text('生成备份'));
      await tester.pumpAndSettle();
      expect(files.saved, isEmpty);
    });

    testWidgets('an oversized document is rejected before password entry', (
      tester,
    ) async {
      final crypto = MockCoreCrypto();
      final controller = await _controllerWithWallet(crypto);
      final files = FakeFileExchange(
        pick: PickedFile(
          name: 'huge.ktbak',
          bytes: Uint8List(WalletBackupFile.maxFileBytes + 1),
        ),
      );

      await tester.pumpWidget(
        _app(BackupRestoreScreen(files: files), controller),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择备份文件'));
      await tester.pumpAndSettle();

      expect(find.text('此文件过大，不可能是 KT 钱包备份'), findsOneWidget);
      expect(find.textContaining('huge.ktbak'), findsNothing);
    });

    testWidgets('provider read failures show fixed localized retry copy', (
      tester,
    ) async {
      const cases = <(Locale, String, String)>[
        (
          Locale('en'),
          'Choose backup file',
          'Could not read the selected file. Try again',
        ),
        (Locale('zh'), '选择备份文件', '无法读取所选文件，请重试'),
        (Locale('ja'), 'バックアップファイルを選択', '選択したファイルを読み込めませんでした。もう一度お試しください'),
      ];
      for (final (locale, action, message) in cases) {
        final controller = WalletController(
          WalletManager(),
          crypto: MockCoreCrypto(),
        );
        final files = FakeFileExchange(
          pickFailure: const FilePickException(FilePickFailure.failed),
        );

        await tester.pumpWidget(
          _app(BackupRestoreScreen(files: files), controller, locale: locale),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(action));
        await tester.pumpAndSettle();

        expect(find.text(message), findsOneWidget);
        expect(find.textContaining('/private/'), findsNothing);
        final password = tester.widget<TextField>(find.byType(TextField));
        expect(password.decoration?.errorText, isNull);
        expect(password.enabled, isFalse);
        expect(
          tester.getTopLeft(find.text(message)).dy,
          lessThan(tester.getTopLeft(find.byType(TextField)).dy),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      }
    });

    testWidgets('an unavailable native picker has distinct recovery copy', (
      tester,
    ) async {
      final controller = WalletController(
        WalletManager(),
        crypto: MockCoreCrypto(),
      );
      addTearDown(controller.dispose);
      final files = FakeFileExchange(
        pickFailure: const FilePickException(FilePickFailure.unavailable),
      );

      await tester.pumpWidget(
        _app(BackupRestoreScreen(files: files), controller),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择备份文件'));
      await tester.pumpAndSettle();

      expect(find.text('此设备无法打开备份文件'), findsOneWidget);
      expect(find.text('无法读取所选文件，请重试'), findsNothing);
    });

    testWidgets('an empty sanitized name uses localized neutral copy', (
      tester,
    ) async {
      final controller = WalletController(
        WalletManager(),
        crypto: MockCoreCrypto(),
      );
      addTearDown(controller.dispose);
      final bytes = WalletBackupFile.encode(
        sealed: Uint8List.fromList([1, 2, 3]),
        createdAt: DateTime.utc(2026),
      );
      final files = FakeFileExchange(
        pick: PickedFile(name: '\u202E\n', bytes: bytes),
      );

      await tester.pumpWidget(
        _app(BackupRestoreScreen(files: files), controller),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择备份文件'));
      await tester.pumpAndSettle();

      expect(find.text('已选择：备份文件'), findsOneWidget);
      expect(find.textContaining('\u202E'), findsNothing);
    });

    testWidgets('a failed re-pick cannot retain a password for the old file', (
      tester,
    ) async {
      final controller = WalletController(
        WalletManager(),
        crypto: MockCoreCrypto(),
      );
      addTearDown(controller.dispose);
      final bytes = WalletBackupFile.encode(
        sealed: Uint8List.fromList([1, 2, 3]),
        createdAt: DateTime.utc(2026),
      );
      final files = FakeFileExchange(
        pick: PickedFile(name: 'first.ktbak', bytes: bytes),
      );

      await tester.pumpWidget(
        _app(BackupRestoreScreen(files: files), controller),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择备份文件'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'password for first');
      expect(find.byType(TextField), findsOneWidget);

      files.pickFailure = const FilePickException(FilePickFailure.failed);
      await tester.tap(find.text('已选择：first.ktbak'));
      await tester.pumpAndSettle();

      final password = tester.widget<TextField>(find.byType(TextField));
      expect(password.controller?.text, isEmpty);
      expect(password.enabled, isFalse);
      expect(find.text('无法读取所选文件，请重试'), findsOneWidget);
    });

    testWidgets('provider read failure has a stable phone-size visual', (
      tester,
    ) async {
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('fonts/Inter.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = WalletController(
        WalletManager(),
        crypto: MockCoreCrypto(),
      );
      addTearDown(controller.dispose);
      final files = FakeFileExchange(
        pickFailure: const FilePickException(FilePickFailure.failed),
      );

      await tester.pumpWidget(
        _app(
          BackupRestoreScreen(files: files),
          controller,
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose backup file'));
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/backup/provider-read-failed-en.png'),
      );
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

    testWidgets('legacy envelope stays bound to the legacy native reader', (
      tester,
    ) async {
      final source = MockCoreCrypto();
      final sourceController = await _controllerWithWallet(source);
      final sealed = await source.createBackup(
        walletId: sourceController.current!.id,
        password: 'a good long password',
      );
      final legacyFile = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'format': WalletBackupFile.format,
            'version': WalletBackupFile.legacyVersion,
            'kdf': {
              'alg': WalletBackupFile.kdfAlgorithm,
              'rounds': WalletBackupFile.kdfRounds,
            },
            'cipher': WalletBackupFile.cipher,
            'createdAt': '2026-08-02T00:00:00.000Z',
            'payload': base64Encode(sealed),
          }),
        ),
      );

      final crypto = _RecordingBackupCrypto();
      final controller = WalletController(WalletManager(), crypto: crypto);
      final files = FakeFileExchange(
        pick: PickedFile(name: 'legacy.ktbak', bytes: legacyFile),
      );
      await tester.pumpWidget(
        _app(BackupRestoreScreen(files: files), controller),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择备份文件'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'a good long password');
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复'));
      await tester.pumpAndSettle();

      expect(crypto.lastReadFormat, BackupCipherFormat.legacyV1);
      expect(controller.count, 1);
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

      await tester.enterText(find.byType(TextField).first, 'try again');
      await tester.pump();
      expect(find.text('密码错误，或文件已损坏'), findsNothing);
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
