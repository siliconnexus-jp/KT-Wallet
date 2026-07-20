import 'package:core_crypto/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/main.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';

/// Proves the receive screen (W14) is bound to the current wallet: the chain
/// picker switches the displayed address to the wallet's address for that
/// chain.
const _mnemonic =
    'abandon ability able about above absent absorb abstract absurd abuse access accident';

void main() {
  testWidgets('chain picker switches the displayed receive address', (tester) async {
    final crypto = MockCoreCrypto();
    final controller = WalletController(WalletManager(), crypto: crypto);
    await crypto.storeWallet(walletId: 'w1', mnemonic: _mnemonic);
    final addresses = await crypto.deriveAddresses('w1');
    controller.add(HotWallet(
      id: 'w1',
      name: '日常钱包',
      avatarColor: 0xFFF59E0B,
      addresses: addresses,
      backedUp: true,
    ));

    tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(KtWalletApp(controller: controller, initialLocation: '/receive'));
    await tester.pumpAndSettle();

    // Default chain is TRON (matches the design).
    expect(find.text('USDT · TRON'), findsOneWidget);
    expect(find.text(addresses.tron), findsOneWidget);

    // Switch to Ethereum via the pill's bottom sheet.
    await tester.tap(find.text('USDT · TRON'));
    await tester.pumpAndSettle();
    expect(find.text('Polygon'), findsOneWidget);
    expect(find.text('Solana'), findsOneWidget);
    await tester.tap(find.text('Ethereum'));
    await tester.pumpAndSettle();

    expect(find.text('ETH · Ethereum'), findsOneWidget);
    expect(find.text(addresses.eth), findsOneWidget);
    expect(find.text(addresses.tron), findsNothing);

    // And to Solana.
    await tester.tap(find.text('ETH · Ethereum'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Solana'));
    await tester.pumpAndSettle();
    expect(find.text('SOL · Solana'), findsOneWidget);
    expect(find.text(addresses.solana), findsOneWidget);
  });
}
