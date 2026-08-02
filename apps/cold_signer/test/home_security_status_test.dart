import 'package:cold_signer/l10n/app_localizations.dart';
import 'package:cold_signer/src/screens/signer_signing_screens.dart';
import 'package:cold_signer/src/security/security_check.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _offline = DeviceState(
  networkReachable: false,
  airplaneMode: true,
  bluetoothOn: false,
  devicePasscodeSet: true,
  biometricEnrolled: true,
  screenCaptured: false,
  rootedOrJailbroken: false,
);

const _online = DeviceState(
  networkReachable: true,
  airplaneMode: false,
  bluetoothOn: false,
  devicePasscodeSet: true,
  biometricEnrolled: true,
  screenCaptured: false,
  rootedOrJailbroken: false,
);

Widget _app(Future<DeviceState> Function() probe) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: SignerHomeScreen(probe: probe),
);

void main() {
  testWidgets('home never paints an unmeasured device as a green pass', (
    tester,
  ) async {
    await tester.pumpWidget(_app(() async => const DeviceState.unknown()));
    await tester.pump();

    expect(find.text('无法确认网络状态'), findsOneWidget);
    expect(find.text('存在风险 · 请谨慎操作'), findsOneWidget);
    expect(find.text('安全检查通过 · 飞行模式已开启'), findsNothing);
    expect(find.textContaining('42'), findsNothing);
  });

  testWidgets('home displays a measured offline pass', (tester) async {
    await tester.pumpWidget(_app(() async => _offline));
    await tester.pump();

    expect(find.text('网络已断开'), findsOneWidget);
    expect(find.text('检查通过 · 可以签名'), findsOneWidget);
  });

  testWidgets('home displays online state as a blocking danger', (
    tester,
  ) async {
    await tester.pumpWidget(_app(() async => _online));
    await tester.pump();

    expect(find.text('检测到网络连接'), findsOneWidget);
    expect(find.text('存在高危项 · 已禁止签名'), findsOneWidget);
  });

  testWidgets('probe failure remains unknown instead of falling back to pass', (
    tester,
  ) async {
    await tester.pumpWidget(_app(() async => throw StateError('probe failed')));
    await tester.pump();

    expect(find.text('无法确认网络状态'), findsOneWidget);
    expect(find.text('存在风险 · 请谨慎操作'), findsOneWidget);
  });
}
