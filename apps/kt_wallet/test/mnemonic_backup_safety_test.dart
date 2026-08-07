import 'dart:async';

import 'package:core_crypto/core_crypto.dart';
import 'package:core_crypto/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/main.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:ui_kit/ui_kit.dart';

/// The backup screens and the view-recovery-phrase sheet must never display a
/// phrase that is not the wallet's own.
///
/// Two paths used to substitute the design-gallery constant
/// (`walnut breeze copper …`) for a real seed: the backup banner reaching
/// `/mnemonic-show` with no pending mnemonic, and any `CoreCryptoException`
/// out of `exportMnemonic`. Both ended at a "mark as backed up" affordance, so
/// a user could record a phrase that unlocks nothing and lose the funds.

const _mnemonic =
    'abandon ability able about above absent absorb abstract absurd abuse access accident';

/// The demo words that must never surface on a real path.
const _demoWords = ['walnut', 'breeze', 'copper', 'stadium'];

class _LockedStoreCoreCrypto extends MockCoreCrypto {
  final storeStarted = Completer<void>();
  final releaseStore = Completer<void>();

  @override
  Future<void> storeWallet({
    required String walletId,
    required String mnemonic,
    bool requireAuth = true,
    String? kdfPassword,
  }) async {
    if (!storeStarted.isCompleted) storeStarted.complete();
    await releaseStore.future;
    throw const AuthLockedException(60);
  }
}

Future<WalletController> _controller({
  MockCoreCrypto? crypto,
  bool store = true,
  bool backedUp = false,
}) async {
  final c = crypto ?? MockCoreCrypto();
  final controller = WalletController(WalletManager(), crypto: c);
  if (store) await c.storeWallet(walletId: 'w1', mnemonic: _mnemonic);
  await controller.add(
    HotWallet(
      id: 'w1',
      name: '日常钱包',
      avatarColor: 0xFFF59E0B,
      addresses: const ChainAddresses(
        eth: '0xa71c8B29b3d4b79E19bE1',
        polygon: '0xa71c8B29b3d4b79E19bE1',
        tron: 'TQm9xPa2Wc8hJdU5eRnT6yGb1sVb7L3kFa',
        solana: 'ayKpXwMWd4qmDqVr2W',
      ),
      backedUp: backedUp,
    ),
  );
  return controller;
}

Future<void> _pump(
  WidgetTester tester,
  WalletController controller,
  String location,
) async {
  tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  await tester.pumpWidget(
    KtWalletApp(controller: controller, initialLocation: location),
  );
  await tester.pumpAndSettle();
}

Future<void> _sendScreenshotEvent(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'kt/screen_security',
    const StandardMethodCodec().encodeMethodCall(MethodCall('screenshotTaken')),
    (_) {},
  );
  await tester.pump();
}

void expectNoDemoWords() {
  for (final word in _demoWords) {
    expect(find.text(word), findsNothing, reason: 'demo phrase leaked: $word');
  }
}

void main() {
  testWidgets(
    'home backup banner opens the current wallet export, not new-wallet creation',
    (tester) async {
      final controller = await _controller();
      await _pump(tester, controller, '/home');

      await tester.tap(find.text('助记词尚未备份'));
      await tester.pumpAndSettle();

      expect(find.text('钱包详情'), findsOneWidget);
      expect(find.text('查看助记词'), findsOneWidget);
      expect(controller.pendingMnemonic, isNull);
    },
  );

  group('/mnemonic-show', () {
    testWidgets(
      'existing wallet, no pending mnemonic: route is rejected, no demo words',
      (tester) async {
        // A stale/deep link for an existing wallet has no creation session.
        // The router rejects it before the sensitive screen is mounted.
        final controller = await _controller();
        await _pump(tester, controller, '/mnemonic-show');

        expectNoDemoWords();
        expect(find.text('添加钱包'), findsOneWidget);
        expect(find.text('备份助记词'), findsNothing);
        // No way onward to the verify step (and therefore to markBackedUp).
        expect(find.text('我已抄写，去校验'), findsNothing);
      },
    );

    testWidgets('create-onboarding shows the freshly generated phrase', (
      tester,
    ) async {
      final controller = await _controller();
      await controller.beginCreate();
      final words = controller.pendingMnemonic!.split(' ');
      await _pump(tester, controller, '/mnemonic-show');

      expect(find.text('无法显示助记词'), findsNothing);
      // The mock wordlist is small, so a generated phrase may repeat a word.
      expect(find.text(words.first), findsAtLeastNWidgets(1));
      expect(find.text(words.last), findsAtLeastNWidgets(1));
      expectNoDemoWords();
    });

    testWidgets('screenshot event does not hide recovery words', (
      tester,
    ) async {
      final controller = await _controller();
      await controller.beginCreate();
      await _pump(tester, controller, '/mnemonic-show');
      final wordFinder = find.byKey(const Key('mnemonic-word-0'));

      expect(tester.widget<Text>(wordFinder).style?.color, WalletColors.text);
      await _sendScreenshotEvent(tester);
      expect(tester.widget<Text>(wordFinder).style?.color, WalletColors.text);
    });
  });

  group('/mnemonic-verify', () {
    testWidgets(
      'with no pending mnemonic: route rejected, markBackedUp unreachable',
      (tester) async {
        final controller = await _controller();
        await _pump(tester, controller, '/mnemonic-verify');

        expectNoDemoWords();
        expect(find.text('添加钱包'), findsOneWidget);
        expect(find.text('校验备份'), findsNothing);
        expect(find.text('确认'), findsNothing); // no confirm button at all
        expect((controller.wallets.single as HotWallet).backedUp, isFalse);
      },
    );

    testWidgets('create-onboarding: the quiz still gates on the right word', (
      tester,
    ) async {
      // The quiz coverage that used to live on the (now refused) existing-
      // wallet path, moved to the only flow that legitimately reaches it.
      final controller = await _controller();
      await controller.beginCreate();
      final words = controller.pendingMnemonic!.split(' ');
      final correct = words[3]; // the quiz challenges word #4
      final wrong = words.firstWhere((w) => w != correct);
      final before = controller.count;
      await _pump(tester, controller, '/mnemonic-verify');

      expect(find.text('第 4 个单词是？'), findsOneWidget);
      await tester.tap(find.text(wrong).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(find.text('第 4 个单词是？'), findsOneWidget); // still on the quiz
      expect(controller.count, before); // nothing committed

      // Let the feedback SnackBar clear so it no longer overlays the button.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      await tester.tap(find.text(correct).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      // The durable commit clears pendingMnemonic before the router reaches
      // home. No intermediate frame may reinterpret that successful cleanup
      // as a missing phrase and flash the refusal panel.
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          find.text('无法显示助记词'),
          findsNothing,
          reason: 'successful wallet creation flashed a false error page',
        );
      }
      await tester.pumpAndSettle();
      expect(controller.count, before + 1); // the new wallet is committed
      expect(controller.pendingMnemonic, isNull);
    });

    testWidgets(
      'native lockout shows an in-button spinner and a retryable error',
      (tester) async {
        final crypto = _LockedStoreCoreCrypto();
        final controller = await _controller(crypto: crypto, store: false);
        await controller.beginCreate();
        final correct = controller.pendingMnemonic!.split(' ')[3];
        await _pump(tester, controller, '/mnemonic-verify');

        await tester.tap(find.text(correct).last);
        await tester.pump();
        await tester.tap(find.text('确认'));
        await tester.pump();

        expect(crypto.storeStarted.isCompleted, isTrue);
        expect(
          find.byKey(const ValueKey('kt-primary-button-loading')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<AnimatedOpacity>(
                find.byKey(const ValueKey('kt-primary-button-loading-layer')),
              )
              .opacity,
          1,
        );

        crypto.releaseStore.complete();
        await tester.pumpAndSettle();

        expect(find.text('安全验证暂时锁定，请在 60 秒后重试。'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('mnemonic-verify-submit-error')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<AnimatedOpacity>(
                find.byKey(const ValueKey('kt-primary-button-loading-layer')),
              )
              .opacity,
          0,
        );
        expect(find.text('确认'), findsOneWidget);
        expect(controller.pendingMnemonic, isNotNull);
      },
    );
  });

  group('view-recovery-phrase sheet', () {
    testWidgets('auth failure: error state, no demo words, no confirm', (
      tester,
    ) async {
      // Every export attempt fails authentication (cancel / wrong biometric).
      final crypto = MockCoreCrypto(authenticator: () async => false);
      final controller = await _controller(crypto: crypto);
      await _pump(tester, controller, '/wallet-detail?id=w1');

      await tester.tap(find.text('立即备份'));
      await tester.pumpAndSettle();

      expect(find.text('无法显示助记词'), findsOneWidget);
      expect(find.textContaining('需要通过身份验证'), findsOneWidget);
      expectNoDemoWords();
      expect(find.text('abandon'), findsNothing);
      // The one thing that must never be reachable here.
      expect(find.text('我已抄写'), findsNothing);
      expect((controller.wallets.single as HotWallet).backedUp, isFalse);
    });

    testWidgets(
      'retry after a recovered authentication shows the real phrase',
      (tester) async {
        var attempts = 0;
        final crypto = MockCoreCrypto(
          authenticator: () async => attempts++ > 0,
        );
        final controller = await _controller(crypto: crypto);
        await _pump(tester, controller, '/wallet-detail?id=w1');

        await tester.tap(find.text('立即备份'));
        await tester.pumpAndSettle();
        expect(find.text('无法显示助记词'), findsOneWidget);

        await tester.tap(find.text('重试'));
        await tester.pumpAndSettle();

        expect(find.text('无法显示助记词'), findsNothing);
        expect(find.text('abandon'), findsOneWidget); // the wallet's own phrase
        expect(find.text('accident'), findsOneWidget);
        expect(find.text('我已抄写'), findsOneWidget);
      },
    );

    testWidgets('no stored key material: honest error, no retry, no confirm', (
      tester,
    ) async {
      // Demo-seeded / imported-elsewhere wallet: nothing to export. This used
      // to fall back to the demo phrase "so the flow stays exercisable".
      final controller = await _controller(store: false);
      await _pump(tester, controller, '/wallet-detail?id=w1');

      await tester.tap(find.text('立即备份'));
      await tester.pumpAndSettle();

      expect(find.text('无法显示助记词'), findsOneWidget);
      expect(find.textContaining('本机未保存'), findsOneWidget);
      expectNoDemoWords();
      expect(find.text('重试'), findsNothing); // retrying cannot help
      expect(find.text('我已抄写'), findsNothing);
      expect((controller.wallets.single as HotWallet).backedUp, isFalse);
    });
  });
}
