import 'dart:io';

import 'package:cold_signer/l10n/app_localizations.dart';
import 'package:cold_signer/src/screens/signer_about_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

void main() {
  test('about version matches cold signer pubspec', () {
    final version = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((line) => line.startsWith('version:'))
        .split(':')[1]
        .trim()
        .split('+')[0];
    expect(SignerAboutScreen.version, version);
  });

  for (final lang in ['en', 'zh', 'ja']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('offline about $lang at text scale $scale', (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final l10n = await AppLocalizations.delegate.load(Locale(lang));
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(lang),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const SignerAboutScreen(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(l10n.aboutPoweredBy), findsOneWidget);
        expect(find.text(KtProductAttribution.copyright), findsOneWidget);
        expect(find.text(l10n.aboutOfflineNote), findsOneWidget);
        final copy = find.byKey(const ValueKey('signer-about-copy-source'));
        await tester.ensureVisible(copy);
        await tester.tap(copy);
        await tester.pumpAndSettle();
        expect(copied, SignerAboutScreen.repositoryUrl);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
