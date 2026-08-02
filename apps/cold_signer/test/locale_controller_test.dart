import 'package:cold_signer/main.dart';
import 'package:cold_signer/src/state/locale_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('manual language round-trips and follow-system removes it', () async {
    final locale = LocaleController();
    await locale.setLocale(const Locale('ja'));

    final reloaded = LocaleController();
    await reloaded.load();
    expect(reloaded.locale?.languageCode, 'ja');

    await reloaded.setLocale(null);
    final system = LocaleController();
    await system.load();
    expect(system.locale, isNull);
  });

  test(
    'unsupported stored language is removed and fails closed to system',
    () async {
      SharedPreferences.setMockInitialValues({'app_locale': 'fr'});
      final locale = LocaleController(initial: const Locale('en'));
      await locale.load();

      expect(locale.locale, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('app_locale'), isFalse);
    },
  );

  test('unsupported language cannot enter memory or persistence', () async {
    final locale = LocaleController();
    await expectLater(
      locale.setLocale(const Locale('fr')),
      throwsArgumentError,
    );
    expect(locale.locale, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('app_locale'), isFalse);
  });

  test(
    'write failure keeps the visible language and queue can recover',
    () async {
      var offline = true;
      final locale = LocaleController(
        initial: const Locale('zh'),
        preferencesProvider: () async {
          if (offline) throw StateError('storage offline');
          return SharedPreferences.getInstance();
        },
      );
      var notified = 0;
      locale.addListener(() => notified++);

      await expectLater(locale.setLocale(const Locale('en')), throwsStateError);
      expect(locale.locale?.languageCode, 'zh');
      expect(notified, 0);

      offline = false;
      await locale.setLocale(const Locale('ja'));
      expect(locale.locale?.languageCode, 'ja');
      expect(notified, 1);
    },
  );

  test('rapid language intents are serialized and newest persists', () async {
    final locale = LocaleController();
    await Future.wait([
      locale.setLocale(const Locale('zh')),
      locale.setLocale(const Locale('en')),
      locale.setLocale(const Locale('ja')),
    ]);
    expect(locale.locale?.languageCode, 'ja');

    final reloaded = LocaleController();
    await reloaded.load();
    expect(reloaded.locale?.languageCode, 'ja');
  });

  testWidgets('language save failure keeps the picker and current language', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
    tester.platformDispatcher.localeTestValue = const Locale('zh');
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    final locale = LocaleController(
      preferencesProvider: () async => throw StateError('storage offline'),
    );

    await tester.pumpWidget(ColdSignerApp(localeController: locale));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('C20 安全设置'), 200);
    await tester.tap(find.text('C20 安全设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示语言'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(locale.locale, isNull);
    expect(find.text('显示语言'), findsWidgets);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('无法保存设置，当前内容未改变，请重试。'), findsOneWidget);
  });
}
