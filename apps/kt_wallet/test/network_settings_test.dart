import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/market/balance_service.dart';
import 'package:kt_wallet/src/screens/settings_screens.dart';
import 'package:kt_wallet/src/state/app_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(Widget home) => MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

void main() {
  testWidgets(
      'without an AppPrefsScope the demo hostnames render unchanged (goldens)',
      (tester) async {
    await tester.pumpWidget(_app(const NetworkSettingsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('eth-mainnet.g.alchemy.com'), findsOneWidget);
    expect(find.text('polygon-rpc.com'), findsOneWidget);
    expect(find.text('api.trongrid.io'), findsOneWidget);
    // The live effective URLs must NOT leak into the scope-absent rendering.
    expect(find.text(defaultEthRpcUrl), findsNothing);
    // No reset action in the demo edit sheet.
    await tester.tap(find.text('eth-mainnet.g.alchemy.com'));
    await tester.pumpAndSettle();
    expect(find.text('恢复默认'), findsNothing);
  });

  testWidgets(
      'under an AppPrefsScope: shows effective URLs, edit persists, reset '
      'restores the default', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = AppPrefsController();
    await prefs.load();

    await tester.pumpWidget(_app(
        AppPrefsScope(controller: prefs, child: const NetworkSettingsScreen())));
    await tester.pumpAndSettle();

    // No override yet: the built-in default endpoints are shown.
    expect(find.text(defaultEthRpcUrl), findsOneWidget);
    expect(find.text(defaultTronApiUrl), findsOneWidget);

    // Edit Ethereum's node and save.
    await tester.tap(find.text(defaultEthRpcUrl));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'https://my-eth.example');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(prefs.rpcOverride(Coin.eth), 'https://my-eth.example');
    expect(find.text('https://my-eth.example'), findsOneWidget);
    expect(find.text(defaultEthRpcUrl), findsNothing);

    // The override round-trips through SharedPreferences.
    final reloaded = AppPrefsController();
    await reloaded.load();
    expect(reloaded.rpcOverride(Coin.eth), 'https://my-eth.example');
    expect(reloaded.rpcOverride(Coin.tron), isNull);

    // 恢复默认 clears the override and the row shows the default again.
    await tester.tap(find.text('https://my-eth.example'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复默认'));
    await tester.pumpAndSettle();

    expect(prefs.rpcOverride(Coin.eth), isNull);
    expect(find.text(defaultEthRpcUrl), findsOneWidget);
    await reloaded.load();
    expect(reloaded.rpcOverride(Coin.eth), isNull);
  });

  testWidgets('saving the built-in default back counts as no override',
      (tester) async {
    SharedPreferences.setMockInitialValues({'rpc.eth': 'https://old.example'});
    final prefs = AppPrefsController();
    await prefs.load();

    await tester.pumpWidget(_app(
        AppPrefsScope(controller: prefs, child: const NetworkSettingsScreen())));
    await tester.pumpAndSettle();
    expect(find.text('https://old.example'), findsOneWidget);

    await tester.tap(find.text('https://old.example'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), defaultEthRpcUrl);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(prefs.rpcOverride(Coin.eth), isNull);
    final store = await SharedPreferences.getInstance();
    expect(store.getString('rpc.eth'), isNull);
  });
}
