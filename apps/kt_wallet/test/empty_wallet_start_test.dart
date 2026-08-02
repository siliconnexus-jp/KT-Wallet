import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/main.dart';
import 'package:kt_wallet/src/screens/wallet_screens.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';

void main() {
  testWidgets(
    'production-empty wallet shows create/import entry, not a crash',
    (tester) async {
      final controller = WalletController(WalletManager());
      await tester.pumpWidget(
        KtWalletApp(controller: controller, initialLocation: '/home'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AddWalletScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('production root deep link never exposes the developer gallery', (
    tester,
  ) async {
    final controller = WalletController(WalletManager());
    // Supplying the persistent-controller seam selects production routing;
    // even an explicit "/" location must fail closed into the wallet shell.
    await tester.pumpWidget(KtWalletApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.byType(AddWalletScreen), findsOneWidget);
    expect(find.text('KT Wallet — 屏幕库'), findsNothing);
    expect(find.text('W10 启动页'), findsNothing);
  });

  for (final route in const [
    '/transfer-auth',
    '/broadcast-confirm',
    '/broadcast-result',
  ]) {
    testWidgets(
      'production deep link $route cannot fabricate a signed/submitted transaction',
      (tester) async {
        tester.platformDispatcher.localesTestValue = const [Locale('zh')];
        addTearDown(tester.platformDispatcher.clearLocalesTestValue);
        final controller = WalletController(WalletManager());

        await tester.pumpWidget(
          KtWalletApp(
            key: ValueKey(route),
            controller: controller,
            initialLocation: route,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('无法验证链上交易参数，签名已禁用。'), findsOneWidget);
        expect(find.text('交易已提交'), findsNothing);
        expect(find.text('-120.00 USDT · TRON'), findsNothing);
        expect(find.text('8f6d2c…a94e07'), findsNothing);
      },
    );
  }
}
