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
  });
}
