import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/security/secure_screen.dart';
import 'package:ui_kit/ui_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('kt/screen_security');

  Future<void> send(String method, [Object? args]) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, args),
          ),
          (_) {},
        );
  }

  Widget app() => MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const SecureContent(child: Text('phrase words here')),
  );

  setUp(ScreenSecurity.resetForTest);
  tearDown(ScreenSecurity.resetForTest);

  testWidgets('sensitive content remains visible during ordinary use', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pump();

    expect(find.text('phrase words here'), findsOneWidget);
    expect(find.text('检测到录屏或投屏'), findsNothing);
  });

  testWidgets('recording or mirroring conceals content until it stops', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pump();

    await send('screenCaptureChanged', true);
    await tester.pumpAndSettle();
    expect(find.text('phrase words here'), findsNothing);
    expect(find.text('检测到录屏或投屏'), findsOneWidget);

    await send('screenCaptureChanged', false);
    await tester.pumpAndSettle();
    expect(find.text('phrase words here'), findsOneWidget);
  });
}
