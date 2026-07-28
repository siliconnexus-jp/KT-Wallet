import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/main.dart';
import 'package:kt_wallet/src/state/networks.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';

const _mnemonic = String.fromEnvironment('SEPOLIA_E2E_MNEMONIC');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home displays live funded Sepolia ETH and Test USDT', (
    tester,
  ) async {
    expect(_mnemonic, isNotEmpty);
    tester.platformDispatcher.localesTestValue = const [Locale('zh')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    final crypto = MethodChannelCoreCrypto();
    const walletId = 'sepolia-mobile-ui';
    await crypto.storeWallet(
      walletId: walletId,
      mnemonic: _mnemonic,
      requireAuth: false,
    );
    final addresses = await crypto.deriveAddresses(walletId);
    final wallets = WalletController(
      WalletManager(
        initial: [
          HotWallet(
            id: walletId,
            name: 'Sepolia 测试钱包',
            avatarColor: 0xFF5B86FF,
            addresses: addresses,
            backedUp: true,
          ),
        ],
      ),
      crypto: crypto,
    );
    final networks = NetworkController(
      initialEnvironment: NetworkEnvironment.testnet,
    );

    await binding.convertFlutterSurfaceToImage();
    await tester.pumpWidget(
      KtWalletApp(
        controller: wallets,
        networkController: networks,
        initialLocation: '/home',
      ),
    );
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.textContaining('198 USDT · Sepolia').evaluate().isNotEmpty) {
        break;
      }
    }

    expect(find.text('Sepolia 测试钱包'), findsOneWidget);
    _expectFundedAsset(tester, 'ETH');
    _expectFundedAsset(tester, 'USDT');

    await tester.pumpAndSettle();
    await binding.takeScreenshot('sepolia-live-balances');
  });
}

void _expectFundedAsset(WidgetTester tester, String symbol) {
  final labelPattern = RegExp(
    '^([0-9]+(?:\\.[0-9]+)?) ${RegExp.escape(symbol)} · ',
  );
  final finder = find.textContaining(labelPattern);
  expect(finder, findsOneWidget);

  final label = tester.widget<Text>(finder).data;
  final match = label == null ? null : labelPattern.firstMatch(label);
  final amount = match == null ? null : double.tryParse(match.group(1)!);
  expect(amount, isNotNull);
  expect(amount!, greaterThan(0));
}
