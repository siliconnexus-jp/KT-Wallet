import 'package:core_crypto/core_crypto.dart' show ChainAddresses, Coin;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/market/asset_ref.dart';
import 'package:kt_wallet/src/market/token_balance_service.dart';
import 'package:kt_wallet/src/screens/assets_screens.dart';
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

Widget _app(Widget home, WalletController wallets) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: WalletScope(controller: wallets, child: home),
);

void main() {
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
      expect(onTron.group, _usdtGroup);
      expect(onTron.chainIndex, 1);
    });

    test('an out-of-range index clamps instead of throwing', () {
      final ref = AssetRef.tokenGroup(_usdtGroup);
      expect(ref.selecting(99).coin, usdtPolygonToken.chain);
      expect(ref.selecting(-1).coin, usdtEthToken.chain);
    });

    test('a native coin is returned untouched', () {
      const ref = AssetRef.native(
        coin: Coin.eth,
        name: 'Ethereum',
        symbol: 'ETH',
      );
      expect(identical(ref.selecting(3), ref), isTrue);
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
