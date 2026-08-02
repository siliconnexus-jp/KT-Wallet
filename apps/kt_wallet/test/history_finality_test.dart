import 'package:core_crypto/core_crypto.dart' show ChainAddresses, Coin;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/market/history_controller.dart';
import 'package:kt_wallet/src/market/history_service.dart';
import 'package:kt_wallet/src/market/transaction_status_service.dart';
import 'package:kt_wallet/src/observability/experience_metrics.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:kt_wallet/src/wallets/wallet_store.dart';
import 'package:wallet_data/wallet_data.dart';

class _History extends HistoryService {
  _History({this.results = const {}});

  final Map<Coin, HistoryResult> results;

  @override
  Future<HistoryResult> fetch(
    Coin coin,
    String address, {
    int limit = HistoryService.pageSize,
    String? networkId,
  }) async => results[coin] ?? const HistoryResult.unsupported();
}

class _StatusService extends TransactionStatusService {
  _StatusService(this.status);

  final ChainTransactionStatus status;

  @override
  Future<ChainTransactionStatus> check(Transaction transaction) async => status;
}

Future<
  ({
    WalletController wallets,
    WalletDatabase database,
    HistoryController history,
  })
>
_fixture({
  required HistoryResult remote,
  required ChainTransactionStatus hashStatus,
  Coin localCoin = Coin.eth,
  String localNetworkId = 'eth-mainnet',
  String? localHash,
  Coin remoteCoin = Coin.eth,
}) async {
  final database = WalletDatabase(NativeDatabase.memory());
  final wallet = HotWallet(
    id: 'w-finality',
    name: 'Finality',
    avatarColor: 0xFF000000,
    addresses: const ChainAddresses(
      eth: '0x1111111111111111111111111111111111111111',
      polygon: '0x1111111111111111111111111111111111111111',
      tron: 'TJRabPrwbZy45sbavfcjinPJC18kjpRTv8',
      solana: '11111111111111111111111111111111',
    ),
    backedUp: true,
  );
  final store = WalletStore(database);
  await store.save(wallet);
  final wallets = WalletController(
    WalletManager(initial: [wallet]),
    store: store,
  );
  await wallets.saveOutgoingTransaction(
    id: 'local-pending',
    coin: localCoin,
    networkId: localNetworkId,
    from: switch (localCoin) {
      Coin.polygon => wallet.addresses.polygon,
      Coin.solana => wallet.addresses.solana,
      Coin.tron => wallet.addresses.tron,
      _ => wallet.addresses.eth,
    },
    to: '0x2222222222222222222222222222222222222222',
    amountRaw: '1000000000000000',
    hash: localHash ?? '0x${'a' * 64}',
    status: TxStatus.pending,
    signMode: SignMode.local,
    createdAt: DateTime.now()
        .subtract(const Duration(hours: 72))
        .millisecondsSinceEpoch,
    broadcastAt: DateTime.now()
        .subtract(const Duration(hours: 71))
        .millisecondsSinceEpoch,
  );
  final history = HistoryController(
    wallets: wallets,
    service: _History(results: {remoteCoin: remote}),
    statusService: _StatusService(hashStatus),
    activeNetworkIds: () => {'eth-mainnet', localNetworkId},
    pollInterval: const Duration(days: 1),
  );
  return (wallets: wallets, database: database, history: history);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(ExperienceMetrics.instance.clear);

  test('a 72-hour history miss never invents a dropped transaction', () async {
    final fixture = await _fixture(
      remote: const HistoryResult.ok([]),
      hashStatus: ChainTransactionStatus.unknown,
    );
    addTearDown(fixture.history.dispose);
    addTearDown(fixture.database.close);

    await fixture.history.refresh();

    final row = await fixture.wallets.localTransactionById('local-pending');
    expect(row?.status, TxStatus.pending);
    expect(
      row?.lastCheckedAt,
      isNotNull,
      reason: 'an unknown result still records when the chain lookup ran',
    );
    expect(row?.lastCheckOutcome, TxCheckOutcome.unknown);
    expect(
      fixture.history.records.single.status,
      ChainTxStatus.unknown,
      reason: 'the UI must not keep claiming an unproven pending state',
    );
    expect(fixture.history.records.single.networkId, 'eth-mainnet');
  });

  test('remote unknown status never becomes failed', () async {
    final fixture = await _fixture(
      remote: HistoryResult.ok([
        ChainTxRecord(
          coin: Coin.eth,
          networkId: 'eth-mainnet',
          hash: '0x${'a' * 64}',
          outgoing: true,
          amountText: '0.001 ETH',
          timestamp: DateTime.now(),
          status: ChainTxStatus.unknown,
        ),
      ]),
      hashStatus: ChainTransactionStatus.unknown,
    );
    addTearDown(fixture.history.dispose);
    addTearDown(fixture.database.close);

    await fixture.history.refresh();

    final row = await fixture.wallets.localTransactionById('local-pending');
    expect(row?.status, TxStatus.pending);
    expect(row?.lastCheckOutcome, TxCheckOutcome.unknown);
    expect(fixture.history.records.single.status, ChainTxStatus.unknown);
  });

  test(
    'explicit pending evidence restores the live pending presentation',
    () async {
      final fixture = await _fixture(
        remote: const HistoryResult.ok([]),
        hashStatus: ChainTransactionStatus.pending,
      );
      addTearDown(fixture.history.dispose);
      addTearDown(fixture.database.close);

      await fixture.history.refresh();

      final row = await fixture.wallets.localTransactionById('local-pending');
      expect(row?.status, TxStatus.pending);
      expect(row?.lastCheckOutcome, TxCheckOutcome.pending);
      expect(fixture.history.records.single.status, ChainTxStatus.pending);
    },
  );

  test('only an explicit remote failure settles the row as failed', () async {
    final fixture = await _fixture(
      remote: HistoryResult.ok([
        ChainTxRecord(
          coin: Coin.eth,
          networkId: 'eth-mainnet',
          hash: '0x${'A' * 64}',
          outgoing: true,
          amountText: '0.001 ETH',
          timestamp: DateTime.now(),
          status: ChainTxStatus.failed,
        ),
      ]),
      hashStatus: ChainTransactionStatus.unknown,
    );
    addTearDown(fixture.history.dispose);
    addTearDown(fixture.database.close);

    await fixture.history.refresh();

    final row = await fixture.wallets.localTransactionById('local-pending');
    expect(row?.status, TxStatus.failed);
  });

  test(
    'same hash on another chain cannot settle or hide local Pending',
    () async {
      final hash = '0x${'a' * 64}';
      final fixture = await _fixture(
        remote: HistoryResult.ok([
          ChainTxRecord(
            coin: Coin.eth,
            networkId: 'eth-mainnet',
            hash: hash,
            outgoing: true,
            amountText: '0.001 ETH',
            timestamp: DateTime.now(),
            status: ChainTxStatus.confirmed,
          ),
        ]),
        hashStatus: ChainTransactionStatus.unknown,
        localCoin: Coin.polygon,
        localNetworkId: 'polygon-mainnet',
      );
      addTearDown(fixture.history.dispose);
      addTearDown(fixture.database.close);

      await fixture.history.refresh();

      final local = await fixture.wallets.localTransactionById('local-pending');
      expect(local?.status, TxStatus.pending);
      final collisions = fixture.history.records
          .where((record) => record.hash == hash)
          .toList();
      expect(collisions, hasLength(2));
      expect(
        collisions.map((record) => (record.coin, record.networkId)).toSet(),
        {(Coin.eth, 'eth-mainnet'), (Coin.polygon, 'polygon-mainnet')},
      );
      final ethereum = collisions.singleWhere(
        (record) => record.coin == Coin.eth,
      );
      final polygon = collisions.singleWhere(
        (record) => record.coin == Coin.polygon,
      );
      expect(fixture.history.localTransactionForRecord(ethereum), isNull);
      expect(
        fixture.history.localTransactionForRecord(polygon)?.id,
        'local-pending',
      );
    },
  );

  test('Solana signatures remain case-sensitive history identities', () async {
    final localHash = '3sAbC${'1' * 60}';
    final remoteHash = '3saBc${'1' * 60}';
    final fixture = await _fixture(
      remote: HistoryResult.ok([
        ChainTxRecord(
          coin: Coin.solana,
          networkId: 'sol-mainnet',
          hash: remoteHash,
          outgoing: true,
          amountText: '0.001 SOL',
          timestamp: DateTime.now(),
          status: ChainTxStatus.confirmed,
        ),
      ]),
      hashStatus: ChainTransactionStatus.unknown,
      localCoin: Coin.solana,
      localNetworkId: 'sol-mainnet',
      localHash: localHash,
      remoteCoin: Coin.solana,
    );
    addTearDown(fixture.history.dispose);
    addTearDown(fixture.database.close);

    await fixture.history.refresh();

    final local = await fixture.wallets.localTransactionById('local-pending');
    expect(local?.status, TxStatus.pending);
    expect(fixture.history.records.map((record) => record.hash).toSet(), {
      localHash,
      remoteHash,
    });
  });

  test('chain-authoritative expiration settles the row as expired', () async {
    final fixture = await _fixture(
      remote: const HistoryResult.ok([]),
      hashStatus: ChainTransactionStatus.expired,
    );
    addTearDown(fixture.history.dispose);
    addTearDown(fixture.database.close);

    await fixture.history.refresh();

    final row = await fixture.wallets.localTransactionById('local-pending');
    expect(row?.status, TxStatus.expired);
    final notices = fixture.history.takeNotices();
    expect(notices, hasLength(1));
    expect(notices.single.confirmed, isFalse);
    final finality = ExperienceMetrics.instance.recent.singleWhere(
      (metric) => metric.name == ExperienceMetricNames.transactionFinality,
    );
    expect(finality.success, isFalse);
    expect(finality.duration, greaterThan(const Duration(hours: 70)));
  });
}
