import 'package:cold_signer/l10n/app_localizations.dart';
import 'package:cold_signer/src/screens/signer_signing_screens.dart';
import 'package:cold_signer/src/signer_router.dart';
import 'package:cold_signer/src/signing/demo_airgap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

Widget _screenFor(
  MapEntry<String, (String, WidgetBuilder)> entry,
  BuildContext context,
) {
  if (entry.key != 'C9 签名结果二维码') return entry.value.$2(context);
  final request = demoSignRequest();
  return SignerResultQrScreen(
    request: request,
    result: demoSignResult(request),
    fragmentChunkSize: demoChunkSize,
  );
}

/// Whole-app automated accessibility and 200% Dynamic Type gate for the
/// standalone KT Cold Signer.
///
/// This catches layout overflow, unlabeled controls, undersized targets and
/// insufficient text contrast in every registered screen. It complements,
/// but does not replace, physical-device VoiceOver and TalkBack testing.
void main() {
  const viewports = [
    ('compact', Size(320, 568)),
    ('phone', Size(390, 844)),
    ('landscape', Size(844, 390)),
  ];
  const evidenceScreens = {
    'C3 助记词展示',
    'C5 离线首页',
    'C2 离线安全检查',
    'C10 地址导出',
    'C20 安全设置',
    'C21 删除钱包',
  };
  for (final locale in const [Locale('en'), Locale('zh'), Locale('ja')]) {
    for (final viewport in viewports) {
      for (final scale in const [1.0, 2.0]) {
        for (final entry in signerRegistry.entries) {
          testWidgets(
            '${entry.key} (${locale.languageCode}, ${viewport.$1}) meets ${scale == 1 ? 'default' : '200% text'} accessibility gate',
            (tester) async {
              tester.view.physicalSize = viewport.$2;
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              final semantics = tester.ensureSemantics();

              try {
                await tester.pumpWidget(
                  MaterialApp(
                    debugShowCheckedModeBanner: false,
                    locale: locale,
                    localizationsDelegates:
                        AppLocalizations.localizationsDelegates,
                    supportedLocales: AppLocalizations.supportedLocales,
                    theme: ThemeData(
                      brightness: Brightness.dark,
                      scaffoldBackgroundColor: SignerColors.bg,
                    ),
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!,
                    ),
                    home: Builder(
                      builder: (context) => _screenFor(entry, context),
                    ),
                  ),
                );
                await tester.pump();

                await expectLater(
                  tester,
                  meetsGuideline(labeledTapTargetGuideline),
                );
                await expectLater(
                  tester,
                  meetsGuideline(androidTapTargetGuideline),
                );
                await expectLater(
                  tester,
                  meetsGuideline(iOSTapTargetGuideline),
                );
                if (scale == 1) {
                  await expectLater(
                    tester,
                    meetsGuideline(textContrastGuideline),
                  );
                }
                if (viewport.$1 == 'phone' &&
                    locale.languageCode == 'en' &&
                    scale == 2 &&
                    evidenceScreens.contains(entry.key)) {
                  final slug = entry.value.$1.replaceAll('/', '');
                  await expectLater(
                    find.byType(MaterialApp),
                    matchesGoldenFile('goldens/large-text/$slug.png'),
                  );
                }
              } finally {
                semantics.dispose();
              }
            },
          );
        }
      }
    }
  }
}
