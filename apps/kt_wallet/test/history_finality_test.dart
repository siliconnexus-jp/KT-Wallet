import 'dart:async';

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

class _ConcurrencyStatusService extends TransactionStatusService {
  int active = 0;
  int maxActive = 0;
  int calls = 0;

  @override
  Future<ChainTransactionStatus> check(Transaction transaction) async {
    calls++;
    active++;
    if (active > maxActive) maxActive = active;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    active--;
    return ChainTransactionStatus.pending;
  }
}

class _PartiallyThrowingStatusService extends TransactionStatusService {
  @override
  Future<ChainTransactionStatus> check(Transaction transaction) async {
    if (transaction.id == 'local-pending-1') {
      throw StateError('provider implementation failed');
    }
    return ChainTransactionStatus.pending;
  }
}

class _GatedStatusService extends TransactionStatusService {
  final gate = Completer<void>();
  int calls = 0;

  @override
  Future<ChainTransactionStatus> check(Transaction transaction) async {
    calls++;
    await gate.future;
    return ChainTransactionStatus.pending;
  }
}

class _RacingReplacementStatusService extends TransactionStatusService {
  final releaseOriginal = Completer<void>();

  @override
  Future<ChainTransactionStatus> check(Transaction transaction) async {
    if (transaction.id == 'local-pending') {
      await releaseOriginal.future;
      return ChainTransactionStatus.pending;
    }
    if (transaction.id == 'local-replacement') {
      return ChainTransactionStatus.confirmed;
    }
    return ChainTransactionStatus.unknown;
  }
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
  Set<String>? activeNetworkIds,
  int pendingCount = 1,
  TransactionStatusService? statusService,
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
  for (var index = 0; index < pendingCount; index++) {
    await wallets.saveOutgoingTransaction(
      id: index == 0 ? 'local-pending' : 'local-pending-$index',
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
      hash:
          localHash ??
          (index == 0
              ? '0x${'a' * 64}'
              : '0x${index.toRadixString(16).padLeft(64, '0')}'),
      status: TxStatus.pending,
      signMode: SignMode.local,
      createdAt: DateTime.now()
          .subtract(Duration(hours: 72, seconds: index))
          .millisecondsSinceEpoch,
      broadcastAt: DateTime.now()
          .subtract(Duration(hours: 71, seconds: index))
          .millisecondsSinceEpoch,
    );
  }
  final history = HistoryController(
    wallets: wallets,
    service: _History(results: {remoteCoin: remote}),
    statusService: statusService ?? _StatusService(hashStatus),
    activeNetworkIds: () => activeNetworkIds ?? {'eth-mainnet', localNetworkId},
    pollInterval: const Duration(days: 1),
  );
  return (wallets: wallets, database: database, history: history);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(ExperienceMetrics.instance.clear);

  test('Pending finality checks use bounded concurrency', () async {
    final statuses = _ConcurrencyStatusService();
    final fixture = await _fixture(
      remote: const HistoryResult.ok([]),
      hashStatus: ChainTransactionStatus.pending,
      pendingCount: 12,
      statusService: statuses,
    );
    addTearDown(fixture.history.dispose);
    addTearDown(fixture.database.close);

    await fixture.history.refresh();

    expect(statuses.calls, 12);
    expect(statuses.maxActive, HistoryController.pendingStatusConcurrency);
  });

  test('superseded reconciliation never starts queued hash lookups', () async {
    final statuses = _GatedStatusService();
    final fixture = await _fixture(
      remote: const HistoryResult.ok([]),
      hashStatus: ChainTransactionStatus.pending,
      pendingCount: 12,
      statusService: statuses,
    );
    addTearDown(fixture.database.close);

    final refresh = fixture.history.refresh();
    while (statuses.calls < HistoryController.pendingStatusConcurrency) {
      await Future<void>.delayed(Duration.zero);
    }
    fixture.history.dispose();
    statuses.gate.complete();
    await refresh;

    expect(statuses.calls, HistoryController.pendingStatusConcurrency);
  });

  test(
    'one status provider exception stays unknown and does not abort peers',
    () async {
      final fixture = await _fixture(
        remote: const HistoryResult.ok([]),
        hashStatus: ChainTransactionStatus.pending,
        pendingCount: 3,
        statusService: _PartiallyThrowingStatusService(),
      );
      addTearDown(fixture.history.dispose);
      addTearDown(fixture.database.close);

      await fixture.history.refresh();

      final failedLookup = await fixture.wallets.localTransactionById(
        'local-pending-1',
      );
      final healthyPeer = await fixture.wallets.localTransactionById(
        'local-pending-2',
      );
      expect(failedLookup?.status, TxStatus.pending);
      expect(failedLookup?.lastCheckOutcome, TxCheckOutcome.unknown);
      expect(healthyPeer?.lastCheckOutcome, TxCheckOutcome.pending);
    },
  );

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
    final finality = ExperienceMetrics.instance.recent.singleWhere(
      (metric) => metric.name == ExperienceMetricNames.transactionFinality,
    );
    expect(finality.success, isFalse);
    expect(finality.duration, greaterThan(const Duration(hours: 70)));
  });

  test(
    'chain-authoritative replacement wins over history and records once',
    () async {
      final fixture = await _fixture(
        remote: HistoryResult.ok([
          ChainTxRecord(
            coin: Coin.eth,
            networkId: 'eth-mainnet',
            hash: '0x${'a' * 64}',
            outgoing: true,
            amountText: '0.001 ETH',
            timestamp: DateTime.now(),
            status: ChainTxStatus.confirmed,
          ),
        ]),
        hashStatus: ChainTransactionStatus.replaced,
      );
      addTearDown(fixture.history.dispose);
      addTearDown(fixture.database.close);

      await fixture.history.refresh();

      final row = await fixture.wallets.localTransactionById('local-pending');
      expect(row?.status, TxStatus.replaced);
      final finality = ExperienceMetrics.instance.recent.singleWhere(
        (metric) => metric.name == ExperienceMetricNames.transactionFinality,
      );
      expect(finality.success, isFalse);
      expect(finality.duration, greaterThan(const Duration(hours: 70)));
    },
  );

  test(
    'late pending evidence cannot undo replacement lineage or hide finality',
    () async {
      final statuses = _RacingReplacementStatusService();
      final fixture = await _fixture(
        remote: const HistoryResult.ok([]),
        hashStatus: ChainTransactionStatus.unknown,
        statusService: statuses,
      );
      addTearDown(fixture.history.dispose);
      addTearDown(fixture.database.close);
      final now = DateTime.now();
      await fixture.wallets.saveOutgoingTransaction(
        id: 'local-replacement',
        coin: Coin.eth,
        networkId: 'eth-mainnet',
        from: '0x1111111111111111111111111111111111111111',
        to: '0x2222222222222222222222222222222222222222',
        amountRaw: '1000000000000000',
        hash: '0x${'b' * 64}',
        status: TxStatus.pending,
        signMode: SignMode.local,
        createdAt: now
            .subtract(const Duration(hours: 72))
            .millisecondsSinceEpoch,
        broadcastAt: now
            .subtract(const Duration(hours: 71))
            .millisecondsSinceEpoch,
        nonce: '7',
        replacesId: 'local-pending',
        replacementKind: TxReplacementKind.speedUp,
      );

      final refresh = fixture.history.refresh();
      while ((await fixture.wallets.localTransactionById(
            'local-pending',
          ))?.status !=
          TxStatus.replaced) {
        await Future<void>.delayed(Duration.zero);
      }
      statuses.releaseOriginal.complete();
      await refresh;

      final original = await fixture.wallets.localTransactionById(
        'local-pending',
      );
      final replacement = await fixture.wallets.localTransactionById(
        'local-replacement',
      );
      expect(original?.status, TxStatus.replaced);
      expect(original?.replacedById, 'local-replacement');
      expect(replacement?.status, TxStatus.confirmed);
      final finality = ExperienceMetrics.instance.recent
          .where(
            (metric) =>
                metric.name == ExperienceMetricNames.transactionFinality,
          )
          .toList(growable: false);
      expect(finality, hasLength(2));
      expect(finality.where((metric) => metric.success), hasLength(1));
      expect(finality.where((metric) => !metric.success), hasLength(1));
    },
  );

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

  test(
    'duplicate EVM events are case-insensitively merged before rendering',
    () async {
      final lowerHash = '0x${'a' * 64}';
      final upperHash = '0x${'A' * 64}';
      final fixture = await _fixture(
        remote: HistoryResult.ok([
          ChainTxRecord(
            coin: Coin.eth,
            networkId: 'eth-mainnet',
            hash: lowerHash,
            id: lowerHash,
            outgoing: true,
            amountText: '0.001 ETH',
            timestamp: DateTime(2026, 8, 3, 12),
            status: ChainTxStatus.confirmed,
          ),
          ChainTxRecord(
            coin: Coin.eth,
            networkId: 'eth-mainnet',
            hash: upperHash,
            id: upperHash,
            outgoing: true,
            amountText: '0.001 ETH',
            timestamp: DateTime(2026, 8, 3, 12),
            status: ChainTxStatus.confirmed,
          ),
        ]),
        hashStatus: ChainTransactionStatus.unknown,
      );
      addTearDown(fixture.history.dispose);
      addTearDown(fixture.database.close);

      await fixture.history.refresh();

      expect(fixture.history.records, hasLength(1));
      expect(
        (await fixture.wallets.localTransactionById('local-pending'))?.status,
        TxStatus.confirmed,
      );
    },
  );

  test(
    'different transfer events in one EVM transaction stay distinct',
    () async {
      final hash = '0x${'a' * 64}';
      final fixture = await _fixture(
        remote: HistoryResult.ok([
          ChainTxRecord(
            coin: Coin.eth,
            networkId: 'eth-mainnet',
            hash: hash,
            id: hash,
            outgoing: true,
            amountText: '0.001 ETH',
            timestamp: DateTime(2026, 8, 3, 12),
            status: ChainTxStatus.confirmed,
          ),
          ChainTxRecord(
            coin: Coin.eth,
            networkId: 'eth-mainnet',
            hash: hash,
            id: '$hash:token:0x${'b' * 40}:0',
            outgoing: true,
            amountText: '1 USDC',
            timestamp: DateTime(2026, 8, 3, 12),
            status: ChainTxStatus.confirmed,
          ),
        ]),
        hashStatus: ChainTransactionStatus.unknown,
      );
      addTearDown(fixture.history.dispose);
      addTearDown(fixture.database.close);

      await fixture.history.refresh();

      expect(fixture.history.records, hasLength(2));
      expect(
        fixture.history.records.map((record) => record.amountText).toSet(),
        {'0.001 ETH', '1 USDC'},
      );
    },
  );

  test(
    'conflicting terminal history evidence stays unknown and cannot settle',
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
            timestamp: DateTime(2026, 8, 3, 12),
            status: ChainTxStatus.confirmed,
          ),
          ChainTxRecord(
            coin: Coin.eth,
            networkId: 'eth-mainnet',
            hash: hash,
            id: '$hash:token:0x${'b' * 40}:0',
            outgoing: true,
            amountText: '0.001 ETH',
            timestamp: DateTime(2026, 8, 3, 12),
            status: ChainTxStatus.failed,
          ),
          // Repeated good-looking rows cannot erase a terminal contradiction.
          ChainTxRecord(
            coin: Coin.eth,
            networkId: 'eth-mainnet',
            hash: hash,
            outgoing: true,
            amountText: '0.001 ETH',
            timestamp: DateTime(2026, 8, 3, 12),
            status: ChainTxStatus.confirmed,
          ),
        ]),
        hashStatus: ChainTransactionStatus.unknown,
      );
      addTearDown(fixture.history.dispose);
      addTearDown(fixture.database.close);

      await fixture.history.refresh();

      final local = await fixture.wallets.localTransactionById('local-pending');
      expect(local?.status, TxStatus.pending);
      expect(local?.lastCheckOutcome, TxCheckOutcome.unknown);
      expect(fixture.history.records, hasLength(2));
      expect(fixture.history.records.map((record) => record.status).toSet(), {
        ChainTxStatus.unknown,
      });
    },
  );

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

  test(
    'inactive-network Pending keeps reconciling without entering active history',
    () async {
      final fixture = await _fixture(
        remote: const HistoryResult.ok([]),
        hashStatus: ChainTransactionStatus.confirmed,
        localNetworkId: 'eth-sepolia',
        activeNetworkIds: const {'eth-mainnet'},
      );
      addTearDown(fixture.history.dispose);
      addTearDown(fixture.database.close);

      await fixture.history.refresh();

      final row = await fixture.wallets.localTransactionById('local-pending');
      expect(
        row?.status,
        TxStatus.confirmed,
        reason: 'network selection must not pause finality reconciliation',
      );
      expect(
        fixture.history.records,
        isEmpty,
        reason: 'inactive-network rows must remain hidden from the active list',
      );
    },
  );
}
