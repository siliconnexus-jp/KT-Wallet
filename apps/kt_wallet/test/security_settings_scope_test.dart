import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/screens/settings_screens.dart';
import 'package:kt_wallet/src/state/app_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The security screen used to own a second [AppPrefsController] over the same
/// SharedPreferences keys. Toggles persisted, so the value survived a restart
/// and the screen looked correct — but the app-wide controller never heard
/// about them, and the home balances stayed masked (or unmasked) until the
/// next cold start. These tests pin the switches to the scoped controller.
Widget _app(Widget home) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

/// The 隐私模式 / App 锁 switches carry no text, so they are found by the
/// tappable box next to their label.
Finder _switchFor(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(Row));

Future<void> _tapSwitchIn(WidgetTester tester, String label) async {
  final row = _switchFor(label).last;
  final box = find.descendant(of: row, matching: find.byType(GestureDetector));
  await tester.tap(box.last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('toggling 隐私模式 writes through the scoped controller', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = AppPrefsController();
    await prefs.load();
    expect(prefs.privacyMode, isFalse);

    await tester.pumpWidget(
      _app(
        AppPrefsScope(controller: prefs, child: const SecuritySettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await _tapSwitchIn(tester, '隐私模式');
    expect(prefs.privacyMode, isTrue, reason: 'on must reach the app scope');

    await _tapSwitchIn(tester, '隐私模式');
    expect(prefs.privacyMode, isFalse, reason: 'off must reach it too');
  });

  testWidgets('an external change to the scope updates the switches', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = AppPrefsController();
    await prefs.load();

    await tester.pumpWidget(
      _app(
        AppPrefsScope(controller: prefs, child: const SecuritySettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await prefs.setAutoLockMinutes(5);
    await tester.pumpAndSettle();
    expect(find.text('5 分钟'), findsOneWidget);
  });

  testWidgets('without a scope the screen still works on its own controller', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_app(const SecuritySettingsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('隐私模式'), findsOneWidget);
    await _tapSwitchIn(tester, '隐私模式');
    // Nothing to assert against but the absence of a crash: the fallback
    // controller keeps the design gallery and the goldens rendering.
    expect(find.text('隐私模式'), findsOneWidget);
  });
}
