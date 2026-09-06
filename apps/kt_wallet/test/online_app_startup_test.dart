import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/main.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/onboarding/product_intro_app.dart';
import 'package:kt_wallet/src/security/biometric_auth.dart';
import 'package:kt_wallet/src/state/locale_controller.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart';

WalletManager _wallets() => WalletManager(
  initial: [
    HotWallet(
      id: 'daily',
      name: '日常钱包',
      avatarColor: 0xFFF59E0B,
      addresses: const ChainAddresses(
        eth: '0x1111111111111111111111111111111111111111',
        polygon: '0x1111111111111111111111111111111111111111',
        tron: 'TS6pWDWcKRYfZFzDMgUp7vzjVhyHfq4c4C',
        solana: 'A1TMhSGzQxMr1TboBKtgixKz1sS6REASMxPo1qsyTSJd',
      ),
      backedUp: true,
    ),
  ],
);

Future<void> _unlock(WidgetTester tester) async {
  final button = find.text('使用生物识别验证');
  if (button.evaluate().isNotEmpty) {
    await tester.tap(button);
    await tester.pumpAndSettle();
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BiometricAuth.instance = const FakeBiometricAuth(BiometricOutcome.success);
  });
  tearDown(() => BiometricAuth.instance = const LocalAuthBiometricAuth());

  for (final language in ['zh', 'en', 'ja']) {
    testWidgets('introduction supports $language and persists independently', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'signer.productIntro.v1': true});
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      Widget intro() => WalletIntroApp(
        localeController: LocaleController(initial: Locale(language)),
        child: const MaterialApp(home: Text('wallet setup')),
      );
      await tester.pumpWidget(intro());
      await tester.pumpAndSettle();
      expect(find.byType(KtProductIntro), findsOneWidget);
      for (var page = 0; page < 3; page++) {
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('intro-next')));
        await tester.pumpAndSettle();
      }
      expect(find.text('wallet setup'), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          walletIntroCompletedKey,
        ),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(intro());
      await tester.pumpAndSettle();
      expect(find.text('wallet setup'), findsOneWidget);
    });
  }

  for (final legacyMode in [null, 'wallet', 'signer', 'corrupt']) {
    testWidgets('online startup ignores legacy mode $legacyMode', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'device.mode': ?legacyMode});
      await tester.pumpWidget(
        RootApp(
          localeController: LocaleController(initial: const Locale('zh')),
          walletBootstrap: () async => WalletController(_wallets()),
        ),
      );
      await tester.pumpAndSettle();
      await _unlock(tester);
      expect(find.text('日常钱包'), findsOneWidget);
      expect(find.text('选择设备模式'), findsNothing);
      expect(find.text('离线签名器'), findsNothing);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('device.mode'), legacyMode);
    });
  }

  testWidgets(
    'fresh install completes introduction before online wallet setup',
    (tester) async {
      await tester.pumpWidget(
        RootApp(
          localeController: LocaleController(initial: const Locale('zh')),
          walletBootstrap: () async => WalletController(WalletManager()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('前后端 100% 开源'), findsOneWidget);
      expect(find.text('添加钱包'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('intro-next')));
      await tester.pumpAndSettle();
      expect(find.text('安全第一。\n掌控始终在你。'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('intro-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始使用在线钱包'));
      await tester.pumpAndSettle();
      expect(
        (await SharedPreferences.getInstance()).getBool(
          'wallet.productIntro.v1',
        ),
        isTrue,
      );
      expect(find.text('添加钱包'), findsOneWidget);
      expect(find.text('创建新钱包'), findsOneWidget);
      expect(find.text('连接离线钱包'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsNothing);
      expect(find.text('选择设备模式'), findsNothing);
    },
  );

  testWidgets('bootstrap failure retries into the online wallet', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      RootApp(
        localeController: LocaleController(initial: const Locale('zh')),
        walletBootstrap: () async {
          if (++calls == 1) throw StateError('unavailable database');
          return WalletController(_wallets());
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('钱包加载失败'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    await _unlock(tester);
    expect(find.text('日常钱包'), findsOneWidget);
    expect(calls, 2);
  });

  for (final language in ['zh', 'en', 'ja']) {
    for (final failure in const <CoreCryptoException>[
      AuthCancelledException(),
      AuthFailedException(),
      AuthUnavailableException(),
      AuthLockedException(30),
    ]) {
      testWidgets(
        'pending deletion ${failure.code} is explicit and user-retried ($language)',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var calls = 0;
          final l10n = lookupAppLocalizations(Locale(language));
          await tester.pumpWidget(
            RootApp(
              localeController: LocaleController(initial: Locale(language)),
              walletBootstrap: () async {
                if (++calls == 1) {
                  throw PendingDeletionAuthenticationException(failure);
                }
                return WalletController(_wallets());
              },
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text(l10n.pendingDeletionAuthTitle), findsOneWidget);
          expect(find.text(l10n.pendingDeletionAuthDesc), findsOneWidget);
          expect(find.text(l10n.walletLoadErrorTitle), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pump(const Duration(minutes: 1));
          expect(calls, 1);
          await tester.tap(find.text(l10n.pendingDeletionAuthAction));
          await tester.pumpAndSettle();
          expect(calls, 2);
          expect(find.text(l10n.pendingDeletionAuthTitle), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('root disposal closes the wallet database', (tester) async {
    final controller = _ClosableController();
    await tester.pumpWidget(RootApp(walletBootstrap: () async => controller));
    await tester.pumpAndSettle();
    expect(controller.closed, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(controller.closed, isTrue);
  });

  testWidgets('screenshot warning follows the online app language', (
    tester,
  ) async {
    ScreenSecurity.resetForTest();
    addTearDown(ScreenSecurity.resetForTest);
    await tester.pumpWidget(
      RootApp(
        localeController: LocaleController(initial: const Locale('en')),
        walletBootstrap: () async => WalletController(WalletManager()),
      ),
    );
    await tester.pumpAndSettle();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'kt/screen_security',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('screenshotTaken'),
          ),
          (_) {},
        );
    await tester.pump();
    expect(
      find.text('A screenshot was taken. Please protect your wallet.'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
  });
}

class _ClosableController extends WalletController {
  _ClosableController() : super(_wallets());
  bool closed = false;
  @override
  Future<void> close() async {
    closed = true;
    await super.close();
  }
}
