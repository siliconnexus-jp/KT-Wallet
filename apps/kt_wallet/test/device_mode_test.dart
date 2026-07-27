import 'dart:async';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/main.dart';
import 'package:kt_wallet/src/security/biometric_auth.dart';
import 'package:kt_wallet/src/state/device_mode.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';

/// Proves the combined single-installer gate: first launch shows the
/// device-mode picker, each choice boots the full corresponding experience,
/// a persisted choice skips the picker, and the settings "device mode" row
/// returns to the picker.
ChainAddresses _addr(String seed) => ChainAddresses(
      eth: '0x${seed}71c8B29b3d4b79E19bE1',
      polygon: '0x${seed}71c8B29b3d4b79E19bE1',
      tron: 'T${seed}Pa2Wc8hJdU5eRnT6yGb1sVb7L3kFa',
      solana: '${seed}yKpXwMWd4qmDqVr2W',
    );

WalletController _testWalletController() => WalletController(WalletManager(initial: [
      HotWallet(id: 'daily', name: '日常钱包', avatarColor: 0xFFF59E0B, addresses: _addr('a'), backedUp: true),
    ]));

/// Wallet mode boots behind [AppLockGate], which — with the shipped default of
/// app-lock ON — will not let anything through unless it can actually verify
/// the user. These tests are about device mode, not the lock, so they script a
/// passing biometric prompt and step through it. Call after every pump that
/// may have entered wallet mode; a no-op in picker / signer mode.
void _useScriptedBiometrics() {
  BiometricAuth.instance = const FakeBiometricAuth(BiometricOutcome.success);
  addTearDown(() => BiometricAuth.instance = const LocalAuthBiometricAuth());
}

Future<void> _passAppLock(WidgetTester tester) async {
  final unlock = find.text('使用生物识别验证');
  if (unlock.evaluate().isEmpty) return;
  await tester.tap(unlock);
  await tester.pumpAndSettle();
}

Future<DeviceModeController> _pumpRoot(WidgetTester tester, {DeviceMode? initialMode}) async {
  // Run under zh, like the rest of the suite.
  tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  _useScriptedBiometrics();

  final modeController = DeviceModeController(initial: initialMode);
  await tester.pumpWidget(RootApp(
    modeController: modeController,
    walletBootstrap: () async => _testWalletController(),
  ));
  await tester.pumpAndSettle();
  await _passAppLock(tester);
  return modeController;
}

void main() {
  testWidgets('fresh start (no mode) shows the device-mode picker', (tester) async {
    await _pumpRoot(tester);

    expect(find.text('选择设备模式'), findsOneWidget);
    expect(find.text('联网钱包'), findsOneWidget);
    expect(find.text('离线签名器'), findsOneWidget);
  });

  testWidgets('tapping 联网钱包 boots the wallet home', (tester) async {
    final mode = await _pumpRoot(tester);

    await tester.tap(find.text('联网钱包'));
    await tester.pumpAndSettle();
    await _passAppLock(tester);

    expect(mode.mode, DeviceMode.wallet);
    expect(find.text('选择设备模式'), findsNothing);
    expect(find.text('日常钱包'), findsOneWidget); // wallet home header
  });

  testWidgets('tapping 离线签名器 requires confirmation, then boots the signer', (tester) async {
    final mode = await _pumpRoot(tester);

    await tester.tap(find.text('离线签名器'));
    await tester.pumpAndSettle();

    // Air-gap warning dialog.
    expect(find.text('启用离线签名器'), findsOneWidget);
    expect(find.text('此模式供离线设备使用，请开启飞行模式并保持设备永不联网。'), findsOneWidget);

    // Cancel keeps the picker.
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(mode.mode, isNull);
    expect(find.text('选择设备模式'), findsOneWidget);

    // Confirm enters signer mode (the Cold Signer experience appears).
    await tester.tap(find.text('离线签名器'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(mode.mode, DeviceMode.signer);
    expect(find.text('选择设备模式'), findsNothing);
    expect(find.text('创建新钱包'), findsOneWidget);
  });

  testWidgets('an injected signer mode skips the picker entirely', (tester) async {
    await _pumpRoot(tester, initialMode: DeviceMode.signer);

    expect(find.text('选择设备模式'), findsNothing);
    expect(find.text('创建新钱包'), findsOneWidget);
  });

  testWidgets('settings 设备模式 row exits wallet mode back to the picker', (tester) async {
    final mode = await _pumpRoot(tester, initialMode: DeviceMode.wallet);
    expect(find.text('日常钱包'), findsOneWidget);

    // Home shell → settings tab → security settings screen.
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('安全设置'));
    await tester.pumpAndSettle();

    // The device-mode row is rendered (DeviceModeScope present) and shows the
    // current mode.
    await tester.ensureVisible(find.text('设备模式'));
    expect(find.text('联网钱包'), findsOneWidget);
    await tester.tap(find.text('设备模式'));
    await tester.pumpAndSettle();

    // Cancel stays in wallet mode.
    expect(find.text('切换设备模式'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(mode.mode, DeviceMode.wallet);

    // Confirm returns to the picker.
    await tester.tap(find.text('设备模式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(mode.mode, isNull);
    expect(find.text('选择设备模式'), findsOneWidget);
  });

  testWidgets('a failed wallet bootstrap shows a retryable error, not a hang', (tester) async {
    tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    _useScriptedBiometrics();

    var calls = 0;
    await tester.pumpWidget(RootApp(
      modeController: DeviceModeController(initial: DeviceMode.wallet),
      walletBootstrap: () async {
        calls++;
        if (calls == 1) throw StateError('corrupt database');
        return _testWalletController();
      },
    ));
    await tester.pumpAndSettle();

    // First attempt fails → error screen with a retry button.
    expect(find.text('钱包加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    // Retry succeeds → wallet home.
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    await _passAppLock(tester);
    expect(find.text('钱包加载失败'), findsNothing);
    expect(find.text('日常钱包'), findsOneWidget);
  });

  testWidgets('signer welcome offers an escape hatch back to the picker', (tester) async {
    final mode = await _pumpRoot(tester, initialMode: DeviceMode.signer);

    // The scope-gated link is on the welcome screen (before any onboarding).
    await tester.tap(find.text('切换设备模式'));
    await tester.pumpAndSettle();

    expect(mode.mode, isNull);
    expect(find.text('选择设备模式'), findsOneWidget);
  });

  testWidgets('leaving wallet mode closes the wallet controller (database)', (tester) async {
    tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    _useScriptedBiometrics();

    final controller = _ClosableController();
    final mode = DeviceModeController(initial: DeviceMode.wallet);
    await tester.pumpWidget(RootApp(
      modeController: mode,
      walletBootstrap: () async => controller,
    ));
    await tester.pumpAndSettle();
    await _passAppLock(tester);
    expect(find.text('日常钱包'), findsOneWidget);
    expect(controller.closed, isFalse);

    // Exiting the mode tears down the wallet subtree and must release the DB.
    unawaited(mode.clear());
    await tester.pumpAndSettle();
    expect(find.text('选择设备模式'), findsOneWidget);
    expect(controller.closed, isTrue);
  });
}

class _ClosableController extends WalletController {
  _ClosableController() : super(WalletManager(initial: [
          HotWallet(id: 'daily', name: '日常钱包', avatarColor: 0xFFF59E0B, addresses: _addr('a'), backedUp: true),
        ]));

  bool closed = false;

  @override
  Future<void> close() async {
    closed = true;
    await super.close();
  }
}
