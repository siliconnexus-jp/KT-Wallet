import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:core_crypto/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/main.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';

const _phrase =
    'abandon ability able about above absent absorb abstract absurd abuse access accident';

class _ObservedCrypto extends MockCoreCrypto {
  _ObservedCrypto({super.authenticator});
  int phraseReads = 0;
  int keySessions = 0;
  int endedSessions = 0;

  @override
  Future<String> exportMnemonic(String walletId) {
    phraseReads++;
    return super.exportMnemonic(walletId);
  }

  @override
  Future<String> beginPrivateKeyExport(String walletId) {
    keySessions++;
    return super.beginPrivateKeyExport(walletId);
  }

  @override
  Future<void> endPrivateKeyExport(String sessionId) {
    endedSessions++;
    return super.endPrivateKeyExport(sessionId);
  }
}

Future<void> _pump(
  WidgetTester tester,
  _ObservedCrypto crypto, {
  Locale locale = const Locale('zh'),
  Key? boundaryKey,
}) async {
  tester.platformDispatcher.localesTestValue = [locale];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  await crypto.storeWallet(walletId: 'w1', mnemonic: _phrase);
  final controller = WalletController(WalletManager(), crypto: crypto);
  addTearDown(controller.dispose);
  await controller.add(
    HotWallet(
      id: 'w1',
      name: '风险提示测试钱包',
      avatarColor: 0xFF2557E8,
      addresses: await crypto.deriveAddresses('w1'),
      backedUp: true,
    ),
  );
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: KtWalletApp(
        controller: controller,
        initialLocation: '/wallet-detail?id=w1',
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _continue(bool privateKey) => find.byKey(
  ValueKey(
    privateKey ? 'private-key-warning-primary' : 'mnemonic-risk-continue',
  ),
);

Future<void> _open(WidgetTester tester, bool privateKey) async {
  final entry = find.byKey(
    ValueKey(
      privateKey
          ? 'wallet-detail-view-private-key'
          : 'wallet-detail-view-mnemonic',
    ),
  );
  await tester.ensureVisible(entry);
  await tester.tap(entry);
  await tester.pumpAndSettle();
}

void main() {
  for (final locale in const [Locale('zh'), Locale('en'), Locale('ja')]) {
    for (final privateKey in [false, true]) {
      testWidgets(
        'risk notice ${locale.languageCode} privateKey=$privateKey supports compact large text',
        (tester) async {
          tester.view.physicalSize = const Size(320, 568);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final crypto = _ObservedCrypto();
          await _pump(tester, crypto, locale: locale);
          await _open(tester, privateKey);
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(_continue(privateKey));
          expect(_continue(privateKey).hitTestable(), findsOneWidget);
          expect(crypto.phraseReads + crypto.keySessions, 0);
        },
      );
    }
  }

  for (final privateKey in [false, true]) {
    final name = privateKey ? 'private key' : 'mnemonic';
    testWidgets('$name risk cancellation never accesses native secrets', (
      tester,
    ) async {
      final crypto = _ObservedCrypto();
      await _pump(tester, crypto);
      await _open(tester, privateKey);
      expect(find.text('查看前请注意'), findsOneWidget);
      expect(find.text('我已了解，继续'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
      expect(crypto.phraseReads, 0);
      expect(crypto.keySessions, 0);
      expect(find.text('abandon'), findsNothing);
      expect(
        find.byKey(const ValueKey('private-key-directory-screen')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(
          ValueKey(
            privateKey ? 'private-key-warning-cancel' : 'mnemonic-risk-cancel',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('查看前请注意'), findsNothing);
      expect(crypto.phraseReads + crypto.keySessions, 0);
      // Acceptance is not persisted: every new entry asks again.
      await _open(tester, privateKey);
      expect(find.text('查看前请注意'), findsOneWidget);
      expect(crypto.phraseReads + crypto.keySessions, 0);
    });

    testWidgets(
      '$name repeat taps trigger one authentication and failure reveals nothing',
      (tester) async {
        final auth = Completer<bool>();
        final crypto = _ObservedCrypto(authenticator: () => auth.future);
        await _pump(tester, crypto);
        await _open(tester, privateKey);
        await tester.tap(_continue(privateKey));
        await tester.tap(_continue(privateKey));
        await tester.pump();
        expect(crypto.phraseReads + crypto.keySessions, 1);
        expect(find.text('abandon'), findsNothing);
        expect(
          find.byKey(const ValueKey('private-key-directory-screen')),
          findsNothing,
        );
        auth.complete(false);
        await tester.pumpAndSettle();
        expect(find.text('abandon'), findsNothing);
        expect(
          find.byKey(const ValueKey('private-key-directory-screen')),
          findsNothing,
        );
        expect(
          find.byKey(
            ValueKey(
              privateKey ? 'private-key-auth-error' : 'mnemonic-risk-notice',
            ),
          ),
          privateKey ? findsOneWidget : findsNothing,
        );
      },
    );

    testWidgets(
      '$name requires explicit acceptance before successful authentication',
      (tester) async {
        final crypto = _ObservedCrypto();
        await _pump(tester, crypto);
        await _open(tester, privateKey);
        expect(crypto.phraseReads + crypto.keySessions, 0);
        await tester.tap(_continue(privateKey));
        await tester.pumpAndSettle();
        expect(crypto.phraseReads + crypto.keySessions, 1);
        expect(find.text('查看前请注意'), findsNothing);
        if (privateKey) {
          expect(
            find.byKey(const ValueKey('private-key-directory-screen')),
            findsOneWidget,
          );
        } else {
          expect(find.text('abandon'), findsOneWidget);
          expect(find.text('accident'), findsOneWidget);
        }
      },
    );
  }

  testWidgets(
    'mnemonic is hidden after background and needs fresh authentication',
    (tester) async {
      final crypto = _ObservedCrypto();
      await _pump(tester, crypto);
      await _open(tester, false);
      await tester.tap(_continue(false));
      await tester.pumpAndSettle();
      expect(find.text('abandon'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('abandon'), findsNothing);
      expect(crypto.phraseReads, 1);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(crypto.phraseReads, 2);
      expect(find.text('abandon'), findsOneWidget);
    },
  );

  for (final backgrounded in [false, true]) {
    testWidgets('mnemonic pending authentication backgrounded=$backgrounded', (
      tester,
    ) async {
      final auth = Completer<bool>();
      final crypto = _ObservedCrypto(authenticator: () => auth.future);
      await _pump(tester, crypto);
      await _open(tester, false);
      await tester.tap(_continue(false));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(
        backgrounded ? AppLifecycleState.paused : AppLifecycleState.inactive,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      auth.complete(true);
      await tester.pumpAndSettle();
      expect(crypto.phraseReads, 1);
      expect(
        find.text('abandon'),
        backgrounded ? findsNothing : findsOneWidget,
      );
    });
  }

  testWidgets(
    'private key authentication survives the inactive system prompt state',
    (tester) async {
      final auth = Completer<bool>();
      final crypto = _ObservedCrypto(authenticator: () => auth.future);
      await _pump(tester, crypto);
      await _open(tester, true);
      await tester.tap(_continue(true));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      auth.complete(true);
      await tester.pumpAndSettle();
      expect(crypto.keySessions, 1);
      expect(crypto.endedSessions, 0);
      expect(
        find.byKey(const ValueKey('private-key-directory-screen')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'private key authentication completing after backgrounding is discarded',
    (tester) async {
      final auth = Completer<bool>();
      final crypto = _ObservedCrypto(authenticator: () => auth.future);
      await _pump(tester, crypto);
      await _open(tester, true);
      await tester.tap(_continue(true));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      auth.complete(true);
      await tester.pumpAndSettle();
      expect(crypto.keySessions, 1);
      expect(crypto.endedSessions, 1);
      expect(
        find.byKey(const ValueKey('private-key-directory-screen')),
        findsNothing,
      );
      expect(find.text('查看前请注意'), findsOneWidget);
    },
  );

  // Optional screenshots contain only risk notices and the mock wallet above.
  // Native authentication and secret export are never triggered by this test.
  testWidgets('risk notices render visual evidence', (tester) async {
    final output = Platform.environment['KT_UI_QA_OUTPUT'];
    final fontPath = Platform.environment['KT_UI_QA_FONT'];
    if (output == null || fontPath == null) return;
    await tester.runAsync(() async {
      final font = FontLoader('Inter')
        ..addFont(File(fontPath).readAsBytes().then(ByteData.sublistView));
      await font.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    final crypto = _ObservedCrypto();
    await _pump(tester, crypto, boundaryKey: boundary);
    for (final privateKey in [false, true]) {
      await _open(tester, privateKey);
      expect(tester.takeException(), isNull);
      expect(crypto.phraseReads + crypto.keySessions, 0);
      expect(_continue(privateKey).hitTestable(), findsOneWidget);
      // Capture a fresh paint after the preceding modal/route transition.
      (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary)
          .markNeedsPaint();
      await tester.pump();
      await tester.runAsync(() async {
        final raster =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
        final data = await raster.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '$output/${privateKey ? 'private-key' : 'mnemonic'}-risk.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        raster.dispose();
      });
      await tester.tap(
        find.byKey(
          ValueKey(
            privateKey ? 'private-key-warning-cancel' : 'mnemonic-risk-cancel',
          ),
        ),
      );
      await tester.pumpAndSettle();
    }
  });
}
