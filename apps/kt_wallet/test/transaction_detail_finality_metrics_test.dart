import 'dart:async';

import 'package:chains/chains.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/market/transaction_status_service.dart';
import 'package:kt_wallet/src/observability/experience_metrics.dart';
import 'package:kt_wallet/src/screens/transfer_screens.dart';
import 'package:kt_wallet/src/state/networks.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/state/wallet_scope.dart';
import 'package:kt_wallet/src/transfer/transaction_confirmation_service.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:kt_wallet/src/wallets/wallet_store.dart';
import 'package:wallet_data/wallet_data.dart';

const _walletId = 'detail-finality-wallet';
const _owner = '0x1111111111111111111111111111111111111111';
const _recipient = '0x2222222222222222222222222222222222222222';
const _originalHash =
    '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _replacementHash =
    '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

class _ConfirmedStatusService extends TransactionStatusService {
  @override
  Future<ChainTransactionStatus> check(Transaction transaction) async =>
      ChainTransactionStatus.confirmed;
}

class _ConfirmedConfirmationService extends TransactionConfirmationService {
  _ConfirmedConfirmationService() : super(endpoints: (_) => 'https://unused');

  @override
  Future<TransactionConfirmation> check(Chain chain, String hash) async =>
      TransactionConfirmation(
        status: TxStatus.confirmed,
        confirmations: 1,
        actualFeeRaw: BigInt.from(1800646949999),
      );
}

class _PendingStatusService extends TransactionStatusService {
  @override
  Future<ChainTransactionStatus> check(Transaction transaction) async =>
      ChainTransactionStatus.pending;
}

class _BlockingConfirmationService extends TransactionConfirmationService {
  _BlockingConfirmationService() : super(endpoints: (_) => 'https://unused');

  final release = Completer<void>();

  @override
  Future<TransactionConfirmation> check(Chain chain, String hash) async {
    await release.future;
    return const TransactionConfirmation(
      status: TxStatus.confirmed,
      confirmations: 1,
    );
  }
}

HotWallet _wallet() => HotWallet(
  id: _walletId,
  name: 'Finality wallet',
  avatarColor: 0xFF2557E8,
  addresses: ChainAddresses(
    eth: _owner,
    polygon: _owner,
    base: _owner,
    arbitrum: _owner,
    avalanche: _owner,
    bnb: _owner,
    tron: 'TJRabPrwbZy45sbavfcjinPJC18kjpRTv8',
    solana: '11111111111111111111111111111111',
  ),
  backedUp: true,
);

Future<void> _savePendingLineage(WalletStore store, int now) async {
  await store.upsertTransaction(
    id: 'original',
    walletId: _walletId,
    coin: Coin.eth,
    networkId: 'eth-mainnet',
    from: _owner,
    to: _recipient,
    amountRaw: '1',
    hash: _originalHash,
    status: TxStatus.pending,
    signMode: SignMode.local,
    createdAt: now - 2000,
    broadcastAt: now - 1900,
    nonce: '7',
    replacedById: 'replacement',
  );
  await store.upsertTransaction(
    id: 'replacement',
    walletId: _walletId,
    coin: Coin.eth,
    networkId: 'eth-mainnet',
    from: _owner,
    to: _recipient,
    amountRaw: '1',
    hash: _replacementHash,
    status: TxStatus.pending,
    signMode: SignMode.local,
    createdAt: now - 1000,
    broadcastAt: now - 900,
    nonce: '7',
    replacesId: 'original',
    replacementKind: TxReplacementKind.speedUp,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(ExperienceMetrics.instance.clear);

  testWidgets(
    'detail-first EVM settlement records winner and replaced finality once',
    (tester) async {
      final database = WalletDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final store = WalletStore(database);
      final wallet = _wallet();
      await store.save(wallet);
      await _savePendingLineage(store, DateTime.now().millisecondsSinceEpoch);
      final wallets = WalletController(
        WalletManager(initial: [wallet]),
        store: store,
      );
      addTearDown(wallets.dispose);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: WalletScope(
            controller: wallets,
            child: NetworkScope(
              controller: NetworkController(),
              child: TxDetailScreen(
                transactionId: 'replacement',
                statusService: _ConfirmedStatusService(),
                pollInterval: Duration.zero,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();

      final rows = await wallets.localTransactions();
      expect(
        rows.singleWhere((row) => row.id == 'replacement').status,
        TxStatus.confirmed,
      );
      expect(
        rows.singleWhere((row) => row.id == 'original').status,
        TxStatus.replaced,
      );
      final samples = ExperienceMetrics.instance.recent
          .where(
            (metric) =>
                metric.name == ExperienceMetricNames.transactionFinality,
          )
          .toList();
      expect(samples, hasLength(2));
      expect(samples.where((metric) => metric.success), hasLength(1));
      expect(samples.where((metric) => !metric.success), hasLength(1));

      // A second observer sees terminal rows and must not emit duplicates.
      await tester.pump(const Duration(milliseconds: 20));
      expect(
        ExperienceMetrics.instance.recent.where(
          (metric) => metric.name == ExperienceMetricNames.transactionFinality,
        ),
        hasLength(2),
      );
    },
  );

  testWidgets('TRON pending result follows the exchange-style KT adaptation', (
    tester,
  ) async {
    final database = WalletDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = WalletStore(database);
    final wallet = _wallet();
    await store.save(wallet);
    final now = DateTime.now().millisecondsSinceEpoch;
    const hash =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    await store.upsertTransaction(
      id: 'tron-broadcast-result',
      walletId: _walletId,
      coin: Coin.tron,
      networkId: 'tron-mainnet',
      contract: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
      from: wallet.addresses.tron,
      to: 'TA5X6WfP1smMYoVx92yP9xiFPcPm7fqK2w',
      amountRaw: '10000000',
      feeRaw: '7714200',
      hash: hash,
      status: TxStatus.pending,
      signMode: SignMode.local,
      createdAt: now - 1000,
      broadcastAt: now - 900,
    );
    final wallets = WalletController(
      WalletManager(initial: [wallet]),
      store: store,
    );
    addTearDown(wallets.dispose);
    final session = TransferSession()
      ..begin(
        TransferDraft(
          symbol: 'USDT',
          networkLabel: 'TRON · TRC-20',
          chain: Chain.tron,
          recipient: 'TA5X6WfP1smMYoVx92yP9xiFPcPm7fqK2w',
          amount: Amount(
            raw: BigInt.from(10000000),
            decimals: 6,
            symbol: 'USDT',
          ),
          feeTier: 1,
          tokenContract: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
        ),
      )
      ..localTransactionId = 'tron-broadcast-result'
      ..broadcastTxHash = hash;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: WalletScope(
          controller: wallets,
          child: NetworkScope(
            controller: NetworkController(),
            child: TransferSessionScope(
              session: session,
              child: BroadcastResultScreen(
                statusService: _PendingStatusService(),
                pollInterval: const Duration(days: 1),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('正在转账 10 USDT'), findsOneWidget);
    expect(find.text(r'≈ $10.00'), findsOneWidget);
    expect(find.text('处理中'), findsOneWidget);
    expect(find.text('确认中'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('broadcast-processing-icon')),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('broadcast-processing-icon'))),
      const Size(32, 32),
    );
    final statusIconTop = tester
        .getTopLeft(find.byKey(const ValueKey('broadcast-processing-icon')))
        .dy;
    final statusLabelTop = tester.getTopLeft(find.text('状态')).dy;
    final stateValueTop = tester
        .getTopLeft(find.byKey(const ValueKey('broadcast-result-state')))
        .dy;
    expect(statusLabelTop, closeTo(statusIconTop + 7, 1));
    expect(stateValueTop, closeTo(statusIconTop + 7, 1));
    expect(
      find.byKey(const ValueKey('broadcast-result-divider')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('broadcast-asset-icon')), findsOneWidget);
    expect(find.text('TRON · TRC-20'), findsOneWidget);
    expect(find.text('≤ 7.7142 TRX'), findsOneWidget);
    final rightEdge = tester.getTopRight(find.text(r'$10.00')).dx;
    expect(
      tester
          .getTopRight(find.byKey(const ValueKey('broadcast-result-state')))
          .dx,
      closeTo(rightEdge, 1),
    );
    expect(
      tester.getTopRight(find.text('TRON · TRC-20')).dx,
      closeTo(rightEdge, 1),
    );
    final addressCopyIcon = find.descendant(
      of: find.byKey(const ValueKey('copy-broadcast-address')),
      matching: find.byIcon(Icons.copy_rounded),
    );
    final hashCopyIcon = find.descendant(
      of: find.byKey(const ValueKey('copy-broadcast-hash')),
      matching: find.byIcon(Icons.copy_rounded),
    );
    expect(tester.getTopRight(addressCopyIcon).dx, closeTo(rightEdge, 1));
    expect(tester.getTopRight(hashCopyIcon).dx, closeTo(rightEdge, 1));
    final hashValue = find.text('aaaaaaa…aaaaaaa');
    expect(
      tester.getTopLeft(hashCopyIcon).dy,
      closeTo(tester.getTopLeft(hashValue).dy, 1),
    );
    final addressLabelTop = tester.getTopLeft(find.text('地址')).dy;
    final addressValueTop = tester
        .getTopLeft(find.text('TA5X6WfP1smMYoVx92yP9xiFPcPm7fqK2w'))
        .dy;
    expect(addressValueTop, closeTo(addressLabelTop, 1));
    expect(find.text('返回首页'), findsOneWidget);
    expect(find.textContaining('参考编号'), findsNothing);
  });

  testWidgets(
    'broadcast direct confirmation is terminal and records finality once',
    (tester) async {
      final database = WalletDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final store = WalletStore(database);
      final wallet = _wallet();
      await store.save(wallet);
      final now = DateTime.now().millisecondsSinceEpoch;
      await store.upsertTransaction(
        id: 'broadcast-result',
        walletId: _walletId,
        coin: Coin.eth,
        networkId: 'eth-mainnet',
        from: _owner,
        to: _recipient,
        amountRaw: '1',
        feeRaw: '4341584310463',
        hash: _replacementHash,
        status: TxStatus.pending,
        signMode: SignMode.local,
        createdAt: now - 1000,
        broadcastAt: now - 900,
        nonce: '8',
      );
      final wallets = WalletController(
        WalletManager(initial: [wallet]),
        store: store,
      );
      addTearDown(wallets.dispose);
      final session = TransferSession()
        ..begin(
          TransferDraft(
            symbol: 'ETH',
            networkLabel: 'Ethereum',
            chain: Chain.ethereum,
            recipient: _recipient,
            amount: Amount(raw: BigInt.one, decimals: 18, symbol: 'ETH'),
            feeTier: 1,
          ),
        )
        ..localTransactionId = 'broadcast-result'
        ..broadcastTxHash = _replacementHash
        ..broadcastOutcomeUnknown = true;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: WalletScope(
            controller: wallets,
            child: NetworkScope(
              controller: NetworkController(),
              child: TransferSessionScope(
                session: session,
                child: BroadcastResultScreen(
                  confirmationService: _ConfirmedConfirmationService(),
                  statusService: _ConfirmedStatusService(),
                  pollInterval: Duration.zero,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();

      expect(
        (await wallets.localTransactionById('broadcast-result'))?.status,
        TxStatus.confirmed,
      );
      expect(session.broadcastOutcomeUnknown, isFalse);
      expect(find.text('Completed'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('broadcast-completed-icon')),
        findsOneWidget,
      );
      expect(find.text('View on blockchain explorer'), findsOneWidget);
      expect(find.text('Broadcast result unknown'), findsNothing);
      expect(find.text('0.0000018 ETH'), findsOneWidget);
      expect(
        (await wallets.localTransactionById('broadcast-result'))?.actualFeeRaw,
        '1800646949999',
      );
      final samples = ExperienceMetrics.instance.recent.where(
        (metric) => metric.name == ExperienceMetricNames.transactionFinality,
      );
      expect(samples, hasLength(1));
      expect(samples.single.success, isTrue);

      await tester.pump(const Duration(milliseconds: 20));
      expect(
        ExperienceMetrics.instance.recent.where(
          (metric) => metric.name == ExperienceMetricNames.transactionFinality,
        ),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'gateway finality is not blocked by an unreachable direct RPC depth lookup',
    (tester) async {
      final database = WalletDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final store = WalletStore(database);
      final wallet = _wallet();
      await store.save(wallet);
      final now = DateTime.now().millisecondsSinceEpoch;
      await store.upsertTransaction(
        id: 'gateway-first-result',
        walletId: _walletId,
        coin: Coin.eth,
        networkId: 'eth-mainnet',
        from: _owner,
        to: _recipient,
        amountRaw: '1',
        hash: _replacementHash,
        status: TxStatus.pending,
        signMode: SignMode.local,
        createdAt: now - 1000,
        broadcastAt: now - 900,
        nonce: '9',
      );
      final wallets = WalletController(
        WalletManager(initial: [wallet]),
        store: store,
      );
      addTearDown(wallets.dispose);
      final session = TransferSession()
        ..begin(
          TransferDraft(
            symbol: 'ETH',
            networkLabel: 'Ethereum',
            chain: Chain.ethereum,
            recipient: _recipient,
            amount: Amount(raw: BigInt.one, decimals: 18, symbol: 'ETH'),
            feeTier: 1,
          ),
        )
        ..localTransactionId = 'gateway-first-result'
        ..broadcastTxHash = _replacementHash;
      final depth = _BlockingConfirmationService();
      addTearDown(() {
        if (!depth.release.isCompleted) depth.release.complete();
      });

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: WalletScope(
            controller: wallets,
            child: NetworkScope(
              controller: NetworkController(),
              child: TransferSessionScope(
                session: session,
                child: BroadcastResultScreen(
                  confirmationService: depth,
                  statusService: _ConfirmedStatusService(),
                  pollInterval: const Duration(days: 1),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(
        (await wallets.localTransactionById('gateway-first-result'))?.status,
        TxStatus.confirmed,
      );

      depth.release.complete();
      await tester.pumpAndSettle();
    },
  );
}
