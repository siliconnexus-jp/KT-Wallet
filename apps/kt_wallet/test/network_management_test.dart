import 'dart:convert';

import 'package:chains/chains.dart' show Chain;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/screens/settings_screens.dart';
import 'package:kt_wallet/src/state/networks.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Network management UX in the settings screen: environment switch,
/// per-chain picker, probed add-network form, custom-network deletion — all
/// NetworkScope-only (the scope-absent rendering stays the pre-feature one).
Widget _app(
  NetworkController net, {
  http.Client? probeClient,
  Locale locale = const Locale('zh'),
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: NetworkScope(
    controller: net,
    child: NetworkSettingsScreen(probeClient: probeClient),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('scope-absent: no environment or per-chain cards render', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const NetworkSettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Today's screen exactly: demo hostnames, none of the new affordances.
    expect(find.text('eth-mainnet.g.alchemy.com'), findsOneWidget);
    expect(find.text('网络环境'), findsNothing);
    expect(find.text('逐链网络'), findsNothing);
    expect(find.byKey(const ValueKey('add-network')), findsNothing);
  });

  testWidgets('environment segmented switches the environment and persists', (
    tester,
  ) async {
    final net = NetworkController();
    await net.load();
    await tester.pumpWidget(_app(net));
    await tester.pumpAndSettle();

    expect(find.text('网络环境'), findsOneWidget);
    expect(find.text('逐链网络'), findsOneWidget);
    // Mainnet default: active names are the mainnet ones (family label and
    // network name coincide, hence the duplicated texts per row).
    expect(find.text('Sepolia'), findsNothing);

    await tester.tap(find.text('测试网'));
    await tester.pumpAndSettle();

    expect(net.environment, NetworkEnvironment.testnet);
    expect(find.text('Sepolia'), findsOneWidget);
    expect(find.text('Amoy'), findsOneWidget);
    expect(find.text('Nile'), findsOneWidget);
    expect(find.text('Devnet'), findsOneWidget);

    // Persisted: a fresh controller loads testnet back.
    final reloaded = NetworkController();
    await reloaded.load();
    expect(reloaded.environment, NetworkEnvironment.testnet);

    // And back to mainnet.
    await tester.tap(find.text('主网'));
    await tester.pumpAndSettle();
    expect(net.environment, NetworkEnvironment.mainnet);
    expect(find.text('Sepolia'), findsNothing);
  });

  testWidgets('network storage failure keeps active chain and shows feedback', (
    tester,
  ) async {
    final net = NetworkController(
      preferencesProvider: () async => throw StateError('storage offline'),
    );
    await tester.pumpWidget(_app(net));
    await tester.pumpAndSettle();

    await tester.tap(find.text('测试网'));
    await tester.pumpAndSettle();

    expect(net.environment, NetworkEnvironment.mainnet);
    expect(find.text('Sepolia'), findsNothing);
    expect(find.text('无法保存更改，当前内容未改变，请重试。'), findsOneWidget);
  });

  testWidgets(
    'per-chain picker lists built-ins and sets an override; re-picking the '
    'profile default clears it',
    (tester) async {
      final net = NetworkController();
      await net.load();
      await tester.pumpWidget(_app(net));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('net-row-ethereum')));
      await tester.pumpAndSettle();

      // Both built-ins listed, the active (mainnet) one checked.
      expect(find.byKey(const ValueKey('net-opt-eth-mainnet')), findsOneWidget);
      expect(find.byKey(const ValueKey('net-opt-eth-sepolia')), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('net-opt-eth-sepolia')));
      await tester.pumpAndSettle();

      expect(net.activeFor(Chain.ethereum).id, 'eth-sepolia');
      // The row now shows the testnet name; the environment stays mainnet.
      expect(net.environment, NetworkEnvironment.mainnet);
      expect(find.text('Sepolia'), findsOneWidget);

      // Picking what the mainnet profile already dictates clears the override
      // (observable via the persisted overrides map going empty).
      await tester.tap(find.byKey(const ValueKey('net-row-ethereum')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('net-opt-eth-mainnet')));
      await tester.pumpAndSettle();

      expect(net.activeFor(Chain.ethereum).id, 'eth-mainnet');
      final store = await SharedPreferences.getInstance();
      final snapshot =
          jsonDecode(store.getString(NetworkController.snapshotKey)!)
              as Map<String, dynamic>;
      expect(snapshot['overrides'], isEmpty);
    },
  );

  testWidgets('add network: probe success adds the custom network (eth_chainId '
      'request asserted)', (tester) async {
    final net = NetworkController();
    await net.load();
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      final body = jsonDecode(request.body) as Map<String, Object?>;
      expect(body['method'], 'eth_chainId');
      return http.Response(
        jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': '0x7a69'}),
        200,
      );
    });
    await tester.pumpWidget(_app(net, probeClient: client));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add-network')));
    await tester.pumpAndSettle();
    expect(find.text('添加网络'), findsOneWidget);

    // Family default is Ethereum → the Chain ID field is present.
    expect(find.text('Chain ID'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'Local Anvil'); // 网络名称
    await tester.enterText(
      find.byType(TextField).at(1),
      'http://127.0.0.1:8545',
    ); // RPC
    await tester.enterText(find.byType(TextField).at(2), 'eth'); // 符号
    await tester.enterText(find.byType(TextField).at(3), '31337'); // Chain ID
    await tester.pump();
    await tester.ensureVisible(find.text('保存'));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(requests, hasLength(1));
    expect(requests.single.url.toString(), 'http://127.0.0.1:8545');
    expect(find.text('探测通过，已保存'), findsOneWidget);
    final added = net.customNetworks.single;
    expect(added.chain, Chain.ethereum);
    expect(added.name, 'Local Anvil');
    expect(added.evmChainId, 31337);
    expect(added.symbol, 'ETH');
    expect(added.isTestnet, isTrue);

    // The new network shows up in the family picker.
    await tester.tap(find.byKey(const ValueKey('net-row-ethereum')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('net-opt-${added.id}')), findsOneWidget);
  });

  testWidgets('all EVM families require Chain ID and can save a custom RPC', (
    tester,
  ) async {
    final net = NetworkController();
    await net.load();
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      expect(body['method'], 'eth_chainId');
      return http.Response(
        jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': '0x14a34'}),
        200,
      );
    });
    await tester.pumpWidget(
      _app(net, probeClient: client, locale: const Locale('en')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add-network')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Base').last);
    await tester.pumpAndSettle();

    expect(find.text('Chain ID'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'Base Local');
    await tester.enterText(
      find.byType(TextField).at(1),
      'https://base-rpc.example',
    );
    await tester.enterText(find.byType(TextField).at(2), 'ETH');
    await tester.enterText(find.byType(TextField).at(3), '84532');
    await tester.pump();
    await tester.ensureVisible(find.text('Save'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(net.customNetworks, hasLength(1));
    expect(net.customNetworks.single.chain, Chain.base);
    expect(net.customNetworks.single.evmChainId, 84532);
    expect(find.text('Probe passed, saved'), findsOneWidget);

    final reloaded = NetworkController();
    await reloaded.load();
    expect(reloaded.customNetworks, hasLength(1));
    expect(reloaded.customNetworks.single.networkIdentity, '84532');
  });

  testWidgets(
    'add network: chain id mismatch shows the node\'s actual id inline and '
    'does NOT persist',
    (tester) async {
      final net = NetworkController();
      await net.load();
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': '0x1'}),
          200,
        ),
      );
      await tester.pumpWidget(_app(net, probeClient: client));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('add-network')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Wrong Net');
      await tester.enterText(
        find.byType(TextField).at(1),
        'https://rpc.example',
      );
      await tester.enterText(find.byType(TextField).at(2), 'ETH');
      await tester.enterText(find.byType(TextField).at(3), '31337');
      await tester.pump();
      await tester.ensureVisible(find.text('保存'));
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      // Inline error with the node's ACTUAL id (decimal); sheet stays open.
      expect(find.text('Chain ID 不匹配：节点返回 1'), findsOneWidget);
      expect(find.text('添加网络'), findsOneWidget);
      expect(net.customNetworks, isEmpty);
    },
  );

  testWidgets('add network: probe failure shows rpcProbeFailed, sheet stays', (
    tester,
  ) async {
    final net = NetworkController();
    await net.load();
    final client = MockClient(
      (request) async => http.Response('unavailable', 503),
    );
    await tester.pumpWidget(_app(net, probeClient: client));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add-network')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Dead Net');
    await tester.enterText(
      find.byType(TextField).at(1),
      'https://down.example',
    );
    await tester.enterText(find.byType(TextField).at(2), 'ETH');
    await tester.enterText(find.byType(TextField).at(3), '1');
    await tester.pump();
    await tester.ensureVisible(find.text('保存'));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('RPC 探测失败，请检查地址'), findsOneWidget);
    expect(find.text('添加网络'), findsOneWidget);
    expect(net.customNetworks, isEmpty);
  });

  testWidgets('add network: public HTTP is rejected before any RPC probe', (
    tester,
  ) async {
    final net = NetworkController();
    await net.load();
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return http.Response(
        jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': '0x1'}),
        200,
      );
    });
    await tester.pumpWidget(_app(net, probeClient: client));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add-network')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Unsafe Net');
    await tester.enterText(
      find.byType(TextField).at(1),
      'http://public-rpc.example',
    );
    await tester.enterText(find.byType(TextField).at(2), 'ETH');
    await tester.enterText(find.byType(TextField).at(3), '1');
    await tester.pump();
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(
      find.text('请输入不包含账号凭证的有效 HTTPS 地址。仅 localhost 可使用 HTTP。'),
      findsOneWidget,
    );
    expect(requests, 0);
    expect(net.customNetworks, isEmpty);
  });

  testWidgets(
    'delete custom network: in-use warning shown, deletion falls back to '
    'the profile network',
    (tester) async {
      final net = NetworkController();
      await net.load();
      final custom = await net.addCustom(
        chain: Chain.solana,
        name: 'My Localnet',
        rpcUrl: 'http://127.0.0.1:8899',
        symbol: 'SOL',
        networkIdentity: solanaDevnet.networkIdentity,
      );
      await net.setOverride(Chain.solana, custom.id);
      expect(net.activeFor(Chain.solana).id, custom.id);

      await tester.pumpWidget(_app(net));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('net-row-solana')));
      await tester.pumpAndSettle();
      // Built-ins carry no delete affordance; the custom row does.
      expect(find.byKey(const ValueKey('net-del-sol-mainnet')), findsNothing);
      expect(find.byKey(const ValueKey('net-del-sol-devnet')), findsNothing);
      await tester.tap(find.byKey(ValueKey('net-del-${custom.id}')));
      await tester.pumpAndSettle();

      // Confirm dialog names the network and flags that it is in use.
      expect(find.text('删除网络'), findsOneWidget);
      expect(find.textContaining('该网络正在使用中'), findsOneWidget);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      // Gone from the controller and the picker; the active network fell back
      // to the environment profile (mainnet).
      expect(net.customNetworks, isEmpty);
      expect(net.activeFor(Chain.solana).id, 'sol-mainnet');
      expect(find.byKey(ValueKey('net-opt-${custom.id}')), findsNothing);
      expect(find.byKey(const ValueKey('net-opt-sol-mainnet')), findsOneWidget);
    },
  );
}
