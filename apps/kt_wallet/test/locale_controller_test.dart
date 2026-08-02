import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/state/locale_controller.dart';
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
}
