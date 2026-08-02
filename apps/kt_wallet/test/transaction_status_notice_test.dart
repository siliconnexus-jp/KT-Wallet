import 'package:core_crypto/core_crypto.dart' show ChainAddresses, Coin;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/market/history_controller.dart';
import 'package:kt_wallet/src/market/history_service.dart';
import 'package:kt_wallet/src/market/transaction_status_service.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:kt_wallet/src/wallets/wallet_store.dart';
import 'package:kt_wallet/src/widgets/transaction_status_notice.dart';
import 'package:wallet_data/wallet_data.dart';

const _hash1 =
    '0x1111111111111111111111111111111111111111111111111111111111111111';
const _hash2 =
    '0x2222222222222222222222222222222222222222222222222222222222222222';

class _NoHistory extends HistoryService {
  @override
  Future<HistoryResult> fetch(
    Coin coin,
    String address, {
    int limit = HistoryService.pageSize,
    String? networkId,
  }) async => const HistoryResult.unsupported();
}

class _MutableStatuses extends TransactionStatusService {
  ChainTransactionStatus status = ChainTransactionStatus.pending;
  int checks = 0;

  @override
  Future<ChainTransactionStatus> check(Transaction transaction) async {
    checks++;
    return status;
  }
}

Future<
  ({
    WalletDatabase database,
    WalletController wallets,
    HistoryController history,
    _MutableStatuses statuses,
  })
>
_fixture() async {
  final database = WalletDatabase(NativeDatabase.memory());
  final wallet = HotWallet(
    id: 'status-wallet',
    name: 'Status',
    avatarColor: 0xFF123456,
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
  for (var i = 1; i <= 2; i++) {
    await wallets.saveOutgoingTransaction(
      id: 'pending-$i',
      coin: Coin.eth,
      networkId: 'eth-mainnet',
      from: wallet.addresses.eth,
      to: '0x2222222222222222222222222222222222222222',
      amountRaw: '$i',
      hash: i == 1 ? _hash1 : _hash2,
      status: TxStatus.pending,
      signMode: SignMode.local,
      createdAt: i,
      broadcastAt: i,
    );
  }
  final statuses = _MutableStatuses();
  final history = HistoryController(
    wallets: wallets,
    service: _NoHistory(),
    statusService: statuses,
    activeNetworkIds: () => {'eth-mainnet'},
    pollInterval: const Duration(days: 1),
  );
  return (
    database: database,
    wallets: wallets,
    history: history,
    statuses: statuses,
  );
}

Widget _noticeApp(HistoryController controller) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: TransactionStatusNoticeHost(
    controller: controller,
    child: const Scaffold(body: SizedBox.expand()),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('simultaneous confirmations are queued and shown once each', (
    tester,
  ) async {
    final fixture = await _fixture();
    addTearDown(fixture.history.dispose);
    addTearDown(fixture.database.close);
    fixture.statuses.status = ChainTransactionStatus.confirmed;

    await tester.pumpWidget(_noticeApp(fixture.history));
    await fixture.history.refresh();
    await tester.pump();

    final first = find.byKey(
      const ValueKey('transaction-status-notice-$_hash1'),
    );
    final second = find.byKey(
      const ValueKey('transaction-status-notice-$_hash2'),
    );
    expect(first.evaluate().length + second.evaluate().length, 1);

    final firstWasVisible = first.evaluate().isNotEmpty;
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(first.evaluate().isNotEmpty, isNot(firstWasVisible));
    expect(second.evaluate().isNotEmpty, firstWasVisible);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(first, findsNothing);
    expect(second, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'resuming immediately rechecks pending hashes and emits transitions',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.history.dispose);
      addTearDown(fixture.database.close);

      await fixture.history.refresh();
      expect(fixture.statuses.checks, 2);
      expect(fixture.history.takeNotices(), isEmpty);

      fixture.statuses.status = ChainTransactionStatus.confirmed;
      fixture.history.didChangeAppLifecycleState(AppLifecycleState.paused);
      fixture.history.didChangeAppLifecycleState(AppLifecycleState.resumed);
      for (var i = 0; i < 50 && fixture.statuses.checks < 4; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }

      expect(fixture.statuses.checks, 4);
      final notices = fixture.history.takeNotices();
      expect(notices, hasLength(2));
      expect(notices.map((notice) => notice.hash).toSet(), {_hash1, _hash2});
      expect(notices.every((notice) => notice.confirmed), isTrue);
      expect(
        (await fixture.wallets.localTransactions()).every(
          (transaction) => transaction.status == TxStatus.confirmed,
        ),
        isTrue,
      );
    },
  );
}
