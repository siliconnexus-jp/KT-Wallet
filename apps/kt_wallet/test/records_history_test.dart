import 'dart:async';

import 'package:chains/chains.dart' show Chain;
import 'package:core_crypto/core_crypto.dart' show ChainAddresses, Coin;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/market/asset_ref.dart';
import 'package:kt_wallet/src/market/history_controller.dart';
import 'package:kt_wallet/src/market/history_service.dart';
import 'package:kt_wallet/src/market/history_snapshot.dart';
import 'package:kt_wallet/src/market/token_balance_service.dart'
    show usdtEthToken, usdtTronToken;
import 'package:kt_wallet/src/market/transaction_status_service.dart';
import 'package:kt_wallet/src/observability/experience_metrics.dart';
import 'package:kt_wallet/src/screens/home_screen.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/state/networks.dart';
import 'package:kt_wallet/src/state/wallet_scope.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:kt_wallet/src/wallets/wallet_store.dart';
import 'package:kt_wallet/src/widgets/token_icon.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:wallet_data/wallet_data.dart';

/// Real history page wiring: live rows when fetch succeeds, honest empty/error
/// states otherwise, and no design fixtures on any wallet-facing path.
class _FakeHistoryService extends HistoryService {
  _FakeHistoryService(this.results);
  final Map<Coin, HistoryResult> results;
  final Map<Coin, int> fetchCounts = {};
  final Map<Coin, String?> requestedNetworkIds = {};

  @override
  Future<HistoryResult> fetch(
    Coin coin,
    String address, {
    int limit = HistoryService.pageSize,
    String? networkId,
  }) async {
    fetchCounts.update(coin, (count) => count + 1, ifAbsent: () => 1);
    requestedNetworkIds[coin] = networkId;
    return results[coin]!;
  }
}

class _PagedHistoryService extends HistoryService {
  final requestedLimits = <int>[];

  @override
  Future<HistoryResult> fetch(
    Coin coin,
    String address, {
    int limit = HistoryService.pageSize,
    String? networkId,
  }) async {
    requestedLimits.add(limit);
    if (coin != Coin.eth) return const HistoryResult.unsupported();
    return HistoryResult.ok([
      for (var i = 0; i < limit; i++)
        ChainTxRecord(
          coin: Coin.eth,
          id: '0x${i.toRadixString(16)}:0',
          hash: '0x${i.toRadixString(16)}',
          outgoing: i.isEven,
          amountText: '$i ETH',
          timestamp: DateTime(2026, 7, 30).subtract(Duration(minutes: i)),
          confirmed: true,
        ),
    ]);
  }
}

class _DelayedHistoryService extends HistoryService {
  final started = Completer<void>();
  final result = Completer<HistoryResult>();

  @override
  Future<HistoryResult> fetch(
    Coin coin,
    String address, {
    int limit = HistoryService.pageSize,
    String? networkId,
  }) {
    if (!started.isCompleted) started.complete();
    return result.future;
  }
}

class _HistorySnapshotMemory implements HistorySnapshotStore {
  _HistorySnapshotMemory(this.snapshot);
  HistorySnapshot? snapshot;
  HistorySnapshot? saved;

  @override
  Future<HistorySnapshot?> load(String walletId, String scope) async =>
      snapshot?.scope == scope ? snapshot : null;

  @override
  Future<void> save(String walletId, HistorySnapshot snapshot) async {
    saved = snapshot;
  }
}

class _ThrowingHistorySnapshotStore implements HistorySnapshotStore {
  int loadCalls = 0;

  @override
  Future<HistorySnapshot?> load(String walletId, String scope) async {
    loadCalls++;
    throw StateError('corrupt display cache');
  }

  @override
  Future<void> save(String walletId, HistorySnapshot snapshot) async {}
}

class _ThrowOnceHistoryService extends HistoryService {
  bool failed = false;

  @override
  Future<HistoryResult> fetch(
    Coin coin,
    String address, {
    int limit = HistoryService.pageSize,
    String? networkId,
  }) async {
    if (!failed) {
      failed = true;
      throw StateError('temporary indexer failure');
    }
    return const HistoryResult.unsupported();
  }
}

class _ThrowNextWalletStore extends WalletStore {
  _ThrowNextWalletStore(super.database);

  bool throwNextMirror = false;
  bool throwNextPending = false;
  int pendingCalls = 0;

  @override
  Future<void> mirrorIncomingTransactions({
    required String targetWalletId,
    required Map<String, String> addressesByCoin,
    Set<String>? networkIds,
  }) async {
    if (throwNextMirror) {
      throwNextMirror = false;
      throw StateError('temporary database failure');
    }
    await super.mirrorIncomingTransactions(
      targetWalletId: targetWalletId,
      addressesByCoin: addressesByCoin,
      networkIds: networkIds,
    );
  }

  @override
  Future<List<Transaction>> pendingTransactions(String walletId) async {
    pendingCalls++;
    if (throwNextPending) {
      throwNextPending = false;
      throw StateError('temporary pending-query failure');
    }
    return super.pendingTransactions(walletId);
  }
}

class _AlwaysPendingStatusService extends TransactionStatusService {
  @override
  Future<ChainTransactionStatus> check(Transaction transaction) async =>
      ChainTransactionStatus.pending;
}

class _BlockingPendingStatusService extends TransactionStatusService {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<ChainTransactionStatus> check(Transaction transaction) async {
    if (!started.isCompleted) started.complete();
    await release.future;
    return ChainTransactionStatus.pending;
  }
}

WalletController _wallets() => WalletController(
  WalletManager(
    initial: [
      HotWallet(
        id: 'w1',
        name: '日常钱包',
        avatarColor: 0xFFF59E0B,
        addresses: const ChainAddresses(
          eth: '0xa',
          polygon: '0xa',
          tron: 'Ta',
          solana: 'a',
        ),
        backedUp: true,
      ),
    ],
  ),
);

WalletController _singleWatchWallet() => WalletController(
  WalletManager(
    initial: [
      WatchWallet(
        id: 'watch-only',
        name: 'Watch only',
        avatarColor: 0xFF000000,
        addresses: const ChainAddresses(
          eth: '0xwatch',
          polygon: '0xwatch',
          tron: 'Twatch',
          solana: 'watch',
        ),
        coldWalletId: 'cold-watch-only',
        protocolVersion: 1,
      ),
    ],
  ),
);

HistoryController _controller(Map<Coin, HistoryResult> results) =>
    HistoryController(
      wallets: _wallets(),
      service: _FakeHistoryService(results),
    );

Widget _app(HistoryController controller) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: HistoryScope(controller: controller, child: const RecordsScreen()),
);

Widget _walletApp(HistoryController controller, WalletController wallets) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: WalletScope(
        controller: wallets,
        child: HistoryScope(
          controller: controller,
          child: const RecordsScreen(),
        ),
      ),
    );

const _unsupported = HistoryResult.unsupported();

void main() {
  for (final locale in const [Locale('zh'), Locale('en'), Locale('ja')]) {
    testWidgets(
      'activity network picker has chain icons (${locale.languageCode})',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final networks = NetworkController();
        final wallets = WalletController(
          WalletManager(
            initial: [
              HotWallet(
                id: 'icons-test',
                name: 'Wallet',
                avatarColor: 0xFF2557E8,
                backedUp: true,
                addresses: const ChainAddresses(
                  eth: '0xa',
                  polygon: '0xa',
                  base: '0xa',
                  arbitrum: '0xa',
                  avalanche: '0xa',
                  bnb: '0xa',
                  tron: 'Ta',
                  solana: 'a',
                ),
              ),
            ],
          ),
        );
        addTearDown(networks.dispose);
        addTearDown(wallets.dispose);
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            theme: ktWalletTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: WalletScope(
                controller: wallets,
                child: NetworkScope(
                  controller: networks,
                  child: const RecordsScreen(tabbed: true),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> openPicker() async {
          await tester.tap(
            find.byKey(const ValueKey('history-network-filter-button')),
          );
          await tester.pumpAndSettle();
        }

        await openPicker();
        final pickerScroll = find.descendant(
          of: find.byKey(const ValueKey('history-filter-options')),
          matching: find.byType(Scrollable),
        );
        final all = find.byKey(const ValueKey('history-network-option-all'));
        expect(
          find.descendant(
            of: all,
            matching: find.byIcon(Icons.language_rounded),
          ),
          findsOneWidget,
        );
        for (final chain in Chain.values) {
          final row = find.byKey(
            ValueKey('history-network-option-${networks.activeFor(chain).id}'),
          );
          await tester.scrollUntilVisible(row, 100, scrollable: pickerScroll);
          await tester.pumpAndSettle();
          final icon = tester.widget<ChainIcon>(
            find.descendant(of: row, matching: find.byType(ChainIcon)),
          );
          expect(icon.chain, chain);
          expect(icon.size, 32);
          expect(ChainIcon.assetFor(chain), isNotNull);
        }
        final base = find.byKey(
          ValueKey(
            'history-network-option-${networks.activeFor(Chain.base).id}',
          ),
        );
        await tester.scrollUntilVisible(base, -100, scrollable: pickerScroll);
        await tester.pumpAndSettle();
        await tester.tap(base);
        await tester.pumpAndSettle();
        await openPicker();
        await tester.scrollUntilVisible(base, 100, scrollable: pickerScroll);
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: base,
            matching: find.byKey(
              const ValueKey('history-filter-selected-check'),
            ),
          ),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(all, -100, scrollable: pickerScroll);
        await tester.pumpAndSettle();
        await tester.tap(all);
        await tester.pumpAndSettle();
        await openPicker();
        expect(
          find.descendant(
            of: all,
            matching: find.byKey(
              const ValueKey('history-filter-selected-check'),
            ),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  setUp(ExperienceMetrics.instance.clear);

  test(
    'a broken history snapshot is ignored and live history still loads',
    () async {
      final snapshots = _ThrowingHistorySnapshotStore();
      final liveRecord = ChainTxRecord(
        coin: Coin.eth,
        networkId: 'eth-mainnet',
        hash: '0xlive',
        outgoing: false,
        amountText: '1 ETH',
        timestamp: DateTime(2026, 8, 3),
        confirmed: true,
      );
      final controller = HistoryController(
        wallets: _wallets(),
        service: _FakeHistoryService({
          for (final coin in Coin.values)
            coin: coin == Coin.eth
                ? HistoryResult.ok([liveRecord])
                : _unsupported,
        }),
        snapshots: snapshots,
        snapshotScope: () => 'mainnet',
      );
      addTearDown(controller.dispose);

      await controller.refresh();

      expect(snapshots.loadCalls, 1);
      expect(controller.isRefreshing, isFalse);
      expect(controller.isLoading, isFalse);
      expect(controller.records.map((record) => record.hash), ['0xlive']);
      expect(controller.showingCachedData, isFalse);
      final metric = ExperienceMetrics.instance.recent.singleWhere(
        (event) => event.name == ExperienceMetricNames.historyRefresh,
      );
      expect(metric.success, isTrue);
    },
  );

  test('a partial indexer outage never records a successful refresh', () async {
    final controller = _controller({
      Coin.eth: const HistoryResult.ok([]),
      Coin.polygon: const HistoryResult.error(),
      Coin.tron: _unsupported,
      Coin.solana: _unsupported,
    });
    addTearDown(controller.dispose);

    await controller.refresh();

    final metric = ExperienceMetrics.instance.recent.singleWhere(
      (event) => event.name == ExperienceMetricNames.historyRefresh,
    );
    expect(metric.success, isFalse);
  });

  test('an unexpected indexer failure closes honestly and can retry', () async {
    final controller = HistoryController(
      wallets: _wallets(),
      service: _ThrowOnceHistoryService(),
    );
    addTearDown(controller.dispose);

    await controller.refresh();

    expect(controller.isRefreshing, isFalse);
    expect(controller.isLoading, isFalse);
    expect(controller.resultFor(Coin.eth).status, HistoryStatus.error);

    await controller.refresh();

    expect(controller.isRefreshing, isFalse);
    expect(controller.resultFor(Coin.eth).status, HistoryStatus.unsupported);
  });

  test('an indexer failure still joins the in-flight status refresh', () async {
    final database = WalletDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final wallet = HotWallet(
      id: 'joined-failure-wallet',
      name: 'Joined failure wallet',
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
      id: 'joined-failure-pending',
      coin: Coin.eth,
      networkId: 'eth-mainnet',
      from: wallet.addresses.eth,
      to: '0x2222222222222222222222222222222222222222',
      amountRaw: '1',
      hash: '0x${'b' * 64}',
      status: TxStatus.pending,
      signMode: SignMode.local,
      createdAt: DateTime(2026, 8, 3).millisecondsSinceEpoch,
    );
    final statusService = _BlockingPendingStatusService();
    final controller = HistoryController(
      wallets: wallets,
      service: _ThrowOnceHistoryService(),
      statusService: statusService,
    );
    addTearDown(controller.dispose);

    var completed = false;
    final refresh = controller.refresh().whenComplete(() => completed = true);
    await statusService.started.future;
    await Future<void>.delayed(Duration.zero);

    expect(completed, isFalse);
    statusService.release.complete();
    await refresh;

    expect(completed, isTrue);
    expect(controller.isRefreshing, isFalse);
    expect(controller.resultFor(Coin.eth).status, HistoryStatus.error);
  });

  test('a database failure cannot latch load-more or block retry', () async {
    final database = WalletDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = _ThrowNextWalletStore(database);
    final wallets = WalletController(
      WalletManager(initial: _wallets().wallets),
      store: store,
    );
    final controller = HistoryController(
      wallets: wallets,
      service: _PagedHistoryService(),
    );
    addTearDown(controller.dispose);
    await controller.refresh();

    store.throwNextMirror = true;
    await controller.loadMore();

    expect(controller.isRefreshing, isFalse);
    expect(controller.isLoadingMore, isFalse);
    expect(controller.isLoading, isFalse);

    await controller.refresh();
    expect(controller.isRefreshing, isFalse);
    expect(controller.records, isNotEmpty);
  });

  test('a polling database failure backs off and resumes finality', () async {
    final database = WalletDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final wallet = HotWallet(
      id: 'poll-wallet',
      name: 'Poll wallet',
      avatarColor: 0xFF000000,
      addresses: const ChainAddresses(
        eth: '0x1111111111111111111111111111111111111111',
        polygon: '0x1111111111111111111111111111111111111111',
        tron: 'TJRabPrwbZy45sbavfcjinPJC18kjpRTv8',
        solana: '11111111111111111111111111111111',
      ),
      backedUp: true,
    );
    final store = _ThrowNextWalletStore(database);
    await store.save(wallet);
    final wallets = WalletController(
      WalletManager(initial: [wallet]),
      store: store,
    );
    await wallets.saveOutgoingTransaction(
      id: 'poll-pending',
      coin: Coin.eth,
      networkId: 'eth-mainnet',
      from: wallet.addresses.eth,
      to: '0x2222222222222222222222222222222222222222',
      amountRaw: '1',
      hash: '0x${'a' * 64}',
      status: TxStatus.pending,
      signMode: SignMode.local,
      createdAt: DateTime(2026, 8, 3).millisecondsSinceEpoch,
    );
    final controller = HistoryController(
      wallets: wallets,
      service: _FakeHistoryService({
        for (final coin in Coin.values) coin: _unsupported,
      }),
      statusService: _AlwaysPendingStatusService(),
      pollInterval: const Duration(milliseconds: 5),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    final baseline = store.pendingCalls;

    store.throwNextPending = true;
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    final deadline = DateTime.now().add(const Duration(milliseconds: 250));
    while (store.pendingCalls < baseline + 2 &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    expect(store.pendingCalls, greaterThanOrEqualTo(baseline + 2));
    expect(controller.isRefreshing, isFalse);
    expect(controller.records, isNotEmpty);
  });

  test(
    'switching wallets hides the previous local history synchronously',
    () async {
      final database = WalletDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final first = WatchWallet(
        id: 'watch-a',
        name: 'Watch A',
        avatarColor: 0xFF000000,
        addresses: const ChainAddresses(
          eth: '0xaaaa',
          polygon: '0xaaaa',
          tron: 'Taaaa',
          solana: 'aaaa',
        ),
        coldWalletId: 'cold-a',
        protocolVersion: 1,
      );
      final second = WatchWallet(
        id: 'watch-b',
        name: 'Watch B',
        avatarColor: 0xFF000000,
        addresses: const ChainAddresses(
          eth: '0xbbbb',
          polygon: '0xbbbb',
          tron: 'Tbbbb',
          solana: 'bbbb',
        ),
        sortOrder: 1,
        coldWalletId: 'cold-b',
        protocolVersion: 1,
      );
      final store = WalletStore(database);
      await store.save(first);
      await store.save(second);
      final wallets = WalletController(
        WalletManager(initial: [first, second]),
        store: store,
      );
      await wallets.saveOutgoingTransaction(
        id: 'watch-a-confirmed',
        coin: Coin.eth,
        networkId: 'eth-mainnet',
        from: first.addresses.eth,
        to: '0xcccc',
        amountRaw: '1',
        hash: '0x${'a' * 64}',
        status: TxStatus.confirmed,
        signMode: SignMode.airgap,
        createdAt: DateTime(2026, 8, 3).millisecondsSinceEpoch,
      );
      final controller = HistoryController(
        wallets: wallets,
        service: _FakeHistoryService({
          for (final coin in Coin.values) coin: _unsupported,
        }),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      expect(controller.records, hasLength(1));

      wallets.select(second.id);

      expect(
        controller.records,
        isEmpty,
        reason: 'wallet A rows must disappear before wallet B I/O completes',
      );
      while (controller.isRefreshing) {
        await Future<void>.delayed(Duration.zero);
      }
    },
  );

  test(
    'same-wallet transaction writes appear without a wallet switch or remote refresh',
    () async {
      final database = WalletDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final wallet = HotWallet(
        id: 'same-wallet',
        name: 'Same wallet',
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
      final controller = HistoryController(
        wallets: wallets,
        service: _FakeHistoryService({
          for (final coin in Coin.values) coin: _unsupported,
        }),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      expect(controller.records, isEmpty);

      final hash = '0x${'c' * 64}';
      await wallets.saveOutgoingTransaction(
        id: 'same-wallet-new-transaction',
        coin: Coin.eth,
        networkId: 'eth-sepolia',
        from: wallet.addresses.eth,
        to: '0x2222222222222222222222222222222222222222',
        amountRaw: '10000000000000',
        hash: hash,
        status: TxStatus.confirmed,
        signMode: SignMode.local,
        createdAt: DateTime(2026, 8, 6).millisecondsSinceEpoch,
      );
      final deadline = DateTime.now().add(const Duration(seconds: 1));
      while (!controller.records.any((record) => record.hash == hash) &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(controller.records.map((record) => record.hash), contains(hash));
    },
  );

  test(
    'removing the last wallet clears history and drops late explorer rows',
    () async {
      final service = _DelayedHistoryService();
      final wallets = _singleWatchWallet();
      final controller = HistoryController(wallets: wallets, service: service);
      addTearDown(controller.dispose);

      final refresh = controller.refresh();
      await service.started.future;
      await wallets.remove('watch-only');
      service.result.complete(
        HistoryResult.ok([
          ChainTxRecord(
            coin: Coin.eth,
            networkId: 'eth-mainnet',
            hash: '0xlate',
            outgoing: false,
            amountText: '1 ETH',
            timestamp: DateTime(2026, 8, 3),
            confirmed: true,
          ),
        ]),
      );
      await refresh;

      expect(wallets.current, isNull);
      expect(controller.isLoading, isTrue);
      expect(controller.records, isEmpty);
      expect(controller.notice, isNull);
    },
  );

  test(
    'disposing while explorer requests are in flight drops every late answer',
    () async {
      final service = _DelayedHistoryService();
      final controller = HistoryController(
        wallets: _wallets(),
        service: service,
      );

      final refresh = controller.refresh();
      await service.started.future;
      controller.dispose();
      service.result.complete(const HistoryResult.unsupported());

      await expectLater(refresh, completes);
    },
  );

  test('history expands its bounded remote window when loading more', () async {
    final service = _PagedHistoryService();
    final controller = HistoryController(wallets: _wallets(), service: service);
    addTearDown(controller.dispose);

    await controller.refresh();
    expect(controller.records, hasLength(20));
    expect(controller.canLoadMore, isTrue);

    await controller.loadMore();
    expect(controller.records, hasLength(40));
    expect(service.requestedLimits, containsAllInOrder([20, 40]));
  });

  test('cached history remains visible when the live refresh fails', () async {
    final cachedAt = DateTime(2026, 7, 30, 12);
    final snapshots = _HistorySnapshotMemory(
      HistorySnapshot(
        scope: 'scope',
        savedAt: cachedAt,
        results: {
          Coin.eth: HistoryResult.ok([
            ChainTxRecord(
              coin: Coin.eth,
              hash: '0xcached',
              outgoing: false,
              amountText: '1 ETH',
              timestamp: cachedAt,
              confirmed: true,
            ),
          ]),
        },
      ),
    );
    final controller = HistoryController(
      wallets: _wallets(),
      service: _FakeHistoryService({
        for (final coin in Coin.values) coin: const HistoryResult.error(),
      }),
      snapshots: snapshots,
      snapshotScope: () => 'scope',
    );
    addTearDown(controller.dispose);

    await controller.refresh();
    expect(
      controller.records.map((record) => record.hash),
      contains('0xcached'),
    );
    expect(controller.showingCachedData, isTrue);
    expect(controller.lastUpdatedAt, cachedAt);
  });

  test(
    'resuming retries account history after a cached refresh failure',
    () async {
      final cachedAt = DateTime(2026, 8, 14, 12);
      final snapshots = _HistorySnapshotMemory(
        HistorySnapshot(
          scope: 'scope',
          savedAt: cachedAt,
          results: {Coin.tron: const HistoryResult.ok([])},
        ),
      );
      final service = _FakeHistoryService({
        for (final coin in Coin.values) coin: const HistoryResult.error(),
      });
      final controller = HistoryController(
        wallets: _wallets(),
        service: service,
        snapshots: snapshots,
        snapshotScope: () => 'scope',
      );
      addTearDown(controller.dispose);

      await controller.refresh();
      expect(controller.showingCachedData, isTrue);

      service.results
        ..[Coin.eth] = _unsupported
        ..[Coin.polygon] = _unsupported
        ..[Coin.solana] = _unsupported
        ..[Coin.tron] = HistoryResult.ok([
          ChainTxRecord(
            coin: Coin.tron,
            networkId: 'tron-mainnet',
            hash:
                '3197906d8668e38b0c3b0378dadc156c9a66b3e4f50ffa103e3c0bd90fc0be17',
            outgoing: false,
            amountText: '10 USDT',
            assetContract: usdtTronToken.contract,
            assetSymbol: 'USDT',
            timestamp: DateTime(2026, 8, 14, 10),
            confirmed: true,
          ),
        ]);

      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      while (controller.isRefreshing) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(controller.records.map((record) => record.amountText), [
        '10 USDT',
      ]);
      expect(controller.showingCachedData, isFalse);
      expect(service.fetchCounts[Coin.tron], 2);
    },
  );

  testWidgets('cached history exposes a retry that reloads incoming records', (
    tester,
  ) async {
    final cachedAt = DateTime(2026, 8, 14, 12);
    final snapshots = _HistorySnapshotMemory(
      HistorySnapshot(
        scope: 'scope',
        savedAt: cachedAt,
        results: {Coin.tron: const HistoryResult.ok([])},
      ),
    );
    final service = _FakeHistoryService({
      for (final coin in Coin.values) coin: const HistoryResult.error(),
    });
    final controller = HistoryController(
      wallets: _wallets(),
      service: service,
      snapshots: snapshots,
      snapshotScope: () => 'scope',
    );
    addTearDown(controller.dispose);
    await controller.refresh();

    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('history-cache-retry')), findsOneWidget);
    expect(find.textContaining('部分交易记录暂未更新'), findsOneWidget);

    service.results
      ..[Coin.eth] = _unsupported
      ..[Coin.polygon] = _unsupported
      ..[Coin.solana] = _unsupported
      ..[Coin.tron] = HistoryResult.ok([
        ChainTxRecord(
          coin: Coin.tron,
          networkId: 'tron-mainnet',
          hash:
              '3197906d8668e38b0c3b0378dadc156c9a66b3e4f50ffa103e3c0bd90fc0be17',
          outgoing: false,
          amountText: '10 USDT',
          assetContract: usdtTronToken.contract,
          assetSymbol: 'USDT',
          timestamp: DateTime(2026, 8, 14, 10),
          confirmed: true,
        ),
      ]);

    await tester.tap(find.byKey(const ValueKey('history-cache-retry')));
    await tester.pumpAndSettle();

    expect(find.text('+10 USDT'), findsOneWidget);
    expect(find.byKey(const ValueKey('history-cached-label')), findsNothing);
  });

  testWidgets('records page pull-to-refresh reloads account history', (
    tester,
  ) async {
    final service = _FakeHistoryService({
      for (final coin in Coin.values) coin: _unsupported,
      Coin.tron: const HistoryResult.ok([]),
    });
    final controller = HistoryController(wallets: _wallets(), service: service);
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(service.fetchCounts[Coin.tron], 1);

    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    expect(find.byType(RefreshIndicator), findsOneWidget);
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 320));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(service.fetchCounts[Coin.tron], 2);
  });

  testWidgets('history refreshes when the active network profile changes', (
    tester,
  ) async {
    final service = _FakeHistoryService({
      for (final coin in Coin.values) coin: _unsupported,
    });
    final networkChanges = ChangeNotifier();
    final controller = HistoryController(
      wallets: _wallets(),
      service: service,
      networkChanges: networkChanges,
    );
    await controller.refresh();

    networkChanges.notifyListeners();
    await tester.pump();
    await tester.pumpAndSettle();

    for (final coin in _wallets().current!.addresses.enabledCoins) {
      expect(service.fetchCounts[coin], 2, reason: '$coin should refetch');
    }
    controller.dispose();
    networkChanges.dispose();
  });

  test(
    'history controller passes the concrete active network per coin',
    () async {
      final service = _FakeHistoryService({
        for (final coin in Coin.values) coin: _unsupported,
      });
      final controller = HistoryController(
        wallets: _wallets(),
        service: service,
        activeNetworkId: (coin) => 'active-${coin.name}',
      );
      addTearDown(controller.dispose);

      await controller.refresh();

      for (final coin in _wallets().current!.addresses.enabledCoins) {
        expect(service.requestedNetworkIds[coin], 'active-${coin.name}');
      }
    },
  );

  testWidgets('records page shows live TRON rows when the fetch succeeds', (
    tester,
  ) async {
    final controller = _controller({
      Coin.tron: HistoryResult.ok([
        ChainTxRecord(
          coin: Coin.tron,
          hash: 'a',
          outgoing: true,
          amountText: '88.5 USDT',
          timestamp: DateTime.now().subtract(const Duration(hours: 1)),
          confirmed: true,
        ),
        ChainTxRecord(
          coin: Coin.tron,
          hash: 'b',
          outgoing: false,
          amountText: '5 TRX',
          timestamp: DateTime(2026, 3, 9, 20, 4),
          confirmed: true,
        ),
      ]),
      Coin.eth: _unsupported,
      Coin.polygon: _unsupported,
      Coin.solana: _unsupported,
    });
    await controller.refresh();

    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    expect(find.text('-88.5 USDT'), findsOneWidget);
    expect(find.text('+5 TRX'), findsOneWidget);
    expect(find.text('2026/03/09'), findsOneWidget);
    // The demo rows must NOT render as if they were live.
    expect(find.text('-120.00 USDT'), findsNothing);
    expect(find.text('离线，显示演示数据'), findsNothing);
    controller.dispose();
  });

  testWidgets(
    'wallet history filters official, user-added, and unknown token records by type',
    (tester) async {
      const customContract = '0x2222222222222222222222222222222222222222';
      const unknownContract = '0x3333333333333333333333333333333333333333';
      const riskyContract = '0x4444444444444444444444444444444444444444';
      final wallets = _wallets();
      await wallets.addToken(
        symbol: 'CUSTOM',
        name: 'My custom token',
        contract: customContract,
        network: 'Polygon · ERC-20',
        networkId: 'polygon-mainnet',
      );
      final service = _FakeHistoryService({
        for (final coin in Coin.values) coin: _unsupported,
        Coin.eth: HistoryResult.ok([
          ChainTxRecord(
            coin: Coin.eth,
            networkId: 'eth-mainnet',
            id: 'official',
            hash: 'official-hash',
            outgoing: false,
            amountText: '1 USDT',
            assetContract: usdtEthToken.contract,
            assetSymbol: 'USDT',
            assetVerified: true,
            timestamp: DateTime.utc(2026, 8, 8, 1),
            confirmed: true,
          ),
        ]),
        Coin.polygon: HistoryResult.ok([
          ChainTxRecord(
            coin: Coin.polygon,
            networkId: 'polygon-mainnet',
            id: 'risky',
            hash: 'risky-hash',
            outgoing: false,
            amountText: '99 USDT',
            assetContract: riskyContract,
            assetSymbol: 'USDT',
            assetVerified: false,
            timestamp: DateTime.utc(2026, 8, 8, 4),
            confirmed: true,
          ),
          ChainTxRecord(
            coin: Coin.polygon,
            networkId: 'polygon-mainnet',
            id: 'unknown',
            hash: 'unknown-hash',
            outgoing: false,
            amountText: '3370 TOKEN',
            assetContract: unknownContract,
            assetSymbol: 'TOKEN',
            assetVerified: false,
            timestamp: DateTime.utc(2026, 8, 8, 3),
            confirmed: true,
          ),
          ChainTxRecord(
            coin: Coin.polygon,
            networkId: 'polygon-mainnet',
            id: 'custom',
            hash: 'custom-hash',
            outgoing: false,
            amountText: '2 CUSTOM',
            assetContract: customContract,
            assetSymbol: 'CUSTOM',
            assetVerified: false,
            timestamp: DateTime.utc(2026, 8, 8, 2),
            confirmed: true,
          ),
        ]),
      });
      final controller = HistoryController(wallets: wallets, service: service);
      addTearDown(controller.dispose);
      addTearDown(wallets.dispose);
      await controller.refresh();

      await tester.pumpWidget(_walletApp(controller, wallets));
      await tester.pumpAndSettle();

      expect(find.text('+1 USDT'), findsOneWidget);
      expect(find.text('+2 CUSTOM'), findsOneWidget);
      expect(find.text('+3370 TOKEN'), findsNothing);
      expect(find.text('+99 USDT'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('history-type-filter-button')),
      );
      await tester.pumpAndSettle();
      expect(find.text('按类型筛选'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('history-filter-selected-check')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('history-type-option-transfers')),
          matching: find.byKey(const ValueKey('history-filter-selected-check')),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('history-type-option-other')));
      await tester.pumpAndSettle();

      expect(find.text('+3370 TOKEN'), findsOneWidget);
      expect(find.text('+99 USDT'), findsOneWidget);
      expect(find.text('未验证'), findsOneWidget);
      expect(find.text('风险'), findsOneWidget);
      final dangerLabels = tester.widgetList<Container>(
        find.byKey(const ValueKey('history-danger-token-label')),
      );
      expect(dangerLabels, hasLength(2));
      for (final element
          in find
              .byKey(const ValueKey('history-danger-token-label'))
              .evaluate()) {
        expect(element.size!.height, 43);
      }
      for (final dangerLabel in dangerLabels) {
        final decoration = dangerLabel.decoration! as BoxDecoration;
        expect(decoration.color, WalletColors.red);
        expect(decoration.borderRadius, isNull);
      }
      expect(find.text('+1 USDT'), findsNothing);
      expect(find.text('+2 CUSTOM'), findsNothing);
    },
  );

  testWidgets(
    'standalone records use the OKX-aligned wallet tab, filters, dates, addresses, and signed amounts',
    (tester) async {
      final controller = _controller({
        Coin.tron: HistoryResult.ok([
          ChainTxRecord(
            coin: Coin.tron,
            networkId: 'tron-mainnet',
            hash: 'incoming-tron',
            outgoing: false,
            fromAddress: 'TLaGjwhvA8XQYSxFAcAXy7Dvuue9eGYitv',
            toAddress: 'TA5X6WfP1smMYoVx92yP9xiFPcPm7fqK2w',
            amountText: '10 USDT',
            assetContract: usdtTronToken.contract,
            assetSymbol: 'USDT',
            timestamp: DateTime(2026, 8, 15, 9),
            confirmed: true,
          ),
          ChainTxRecord(
            coin: Coin.tron,
            networkId: 'tron-mainnet',
            hash: 'outgoing-tron',
            outgoing: true,
            fromAddress: 'TA5X6WfP1smMYoVx92yP9xiFPcPm7fqK2w',
            toAddress: 'TQn9Y2khEsLJW1ChVWFMSMeRDow5KcbLSE',
            amountText: '2 TRX',
            timestamp: DateTime(2026, 8, 14, 9),
            confirmed: true,
          ),
        ]),
        Coin.eth: _unsupported,
        Coin.polygon: _unsupported,
        Coin.solana: _unsupported,
      });
      addTearDown(controller.dispose);
      await controller.refresh();

      await tester.pumpWidget(_app(controller));
      await tester.pumpAndSettle();

      expect(find.text('交易记录'), findsOneWidget);
      expect(find.text('钱包'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('records-wallet-tab-indicator')),
        findsOneWidget,
      );
      expect(find.text('发送/接收'), findsOneWidget);
      expect(find.text('2026/08/15'), findsOneWidget);
      expect(find.text('2026/08/14'), findsOneWidget);
      expect(find.text('接收'), findsOneWidget);
      expect(find.text('发送'), findsOneWidget);
      expect(find.textContaining('来自 TLaGjw...Yitv'), findsOneWidget);
      expect(find.textContaining('至 TQn9Y2...bLSE'), findsOneWidget);
      expect(find.text('+10 USDT'), findsOneWidget);
      expect(find.text('-2 TRX'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.language_rounded));
      await tester.pumpAndSettle();
      expect(find.text('按网络筛选'), findsOneWidget);
      expect(find.text('全部网络'), findsOneWidget);
      expect(find.text('TRON'), findsOneWidget);
      final tronIcon = tester.widget<ChainIcon>(
        find.descendant(
          of: find.byKey(const ValueKey('history-network-option-tron-mainnet')),
          matching: find.byType(ChainIcon),
        ),
      );
      expect(tronIcon.chain, Chain.tron);
      await tester.tap(
        find.byKey(const ValueKey('history-network-option-all')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('history-type-filter-button')),
      );
      await tester.pumpAndSettle();
      expect(find.text('按类型筛选'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('history-type-option-transfers')),
        findsOneWidget,
      );
      expect(find.text('其他'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('history-type-option-transfers')),
          matching: find.byKey(const ValueKey('history-filter-selected-check')),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'records page reports network failure without substituting demo rows',
    (tester) async {
      final controller = _controller({
        Coin.tron: const HistoryResult.error(), // e.g. mock address rejected
        Coin.eth: _unsupported,
        Coin.polygon: _unsupported,
        Coin.solana: _unsupported,
      });
      await controller.refresh();

      await tester.pumpWidget(_app(controller));
      await tester.pumpAndSettle();

      expect(find.text('暂时无法获取资产数据，请稍后重试'), findsOneWidget);
      expect(find.text('-120.00 USDT'), findsNothing);
      expect(find.text('+0.05 ETH'), findsNothing);
      controller.dispose();
    },
  );

  testWidgets(
    'records page shows the unsupported line for a context with no history API',
    (tester) async {
      final controller = _controller({
        for (final coin in Coin.values)
          coin: _unsupported, // "ETH-only" context
      });
      await controller.refresh();

      await tester.pumpWidget(_app(controller));
      await tester.pumpAndSettle();

      expect(find.text('该链暂不支持历史查询'), findsOneWidget);
      expect(find.text('-120.00 USDT'), findsNothing);
      expect(find.text('离线，显示演示数据'), findsNothing);
      controller.dispose();
    },
  );

  testWidgets(
    'records page shows the empty state for a live but empty history',
    (tester) async {
      final controller = _controller({
        Coin.tron: const HistoryResult.ok([]),
        Coin.eth: _unsupported,
        Coin.polygon: _unsupported,
        Coin.solana: _unsupported,
      });
      await controller.refresh();

      await tester.pumpWidget(_app(controller));
      await tester.pumpAndSettle();

      expect(find.text('暂无交易记录'), findsOneWidget);
      expect(find.text('-120.00 USDT'), findsNothing);
      controller.dispose();
    },
  );

  testWidgets('records page shows structural placeholders while loading', (
    tester,
  ) async {
    final controller = _controller({
      for (final coin in Coin.values) coin: _unsupported,
    });
    // No refresh: the controller is still in its pre-first-fetch state.
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('history-loading-skeleton')),
      findsOneWidget,
    );
    for (var i = 0; i < 3; i++) {
      expect(find.byKey(ValueKey('history-skeleton-row-$i')), findsOneWidget);
    }
    expect(find.text('--'), findsNothing);
    expect(find.text('-120.00 USDT'), findsNothing);
    controller.dispose();
  });

  testWidgets('records page without a live source shows a real empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const RecordsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无交易记录'), findsOneWidget);
    expect(find.text('-120.00 USDT'), findsNothing);
    expect(find.text('+0.05 ETH'), findsNothing);
    expect(find.text('离线，显示演示数据'), findsNothing);
    expect(find.text('该链暂不支持历史查询'), findsNothing);
  });

  testWidgets('asset history filters by both token and network', (
    tester,
  ) async {
    final controller = _controller({
      Coin.eth: HistoryResult.ok([
        ChainTxRecord(
          coin: Coin.eth,
          hash: 'eth-native',
          outgoing: true,
          amountText: '0.2 ETH',
          timestamp: DateTime(2026, 7, 28, 12),
          confirmed: true,
        ),
        ChainTxRecord(
          coin: Coin.eth,
          hash: 'eth-usdt',
          outgoing: false,
          amountText: '2 USDT',
          assetContract: usdtEthToken.contract,
          assetSymbol: 'USDT',
          timestamp: DateTime(2026, 7, 28, 13),
          confirmed: true,
        ),
      ]),
      Coin.polygon: HistoryResult.ok([
        ChainTxRecord(
          coin: Coin.polygon,
          hash: 'polygon-usdt',
          outgoing: false,
          amountText: '9 USDT',
          assetContract: usdtEthToken.contract,
          assetSymbol: 'USDT',
          timestamp: DateTime(2026, 7, 28, 14),
          confirmed: true,
        ),
      ]),
      Coin.tron: _unsupported,
      Coin.solana: _unsupported,
    });
    await controller.refresh();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HistoryScope(
          controller: controller,
          child: RecordsScreen(
            asset: AssetRef.token(usdtEthToken),
            embedded: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('+2 USDT'), findsOneWidget);
    expect(find.text('-0.2 ETH'), findsNothing);
    expect(find.text('+9 USDT'), findsNothing);
    controller.dispose();
  });
}
