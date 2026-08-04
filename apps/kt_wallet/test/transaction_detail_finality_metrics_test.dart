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
      const TransactionConfirmation(
        status: TxStatus.confirmed,
        confirmations: 1,
      );
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
        ..broadcastTxHash = _replacementHash;

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
