import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/screens/about_screen.dart';
import 'package:ui_kit/ui_kit.dart';

const _emitScreenshotBase64 = bool.fromEnvironment('KT_EMIT_SCREENSHOT_BASE64');

Widget _frame() => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData(
    fontFamily: 'Inter',
    colorScheme: ColorScheme.fromSeed(seedColor: WalletColors.accent),
    scaffoldBackgroundColor: WalletColors.bg,
  ),
  home: const KtDeviceChrome(mockStatusBar: false, child: AboutScreen()),
);

Future<void> _capture(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
) async {
  final platform = Platform.isIOS ? 'ios' : 'android';
  final fileName = '$platform-$name';
  final bytes = await binding.takeScreenshot(fileName);
  final path = '${Directory.systemTemp.path}/$fileName.png';
  await File(path).writeAsBytes(bytes, flush: true);
  // ignore: avoid_print
  print('TRUST_LEGAL_CAPTURE READY=$name FILE=$path');
  if (_emitScreenshotBase64) {
    // ignore: avoid_print
    print('TRUST_LEGAL_PNG NAME=$fileName DATA=${base64Encode(bytes)}');
  }
  await tester.runAsync(
    () =>
        Future<void>.delayed(Duration(seconds: _emitScreenshotBase64 ? 1 : 30)),
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'privacy, risk, licenses, policy and security reporting stay reachable',
    (tester) async {
      if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
      await tester.pumpWidget(_frame());
      await tester.pumpAndSettle();
      // The iOS host can still be completing its first surface hand-off after
      // Flutter has no pending frames. Capture only after that compositing
      // transition, otherwise the evidence image can contain a uniformly
      // dimmed intermediate frame.
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('信任与法律信息'), findsOneWidget);
      expect(find.text('隐私政策'), findsOneWidget);
      expect(find.text('安全与风险说明'), findsOneWidget);
      expect(find.text('安全政策'), findsOneWidget);
      expect(find.text('开源依赖与许可证'), findsOneWidget);
      expect(find.text('报告安全问题'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('about-report-security')),
        findsOneWidget,
      );
      expect(find.text('KT Wallet 永远不会索要您的助记词或私钥。'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _capture(binding, tester, '23-trust-legal-security');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
