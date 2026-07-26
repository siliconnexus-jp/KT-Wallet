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
}
