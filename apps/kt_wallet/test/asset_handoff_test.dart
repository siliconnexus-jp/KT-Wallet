import 'package:chains/chains.dart' show Chain;
import 'package:core_crypto/core_crypto.dart' show ChainAddresses, Coin;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/market/asset_ref.dart';
import 'package:kt_wallet/src/market/token_balance_service.dart';
import 'package:kt_wallet/src/screens/assets_screens.dart';
import 'package:kt_wallet/src/screens/home_screen.dart' show nativesBySymbol;
import 'package:kt_wallet/src/screens/transfer_screens.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/state/wallet_scope.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';

/// Send and Receive used to lose the asset on the way in. Send carried nothing
/// at all, so it fell through to the first row of its own list — USDT on TRON
/// — no matter which asset you tapped it from, and its dropdown offered every
/// other coin besides. Receive carried only the Coin, so opening it from USDT
/// on Ethereum announced "ETH · Ethereum": the right address under the wrong
/// asset's name. These pin the hand-off down.

const _usdtGroup = [usdtEthToken, usdtTronToken, usdtPolygonToken];

WalletController _wallets() => WalletController(
  WalletManager(
    initial: [
      HotWallet(
        id: 'w1',
        name: 'W',
        avatarColor: 0xFF000000,
        addresses: const ChainAddresses(
          eth: '0x1111111111111111111111111111111111111111',
          polygon: '0x1111111111111111111111111111111111111111',
          tron: 'TQm9xPa2Wc8hJdU5eRnT6yGb1sVb7L3kFa',
          solana: 'So11111111111111111111111111111111111111112',
        ),
      ),
    ],
  ),
);

WalletController _twoWallets() => WalletController(
  WalletManager(
    initial: [
      HotWallet(
        id: 'w1',
        name: 'Current wallet',
        avatarColor: 0xFF000000,
        addresses: const ChainAddresses(
          eth: '0x1111111111111111111111111111111111111111',
          polygon: '0x1111111111111111111111111111111111111111',
          tron: 'TQm9xPa2Wc8hJdU5eRnT6yGb1sVb7L3kFa',
          solana: 'So11111111111111111111111111111111111111112',
        ),
        sortOrder: 0,
      ),
      HotWallet(
        id: 'w2',
        name: 'Savings wallet',
        avatarColor: 0xFF111111,
        addresses: const ChainAddresses(
          eth: '0x2222222222222222222222222222222222222222',
          polygon: '0x2222222222222222222222222222222222222222',
          tron: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
          solana: 'So11111111111111111111111111111111111111113',
        ),
        sortOrder: 1,
      ),
    ],
  ),
);

Widget _app(Widget home, WalletController wallets) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: WalletScope(controller: wallets, child: home),
);

void main() {
  _nativeGrouping();

  group('AssetRef.selecting', () {
    test('narrows to one deployment but keeps the group', () {
      final ref = AssetRef.tokenGroup(_usdtGroup);
      final onTron = ref.selecting(1);

      expect(onTron.symbol, 'USDT');
      expect(onTron.coin, Coin.tron);
      expect(onTron.contract, usdtTronToken.contract);
      expect(onTron.tokenId, usdtTronToken.id);
      // The group survives, so the destination screen can still offer the
      // network picker.
      expect(onTron.group.map((d) => d.tokenId), _usdtGroup.map((t) => t.id));
      expect(onTron.chainIndex, 1);
    });

    test('an out-of-range index clamps instead of throwing', () {
      final ref = AssetRef.tokenGroup(_usdtGroup);
      expect(ref.selecting(99).coin, usdtPolygonToken.chain);
      expect(ref.selecting(-1).coin, usdtEthToken.chain);
    });

    test('a native coin is returned untouched', () {
      final ref = AssetRef.native(
        coin: Coin.eth,
        name: 'Ethereum',
        symbol: 'ETH',
      );
      // A single-chain asset has exactly one deployment, so narrowing to any
      // index lands back on it.
      expect(ref.selecting(3).coin, Coin.eth);
      expect(ref.selecting(3).symbol, 'ETH');
      expect(ref.group, hasLength(1));
    });
  });

  group('send', () {
    testWidgets('opens on the chain it was handed, not on TRON', (
      tester,
    ) async {
      final wallets = _wallets();
      // USDT on Ethereum — the second entry of the screen's own list is TRON,
      // which is what used to win.
      final asset = AssetRef.tokenGroup(_usdtGroup).selecting(0);

      await tester.pumpWidget(_app(TransferInputScreen(asset: asset), wallets));
      await tester.pumpAndSettle();

      expect(find.text('USDT'), findsWidgets);
      expect(find.text('Ethereum'), findsWidgets);
      expect(find.text('TRON · TRC-20'), findsNothing);
    });

    testWidgets('the picker offers other chains, never other assets', (
      tester,
    ) async {
      final wallets = _wallets();
      final asset = AssetRef.tokenGroup(_usdtGroup).selecting(0);

      await tester.pumpWidget(_app(TransferInputScreen(asset: asset), wallets));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('transfer-asset')));
      await tester.pumpAndSettle();

      expect(find.text('选择网络'), findsOneWidget);
      expect(find.text('选择资产'), findsNothing);
      // Every USDT chain is offered...
      expect(find.text('TRON'), findsWidgets);
      expect(find.text('Polygon'), findsWidgets);
      // ...and nothing that would change the asset.
      expect(find.text('ETH'), findsNothing);
      expect(find.text('USDC'), findsNothing);
      expect(find.text('SOL'), findsNothing);
    });

    testWidgets('switching chain keeps the symbol', (tester) async {
      final wallets = _wallets();
      final asset = AssetRef.tokenGroup(_usdtGroup).selecting(0);

      await tester.pumpWidget(_app(TransferInputScreen(asset: asset), wallets));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('transfer-asset')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('TRON').last);
      await tester.pumpAndSettle();

      expect(find.text('USDT'), findsWidgets);
      expect(find.text('TRON'), findsWidgets);
    });

    testWidgets('a single-chain asset shows no picker at all', (tester) async {
      final wallets = _wallets();
      final asset = AssetRef.token(usdtEthToken);

      await tester.pumpWidget(_app(TransferInputScreen(asset: asset), wallets));
      await tester.pumpAndSettle();

      // Nothing to choose, so no chevron inviting a tap that does nothing.
      expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
    });

    testWidgets('Arbitrum address book accepts Ethereum contacts only', (
      tester,
    ) async {
      final wallets = _wallets();
      const evmAddress = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';
      await wallets.addContact(
        name: 'Ethereum Alice',
        address: evmAddress,
        chain: Chain.ethereum.name,
      );
      await wallets.addContact(
        name: 'TRON Bob',
        address: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
        chain: Chain.tron.name,
      );
      final asset = AssetRef.native(
        coin: Coin.arbitrum,
        name: 'Arbitrum One',
        symbol: 'ETH',
      );

      await tester.pumpWidget(_app(TransferInputScreen(asset: asset), wallets));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('transfer-address-book')));
      await tester.pumpAndSettle();

      expect(find.text('Ethereum Alice'), findsOneWidget);
      expect(find.text('TRON Bob'), findsNothing);
      expect(find.textContaining('仅显示可用于 Arbitrum One'), findsOneWidget);

      await tester.tap(find.text('Ethereum Alice'));
      await tester.pumpAndSettle();
      final recipient = tester.widget<TextField>(find.byType(TextField).first);
      expect(recipient.controller!.text, evmAddress);
      expect(
        find.byKey(const ValueKey('transfer-selected-contact')),
        findsOneWidget,
      );
      expect(find.text('Ethereum Alice'), findsOneWidget);
      expect(find.text('地址格式正确 · Arbitrum One 网络'), findsOneWidget);

      // Editing the recipient must clear the stale identity immediately.
      await tester.enterText(find.byType(TextField).first, '${evmAddress}0');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('transfer-selected-contact')),
        findsNothing,
      );
    });

    testWidgets(
      'recipient picker hides the current wallet and lists contacts first',
      (tester) async {
        final wallets = _twoWallets();
        final alice = await wallets.addContact(
          name: 'Alice contact',
          address: '0x3333333333333333333333333333333333333333',
          chain: Chain.ethereum.name,
        );
        // Even if a user saved their own address previously, it must not
        // reappear as a valid recipient through the contact section.
        final self = await wallets.addContact(
          name: 'My own address',
          address: '0x1111111111111111111111111111111111111111',
          chain: Chain.ethereum.name,
        );
        final asset = AssetRef.native(
          coin: Coin.eth,
          name: 'Ethereum',
          symbol: 'ETH',
        );

        await tester.pumpWidget(
          _app(TransferInputScreen(asset: asset), wallets),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('transfer-address-book')));
        await tester.pumpAndSettle();

        final aliceRow = find.byKey(ValueKey('transfer-contact-${alice.id}'));
        const otherWalletRow = ValueKey(
          'transfer-contact-local-wallet:w2:ethereum',
        );
        expect(aliceRow, findsOneWidget);
        expect(find.byKey(otherWalletRow), findsOneWidget);
        expect(
          find.byKey(
            const ValueKey('transfer-contact-local-wallet:w1:ethereum'),
          ),
          findsNothing,
        );
        expect(
          find.byKey(ValueKey('transfer-contact-${self.id}')),
          findsNothing,
        );
        expect(
          tester.getTopLeft(aliceRow).dy,
          lessThan(tester.getTopLeft(find.byKey(otherWalletRow)).dy),
        );
      },
    );

    testWidgets('without an asset the full list is still offered', (
      tester,
    ) async {
      final wallets = _wallets();

      await tester.pumpWidget(_app(const TransferInputScreen(), wallets));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('transfer-asset')));
      await tester.pumpAndSettle();

      // The home Send button is the one legitimate "choose what to send" entry
      // point and must keep working.
      expect(find.text('选择资产'), findsOneWidget);
    });
  });

  group('receive', () {
    testWidgets('names the token, not the chain\'s native coin', (
      tester,
    ) async {
      final wallets = _wallets();
      final asset = AssetRef.tokenGroup(_usdtGroup).selecting(0);

      await tester.pumpWidget(_app(ReceiveScreen(asset: asset), wallets));
      await tester.pumpAndSettle();

      expect(find.text('USDT · Ethereum'), findsOneWidget);
      expect(find.text('ETH · Ethereum'), findsNothing);
    });

    testWidgets('shows both the token and Ethereum network artwork', (
      tester,
    ) async {
      final wallets = _wallets();
      final asset = AssetRef.tokenGroup(_usdtGroup).selecting(0);

      await tester.pumpWidget(_app(ReceiveScreen(asset: asset), wallets));
      await tester.pumpAndSettle();

      final tokenImage = tester.widget<Image>(
        find.descendant(
          of: find.byKey(const ValueKey('receive-token-icon')),
          matching: find.byType(Image),
        ),
      );
      final networkImage = tester.widget<Image>(
        find.descendant(
          of: find.byKey(const ValueKey('receive-network-icon')),
          matching: find.byType(Image),
        ),
      );
      expect(
        (tokenImage.image as AssetImage).assetName,
        'assets/tokens/usdt.png',
      );
      expect(
        (networkImage.image as AssetImage).assetName,
        'assets/tokens/eth.png',
      );
    });

    testWidgets('uses the Ethereum artwork for native ETH', (tester) async {
      final wallets = _wallets();
      final asset = AssetRef.native(
        coin: Coin.eth,
        name: 'Ethereum',
        symbol: 'ETH',
      );

      await tester.pumpWidget(_app(ReceiveScreen(asset: asset), wallets));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('receive-token-icon')), findsNothing);
      final networkImage = tester.widget<Image>(
        find.descendant(
          of: find.byKey(const ValueKey('receive-network-icon')),
          matching: find.byType(Image),
        ),
      );
      expect(
        (networkImage.image as AssetImage).assetName,
        'assets/tokens/eth.png',
      );
    });

    testWidgets('opens BNB receive with its address and network artwork', (
      tester,
    ) async {
      final wallets = _wallets();
      final asset = AssetRef.native(
        coin: Coin.bnb,
        name: 'BNB Smart Chain',
        symbol: 'BNB',
      );

      await tester.pumpWidget(_app(ReceiveScreen(asset: asset), wallets));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('BNB · BNB Smart Chain'), findsOneWidget);
      expect(
        find.text('0x1111111111111111111111111111111111111111'),
        findsOneWidget,
      );
      final networkImage = tester.widget<Image>(
        find.descendant(
          of: find.byKey(const ValueKey('receive-network-icon')),
          matching: find.byType(Image),
        ),
      );
      expect(
        (networkImage.image as AssetImage).assetName,
        'assets/tokens/bnb.png',
      );
    });

    testWidgets('the chain picker is narrowed to that token', (tester) async {
      final wallets = _wallets();
      final asset = AssetRef.tokenGroup(_usdtGroup).selecting(0);

      await tester.pumpWidget(_app(ReceiveScreen(asset: asset), wallets));
      await tester.pumpAndSettle();
      await tester.tap(find.text('USDT · Ethereum'));
      await tester.pumpAndSettle();

      expect(find.text('Ethereum'), findsWidgets);
      expect(find.text('TRON'), findsWidgets);
      expect(find.text('Polygon'), findsWidgets);
      // Solana holds no USDT in this fixture, so offering it would invite a
      // cross-chain mistake the wallet cannot undo.
      expect(find.text('Solana'), findsNothing);
    });

    testWidgets('without an asset it still names the chain\'s own coin', (
      tester,
    ) async {
      final wallets = _wallets();

      await tester.pumpWidget(_app(const ReceiveScreen(), wallets));
      await tester.pumpAndSettle();

      // The generic entry point is unchanged: no asset in hand, so the pill
      // describes the chain.
      expect(find.textContaining(' · '), findsWidgets);
      expect(find.text('USDT · Ethereum'), findsNothing);
    });
  });
}

/// ETH is the gas coin of Ethereum, Base and Arbitrum. Giving each its own row
/// put "Ethereum 0 ETH", "Base 0 ETH" and "Arbitrum 0 ETH" on the home list as
/// though they were three different holdings — the same mistake the registry
/// made with USDC before it was grouped by symbol.
void _nativeGrouping() {
  test('ETH is one asset across Ethereum and its L2s', () {
    final groups = nativesBySymbol();

    expect(groups['ETH']!.map((d) => d.coin), [
      Coin.eth,
      Coin.base,
      Coin.arbitrum,
    ]);
    // The chains that mint their own coin stay single.
    expect(groups['POL'], hasLength(1));
    expect(groups['AVAX'], hasLength(1));
    expect(groups['TRX'], hasLength(1));
    expect(groups['SOL'], hasLength(1));
    // Every supported chain is accounted for exactly once.
    expect(
      groups.values.expand((g) => g).map((d) => d.coin).toSet(),
      Coin.values.toSet(),
    );
  });

  test('a native deployment carries its chain decimals and no contract', () {
    final eth = nativesBySymbol()['ETH']!;
    for (final at in eth) {
      expect(at.decimals, 18, reason: at.network);
      expect(at.contract, isNull);
      expect(at.tokenId, isNull);
      expect(at.isToken, isFalse);
    }
    expect(nativesBySymbol()['TRX']!.single.decimals, 6);
    expect(nativesBySymbol()['SOL']!.single.decimals, 9);
  });

  test('selecting a native chain re-points without changing the symbol', () {
    final ref = AssetRef.group(
      name: 'ETH',
      symbol: 'ETH',
      group: nativesBySymbol()['ETH']!,
    );
    expect(ref.isMultiChain, isTrue);
    // Not a token: nothing here has a contract to send to.
    expect(ref.isToken, isFalse);

    final onBase = ref.selecting(1);
    expect(onBase.symbol, 'ETH');
    expect(onBase.coin, Coin.base);
    expect(onBase.network, 'Base');
    expect(onBase.chainIndex, 1);
    expect(onBase.group, hasLength(3));
  });
}
