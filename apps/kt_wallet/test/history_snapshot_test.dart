import 'dart:convert';

import 'package:core_crypto/core_crypto.dart' show ChainAddresses, Coin;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/market/history_service.dart';
import 'package:kt_wallet/src/market/history_snapshot.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:kt_wallet/src/wallets/wallet_store.dart';
import 'package:wallet_data/wallet_data.dart';

void main() {
  test('history snapshot round-trips and remains network scoped', () async {
    final database = WalletDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final wallet = HotWallet(
      id: 'history-wallet',
      name: 'History',
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
    final store = WalletHistorySnapshotStore(controller);
    final savedAt = DateTime(2026, 7, 30, 15, 30);
    await store.save(
      wallet.id,
      HistorySnapshot(
        scope: 'eth-mainnet|sol-mainnet',
        savedAt: savedAt,
        results: {
          Coin.eth: HistoryResult.ok([
            ChainTxRecord(
              coin: Coin.eth,
              networkId: 'eth-mainnet',
              id: '0xabc:log:1',
              hash: '0xabc',
              outgoing: false,
              fromAddress: '0x2222222222222222222222222222222222222222',
              toAddress: wallet.addresses.eth,
              amountText: '12.5 USDC',
              assetContract: '0x3333333333333333333333333333333333333333',
              assetSymbol: 'USDC',
              timestamp: savedAt.subtract(const Duration(minutes: 2)),
              confirmed: true,
            ),
          ]),
        },
      ),
    );

    final restored = await store.load(wallet.id, 'eth-mainnet|sol-mainnet');
    expect(restored, isNotNull);
    expect(restored!.savedAt, savedAt);
    final record = restored.results[Coin.eth]!.records.single;
    expect(record.id, '0xabc:log:1');
    expect(record.networkId, 'eth-mainnet');
    expect(record.amountText, '12.5 USDC');
    expect(record.assetVerified, isTrue);

    expect(await store.load(wallet.id, 'eth-sepolia|sol-devnet'), isNull);

    final current =
        jsonDecode(
              (await controller.walletSetting(
                wallet.id,
                'history.snapshot.v1',
              ))!,
            )
            as Map<String, dynamic>;
    final currentRecord =
        ((current['results'] as Map)['eth'] as List).single
            as Map<String, dynamic>;
    current['v'] = 1;
    currentRecord.remove('networkId');
    currentRecord['confirmed'] = true;
    currentRecord.remove('status');
    await controller.putWalletSetting(
      wallet.id,
      'history.snapshot.v1',
      jsonEncode(current),
    );
    final legacy = await store.load(wallet.id, 'eth-mainnet|sol-mainnet');
    expect(legacy, isNotNull);
    expect(legacy!.results[Coin.eth]!.records.single.networkId, isNull);
    expect(
      legacy.results[Coin.eth]!.records.single.status,
      ChainTxStatus.confirmed,
    );
  });

  test(
    'history cache rejects ambiguity open records false verification and resource abuse',
    () async {
      final database = WalletDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final wallet = HotWallet(
        id: 'history-boundary-wallet',
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
      final store = WalletHistorySnapshotStore(controller);
      const scope = 'eth-mainnet|sol-mainnet';
      await store.save(
        wallet.id,
        HistorySnapshot(
          scope: scope,
          savedAt: DateTime(2026, 8, 5),
          results: {
            Coin.eth: HistoryResult.ok([
              ChainTxRecord(
                coin: Coin.eth,
                networkId: 'eth-mainnet',
                hash:
                    '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                outgoing: false,
                fromAddress: '0x2222222222222222222222222222222222222222',
                toAddress: wallet.addresses.eth,
                amountText: '1 USDC',
                assetContract: '0x3333333333333333333333333333333333333333',
                assetSymbol: 'USDC',
                assetVerified: false,
                timestamp: DateTime(2026, 8, 5),
                status: ChainTxStatus.confirmed,
              ),
            ]),
          },
        ),
      );
      final valid = (await controller.walletSetting(
        wallet.id,
        'history.snapshot.v1',
      ))!;
      final validSnapshot = await store.load(wallet.id, scope);
      expect(
        validSnapshot!.results[Coin.eth]!.records.single.assetVerified,
        isFalse,
      );
      final decoded = (jsonDecode(valid) as Map).cast<String, Object?>();
      final results = (decoded['results']! as Map).cast<String, Object?>();
      final record = ((results['eth']! as List).single as Map)
          .cast<String, Object?>();
      final missingVerifiedRecord = <String, Object?>{...record}
        ..remove('verified');
      final missingVerified = <String, Object?>{
        ...decoded,
        'results': {
          'eth': [missingVerifiedRecord],
        },
      };
      final unknownRecord = <String, Object?>{
        ...decoded,
        'results': {
          'eth': [
            <String, Object?>{...record, 'memo': 'ignored'},
          ],
        },
      };
      final tooManyRecords = <String, Object?>{
        ...decoded,
        'results': {'eth': List<Object?>.filled(101, record)},
      };
      final hugeRecord = <String, Object?>{
        ...decoded,
        'results': {
          'eth': [
            <String, Object?>{...record, 'amount': 'x' * 1048576},
          ],
        },
      };

      final malformed = <String>[
        valid.replaceFirst(
          '"scope":"$scope"',
          '"scope":"wrong","scope":"$scope"',
        ),
        valid.replaceFirst(
          '"scope":"$scope"',
          '"scope":"wrong","sc\\u006fpe":"$scope"',
        ),
        valid.replaceFirst(
          '"verified":false',
          '"verified":false,"verified":true',
        ),
        '${valid.substring(0, valid.length - 1)},"memo":"ignored"}',
        jsonEncode(missingVerified),
        jsonEncode(unknownRecord),
        jsonEncode(tooManyRecords),
        jsonEncode(hugeRecord),
      ];
      for (final value in malformed) {
        await controller.putWalletSetting(
          wallet.id,
          'history.snapshot.v1',
          value,
        );
        expect(
          await store.load(wallet.id, scope),
          isNull,
          reason: 'accepted malformed cache: ${value.length} chars',
        );
      }
    },
  );
}
