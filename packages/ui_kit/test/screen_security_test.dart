import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ScreenSecurity.resetForTest();
    AndroidScreenshotProtection.resetForTest();
  });
  tearDown(() {
    ScreenSecurity.resetForTest();
    AndroidScreenshotProtection.resetForTest();
  });

  testWidgets('Android raises FLAG_SECURE for the protected widget lifetime', (
    tester,
  ) async {
    const channel = MethodChannel('kt/secure_screen');
    final applied = <bool>[];
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'setSecure') {
          final secure = call.arguments as bool;
          applied.add(secure);
        }
        return null;
      });

      await tester.pumpWidget(
        const AndroidScreenshotBlocked(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Text('recovery phrase', key: ValueKey('protected-content')),
          ),
        ),
      );
      await tester.idle();
      await tester.pump();

      expect(find.byKey(const ValueKey('protected-content')), findsOneWidget);
      expect(applied, [true]);

      await tester.pumpWidget(const SizedBox());
      await tester.idle();
      await tester.pump();
      expect(applied, [true, false]);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    }
  });

  testWidgets('native screenshot warns without changing page content', (
    tester,
  ) async {
    await tester.pumpWidget(
      ScreenSecurityGuard(
        locale: const Locale('zh'),
        child: const MaterialApp(
          home: Scaffold(
            body: Text(
              'secret phrase',
              key: ValueKey('native-sensitive-text'),
              style: TextStyle(color: Colors.black),
            ),
          ),
        ),
      ),
    );

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'kt/screen_security',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('screenshotTaken'),
          ),
          (_) {},
        );
    await tester.pump();

    final text = tester.widget<Text>(
      find.byKey(const ValueKey('native-sensitive-text')),
    );
    expect(text.style?.color, Colors.black);
    expect(
      find.byKey(const ValueKey('screen-security-warning')),
      findsOneWidget,
    );
    expect(find.text('当前屏幕已被截图，请注意您的钱包安全'), findsOneWidget);
  });

  Future<StreamController<void>> pumpGuard(
    WidgetTester tester, {
    Duration duration = const Duration(seconds: 6),
    Locale? locale,
  }) async {
    final events = StreamController<void>.broadcast();
    await tester.pumpWidget(
      ScreenSecurityGuard(
        screenshotEvents: events.stream,
        warningDuration: duration,
        locale: locale,
        child: const MaterialApp(home: Scaffold(body: Text('wallet'))),
      ),
    );
    return events;
  }

  testWidgets('shows and automatically hides screenshot warning', (
    tester,
  ) async {
    final events = await pumpGuard(tester);
    events.add(null);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('screen-security-warning')),
      findsOneWidget,
    );
    expect(
      find.text('A screenshot was taken. Please protect your wallet.'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 6));
    expect(find.byKey(const ValueKey('screen-security-warning')), findsNothing);
    await events.close();
  });

  testWidgets('close button dismisses warning', (tester) async {
    final events = await pumpGuard(tester);
    events.add(null);
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('screen-security-warning-close')),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('screen-security-warning')), findsNothing);
    await events.close();
  });

  testWidgets('a repeated screenshot resets the timer', (tester) async {
    final events = await pumpGuard(tester);
    events.add(null);
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    events.add(null);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(
      find.byKey(const ValueKey('screen-security-warning')),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 4));
    expect(find.byKey(const ValueKey('screen-security-warning')), findsNothing);
    await events.close();
  });

  testWidgets('queues a background event until resumed', (tester) async {
    final events = await pumpGuard(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    events.add(null);
    await tester.pump();
    expect(find.byKey(const ValueKey('screen-security-warning')), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('screen-security-warning')),
      findsOneWidget,
    );
    await events.close();
  });

  testWidgets('uses Chinese and Japanese warning copy', (tester) async {
    tester.binding.platformDispatcher.localeTestValue = const Locale('zh');
    var events = await pumpGuard(tester);
    events.add(null);
    await tester.pump();
    expect(find.text('当前屏幕已被截图，请注意您的钱包安全'), findsOneWidget);
    await events.close();

    tester.binding.platformDispatcher.localeTestValue = const Locale('ja');
    events = await pumpGuard(tester);
    events.add(null);
    await tester.pump();
    expect(find.text('スクリーンショットが撮影されました。ウォレットの安全にご注意ください'), findsOneWidget);
    await events.close();
    tester.binding.platformDispatcher.clearLocaleTestValue();
  });

  // This guard sits above the app's MaterialApp, so it cannot read
  // Localizations. Reading only the platform locale meant a user who set the
  // in-app language to Chinese on a Japanese phone got a Japanese warning.
  testWidgets('an explicit locale beats the platform one', (tester) async {
    tester.binding.platformDispatcher.localeTestValue = const Locale('ja');
    final events = await pumpGuard(tester, locale: const Locale('zh'));
    events.add(null);
    await tester.pump();
    expect(find.text('当前屏幕已被截图，请注意您的钱包安全'), findsOneWidget);
    expect(find.text('スクリーンショットが撮影されました。ウォレットの安全にご注意ください'), findsNothing);
    await events.close();
    tester.binding.platformDispatcher.clearLocaleTestValue();
  });

  testWidgets('no explicit locale still follows the platform', (tester) async {
    tester.binding.platformDispatcher.localeTestValue = const Locale('ja');
    final events = await pumpGuard(tester);
    events.add(null);
    await tester.pump();
    expect(find.text('スクリーンショットが撮影されました。ウォレットの安全にご注意ください'), findsOneWidget);
    await events.close();
    tester.binding.platformDispatcher.clearLocaleTestValue();
  });
}
