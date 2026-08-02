import 'dart:async';
import 'dart:io';

import 'package:core_crypto/core_crypto.dart' show ChainAddresses, Coin;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/main.dart';
import 'package:kt_wallet/src/market/asset_ref.dart';
import 'package:kt_wallet/src/market/history_controller.dart';
import 'package:kt_wallet/src/market/history_service.dart';
import 'package:kt_wallet/src/market/token_balance_service.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';

class _FixtureHistoryService extends HistoryService {
  _FixtureHistoryService(this.results);

  final Map<Coin, HistoryResult> results;

  @override
  Future<HistoryResult> fetch(
    Coin coin,
    String address, {
    int limit = HistoryService.pageSize,
    String? networkId,
  }) async => results[coin] ?? const HistoryResult.unsupported();
}

WalletController _wallets() => WalletController(
  WalletManager(
    initial: [
      HotWallet(
        id: 'records-ui-wallet',
        name: '记录验收钱包',
        avatarColor: 0xFF5570D8,
        addresses: const ChainAddresses(
          eth: '0x1111111111111111111111111111111111111111',
          polygon: '0x1111111111111111111111111111111111111111',
          tron: 'TJRabPrwbZy45sbavfcjinPJC18kjpRTv8',
          solana: '11111111111111111111111111111111',
        ),
        backedUp: true,
      ),
    ],
  ),
);

const _emptyResults = <Coin, HistoryResult>{
  Coin.eth: HistoryResult.ok([]),
  Coin.polygon: HistoryResult.ok([]),
  Coin.tron: HistoryResult.ok([]),
  Coin.solana: HistoryResult.ok([]),
};

final _fixtureResults = <Coin, HistoryResult>{
  Coin.eth: HistoryResult.ok([
    ChainTxRecord(
      coin: Coin.eth,
      hash: '0xeth-usdt',
      outgoing: false,
      amountText: '2 USDT',
      assetContract: usdtEthToken.contract,
      assetSymbol: 'USDT',
      timestamp: DateTime(2026, 7, 28, 14, 32),
      confirmed: true,
    ),
    ChainTxRecord(
      coin: Coin.eth,
      hash: '0xeth-native',
      outgoing: true,
      amountText: '0.2 ETH',
      timestamp: DateTime(2026, 7, 28, 13, 18),
      confirmed: true,
    ),
  ]),
  Coin.polygon: HistoryResult.ok([
    ChainTxRecord(
      coin: Coin.polygon,
      hash: '0xpolygon-usdt',
      outgoing: true,
      amountText: '9 USDT',
      assetContract: usdtPolygonToken.contract,
      assetSymbol: 'USDT',
      timestamp: DateTime(2026, 7, 28, 12, 5),
      confirmed: true,
    ),
  ]),
  Coin.tron: const HistoryResult.ok([]),
  Coin.solana: const HistoryResult.ok([]),
};

final _usdt = AssetRef.tokenGroup([usdtEthToken, usdtPolygonToken]);

Widget _app({
  required WalletController wallets,
  required HistoryController history,
}) => HistoryScope(
  controller: history,
  child: KtWalletApp(
    key: ObjectKey(history),
    controller: wallets,
    initialLocation: '/home',
  ),
);

Future<void> _capture(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
) async {
  final platform = Platform.isIOS ? 'ios' : 'android';
  final fileName = '$platform-$name';
  final bytes = await binding.takeScreenshot(fileName);
  final path = '${Directory.systemTemp.path}/$fileName.png';
  await File(path).writeAsBytes(bytes, flush: true);
  // Host automation uses this path to collect the exact Flutter-rendered PNG.
  // ignore: avoid_print
  print('RECORDS_UI_CAPTURE FILE=$path');
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 900)),
  );
}

Future<void> _openRecords(WidgetTester tester) async {
  expect(find.text('记录'), findsOneWidget);
  await tester.tap(find.text('记录'));
  await tester.pumpAndSettle();
  expect(find.text('交易记录'), findsOneWidget);
}

Future<void> _openToken(WidgetTester tester, AssetRef asset) async {
  final context = tester.element(find.byType(Navigator).first);
  unawaited(GoRouter.of(context).push('/token', extra: asset));
  await tester.pumpAndSettle();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'records information architecture renders and filters on a real simulator',
    (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('zh')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      if (Platform.isAndroid) {
        await binding.convertFlutterSurfaceToImage();
      }

      final wallets = _wallets();
      final results = <Coin, HistoryResult>{..._emptyResults};
      final history = HistoryController(
        wallets: wallets,
        service: _FixtureHistoryService(results),
      );
      addTearDown(history.dispose);
      await history.refresh();
      await tester.pumpWidget(_app(wallets: wallets, history: history));
      await tester.pumpAndSettle();

      expect(find.text('首页'), findsOneWidget);
      // "资产" also titles the home asset section; the bottom navigation is
      // verified by its pie-chart icon while "记录" must exist only once as
      // the quick action (there is no records tab anymore).
      expect(find.byIcon(Icons.pie_chart), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
      expect(find.text('记录'), findsOneWidget);
      await _capture(binding, tester, '01-home-three-tabs');

      await _openRecords(tester);
      expect(find.text('暂无交易记录'), findsOneWidget);
      expect(find.text('-120.00 USDT'), findsNothing);
      expect(find.text('+0.05 ETH'), findsNothing);
      await _capture(binding, tester, '02-wallet-empty-history');

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      results
        ..clear()
        ..addAll(_fixtureResults);
      await history.refresh();
      await tester.pumpAndSettle();
      await _openRecords(tester);
      expect(find.text('+2 USDT'), findsOneWidget);
      expect(find.text('-0.2 ETH'), findsOneWidget);
      expect(find.text('-9 USDT'), findsOneWidget);
      await _capture(binding, tester, '03-wallet-all-history');

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      await _openToken(tester, _usdt);
      expect(find.text('Ethereum'), findsWidgets);
      await _capture(binding, tester, '04-usdt-ethereum-detail');

      await tester.ensureVisible(find.byKey(const ValueKey('asset-history')));
      await tester.pumpAndSettle();
      expect(find.text('+2 USDT'), findsOneWidget);
      expect(find.text('-0.2 ETH'), findsNothing);
      expect(find.text('-9 USDT'), findsNothing);
      await _capture(binding, tester, '05-usdt-ethereum-history');

      await tester.ensureVisible(find.byKey(const ValueKey('chain-chip')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chain-chip')));
      await tester.pumpAndSettle();
      expect(find.text('选择网络'), findsOneWidget);
      expect(find.text('Ethereum'), findsWidgets);
      expect(find.text('Polygon'), findsOneWidget);
      await _capture(binding, tester, '06-usdt-network-picker');

      await tester.tap(find.byKey(const ValueKey('chain-option-usdt-polygon')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('asset-history')));
      await tester.pumpAndSettle();
      expect(find.text('-9 USDT'), findsOneWidget);
      expect(find.text('+2 USDT'), findsNothing);
      expect(find.text('-0.2 ETH'), findsNothing);
      await _capture(binding, tester, '07-usdt-polygon-history');

      // Keep the final frame available briefly so host-side tooling can pull
      // Android cache files before the integration runner exits.
      // ignore: avoid_print
      print('RECORDS_UI_CAPTURE READY=all');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 30)),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
