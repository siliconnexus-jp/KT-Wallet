import 'dart:typed_data';

import 'package:chains/chains.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/screens/transfer_screens.dart';
import 'package:kt_wallet/src/security/transaction_auth.dart';
import 'package:kt_wallet/src/state/app_prefs.dart';
import 'package:kt_wallet/src/state/networks.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/state/wallet_scope.dart';
import 'package:kt_wallet/src/transfer/local_transfer_service.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:kt_wallet/src/wallets/wallet_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallet_data/wallet_data.dart';

const _owner = '0x85f6be9460291e86e0fb49b07d0a83cc5f7206cd';
const _recipient = '0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed';
const _localHash =
    '0x1111111111111111111111111111111111111111111111111111111111111111';

HotWallet _wallet() => HotWallet(
  id: 'wallet-replacement-recovery',
  name: 'Replacement recovery',
  avatarColor: 0xFF2557E8,
  addresses: const ChainAddresses(
    eth: _owner,
    polygon: _owner,
    base: _owner,
    arbitrum: _owner,
    avalanche: _owner,
    bnb: _owner,
    tron: 'TQm9xPa2Wc8hJdU5eRnT6yGb1sVb7L3kFa',
    solana: '6yKpXwMWd4qmDqVr2W1111111111111111111111',
  ),
  backedUp: true,
);

Transaction _original() => const Transaction(
  id: 'original-pending',
  walletId: 'wallet-replacement-recovery',
  coin: 'eth',
  networkId: 'eth-mainnet',
  operation: TxOperationKind.transfer,
  direction: TxDirection.outgoing,
  fromAddr: _owner,
  toAddr: _recipient,
  amountRaw: '1000000000000000',
  feeRaw: '42000000000000',
  hash: '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  status: TxStatus.pending,
  signMode: SignMode.local,
  createdAt: 1700000000000,
  broadcastAt: 1700000000001,
  nonce: '7',
  maxPriorityFeeRaw: '2000000000',
  maxFeeRaw: '30000000000',
  gasLimitRaw: '21000',
);

class _ResponseLostReplacementService extends LocalTransferService {
  int prepareCalls = 0;
  int signCalls = 0;
  int broadcastCalls = 0;

  @override
  Future<PreparedEvmTransfer> prepareEvmReplacement({
    required Chain chain,
    required int evmChainId,
    required String from,
    required String recipient,
    required BigInt amountRaw,
    required String? tokenContract,
    TxOperation? operation,
    required BigInt nonce,
    required BigInt previousMaxPriorityFeePerGas,
    required BigInt previousMaxFeePerGas,
    required BigInt previousGasLimit,
    required bool cancel,
  }) async {
    prepareCalls++;
    return PreparedEvmTransfer(
      chain: chain,
      evmChainId: evmChainId,
      coin: Coin.eth,
      operation: TxOperation.nativeTransfer,
      from: from,
      recipient: cancel ? from : recipient,
      amountRaw: cancel ? BigInt.zero : amountRaw,
      tokenContract: null,
      nonce: nonce,
      maxPriorityFeePerGas: previousMaxPriorityFeePerGas + BigInt.one,
      maxFeePerGas: previousMaxFeePerGas + BigInt.one,
      gasLimit: previousGasLimit,
      unsignedTx: Uint8List.fromList(const [1, 2, 3]),
    );
  }

  @override
  Future<SignedTransaction> signPreparedEvm({
    required HotWallet wallet,
    required CoreCrypto crypto,
    required PreparedEvmTransfer prepared,
  }) async {
    signCalls++;
    return SignedTransaction(
      signedTx: Uint8List.fromList(const [4, 5, 6]),
      txHash: _localHash,
    );
  }

  @override
  Future<String> broadcastSigned(
    Chain chain,
    Uint8List signedTx, {
    required String expectedTxHash,
  }) async {
    broadcastCalls++;
    expect(expectedTxHash, _localHash);
    throw const LocalTransferUncertainException('response lost');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'response-lost replacement is durable and a retry cannot sign or post',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      SharedPreferences.setMockInitialValues({});
      final prefs = AppPrefsController();
      await prefs.load();
      final database = WalletDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final store = WalletStore(database);
      final hot = _wallet();
      final original = _original();
      await store.save(hot);
      await store.upsertTransaction(
        id: original.id,
        walletId: hot.id,
        coin: Coin.eth,
        networkId: original.networkId!,
        from: original.fromAddr,
        to: original.toAddr,
        amountRaw: original.amountRaw,
        feeRaw: original.feeRaw,
        hash: original.hash,
        status: original.status,
        signMode: original.signMode,
        createdAt: original.createdAt,
        broadcastAt: original.broadcastAt,
        nonce: original.nonce,
        maxPriorityFeeRaw: original.maxPriorityFeeRaw,
        maxFeeRaw: original.maxFeeRaw,
        gasLimitRaw: original.gasLimitRaw,
      );
      final wallets = WalletController(
        WalletManager(initial: [hot]),
        store: store,
      );
      final service = _ResponseLostReplacementService();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: WalletScope(
            controller: wallets,
            child: NetworkScope(
              controller: NetworkController(),
              child: AppPrefsScope(
                controller: prefs,
                child: TxDetailScreen(
                  transaction: original,
                  transferService: service,
                  authGate: const FakeTransactionAuthGate(true),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> speedUp() async {
        await tester.tap(find.text('Speed up'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('kt-dialog-confirm')));
        await tester.pumpAndSettle();
      }

      await speedUp();
      expect(find.textContaining('Do not send it again'), findsOneWidget);
      var rows = await wallets.localTransactions();
      expect(rows, hasLength(2));
      final replacement = rows.singleWhere((row) => row.id != original.id);
      expect(replacement.status, TxStatus.submitted);
      expect(replacement.hash, _localHash);
      expect(replacement.broadcastAt, isNotNull);
      expect(replacement.replacesId, original.id);
      expect(service.signCalls, 1);
      expect(service.broadcastCalls, 1);

      // The stale injected screen still exposes the original action, which
      // deliberately exercises the repository nonce guard. The second user
      // tap may prepare, but cannot sign or cross the network boundary.
      ScaffoldMessenger.of(
        tester.element(find.byType(TxDetailScreen)),
      ).hideCurrentSnackBar();
      await tester.pumpAndSettle();
      await speedUp();
      rows = await wallets.localTransactions();
      expect(rows, hasLength(2));
      expect(service.prepareCalls, 2);
      expect(service.signCalls, 1);
      expect(service.broadcastCalls, 1);
      expect(find.textContaining('nonce is already reserved'), findsOneWidget);
    },
  );

  testWidgets('replacement signing is blocked when wallet auth is denied', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    SharedPreferences.setMockInitialValues({});
    final prefs = AppPrefsController();
    await prefs.load();
    final service = _ResponseLostReplacementService();
    final wallets = WalletController(WalletManager(initial: [_wallet()]));

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: WalletScope(
          controller: wallets,
          child: NetworkScope(
            controller: NetworkController(),
            child: AppPrefsScope(
              controller: prefs,
              child: TxDetailScreen(
                transaction: _original(),
                transferService: service,
                authGate: const FakeTransactionAuthGate(false),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speed up'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('kt-dialog-confirm')));
    await tester.pumpAndSettle();

    expect(service.prepareCalls, 0);
    expect(service.signCalls, 0);
    expect(service.broadcastCalls, 0);
  });
}
