import 'dart:convert';

import 'package:chains/chains.dart' show Chain;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/market/rpc_health.dart';
import 'package:kt_wallet/src/screens/settings_screens.dart';
import 'package:kt_wallet/src/state/app_prefs.dart';
import 'package:kt_wallet/src/state/networks.dart';
import 'package:kt_wallet/src/widgets/rpc_probe.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The RPC badges in network settings were string literals: a green '86 ms'
/// for Ethereum, '112 ms' for Polygon, '64 ms' for TRON, and a permanent red
/// 'Timeout' for Solana — while that Solana node was demonstrably healthy.
/// Nothing was ever measured. These pin the measurement down.
void main() {
  group('RpcHealthController', () {
    test(
      'a reachable endpoint reports ok, an unreachable one reports down',
      () async {
        final controller = RpcHealthController(
          probe: RpcProbe(
            client: MockClient((req) async {
              if (req.url.host == 'good') {
                return http.Response(
                  jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': '0x1'}),
                  200,
                );
              }
              throw const SocketFailure();
            }),
          ),
        );
        addTearDown(controller.dispose);

        expect(controller.healthOf('eth'), isA<RpcHealthProbing>());

        await controller.measure(
          networkId: 'eth',
          chain: Chain.ethereum,
          rpcUrl: 'https://good',
        );
        expect(controller.healthOf('eth'), isA<RpcHealthOk>());

        await controller.measure(
          networkId: 'dead',
          chain: Chain.ethereum,
          rpcUrl: 'https://bad',
        );
        expect(controller.healthOf('dead'), isA<RpcHealthDown>());
      },
    );

    test('a measured network is not re-probed unless forced', () async {
      var calls = 0;
      final controller = RpcHealthController(
        probe: RpcProbe(
          client: MockClient((req) async {
            calls++;
            return http.Response(
              jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': '0x1'}),
              200,
            );
          }),
        ),
      );
      addTearDown(controller.dispose);

      await controller.measure(
        networkId: 'eth',
        chain: Chain.ethereum,
        rpcUrl: 'https://x',
      );
      await controller.measure(
        networkId: 'eth',
        chain: Chain.ethereum,
        rpcUrl: 'https://x',
      );
      expect(calls, 1, reason: 'a rebuild must not re-probe');

      await controller.measure(
        networkId: 'eth',
        chain: Chain.ethereum,
        rpcUrl: 'https://x',
        force: true,
      );
      expect(calls, 2);
    });

    test('invalidate drops results so the next build re-measures', () async {
      var calls = 0;
      final controller = RpcHealthController(
        probe: RpcProbe(
          client: MockClient((req) async {
            calls++;
            return http.Response(
              jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': '0x1'}),
              200,
            );
          }),
        ),
      );
      addTearDown(controller.dispose);

      await controller.measure(
        networkId: 'eth',
        chain: Chain.ethereum,
        rpcUrl: 'https://x',
      );
      controller.invalidate();
      expect(controller.healthOf('eth'), isA<RpcHealthProbing>());
      await controller.measure(
        networkId: 'eth',
        chain: Chain.ethereum,
        rpcUrl: 'https://x',
      );
      expect(calls, 2);
    });
  });

  group('network settings badges', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Widget app(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

    testWidgets('scope-absent renders an honest unknown, never a figure', (
      tester,
    ) async {
      await tester.pumpWidget(app(const NetworkSettingsScreen()));
      await tester.pumpAndSettle();

      // The old fabricated values must be gone everywhere.
      expect(find.text('86 ms'), findsNothing);
      expect(find.text('112 ms'), findsNothing);
      expect(find.text('64 ms'), findsNothing);
      expect(find.text('超时'), findsNothing);
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('a live scope shows the MEASURED latency, and a real failure', (
      tester,
    ) async {
      final prefs = AppPrefsController();
      await prefs.load();
      final networks = NetworkController();
      await networks.load();

      await tester.pumpWidget(
        app(
          AppPrefsScope(
            controller: prefs,
            child: NetworkScope(
              controller: networks,
              child: NetworkSettingsScreen(
                // Everything answers; Solana's node 500s.
                healthClient: MockClient((req) async {
                  if (req.url.host.contains('solana')) {
                    return http.Response('nope', 500);
                  }
                  return http.Response(
                    jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': '0x1'}),
                    200,
                  );
                }),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No literal survives; a measured badge ends in ' ms'.
      expect(find.text('86 ms'), findsNothing);
      expect(find.text('112 ms'), findsNothing);
      final measured = tester
          .widgetList<Text>(find.byType(Text))
          .where((t) => (t.data ?? '').endsWith(' ms'))
          .length;
      expect(measured, greaterThan(0), reason: 'at least one real measurement');
      // Solana's node answered 500 → an honest failure, not a fixed 'Timeout'.
      expect(find.text('无法连接'), findsWidgets);
    });
  });
}

/// Stand-in for a transport-level failure inside MockClient.
class SocketFailure implements Exception {
  const SocketFailure();
}
