import 'dart:typed_data';

import 'package:chains/chains.dart';
import 'package:core_crypto/core_crypto.dart' show ChainAddresses, Coin;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/app_router.dart';
import 'package:kt_wallet/src/market/asset_ref.dart';
import 'package:kt_wallet/src/market/balance_service.dart';
import 'package:kt_wallet/src/market/market_controller.dart';
import 'package:kt_wallet/src/market/market_scope.dart';
import 'package:kt_wallet/src/screens/assets_screens.dart';
import 'package:kt_wallet/src/screens/transfer_screens.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/transfer/local_transfer_service.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart';

import 'support/test_wallet_scope.dart';

class _UnactivatedMarket extends MarketController {
  _UnactivatedMarket({required super.wallets});
  @override
  TronActivationStatus get tronActivationStatus =>
      TronActivationStatus.unactivated;
  @override
  Future<void> refresh() async {}
  @override
  bool get hasRefreshed => true;
  @override
  BalanceResult balanceFor(Coin coin) => BalanceResult.ok(
    Amount.parse('100', BalanceService.decimalsFor[coin]!, symbol: coin.name),
  );
}

class _TronQuote extends LocalTransferService {
  _TronQuote({required this.unactivated});
  final bool unactivated;
  @override
  Future<PreparedTronTransfer> prepareTron({
    required TransferDraft draft,
    required String from,
    required String? expectedNetworkIdentity,
  }) async {
    if (unactivated) throw const TronAccountNotActivated();
    return PreparedTronTransfer(
      from: from,
      recipient: draft.recipient,
      amountRaw: draft.amount.raw,
      tokenContract: draft.tokenContract,
      maximumFeeSun: BigInt.from(1000000),
      referenceBlockHeight: 42,
      expiresAt: 9999999999,
      rawTx: Uint8List.fromList([10, 11, 12]),
    );
  }
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  final wallet = WalletController(
    WalletManager(
      initial: [
        HotWallet(
          id: 'tron-scope-test',
          name: 'Test wallet',
          avatarColor: 0xFFF59E0B,
          backedUp: true,
          addresses: const ChainAddresses(
            eth: '0x196EB86d0D146de3B556F8e5D9F4Bed0fb921110',
            polygon: '0x196EB86d0D146de3B556F8e5D9F4Bed0fb921110',
            base: '0x196EB86d0D146de3B556F8e5D9F4Bed0fb921110',
            tron: 'TNXoiAJ3dct8Fjg4M9fkLFh9S2v9TXc32G',
            solana: 'ayKpXwMWd4qmDqVr2W',
          ),
        ),
      ],
    ),
    allowTestBypass: true,
  );
  final market = _UnactivatedMarket(wallets: wallet);
  addTearDown(market.dispose);
  addTearDown(wallet.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: ktWalletTheme(),
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: withTestWalletScope(
        MarketScope(controller: market, child: child),
        controller: wallet,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final notice = find.byKey(const ValueKey('tron-activation-notice'));
  for (final entry in screenRegistry.entries.where(
    (entry) => const {
      '/home',
      '/wallet-detail',
      '/wallet-manage',
      '/wallet-addresses',
      '/assets',
      '/network',
      '/security',
      '/token-manage',
      '/address-book',
    }.contains(entry.value.$1),
  )) {
    testWidgets(
      '${entry.value.$1} does not promote TRON state to a wallet warning',
      (tester) async {
        await _pump(tester, Builder(builder: entry.value.$2));
        expect(notice, findsNothing);
        expect(find.textContaining('此 TRON 地址尚未激活'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final coin in Coin.values) {
    testWidgets('${coin.name} receive only shows its own chain guidance', (
      tester,
    ) async {
      await _pump(tester, ReceiveScreen(initialCoin: coin));
      expect(notice, coin == Coin.tron ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
    });
    testWidgets('${coin.name} transfer only shows its own chain guidance', (
      tester,
    ) async {
      await _pump(
        tester,
        TransferInputScreen(
          asset: AssetRef.native(
            coin: coin,
            symbol: coin.name.toUpperCase(),
            name: coin.name,
            network: coin.name,
          ),
        ),
      );
      expect(notice, coin == Coin.tron ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final unactivated in [false, true]) {
    testWidgets(
      'input uses fresh quote activation=$unactivated over stale market state',
      (tester) async {
        await _pump(
          tester,
          TransferInputScreen(
            asset: AssetRef.native(
              coin: Coin.tron,
              name: 'TRON',
              network: 'TRON',
              symbol: 'TRX',
            ),
            transferService: _TronQuote(unactivated: unactivated),
          ),
        );
        expect(notice, findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('transfer-recipient-input')),
          'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
        );
        await tester.enterText(
          find.byKey(const ValueKey('transfer-amount-input')),
          '1',
        );
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();
        expect(notice, unactivated ? findsOneWidget : findsNothing);
        final button = tester.widget<KtPrimaryButton>(
          find.byType(KtPrimaryButton),
        );
        expect(button.onPressed == null, unactivated);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'confirmation uses current quote activation=$unactivated, not stale market state',
      (tester) async {
        final session = TransferSession()
          ..draft = TransferDraft(
            symbol: 'TRX',
            networkLabel: 'TRON',
            chain: Chain.tron,
            recipient: 'TWd4qCEUf3aVpXe2HKk9gJt6nMxR38uQz',
            amount: Amount.parse('1', 6, symbol: 'TRX'),
            feeTier: 1,
          );
        await _pump(
          tester,
          TransferSessionScope(
            session: session,
            child: TransferConfirmScreen(
              isHot: true,
              transferService: _TronQuote(unactivated: unactivated),
            ),
          ),
        );
        expect(notice, unactivated ? findsOneWidget : findsNothing);
        final button = tester.widget<KtPrimaryButton>(
          find.byType(KtPrimaryButton),
        );
        expect(button.onPressed == null, unactivated);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );
  }
}
