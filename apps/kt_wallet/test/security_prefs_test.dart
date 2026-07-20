import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Proves the security-settings pickers (fiat currency, auto-lock) update the
/// rows and that the choices persist across screen instances.
Future<void> _openSecurity(WidgetTester tester) async {
  tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  await tester.pumpWidget(KtWalletApp(initialLocation: '/security'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('fiat picker updates the row', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _openSecurity(tester);

    expect(find.text('USD'), findsOneWidget);
    await tester.tap(find.text('USD'));
    await tester.pumpAndSettle();
    // Sheet lists all options; pick CNY.
    expect(find.text('JPY'), findsOneWidget);
    await tester.tap(find.text('CNY'));
    await tester.pumpAndSettle();

    expect(find.text('CNY'), findsOneWidget); // row updated
    expect(find.text('USD'), findsNothing);
  });

  testWidgets('auto-lock picker updates the row', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _openSecurity(tester);

    expect(find.text('1 分钟'), findsOneWidget);
    await tester.tap(find.text('1 分钟'));
    await tester.pumpAndSettle();
    expect(find.text('5 分钟'), findsOneWidget);
    await tester.tap(find.text('立即'));
    await tester.pumpAndSettle();

    expect(find.text('立即'), findsOneWidget); // row updated
    expect(find.text('1 分钟'), findsNothing);
  });

  testWidgets('choices persist into a fresh screen instance', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _openSecurity(tester);

    await tester.tap(find.text('USD'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('JPY'));
    await tester.pumpAndSettle();
    expect(find.text('JPY'), findsOneWidget);

    // A brand-new app + screen instance loads the persisted choice.
    await tester.pumpWidget(KtWalletApp(initialLocation: '/security'));
    await tester.pumpAndSettle();
    expect(find.text('JPY'), findsOneWidget);
    expect(find.text('USD'), findsNothing);
  });
}
