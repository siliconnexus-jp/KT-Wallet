import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/market/gateway_client.dart';
import 'package:kt_wallet/src/screens/settings_screens.dart';
import 'package:kt_wallet/src/screens/transfer_screens.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/state/wallet_scope.dart';
import 'package:kt_wallet/src/transfer/airgap_codec.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';
import 'package:kt_wallet/src/widgets/scan_viewfinder.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';

Widget _app(Widget child, WalletController controller) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: WalletScope(controller: controller, child: child),
);

GatewayClient _emptyCatalog() => GatewayClient(
  baseUrl: 'https://gateway.example',
  client: MockClient((request) async {
    final body = jsonDecode(request.body) as Map<String, Object?>;
    return http.Response(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': body['id'],
        'result': {'tokens': <Object>[]},
      }),
      200,
    );
  }),
);

void main() {
  testWidgets('production address book never invents gallery contacts', (
    tester,
  ) async {
    final controller = WalletController(WalletManager());
    await tester.pumpWidget(_app(const AddressBookScreen(), controller));
    await tester.pumpAndSettle();

    expect(controller.contacts, isEmpty);
    expect(find.text('No contacts yet — tap + to add one'), findsOneWidget);
    expect(find.text('Alice'), findsNothing);
    controller.dispose();
  });

  testWidgets('production token manager never invents owned tokens', (
    tester,
  ) async {
    final controller = WalletController(WalletManager());
    await tester.pumpWidget(
      _app(TokenManageScreen(catalogClient: _emptyCatalog()), controller),
    );
    await tester.pumpAndSettle();

    expect(controller.tokens, isEmpty);
    expect(
      find.text('No custom tokens yet — tap + to add one'),
      findsOneWidget,
    );
    controller.dispose();
  });

  testWidgets('production transaction detail never renders demo values', (
    tester,
  ) async {
    final controller = WalletController(WalletManager());
    await tester.pumpWidget(_app(const TxDetailScreen(), controller));
    await tester.pumpAndSettle();

    expect(find.text('Local transaction record not found'), findsOneWidget);
    expect(find.text('-120.00 USDT'), findsNothing);
    controller.dispose();
  });

  testWidgets('explicit gallery bypass retains visual fixtures', (
    tester,
  ) async {
    final controller = WalletController(WalletManager(), allowTestBypass: true);
    await tester.pumpWidget(_app(const AddressBookScreen(), controller));
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('production QR scanner never invents shard progress', (
    tester,
  ) async {
    final controller = WalletController(WalletManager());
    final session = TransferSession()
      ..request = buildSignRequest(
        walletId: 'test-wallet',
        fromAddress: '0x1111111111111111111111111111111111111111',
      );
    await tester.pumpWidget(
      _app(
        TransferSessionScope(
          session: session,
          child: const ScanResultScreen(
            availability: FakeCameraAvailability(false),
          ),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Recognized shard'), findsNothing);
    expect(find.text('Recognized shard 5 / 12'), findsNothing);
    controller.dispose();
  });
}
