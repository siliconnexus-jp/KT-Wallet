import 'dart:convert';

import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
      // The gateway card is live-scope only: goldens stay byte-identical.
      expect(find.text('网关'), findsNothing);
      expect(find.text('测试连接'), findsNothing);
      // No reset action in the demo edit sheet.
      await tester.tap(find.text('eth-mainnet.g.alchemy.com'));
      await tester.pumpAndSettle();
      expect(find.text('恢复默认'), findsNothing);
    },
  );

  testWidgets(
    'under an AppPrefsScope: shows effective URLs, edit persists, reset '
    'restores the default',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = AppPrefsController();
      await prefs.load();

      await tester.pumpWidget(
        _app(
          AppPrefsScope(
            controller: prefs,
            child: const NetworkSettingsScreen(),
          ),
        ),
      );
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
    },
  );

  testWidgets('saving the built-in default back counts as no override', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'rpc.eth': 'https://old.example'});
    final prefs = AppPrefsController();
    await prefs.load();

    await tester.pumpWidget(
      _app(
        AppPrefsScope(controller: prefs, child: const NetworkSettingsScreen()),
      ),
    );
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

  testWidgets('unsafe RPC override stays in editor and is not persisted', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = AppPrefsController();
    await prefs.load();

    await tester.pumpWidget(
      _app(
        AppPrefsScope(controller: prefs, child: const NetworkSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(defaultEthRpcUrl));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'https://user:secret@rpc.example',
    );
    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(
      find.text('请输入不包含账号凭证的有效 HTTPS 地址。仅 localhost 可使用 HTTP。'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsOneWidget);
    expect(prefs.rpcOverride(Coin.eth), isNull);
    final store = await SharedPreferences.getInstance();
    expect(store.containsKey('rpc.eth'), isFalse);
  });

  testWidgets(
    'gateway card: production default, URL edit, and direct mode persist',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = AppPrefsController();
      await prefs.load();

      await tester.pumpWidget(
        _app(
          AppPrefsScope(
            controller: prefs,
            child: const NetworkSettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The card renders above the chain rows with the production Gateway.
      expect(find.text('网关'), findsOneWidget);
      expect(find.text('统一查询网关，留空则直连各链节点'), findsOneWidget);
      expect(find.text(AppPrefsController.defaultGatewayUrl), findsOneWidget);

      // Enter a URL and save.
      await tester.tap(find.text(AppPrefsController.defaultGatewayUrl));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), ' https://gw.example ');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(prefs.gatewayUrl, 'https://gw.example');
      expect(find.text('https://gw.example'), findsOneWidget);
      expect(find.text('未设置'), findsNothing);

      // Round-trips through SharedPreferences (a fresh controller loads it).
      final reloaded = AppPrefsController();
      await reloaded.load();
      expect(reloaded.gatewayUrl, 'https://gw.example');

      // Saving a blank value clears back to direct mode: the prefs value is
      // null again (so prefsGatewayResolver returns null → direct path) and
      // a blank sentinel preserves that explicit choice across restart.
      await tester.tap(find.text('https://gw.example'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(prefs.gatewayUrl, isNull);
      expect(find.text('未设置'), findsOneWidget);
      final store = await SharedPreferences.getInstance();
      expect(store.getString('gateway.url'), '');
      await reloaded.load();
      expect(reloaded.gatewayUrl, isNull);
    },
  );

  testWidgets('gateway card: reset button restores production Gateway', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'gateway.url': 'https://gw.example',
    });
    final prefs = AppPrefsController();
    await prefs.load();

    await tester.pumpWidget(
      _app(
        AppPrefsScope(controller: prefs, child: const NetworkSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('https://gw.example'), findsOneWidget);

    await tester.tap(find.text('https://gw.example'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复默认').last);
    await tester.pumpAndSettle();

    expect(prefs.gatewayUrl, AppPrefsController.defaultGatewayUrl);
    expect(find.text(AppPrefsController.defaultGatewayUrl), findsOneWidget);
  });

  testWidgets('unsafe Gateway URL stays in editor and is not persisted', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = AppPrefsController();
    await prefs.load();

    await tester.pumpWidget(
      _app(
        AppPrefsScope(controller: prefs, child: const NetworkSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppPrefsController.defaultGatewayUrl));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'http://gateway.example');
    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(
      find.text('请输入不包含账号凭证的有效 HTTPS 地址。仅 localhost 可使用 HTTP。'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsOneWidget);
    expect(prefs.gatewayUrl, AppPrefsController.defaultGatewayUrl);
    final store = await SharedPreferences.getInstance();
    expect(store.containsKey(AppPrefsController.gatewayPrefKey), isFalse);
  });

  testWidgets('test connection: kt_health ok → success snackbar', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'gateway.url': 'https://gw.example',
    });
    final prefs = AppPrefsController();
    await prefs.load();

    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      final body = jsonDecode(request.body) as Map<String, Object?>;
      expect(body['method'], 'kt_health');
      return http.Response(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': body['id'],
          'result': {
            'ok': true,
            'version': '1.0.0',
            'networks': ['eth-mainnet'],
            'upstreams': {'eth-mainnet': <String, Object?>{}},
          },
        }),
        200,
      );
    });

    await tester.pumpWidget(
      _app(
        AppPrefsScope(
          controller: prefs,
          child: NetworkSettingsScreen(gatewayTestClient: client),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();

    expect(requests.single.toString(), 'https://gw.example/rpc');
    expect(find.text('网关连接成功'), findsOneWidget);
    expect(find.text('网关连接失败'), findsNothing);
  });

  testWidgets('test connection: unreachable gateway → failure snackbar', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'gateway.url': 'https://gw.example',
    });
    final prefs = AppPrefsController();
    await prefs.load();

    final client = MockClient(
      (request) async => http.Response('bad gateway', 502),
    );

    await tester.pumpWidget(
      _app(
        AppPrefsScope(
          controller: prefs,
          child: NetworkSettingsScreen(gatewayTestClient: client),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();

    expect(find.text('网关连接失败'), findsOneWidget);
    expect(find.text('网关连接成功'), findsNothing);
  });

  testWidgets('test connection is inert while no gateway URL is set', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = AppPrefsController();
    await prefs.load();
    await prefs.setGatewayUrl(null);

    final client = MockClient(
      (request) async =>
          fail('no gateway configured: nothing may be contacted'),
    );

    await tester.pumpWidget(
      _app(
        AppPrefsScope(
          controller: prefs,
          child: NetworkSettingsScreen(gatewayTestClient: client),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();
    expect(find.text('网关连接成功'), findsNothing);
    expect(find.text('网关连接失败'), findsNothing);
  });
}
