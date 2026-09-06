import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/screens/settings_screens.dart';
import 'package:kt_wallet/src/state/app_prefs.dart';
import 'package:kt_wallet/src/state/locale_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart';

Widget host(Widget page, AppPrefsController prefs, LocaleController locale) =>
    LocaleScope(
      controller: locale,
      child: AppPrefsScope(
        controller: prefs,
        child: ListenableBuilder(
          listenable: locale,
          builder: (_, _) => MaterialApp(
            theme: ktWalletTheme(),
            locale: locale.locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: page,
          ),
        ),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'failed currency save retains the previous value and explains retry',
    (tester) async {
      final prefs = AppPrefsController(
        preferencesProvider: () async => throw StateError('unavailable'),
      );
      final locale = LocaleController(initial: const Locale('zh'));
      addTearDown(prefs.dispose);
      addTearDown(locale.dispose);
      await tester.pumpWidget(
        host(const GeneralSettingsScreen(), prefs, locale),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('计价货币'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('JPY'));
      await tester.pumpAndSettle();
      expect(prefs.fiat, 'USD');
      expect(find.text('无法保存更改，当前内容未改变，请重试。'), findsOneWidget);
    },
  );

  for (final language in ['zh', 'en', 'ja']) {
    testWidgets(
      '$language general settings support compact large text without a wallet',
      (tester) async {
        tester.view.physicalSize = const Size(320, 844);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final prefs = AppPrefsController();
        final locale = LocaleController(initial: Locale(language));
        addTearDown(prefs.dispose);
        addTearDown(locale.dispose);
        await prefs.load();
        await tester.pumpWidget(
          host(const GeneralSettingsScreen(), prefs, locale),
        );
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(GeneralSettingsScreen)),
        );
        expect(find.text(l10n.settingsGeneral), findsOneWidget);
        expect(find.text(l10n.displayLanguage), findsOneWidget);
        expect(find.text(l10n.fiatUnit), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(l10n.displayLanguage));
        await tester.pumpAndSettle();
        expect(find.text('日本語'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'general preferences update shared controllers and survive reload',
    (tester) async {
      final prefs = AppPrefsController();
      final locale = LocaleController(initial: const Locale('zh'));
      addTearDown(prefs.dispose);
      addTearDown(locale.dispose);
      await prefs.load();
      await tester.pumpWidget(
        host(const GeneralSettingsScreen(), prefs, locale),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('计价货币'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('JPY'));
      await tester.pumpAndSettle();
      expect(prefs.fiat, 'JPY');
      await tester.tap(find.text('显示语言'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('日本語'));
      await tester.pumpAndSettle();
      expect(locale.locale, const Locale('ja'));
      expect(find.text('一般'), findsOneWidget);
      final reloadedPrefs = AppPrefsController();
      final reloadedLocale = LocaleController();
      addTearDown(reloadedPrefs.dispose);
      addTearDown(reloadedLocale.dispose);
      await reloadedPrefs.load();
      await reloadedLocale.load();
      expect(reloadedPrefs.fiat, 'JPY');
      expect(reloadedLocale.locale, const Locale('ja'));
    },
  );

  testWidgets(
    'security only contains app protection, not wallet or display actions',
    (tester) async {
      final prefs = AppPrefsController();
      final locale = LocaleController(initial: const Locale('zh'));
      addTearDown(prefs.dispose);
      addTearDown(locale.dispose);
      await prefs.load();
      await tester.pumpWidget(
        host(const SecuritySettingsScreen(), prefs, locale),
      );
      await tester.pumpAndSettle();
      expect(find.text('隐私模式'), findsOneWidget);
      for (final label in ['计价货币', '显示语言', '加密备份', '删除观察钱包']) {
        expect(find.text(label), findsNothing);
      }
      expect(tester.takeException(), isNull);
    },
  );
}
