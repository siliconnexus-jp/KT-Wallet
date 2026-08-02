import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/main.dart';
import 'package:kt_wallet/src/state/locale_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Proves the Settings language picker re-localizes the whole app live, and that
/// English and Japanese actually render (the other tests pin zh).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('language picker switches zh → English → 日本語 live', (
    tester,
  ) async {
    // Start on a Chinese device.
    tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(KtWalletApp(initialLocation: '/security'));
    await tester.pumpAndSettle();

    // Security screen in Chinese.
    expect(find.text('安全设置'), findsOneWidget);
    expect(find.text('显示语言'), findsOneWidget);

    // Open the picker and choose English.
    await tester.ensureVisible(find.text('显示语言'));
    await tester.tap(find.text('显示语言'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    // The whole screen is now English.
    expect(find.text('Security'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('显示语言'), findsNothing);

    // Switch to Japanese.
    await tester.ensureVisible(find.text('Language'));
    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日本語'));
    await tester.pumpAndSettle();

    expect(find.text('セキュリティ設定'), findsOneWidget);
    expect(find.text('表示言語'), findsOneWidget);

    // Back to "follow system" (zh) resolves to Chinese again.
    await tester.ensureVisible(find.text('表示言語'));
    await tester.tap(find.text('表示言語'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('システムに従う'));
    await tester.pumpAndSettle();
    expect(find.text('安全设置'), findsOneWidget);
  });

  testWidgets('language save failure keeps the picker and current language', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final locale = LocaleController(
      preferencesProvider: () async => throw StateError('storage offline'),
    );

    await tester.pumpWidget(
      KtWalletApp(initialLocation: '/security', localeController: locale),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('显示语言'));
    await tester.tap(find.text('显示语言'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(locale.locale, isNull);
    expect(find.text('显示语言'), findsWidgets);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('无法保存更改，当前内容未改变，请重试。'), findsOneWidget);
  });
}
