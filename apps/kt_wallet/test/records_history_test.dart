import 'package:core_crypto/core_crypto.dart' show ChainAddresses, Coin;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/market/asset_ref.dart';
import 'package:kt_wallet/src/market/history_controller.dart';
import 'package:kt_wallet/src/market/history_service.dart';
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
  @override
  Future<HistoryResult> fetch(Coin coin, String address) async =>
      results[coin]!;
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

  testWidgets('records page shows -- placeholders while loading', (
    tester,
  ) async {
    final controller = _controller({
      for (final coin in Coin.values) coin: _unsupported,
    });
    // No refresh: the controller is still in its pre-first-fetch state.
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    expect(find.text('--'), findsWidgets);
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
