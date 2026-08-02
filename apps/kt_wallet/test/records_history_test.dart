import 'dart:async';

import 'package:core_crypto/core_crypto.dart' show ChainAddresses, Coin;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/market/asset_ref.dart';
import 'package:kt_wallet/src/market/history_controller.dart';
import 'package:kt_wallet/src/market/history_service.dart';
import 'package:kt_wallet/src/market/history_snapshot.dart';
import 'package:kt_wallet/src/market/token_balance_service.dart'
    show usdtEthToken;
import 'package:kt_wallet/src/screens/home_screen.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';

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

const _unsupported = HistoryResult.unsupported();

void main() {
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
    expect(find.textContaining('3月9日'), findsOneWidget);
    // The demo rows must NOT render as if they were live.
    expect(find.text('-120.00 USDT'), findsNothing);
    expect(find.text('离线，显示演示数据'), findsNothing);
    controller.dispose();
  });

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

      expect(find.text('网络不可用，实时数据加载失败'), findsOneWidget);
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
