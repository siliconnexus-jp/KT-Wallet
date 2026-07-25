import 'dart:convert';

import 'package:core_crypto/core_crypto.dart' show ChainAddresses;
import 'package:core_crypto/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/platform/external_actions.dart';
import 'package:kt_wallet/src/screens/assets_screens.dart';
import 'package:kt_wallet/src/state/networks.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/state/wallet_scope.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Receive-screen faucet affordance: Solana devnet gets a REAL one-tap
/// airdrop (requestAirdrop against the active network's RPC), other testnets
/// with a declared faucet URL open the system browser, mainnet gets nothing.
const _mnemonic =
    'abandon ability able about above absent absorb abstract absurd abuse access accident';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final originalActions = ExternalActions.instance;
  tearDown(() => ExternalActions.instance = originalActions);

  Future<(WalletController, ChainAddresses)> makeWallet() async {
    final crypto = MockCoreCrypto();
    final controller = WalletController(WalletManager(), crypto: crypto);
    await crypto.storeWallet(walletId: 'w1', mnemonic: _mnemonic);
    final addresses = await crypto.deriveAddresses('w1');
    controller.add(
      HotWallet(
        id: 'w1',
        name: '日常钱包',
        avatarColor: 0xFFF59E0B,
        addresses: addresses,
        backedUp: true,
      ),
    );
    return (controller, addresses);
  }

  Widget app(
    WalletController wallets,
    NetworkController net, {
    http.Client? airdropClient,
  }) => MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: WalletScope(
      controller: wallets,
      child: NetworkScope(
        controller: net,
        child: ReceiveScreen(airdropClient: airdropClient),
      ),
    ),
  );

  Future<void> switchToSolana(WidgetTester tester) async {
    await tester.tap(find.text('USDT · TRON'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Solana'));
    await tester.pumpAndSettle();
  }

  testWidgets('devnet: one-tap airdrop sends requestAirdrop for the wallet '
      'address and reports success', (tester) async {
    final (wallets, addresses) = await makeWallet();
    final net = NetworkController();
    await net.setEnvironment(NetworkEnvironment.testnet);

    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      final body = jsonDecode(request.body) as Map<String, Object?>;
      expect(body['method'], 'requestAirdrop');
      expect(body['params'], [addresses.solana, 1000000000]);
      return http.Response(
        jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': 'sig111'}),
        200,
      );
    });

    await tester.pumpWidget(app(wallets, net, airdropClient: client));
    await tester.pumpAndSettle();
    await switchToSolana(tester);

    expect(find.byKey(const ValueKey('faucet-action')), findsOneWidget);
    expect(find.text('领取测试币'), findsOneWidget);
    expect(find.text('Devnet'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('faucet-action')));
    await tester.pumpAndSettle();

    expect(requests, hasLength(1));
    expect(requests.single.url.toString(), 'https://api.devnet.solana.com');
    expect(find.text('空投成功,余额稍后刷新'), findsOneWidget);
  });

  testWidgets('devnet: airdrop failure surfaces the node message', (
    tester,
  ) async {
    final (wallets, _) = await makeWallet();
    final net = NetworkController();
    await net.setEnvironment(NetworkEnvironment.testnet);

    final client = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'error': {'code': -32602, 'message': 'airdrop limit reached'},
        }),
        200,
      ),
    );

    await tester.pumpWidget(app(wallets, net, airdropClient: client));
    await tester.pumpAndSettle();
    await switchToSolana(tester);

    await tester.tap(find.byKey(const ValueKey('faucet-action')));
    await tester.pumpAndSettle();

    expect(find.text('空投失败:airdrop limit reached'), findsOneWidget);
    expect(find.text('空投成功,余额稍后刷新'), findsNothing);
  });

  testWidgets('Nile (TRON testnet): tap opens the faucet in the browser', (
    tester,
  ) async {
    final (wallets, _) = await makeWallet();
    final net = NetworkController();
    await net.setEnvironment(NetworkEnvironment.testnet);

    final actions = FakeExternalActions();
    ExternalActions.instance = actions;

    // No airdrop client: nothing may issue an RPC on the browser path.
    await tester.pumpWidget(
      app(
        wallets,
        net,
        airdropClient: MockClient(
          (request) async => fail('browser path must not call any RPC'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Default chain is TRON; testnet env → Nile is active.
    expect(find.text('领取测试币'), findsOneWidget);
    expect(find.text('Nile'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('faucet-action')));
    await tester.pumpAndSettle();

    expect(actions.opened.map((e) => e.toString()), [
      'https://nileex.io/join/getJoinPage',
    ]);
    expect(find.text('已打开测试币水龙头'), findsOneWidget);
  });

  testWidgets('share action invokes the native share contract with address', (
    tester,
  ) async {
    final (wallets, addresses) = await makeWallet();
    final actions = FakeExternalActions();
    ExternalActions.instance = actions;

    await tester.pumpWidget(app(wallets, NetworkController()));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pumpAndSettle();

    expect(actions.shared, hasLength(1));
    expect(actions.shared.single.text, contains(addresses.tron));
    expect(actions.shared.single.subject, 'TRON 收款地址');
  });

  testWidgets('mainnet: no faucet affordance renders', (tester) async {
    final (wallets, _) = await makeWallet();
    final net = NetworkController(); // mainnet default

    await tester.pumpWidget(app(wallets, net));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('faucet-action')), findsNothing);
    expect(find.text('领取测试币'), findsNothing);

    await switchToSolana(tester);
    expect(find.byKey(const ValueKey('faucet-action')), findsNothing);
  });
}
