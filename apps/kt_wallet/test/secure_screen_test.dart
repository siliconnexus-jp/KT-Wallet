import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/security/secure_screen.dart';

/// FLAG_SECURE must be up on every screen that can put a recovery phrase — in
/// whole or in part — in front of the user, in BOTH device modes. It used to
/// be latched by signer mode alone, so the online wallet's backup / verify /
/// import / view-phrase screens told the user "don't screenshot this" while
/// the OS happily allowed it.
void main() {
  late List<bool> calls;

  setUp(() {
    SecureScreen.resetForTest();
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('kt/secure_screen'), (
          call,
        ) async {
          if (call.method == 'setSecure') calls.add(call.arguments as bool);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('kt/secure_screen'),
          null,
        );
    SecureScreen.resetForTest();
  });

  testWidgets('mounting sensitive content raises the flag, unmounting clears '
      'it', (tester) async {
    expect(SecureScreen.isSecure, isFalse);

    await tester.pumpWidget(
      const MaterialApp(home: SecureContent(child: Text('phrase'))),
    );
    await tester.pump();
    expect(SecureScreen.isSecure, isTrue);
    expect(calls, [true]);

    await tester.pumpWidget(const MaterialApp(home: Text('home')));
    await tester.pump();
    expect(SecureScreen.isSecure, isFalse);
    expect(SecureScreen.holders, 0);
    expect(calls, [true, false]);
  });

  testWidgets('nested/overlapping sensitive screens keep the flag up until '
      'the last one goes', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SecureContent(child: SecureContent(child: Text('phrase'))),
      ),
    );
    await tester.pump();
    expect(SecureScreen.holders, 2);
    // One channel call, not two: the flag is already up.
    expect(calls, [true]);

    await tester.pumpWidget(
      const MaterialApp(home: SecureContent(child: Text('phrase'))),
    );
    await tester.pump();
    expect(SecureScreen.holders, 1);
    expect(SecureScreen.isSecure, isTrue, reason: 'one holder is still up');
    expect(calls, [true], reason: 'the flag never dropped, so no new call');

    await tester.pumpWidget(const MaterialApp(home: Text('home')));
    await tester.pump();
    expect(calls, [true, false]);
  });

  test('signer mode latches the flag independently of screen holders', () {
    SecureScreen.modeSecure = true;
    expect(calls, [true]);

    SecureScreen.retain();
    SecureScreen.release();
    expect(calls, [
      true,
    ], reason: 'a screen coming and going must not clear the mode latch');

    SecureScreen.modeSecure = false;
    expect(calls, [true, false]);
  });

  test('a screen holder keeps the flag up after the mode latch drops', () {
    SecureScreen.modeSecure = true;
    SecureScreen.retain();
    SecureScreen.modeSecure = false;
    expect(SecureScreen.isSecure, isTrue);
    expect(calls, [true]);

    SecureScreen.release();
    expect(calls, [true, false]);
  });

  test('an unbalanced release cannot lower the flag under a live holder', () {
    SecureScreen.retain();
    SecureScreen.release();
    SecureScreen.release(); // stray
    expect(SecureScreen.holders, 0);

    SecureScreen.retain();
    expect(SecureScreen.isSecure, isTrue);
    expect(calls, [true, false, true]);
  });

  group('iOS capture fallback (no FLAG_SECURE equivalent)', () {
    const channel = MethodChannel('kt/screen_security');

    setUp(ScreenCapture.resetForTest);
    tearDown(ScreenCapture.resetForTest);

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

    testWidgets('a recording blanks the content and restores it after', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.pump();
      expect(find.text('phrase words here'), findsOneWidget);

      await send('screenCaptureChanged', true);
      await tester.pumpAndSettle();
      expect(find.text('phrase words here'), findsNothing);
      expect(find.text('检测到录屏或投屏'), findsOneWidget);

      await send('screenCaptureChanged', false);
      await tester.pumpAndSettle();
      expect(find.text('phrase words here'), findsOneWidget);
    });

    testWidgets('a screenshot taken on this screen warns the user', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.pump();
      expect(find.textContaining('截图'), findsNothing);

      await send('screenshotTaken');
      await tester.pumpAndSettle();
      // The phrase is already in the photo library; say so.
      expect(find.textContaining('立刻把资产转移到新钱包'), findsOneWidget);
    });

    testWidgets('a screenshot taken BEFORE this screen does not warn', (
      tester,
    ) async {
      // Something else was screenshotted earlier in the session.
      ScreenCapture.install();
      await send('screenshotTaken');

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.textContaining('立刻把资产转移到新钱包'), findsNothing);
      expect(find.text('phrase words here'), findsOneWidget);
    });
  });
}
