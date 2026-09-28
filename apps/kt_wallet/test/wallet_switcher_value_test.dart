import 'package:chains/chains.dart' show Amount;
import 'package:core_crypto/core_crypto.dart' show ChainAddresses, Coin;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/market/balance_service.dart';
import 'package:kt_wallet/src/market/market_controller.dart';
import 'package:kt_wallet/src/market/market_scope.dart';
import 'package:kt_wallet/src/market/market_snapshot.dart';
import 'package:kt_wallet/src/market/price_service.dart';
import 'package:kt_wallet/src/screens/wallet_screens.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/state/wallet_scope.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';

class _Balances extends BalanceService {
  @override
  Future<Map<Coin, BalanceResult>> fetchAll(
    ChainAddresses addresses, {
    BalanceResultCallback? onResult,
  }) async => {
    Coin.eth: BalanceResult.ok(
      Amount(
        raw: BigInt.parse('1000000000000000000'),
        decimals: 18,
        symbol: 'ETH',
      ),
    ),
  };
}

class _Prices extends PriceService {
  @override
  Future<Map<Coin, double>?> fetchUsdPrices() async => const {Coin.eth: 2000};
  @override
  Map<Coin, double>? get lastGoodUsd => null;
  @override
  double? tokenPriceUsd(String symbol) => null;
}

/// Only wallet 'b' has a saved snapshot; 'c' was never loaded on this device.
class _Snapshots implements MarketSnapshotStore {
  @override
  Future<MarketSnapshot?> load(String walletId, String scope) async =>
      walletId != 'b'
      ? null
      : MarketSnapshot(
          scope: scope,
          savedAt: DateTime(2026, 9, 1),
          native: {
            Coin.eth: BalanceResult.ok(
              Amount(
                raw: BigInt.parse('250000000000000000'),
                decimals: 18,
                symbol: 'ETH',
              ),
            ),
          },
          tokens: const {},
          nativePrices: const {Coin.eth: 1000},
          tokenPrices: const {},
          nativeChanges: const {},
          tokenChanges: const {},
        );

  @override
  Future<void> save(String walletId, MarketSnapshot snapshot) async {}
}

ChainAddresses _addr(String seed) => ChainAddresses(
  eth: '0x$seed',
  polygon: '0x$seed',
  tron: 'T$seed',
  solana: seed,
);

HotWallet _wallet(String id, int order) => HotWallet(
  id: id,
  name: id.toUpperCase(),
  avatarColor: 0xFF000000,
  addresses: _addr(id * 3),
  sortOrder: order,
  backedUp: true,
);

void main() {
  testWidgets('switcher shows live and cached wallet values', (tester) async {
    final wallets = WalletController(
      WalletManager(
        initial: [_wallet('a', 0), _wallet('b', 1), _wallet('c', 2)],
      ),
    );
    final market = MarketController(
      wallets: wallets,
      balances: _Balances(),
      prices: _Prices(),
      snapshots: _Snapshots(),
      snapshotScope: () => 'mainnet',
    );
    addTearDown(market.dispose);
    await market.refresh();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: WalletScope(
          controller: wallets,
          child: MarketScope(
            controller: market,
            child: const WalletSwitcherSheet(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Active wallet: live 1 ETH × $2000. Wallet b: cached 0.25 ETH valued at
    // this session's live quote. Wallet c: unknown, never a fake $0.00.
    expect(find.text(r'$2,000.00'), findsOneWidget);
    expect(find.text(r'$500.00'), findsOneWidget);
    expect(find.text('--'), findsOneWidget);
    expect(find.text(r'$0.00'), findsNothing);
  });
}
