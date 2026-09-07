import 'package:core_crypto/core_crypto.dart' show Coin, ChainAddresses;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/market/history_controller.dart';
import 'package:kt_wallet/src/market/history_service.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';

class _IncomingHistory extends HistoryService {
  int calls = 0;
  bool fail = false;
  @override
  Future<HistoryResult> fetch(
    Coin coin,
    String address, {
    int limit = HistoryService.pageSize,
    String? networkId,
  }) async {
    if (coin != Coin.tron) return const HistoryResult.unsupported();
    calls++;
    if (fail) return const HistoryResult.error();
    return HistoryResult.ok(
      calls < 2
          ? []
          : [
              ChainTxRecord(
                coin: Coin.tron,
                networkId: 'tron-mainnet',
                id: 'incoming',
                hash: 'a' * 64,
                outgoing: false,
                fromAddress: 'external',
                toAddress: address,
                amountText: '1 USDT',
                timestamp: DateTime(2026),
                confirmed: true,
              ),
            ],
    );
  }
}

void main() {
  testWidgets(
    'discovers incoming history without Pending; shares one timer and pauses when hidden/backgrounded',
    (tester) async {
      final wallet = HotWallet(
        id: 'one',
        name: 'One',
        avatarColor: 0,
        addresses: const ChainAddresses(
          eth: '0x1111111111111111111111111111111111111111',
          polygon: '0x1111111111111111111111111111111111111111',
          tron: 'TNXoiAJ3dct8Fjg4M9fkLFh9S2v9TXc32G',
          solana: '11111111111111111111111111111111',
        ),
      );
      final wallets = WalletController(WalletManager(initial: [wallet]));
      final service = _IncomingHistory();
      final history = HistoryController(
        wallets: wallets,
        service: service,
        historyRefreshInterval: const Duration(seconds: 1),
      );
      final viewer = Object(), second = Object();
      history.setHistoryVisible(viewer, true);
      await tester.pump();
      expect(service.calls, 1);
      expect(history.resultFor(Coin.tron).records, isEmpty);
      history.setHistoryVisible(second, true);
      await tester.pump(const Duration(seconds: 1));
      expect(service.calls, 2);
      expect(history.resultFor(Coin.tron).records.single.amountText, '1 USDT');
      history.setHistoryVisible(viewer, false);
      await tester.pump(const Duration(seconds: 1));
      expect(service.calls, 3);
      history.setHistoryVisible(second, false);
      await tester.pump(const Duration(seconds: 5));
      expect(service.calls, 3);
      history.setHistoryVisible(viewer, true);
      await tester.pump();
      expect(service.calls, 4);
      history.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 5));
      expect(service.calls, 4);
      history.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(service.calls, 5);
      service.fail = true;
      await tester.pump(const Duration(seconds: 1));
      expect(service.calls, 6);
      // Failure backs off, without clearing last-good records.
      await tester.pump(const Duration(seconds: 1));
      expect(service.calls, 6);
      expect(history.resultFor(Coin.tron).records, isNotEmpty);
      await tester.pump(const Duration(seconds: 1));
      expect(service.calls, 7);
      history.dispose();
      wallets.dispose();
      await tester.pump(const Duration(seconds: 10));
      expect(service.calls, 7);
    },
  );
}
