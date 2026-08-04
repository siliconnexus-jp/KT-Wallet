import 'dart:convert';

import 'package:chains/chains.dart' show Amount;
import 'package:core_crypto/core_crypto.dart' show ChainAddresses, Coin;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/market/balance_service.dart';
import 'package:kt_wallet/src/market/market_snapshot.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:kt_wallet/src/wallets/wallet_store.dart';
import 'package:wallet_data/wallet_data.dart';

void main() {
  test(
    'market snapshot persists per wallet and rejects another scope',
    () async {
      final database = WalletDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final wallet = HotWallet(
        id: 'wallet-1',
        name: 'Wallet',
        avatarColor: 0xFF000000,
        addresses: const ChainAddresses(
          eth: '0x1111111111111111111111111111111111111111',
          polygon: '0x1111111111111111111111111111111111111111',
          tron: 'TJRabPrwbZy45sbavfcjinPJC18kjpRTv8',
          solana: '11111111111111111111111111111111',
        ),
        backedUp: true,
      );
      final walletStore = WalletStore(database);
      await walletStore.save(wallet);
      final controller = WalletController(
        WalletManager(initial: [wallet]),
        store: walletStore,
      );
      final snapshots = WalletMarketSnapshotStore(controller);
      final savedAt = DateTime(2026, 7, 30, 12);
      await snapshots.save(
        wallet.id,
        MarketSnapshot(
          scope: 'eth-mainnet|sol-mainnet',
          savedAt: savedAt,
          native: {
            Coin.eth: BalanceResult.ok(
              Amount(
                raw: BigInt.parse('1230000000000000000'),
                decimals: 18,
                symbol: 'ETH',
              ),
            ),
          },
          tokens: {
            'usdc-eth': BalanceResult.ok(
              Amount(raw: BigInt.from(2500000), decimals: 6, symbol: 'USDC'),
            ),
          },
          nativePrices: const {Coin.eth: 3200},
          tokenPrices: const {'USDC': 1},
          nativeChanges: const {Coin.eth: 2.5},
          tokenChanges: const {'USDC': -0.01},
          fiatPerUsd: const {'USD': 1, 'CNY': 7.1, 'JPY': 151},
        ),
      );

      final restored = await snapshots.load(
        wallet.id,
        'eth-mainnet|sol-mainnet',
      );
      expect(restored, isNotNull);
      expect(restored!.savedAt, savedAt);
      expect(restored.native[Coin.eth]!.amount!.format(), '1.23');
      expect(restored.tokens['usdc-eth']!.amount!.format(), '2.5');
      expect(restored.nativePrices[Coin.eth], 3200);
      expect(restored.tokenChanges['USDC'], -0.01);
      expect(restored.fiatPerUsd['CNY'], 7.1);

      expect(await snapshots.load(wallet.id, 'eth-sepolia|sol-devnet'), isNull);

      final current =
          jsonDecode(
                (await controller.walletSetting(
                  wallet.id,
                  'market.snapshot.v1',
                ))!,
              )
              as Map<String, dynamic>;
      current['v'] = 1;
      current.remove('fiatPerUsd');
      await controller.putWalletSetting(
        wallet.id,
        'market.snapshot.v1',
        jsonEncode(current),
      );
      final legacy = await snapshots.load(wallet.id, 'eth-mainnet|sol-mainnet');
      expect(legacy, isNotNull);
      expect(legacy!.fiatPerUsd, const {'USD': 1});
    },
  );

  test(
    'market cache rejects ambiguous open unbounded and invalid financial state',
    () async {
      final database = WalletDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final wallet = HotWallet(
        id: 'market-boundary-wallet',
        name: 'Boundary',
        avatarColor: 0xFF000000,
        addresses: const ChainAddresses(
          eth: '0x1111111111111111111111111111111111111111',
          polygon: '0x1111111111111111111111111111111111111111',
          tron: 'TJRabPrwbZy45sbavfcjinPJC18kjpRTv8',
          solana: '11111111111111111111111111111111',
        ),
        backedUp: true,
      );
      final walletStore = WalletStore(database);
      await walletStore.save(wallet);
      final controller = WalletController(
        WalletManager(initial: [wallet]),
        store: walletStore,
      );
      final snapshots = WalletMarketSnapshotStore(controller);
      const scope = 'eth-mainnet|sol-mainnet';
      await snapshots.save(
        wallet.id,
        MarketSnapshot(
          scope: scope,
          savedAt: DateTime(2026, 8, 5),
          native: {
            Coin.eth: BalanceResult.ok(
              Amount(raw: BigInt.one, decimals: 18, symbol: 'ETH'),
            ),
          },
          tokens: const {},
          nativePrices: const {Coin.eth: 3200},
          tokenPrices: const {'USDC': 1},
          nativeChanges: const {Coin.eth: 1},
          tokenChanges: const {'USDC': 0},
          fiatPerUsd: const {'USD': 1, 'CNY': 7, 'JPY': 150},
        ),
      );
      final valid = (await controller.walletSetting(
        wallet.id,
        'market.snapshot.v1',
      ))!;
      final decoded = (jsonDecode(valid) as Map).cast<String, Object?>();
      final negativePrice = <String, Object?>{...decoded};
      negativePrice['nativePrices'] = {'eth': -1};
      final unknownCoin = <String, Object?>{...decoded};
      unknownCoin['nativePrices'] = {'eth': 3200, 'bitcoin': 1};

      final malformed = <String>[
        valid.replaceFirst(
          '"scope":"$scope"',
          '"scope":"wrong","scope":"$scope"',
        ),
        valid.replaceFirst(
          '"scope":"$scope"',
          '"scope":"wrong","sc\\u006fpe":"$scope"',
        ),
        valid.replaceFirst('"raw":"1"', '"raw":"1","raw":"2"'),
        valid.replaceFirst('"raw":"1"', '"raw":"1","memo":"ignored"'),
        '${valid.substring(0, valid.length - 1)},"memo":"ignored"}',
        jsonEncode(negativePrice),
        jsonEncode(unknownCoin),
        valid.replaceFirst('"USDC":1.0', '"${'x' * 262144}":1.0'),
      ];
      for (final value in malformed) {
        await controller.putWalletSetting(
          wallet.id,
          'market.snapshot.v1',
          value,
        );
        expect(
          await snapshots.load(wallet.id, scope),
          isNull,
          reason: 'accepted malformed cache: ${value.length} chars',
        );
      }
    },
  );
}
