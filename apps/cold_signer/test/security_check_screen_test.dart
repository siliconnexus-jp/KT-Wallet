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

Widget _app(Widget home, {Locale locale = const Locale('zh')}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: SignerColors.bg,
  ),
  home: home,
);

void main() {
  testWidgets('C2 runs the engine and renders one localized row per check', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(SignerSecurityCheckScreen(probe: () async => _online)),
    );
    // First frame: probe still in flight.
    expect(find.text('正在检查设备状态…'), findsOneWidget);

    await tester.pump();
    // One row per engine check id, mapped to localized labels.
    expect(SecurityChecks.run(_online), hasLength(7));
    for (final label in [
      '网络连接',
      '飞行模式',
      '蓝牙',
      '设备密码',
      '生物识别',
      '屏幕录制',
      '系统完整性',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    // Diagnostic details are localized by the presentation layer.
    expect(find.text('检测到网络连接'), findsOneWidget);
    // Reachable network → block-level aggregate verdict (honest fail).
    expect(find.text('存在高危项 · 已禁止签名'), findsOneWidget);
    expect(find.text('危险'), findsOneWidget); // network (block)
    expect(find.text('警告'), findsNWidgets(2)); // airplane off + bluetooth on
  });

  testWidgets('re-run button probes again and updates the verdict', (
    tester,
  ) async {
    var completer = Completer<DeviceState>();
    await tester.pumpWidget(
      _app(SignerSecurityCheckScreen(probe: () => completer.future)),
    );
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
    expect(find.text('未检测到网络连接'), findsOneWidget);
    expect(find.text('通过'), findsNWidgets(7)); // all checks pass
  });

  testWidgets('security details do not leak Chinese into English UI', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        SignerSecurityCheckScreen(probe: () async => _online),
        locale: const Locale('en'),
      ),
    );
    await tester.pump();

    expect(find.text('Network connection detected'), findsOneWidget);
    expect(find.text('Airplane mode is off'), findsOneWidget);
    expect(find.text('Bluetooth is on'), findsOneWidget);
    expect(find.text('检测到网络连接'), findsNothing);
    expect(find.text('飞行模式未开启'), findsNothing);
    expect(find.text('蓝牙已开启'), findsNothing);
  });

  testWidgets('security details use Japanese in Japanese UI', (tester) async {
    await tester.pumpWidget(
      _app(
        SignerSecurityCheckScreen(probe: () async => _online),
        locale: const Locale('ja'),
      ),
    );
    await tester.pump();

    expect(find.text('ネットワーク接続を検出しました'), findsOneWidget);
    expect(find.text('機内モードはオフです'), findsOneWidget);
    expect(find.text('Bluetoothはオンです'), findsOneWidget);
    expect(find.text('飞行模式未开启'), findsNothing);
    expect(find.text('蓝牙已开启'), findsNothing);
  });

  testWidgets('unknown probe state is localized and never shown as pass', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        SignerSecurityCheckScreen(
          probe: () async => const DeviceState.unknown(),
        ),
        locale: const Locale('en'),
      ),
    );
    await tester.pump();

    expect(find.text('Status unavailable'), findsNWidgets(7));
    expect(find.text('Warning'), findsNWidgets(7));
    expect(find.text('Pass'), findsNothing);
  });
}
