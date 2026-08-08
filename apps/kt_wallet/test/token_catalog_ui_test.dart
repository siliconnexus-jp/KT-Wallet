import 'dart:convert';

import 'package:core_crypto/core_crypto.dart' show ChainAddresses;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/market/gateway_client.dart';
import 'package:kt_wallet/src/screens/settings_screens.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/state/wallet_scope.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';

GatewayClient _catalogClient() => GatewayClient(
  baseUrl: 'https://gateway.example',
  client: MockClient((request) async {
    final body = jsonDecode(request.body) as Map<String, Object?>;
    expect(body['method'], 'kt_searchTokens');
    return http.Response(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': body['id'],
        'result': {
          'tokens': [
            {
              'network': 'eth-mainnet',
              'symbol': 'KTT',
              'name': 'KT Test Token',
              'contract': '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              'decimals': 8,
              'popular': true,
              'verified': true,
            },
          ],
        },
      }),
      200,
    );
  }),
);

WalletController _wallets() => WalletController(
  WalletManager(
    initial: [
      HotWallet(
        id: 'wallet',
        name: 'Wallet',
        avatarColor: 0xFF2557E8,
        addresses: const ChainAddresses(
          eth: '0x1111111111111111111111111111111111111111',
          polygon: '0x1111111111111111111111111111111111111111',
          tron: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
          solana: '11111111111111111111111111111111',
        ),
        backedUp: true,
      ),
    ],
  ),
);

void main() {
  testWidgets('backend-configured official token gets a blue check and adds', (
    tester,
  ) async {
    final wallets = _wallets();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: WalletScope(
          controller: wallets,
          child: TokenManageScreen(catalogClient: _catalogClient()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('KTT'), findsOneWidget);
    expect(find.text('KT Test Token · Ethereum · ERC-20'), findsOneWidget);
    expect(find.byIcon(Icons.verified_rounded), findsWidgets);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);

    await tester.ensureVisible(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    expect(find.text('已添加官方币 KTT'), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    expect(find.text('KTT'), findsOneWidget);
    expect(find.byIcon(Icons.verified_rounded), findsWidgets);
    wallets.dispose();
  });

  testWidgets('manually added token stores its exact selected network', (
    tester,
  ) async {
    final wallets = _wallets();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: WalletScope(
          controller: wallets,
          child: TokenManageScreen(catalogClient: _catalogClient()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('custom-token-network')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('custom-token-symbol')),
      'mine',
    );
    await tester.enterText(
      find.byKey(const ValueKey('custom-token-name')),
      'My Token',
    );
    await tester.enterText(
      find.byKey(const ValueKey('custom-token-contract')),
      '0x2222222222222222222222222222222222222222',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(wallets.tokens, hasLength(1));
    expect(wallets.tokens.single.symbol, 'MINE');
    expect(wallets.tokens.single.networkId, 'eth-mainnet');
    expect(wallets.tokens.single.network, 'Ethereum · ERC-20');
    wallets.dispose();
  });
}
