import 'dart:async';

import 'package:cold_signer/l10n/app_localizations.dart';
import 'package:cold_signer/src/screens/signer_signing_screens.dart';
import 'package:cold_signer/src/security/security_check.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// An online dev device: honest engine output is a block-level verdict.
const _online = DeviceState(
  networkReachable: true,
  airplaneMode: false,
  bluetoothOn: true,
  devicePasscodeSet: true,
  biometricEnrolled: true,
  screenCaptured: false,
  rootedOrJailbroken: false,
);

/// A clean air-gapped device: everything passes.
const _offline = DeviceState(
  networkReachable: false,
  airplaneMode: true,
  bluetoothOn: false,
  devicePasscodeSet: true,
  biometricEnrolled: true,
  screenCaptured: false,
  rootedOrJailbroken: false,
);

Widget _app(Widget home) => MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: SignerColors.bg),
      home: home,
    );

void main() {
  testWidgets('C2 runs the engine and renders one localized row per check',
      (tester) async {
    await tester.pumpWidget(
        _app(SignerSecurityCheckScreen(probe: () async => _online)));
    // First frame: probe still in flight.
    expect(find.text('正在检查设备状态…'), findsOneWidget);

    await tester.pump();
    // One row per engine check id, mapped to localized labels.
    expect(SecurityChecks.run(_online), hasLength(7));
    for (final label in ['网络连接', '飞行模式', '蓝牙', '设备密码', '生物识别', '屏幕录制', '系统完整性']) {
      expect(find.text(label), findsOneWidget);
    }
    // The engine's untranslated diagnostic detail surfaces as-is.
    expect(find.text('检测到网络连接'), findsOneWidget);
    // Reachable network → block-level aggregate verdict (honest fail).
    expect(find.text('存在高危项 · 已禁止签名'), findsOneWidget);
    expect(find.text('危险'), findsOneWidget); // network (block)
    expect(find.text('警告'), findsNWidgets(2)); // airplane off + bluetooth on
  });

  testWidgets('re-run button probes again and updates the verdict',
      (tester) async {
    var completer = Completer<DeviceState>();
    await tester.pumpWidget(
        _app(SignerSecurityCheckScreen(probe: () => completer.future)));
    expect(find.text('正在检查设备状态…'), findsOneWidget);

    completer.complete(_online);
    await tester.pump();
    expect(find.text('存在高危项 · 已禁止签名'), findsOneWidget);

    // Re-run against a now-clean device.
    completer = Completer<DeviceState>();
    await tester.tap(find.text('重新检查'));
    await tester.pump();
    expect(find.text('正在检查设备状态…'), findsOneWidget);

    completer.complete(_offline);
    await tester.pump();
    expect(find.text('检查通过 · 可以签名'), findsOneWidget);
    expect(find.text('无网络'), findsOneWidget); // engine detail for pass
    expect(find.text('通过'), findsNWidgets(7)); // all checks pass
  });
}
