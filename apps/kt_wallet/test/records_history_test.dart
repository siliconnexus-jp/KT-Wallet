import 'package:core_crypto/core_crypto.dart' show ChainAddresses, Coin;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/market/history_controller.dart';
import 'package:kt_wallet/src/market/history_service.dart';
import 'package:kt_wallet/src/screens/home_screen.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';

/// Records tab wiring: live TRON rows when the fetch succeeds, demo rows
/// behind the offline banner when it fails, and an honest "unsupported" line
/// when no chain in the context has a keyless history API.
class _FakeHistoryService extends HistoryService {
  _FakeHistoryService(this.results);
  final Map<Coin, HistoryResult> results;
  @override
  Future<HistoryResult> fetch(Coin coin, String address) async => results[coin]!;
}

WalletController _wallets() => WalletController(WalletManager(initial: [
      HotWallet(
        id: 'w1',
        name: '日常钱包',
        avatarColor: 0xFFF59E0B,
        addresses: const ChainAddresses(
            eth: '0xa', polygon: '0xa', tron: 'Ta', solana: 'a'),
        backedUp: true,
      ),
    ]));

HistoryController _controller(Map<Coin, HistoryResult> results) =>
    HistoryController(wallets: _wallets(), service: _FakeHistoryService(results));

Widget _app(HistoryController controller) => MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: HistoryScope(controller: controller, child: const HomeScreen()),
    );

Future<void> _openRecordsTab(WidgetTester tester) async {
  // '记录' appears in the quick-action row and the tab bar; the tab bar comes
  // last in the tree.
  await tester.tap(find.text('记录').last);
  await tester.pumpAndSettle();
}

const _unsupported = HistoryResult.unsupported();

void main() {
  testWidgets('records tab shows live TRON rows when the fetch succeeds',
      (tester) async {
    final controller = _controller({
      Coin.tron: HistoryResult.ok([
        ChainTxRecord(
          hash: 'a',
          outgoing: true,
          amountText: '88.5 USDT',
          timestamp: DateTime.now().subtract(const Duration(hours: 1)),
          confirmed: true,
        ),
        ChainTxRecord(
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
    await _openRecordsTab(tester);

    expect(find.text('-88.5 USDT'), findsOneWidget);
    expect(find.text('+5 TRX'), findsOneWidget);
    expect(find.textContaining('3月9日'), findsOneWidget);
    // The demo rows must NOT render as if they were live.
    expect(find.text('-120.00 USDT'), findsNothing);
    expect(find.text('离线，显示演示数据'), findsNothing);
    controller.dispose();
  });

  testWidgets(
      'records tab falls back to demo rows behind the offline banner on error',
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
    await _openRecordsTab(tester);

    expect(find.text('离线，显示演示数据'), findsOneWidget);
    // Demo rows render, explicitly labeled.
    expect(find.text('-120.00 USDT'), findsOneWidget);
    expect(find.text('+0.05 ETH'), findsOneWidget);
    controller.dispose();
  });

  testWidgets(
      'records tab shows the unsupported line for a context with no history API',
      (tester) async {
    final controller = _controller({
      for (final coin in Coin.values) coin: _unsupported, // "ETH-only" context
    });
    await controller.refresh();

    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();
    await _openRecordsTab(tester);

    expect(find.text('该链暂不支持历史查询'), findsOneWidget);
    expect(find.text('-120.00 USDT'), findsNothing);
    expect(find.text('离线，显示演示数据'), findsNothing);
    controller.dispose();
  });

  testWidgets('records tab shows the empty state for a live but empty history',
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
    await _openRecordsTab(tester);

    expect(find.text('暂无交易记录'), findsOneWidget);
    expect(find.text('-120.00 USDT'), findsNothing);
    controller.dispose();
  });

  testWidgets('records tab shows -- placeholders while loading', (tester) async {
    final controller = _controller({
      for (final coin in Coin.values) coin: _unsupported,
    });
    // No refresh: the controller is still in its pre-first-fetch state.
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();
    await _openRecordsTab(tester);

    expect(find.text('--'), findsWidgets);
    expect(find.text('-120.00 USDT'), findsNothing);
    controller.dispose();
  });

  testWidgets('records tab WITHOUT any live context renders the demo rows',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const HomeScreen(),
    ));
    await tester.pumpAndSettle();
    await _openRecordsTab(tester);

    expect(find.text('-120.00 USDT'), findsOneWidget);
    expect(find.text('+0.05 ETH'), findsOneWidget);
    expect(find.text('离线，显示演示数据'), findsNothing);
    expect(find.text('该链暂不支持历史查询'), findsNothing);
  });
}
