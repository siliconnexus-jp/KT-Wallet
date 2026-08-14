import 'package:core_crypto/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/main.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:ui_kit/ui_kit.dart';

/// Proves the receive screen (W14) is bound to the current wallet: the picker
/// selects a network first and then an asset on that exact network, while the
/// displayed address follows the selected network.
const _mnemonic =
    'abandon ability able about above absent absorb abstract absurd abuse access accident';

void main() {
  testWidgets('home receive action and nav back return to the same wallet', (
    tester,
  ) async {
    final crypto = MockCoreCrypto();
    final controller = WalletController(WalletManager(), crypto: crypto);
    await crypto.storeWallet(walletId: 'w1', mnemonic: _mnemonic);
    final addresses = await crypto.deriveAddresses('w1');
    await controller.add(
      HotWallet(
        id: 'w1',
        name: '日常钱包',
        avatarColor: 0xFFF59E0B,
        addresses: addresses,
        backedUp: true,
      ),
    );

    tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      KtWalletApp(controller: controller, initialLocation: '/home'),
    );
    await tester.pumpAndSettle();

    expect(find.text('日常钱包'), findsOneWidget);
    await tester.tap(find.text('收款'));
    await tester.pumpAndSettle();
    expect(find.text('USDT · TRON'), findsOneWidget);

    final back = find.byTooltip('返回').hitTestable();
    expect(back, findsOneWidget);
    await tester.tap(back);
    await tester.pumpAndSettle();

    expect(find.text('日常钱包'), findsOneWidget);
    expect(find.text('USDT · TRON'), findsNothing);
  });

  testWidgets('network then asset picker switches the receive address', (
    tester,
  ) async {
    final crypto = MockCoreCrypto();
    final controller = WalletController(WalletManager(), crypto: crypto);
    await crypto.storeWallet(walletId: 'w1', mnemonic: _mnemonic);
    final addresses = await crypto.deriveAddresses('w1');
    await controller.add(
      HotWallet(
        id: 'w1',
        name: '日常钱包',
        avatarColor: 0xFFF59E0B,
        addresses: addresses,
        backedUp: true,
      ),
    );

    tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      KtWalletApp(controller: controller, initialLocation: '/receive'),
    );
    await tester.pumpAndSettle();

    // Default chain is TRON (matches the design).
    expect(find.text('USDT · TRON'), findsOneWidget);
    expect(find.text(addresses.tron), findsOneWidget);
    expect(
      tester.widget<KtQrCode>(find.byType(KtQrCode)).data,
      addresses.tron,
      reason: 'the receive QR must encode the displayed live address',
    );

    // Switch to Ethereum, then explicitly select its native asset.
    await tester.tap(find.text('USDT · TRON'));
    await tester.pumpAndSettle();
    expect(find.text('选择网络'), findsOneWidget);
    expect(find.text('Polygon'), findsOneWidget);
    expect(find.text('Solana'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('receive-network-eth')));
    await tester.pumpAndSettle();

    expect(find.text('选择资产'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('receive-asset-native:eth')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('receive-asset-official:usdt-eth')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('receive-asset-native:eth')));
    await tester.pumpAndSettle();

    expect(find.text('ETH · Ethereum'), findsOneWidget);
    expect(find.text(addresses.eth), findsOneWidget);
    expect(find.text(addresses.tron), findsNothing);

    // And to Solana.
    await tester.tap(find.text('ETH · Ethereum'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('receive-network-solana')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('receive-asset-native:solana')));
    await tester.pumpAndSettle();
    expect(find.text('SOL · Solana'), findsOneWidget);
    expect(find.text(addresses.solana), findsOneWidget);
    expect(
      tester.widget<KtQrCode>(find.byType(KtQrCode)).data,
      addresses.solana,
    );
  });

  testWidgets('asset step only lists assets on the selected network', (
    tester,
  ) async {
    final crypto = MockCoreCrypto();
    final controller = WalletController(WalletManager(), crypto: crypto);
    await crypto.storeWallet(walletId: 'w1', mnemonic: _mnemonic);
    final addresses = await crypto.deriveAddresses('w1');
    await controller.add(
      HotWallet(
        id: 'w1',
        name: '日常钱包',
        avatarColor: 0xFFF59E0B,
        addresses: addresses,
        backedUp: true,
      ),
    );

    tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      KtWalletApp(controller: controller, initialLocation: '/receive'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('USDT · TRON'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('receive-network-polygon')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('receive-asset-native:polygon')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('receive-asset-official:usdc-polygon')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('receive-asset-official:usdt-polygon')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('receive-asset-native:solana')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('receive-asset-official:usdt-tron')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('receive-asset-official:usdc-polygon')),
    );
    await tester.pumpAndSettle();
    expect(find.text('USDC · Polygon'), findsOneWidget);
    expect(find.text(addresses.polygon), findsOneWidget);
    expect(
      tester.widget<KtQrCode>(find.byType(KtQrCode)).data,
      addresses.polygon,
    );
  });

  testWidgets('enabled custom token is offered only on its exact network', (
    tester,
  ) async {
    final crypto = MockCoreCrypto();
    final controller = WalletController(WalletManager(), crypto: crypto);
    await crypto.storeWallet(walletId: 'w1', mnemonic: _mnemonic);
    final addresses = await crypto.deriveAddresses('w1');
    await controller.add(
      HotWallet(
        id: 'w1',
        name: '日常钱包',
        avatarColor: 0xFFF59E0B,
        addresses: addresses,
        backedUp: true,
      ),
    );
    final polygonToken = await controller.addToken(
      symbol: 'cat',
      name: 'Cat Token',
      contract: '0x1111111111111111111111111111111111111112',
      network: 'Polygon',
      networkId: 'polygon-mainnet',
    );
    final disabledToken = await controller.addToken(
      symbol: 'OFF',
      name: 'Disabled Token',
      contract: '0x1111111111111111111111111111111111111113',
      network: 'Polygon',
      networkId: 'polygon-mainnet',
      enabled: false,
    );
    final legacyToken = await controller.addToken(
      symbol: 'OLD',
      name: 'Unbound Token',
      contract: '0x1111111111111111111111111111111111111114',
      network: 'Polygon',
    );

    tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      KtWalletApp(controller: controller, initialLocation: '/receive'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('USDT · TRON'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('receive-network-polygon')));
    await tester.pumpAndSettle();

    final customRow = find.byKey(
      ValueKey('receive-asset-custom:${polygonToken.id}'),
    );
    expect(customRow, findsOneWidget);
    expect(
      find.byKey(ValueKey('receive-asset-custom:${disabledToken.id}')),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey('receive-asset-custom:${legacyToken.id}')),
      findsNothing,
    );

    await tester.tap(customRow);
    await tester.pumpAndSettle();
    expect(find.text('CAT · Polygon'), findsOneWidget);
    expect(find.text(addresses.polygon), findsOneWidget);
  });
}
