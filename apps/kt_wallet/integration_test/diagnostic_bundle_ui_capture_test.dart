import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/screens/about_screen.dart';
import 'package:ui_kit/ui_kit.dart';

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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'support diagnostics disclose included and excluded data before export',
    (tester) async {
      await tester.pumpWidget(_frame());
      await tester.pumpAndSettle();

      final diagnostics = find.byKey(
        const ValueKey('about-export-diagnostics'),
      );
      await tester.ensureVisible(diagnostics);
      await tester.pumpAndSettle();
      await tester.tap(diagnostics);
      await tester.pumpAndSettle();

      expect(find.text('导出诊断包？'), findsOneWidget);
      expect(find.text('包含'), findsOneWidget);
      expect(find.text('永不包含'), findsOneWidget);
      expect(find.textContaining('地址、余额、金额、交易'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // ignore: avoid_print
      print('DIAGNOSTIC_BUNDLE_CAPTURE READY');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 40)),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'anonymous diagnostics require one-time consent and disclose exclusions',
    (tester) async {
      await tester.pumpWidget(_frame());
      await tester.pumpAndSettle();

      final diagnostics = find.byKey(
        const ValueKey('about-upload-diagnostics'),
      );
      await tester.ensureVisible(diagnostics);
      await tester.pumpAndSettle();
      await tester.tap(diagnostics);
      await tester.pumpAndSettle();

      expect(find.text('发送匿名性能报告？'), findsOneWidget);
      expect(find.textContaining('不会在后台自动上传，也不会自动重试'), findsOneWidget);
      expect(find.textContaining('钱包或设备标识、地址、余额'), findsOneWidget);
      expect(find.text('同意并发送'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // ignore: avoid_print
      print('ANONYMOUS_DIAGNOSTICS_CAPTURE READY');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 40)),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
