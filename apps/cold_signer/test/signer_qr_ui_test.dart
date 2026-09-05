import 'dart:io';
import 'package:cold_signer/l10n/app_localizations.dart';
import 'package:cold_signer/src/screens/signer_qr_import_screen.dart';
import 'package:cold_signer/src/screens/signer_signing_screens.dart';
import 'package:cold_signer/src/security/security_check.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

// Optional local CJK font for visual review; CI goldens use bundled Inter.
const _cjkFont = String.fromEnvironment('KT_QA_CJK_FONT');

void main() {
  for (final entry in <String, Widget>{
    'home': SignerHomeScreen(
      probe: () async => const DeviceState(
        networkReachable: true,
        airplaneMode: false,
        bluetoothOn: false,
        devicePasscodeSet: true,
        biometricEnrolled: true,
        screenCaptured: false,
        rootedOrJailbroken: false,
      ),
    ),
    'qr-import': const SignerQrImportScreen(),
  }.entries) {
    testWidgets('${entry.key} renders readable phone typography', (
      tester,
    ) async {
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('fonts/Inter.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      if (_cjkFont.isNotEmpty) {
        await tester.runAsync(() async {
          final bytes = await File(_cjkFont).readAsBytes();
          await (FontLoader(
            'CjkPreview',
          )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        });
      }
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var theme = ktSignerTheme();
      if (_cjkFont.isNotEmpty) {
        theme = theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'CjkPreview'),
        );
      }
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          locale: Locale(_cjkFont.isEmpty ? 'en' : 'ja'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: entry.value,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          _cjkFont.isEmpty
              ? 'goldens/typography/${entry.key}.png'
              : '/tmp/kt-signer-${entry.key}-ja.png',
        ),
      );
    });
  }
}
