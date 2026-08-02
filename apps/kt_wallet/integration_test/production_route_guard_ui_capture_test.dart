import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/main.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('missing broadcast evidence is visibly fail closed', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('zh')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(
      KtWalletApp(
        controller: WalletController(WalletManager()),
        initialLocation: '/broadcast-result',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('无法验证链上交易参数，签名已禁用。'), findsOneWidget);
    expect(find.text('交易已提交'), findsNothing);
    expect(find.text('-120.00 USDT'), findsNothing);

    // A short stable window lets the strict-loop harness collect a native
    // simulator screenshot of the exact production route, not a widget image.
    // ignore: avoid_print
    print('PRODUCTION_ROUTE_GUARD_CAPTURE READY');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 20)),
    );
  });
}
