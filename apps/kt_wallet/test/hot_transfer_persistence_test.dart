import 'dart:typed_data';

import 'package:chains/chains.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:core_crypto/testing.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/app_router.dart';
import 'package:kt_wallet/src/state/app_prefs.dart';
import 'package:kt_wallet/src/state/networks.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/state/wallet_scope.dart';
import 'package:kt_wallet/src/transfer/local_transfer_service.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:kt_wallet/src/wallets/wallet_store.dart';
import 'package:wallet_data/wallet_data.dart';

const _evmAddress = '0x85f6be9460291e86e0fb49b07d0a83cc5f7206cd';
const _evmRecipient = '0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed';
const _tronAddress = 'TQm9xPa2Wc8hJdU5eRnT6yGb1sVb7L3kFa';
const _tronRecipient = 'TWd4qCEUf3aVpXe2HKk9gJt6nMxR38uQz';
const _solanaAddress = '6yKpXwMWd4qmDqVr2W1111111111111111111111';
const _solanaRecipient = '11111111111111111111111111111111';

HotWallet _wallet() => HotWallet(
  id: 'wallet-durable-send',
  name: 'Durable send',
  avatarColor: 0xFF2557E8,
  addresses: const ChainAddresses(
    eth: _evmAddress,
    polygon: _evmAddress,
    base: _evmAddress,
    arbitrum: _evmAddress,
    avalanche: _evmAddress,
    bnb: _evmAddress,
    tron: _tronAddress,
    solana: _solanaAddress,
  ),
  backedUp: true,
);

TransferSession _session(Chain chain) {
  final session = TransferSession();
  final now = DateTime.now().millisecondsSinceEpoch;
  switch (chain) {
    case Chain.ethereum:
      final draft = TransferDraft(
        symbol: 'ETH',
        networkLabel: 'Sepolia',
        chain: chain,
        recipient: _evmRecipient,
        amount: Amount(
          raw: BigInt.from(1000000000000000),
          decimals: 18,
          symbol: 'ETH',
        ),
        feeTier: 1,
      );
      session
        ..begin(draft)
        ..preparedEvm = PreparedEvmTransfer(
          chain: chain,
          evmChainId: ethSepolia.evmChainId!,
          coin: Coin.eth,
          operation: TxOperation.nativeTransfer,
          from: _evmAddress,
          recipient: _evmRecipient,
          amountRaw: draft.amount.raw,
          tokenContract: null,
          nonce: BigInt.from(7),
          maxPriorityFeePerGas: BigInt.from(2),
          maxFeePerGas: BigInt.from(30),
          gasLimit: BigInt.from(21000),
          unsignedTx: Uint8List.fromList(const [1, 2, 3]),
        )
        ..preparedNetworkId = ethSepolia.id
        ..preparedAtMs = now;
    case Chain.tron:
      final draft = TransferDraft(
        symbol: 'TRX',
        networkLabel: 'Nile',
        chain: chain,
        recipient: _tronRecipient,
        amount: Amount(raw: BigInt.from(1500000), decimals: 6, symbol: 'TRX'),
        feeTier: 1,
      );
      session
        ..begin(draft)
        ..preparedTron = PreparedTronTransfer(
          from: _tronAddress,
          recipient: _tronRecipient,
          amountRaw: draft.amount.raw,
          tokenContract: null,
          maximumFeeSun: BigInt.from(1200000),
          referenceBlockHeight: 4242,
          expiresAt: now + const Duration(minutes: 10).inMilliseconds,
          rawTx: Uint8List.fromList(const [4, 5, 6]),
        )
        ..preparedNetworkId = tronNile.id
        ..preparedAtMs = now;
    case Chain.solana:
      final draft = TransferDraft(
        symbol: 'SOL',
        networkLabel: 'Devnet',
        chain: chain,
        recipient: _solanaRecipient,
        amount: Amount(raw: BigInt.from(1000000), decimals: 9, symbol: 'SOL'),
        feeTier: 1,
      );
      session
        ..begin(draft)
        ..preparedSolana = PreparedSolanaTransfer(
          from: _solanaAddress,
          recipient: _solanaRecipient,
          amountRaw: draft.amount.raw,
          tokenMint: null,
          tokenProgram: null,
          networkFeeLamports: BigInt.from(5000),
          rentDepositLamports: BigInt.zero,
          lastValidBlockHeight: 987654,
          message: Uint8List.fromList(const [7, 8, 9]),
        )
        ..preparedNetworkId = solanaDevnet.id
        ..preparedAtMs = now;
    case Chain.polygon ||
        Chain.base ||
        Chain.arbitrum ||
        Chain.avalanche ||
        Chain.bnb:
      throw ArgumentError.value(chain, 'chain');
  }
  return session;
}

class _ResponseLostService extends LocalTransferService {
  _ResponseLostService({required this.wallets, required this.session});

  final WalletController wallets;
  final TransferSession session;
  int signCalls = 0;
  int broadcastCalls = 0;
  bool intentWasDurableBeforeSign = false;
  bool hashWasDurableBeforeBroadcast = false;

  static const localHash = 'locally-derived-transaction-hash';

  Future<SignedTransaction> _sign() async {
    signCalls++;
    final id = session.localTransactionId;
    final row = id == null ? null : await wallets.localTransactionById(id);
    intentWasDurableBeforeSign =
        row != null && row.status == TxStatus.submitted && row.hash == null;
    return SignedTransaction(
      signedTx: Uint8List.fromList(const [10, 11, 12]),
      txHash: localHash,
    );
  }

  @override
  Future<SignedTransaction> signPreparedEvm({
    required HotWallet wallet,
    required CoreCrypto crypto,
    required PreparedEvmTransfer prepared,
  }) => _sign();

  @override
  Future<SignedTransaction> signPreparedTron({
    required HotWallet wallet,
    required CoreCrypto crypto,
    required PreparedTronTransfer prepared,
    required String? expectedNetworkIdentity,
  }) => _sign();

  @override
  Future<SignedTransaction> signPreparedSolana({
    required HotWallet wallet,
    required CoreCrypto crypto,
    required PreparedSolanaTransfer prepared,
    required String? expectedNetworkIdentity,
  }) => _sign();

  @override
  Future<String> broadcastSigned(
    Chain chain,
    Uint8List signedTx, {
    required String expectedTxHash,
  }) async {
    broadcastCalls++;
    final id = session.localTransactionId;
    final row = id == null ? null : await wallets.localTransactionById(id);
    hashWasDurableBeforeBroadcast =
        row != null &&
        row.status == TxStatus.submitted &&
        row.hash == localHash &&
        expectedTxHash == localHash &&
        row.broadcastAt != null &&
        signedTx.length == 3;
    // Model the dangerous ambiguity: the node may have accepted the bytes,
    // but the HTTP response was lost before the app received its tx hash.
    throw const LocalTransferUncertainException('broadcast response lost');
  }
}

Widget _app({
  required GoRouter router,
  required WalletController wallets,
  required NetworkController networks,
  required TransferSession session,
}) => MaterialApp.router(
  debugShowCheckedModeBanner: false,
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  routerConfig: router,
  builder: (context, child) => WalletScope(
    controller: wallets,
    child: NetworkScope(
      controller: networks,
      child: AppPrefsScope(
        controller: AppPrefsController(),
        child: TransferSessionScope(session: session, child: child!),
      ),
    ),
  ),
);

Future<({WalletDatabase database, WalletController wallets})> _fixture() async {
  final database = WalletDatabase(NativeDatabase.memory());
  final store = WalletStore(database);
  final wallet = _wallet();
  await store.save(wallet);
  return (
    database: database,
    wallets: WalletController(
      WalletManager(initial: [wallet]),
      crypto: MockCoreCrypto(),
      store: store,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final chain in [Chain.ethereum, Chain.tron, Chain.solana]) {
    testWidgets(
      '${chain.name}: intent and local hash are durable before a response-lost broadcast',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);

        final fixture = await _fixture();
        addTearDown(fixture.database.close);
        final session = _session(chain);
        final networks = NetworkController(
          initialEnvironment: NetworkEnvironment.testnet,
        );
        final service = _ResponseLostService(
          wallets: fixture.wallets,
          session: session,
        );
        final router = buildRouter(
          initialLocation: '/transfer-auth',
          galleryMode: false,
          walletController: fixture.wallets,
          transferService: service,
          transferSession: session,
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _app(
            router: router,
            wallets: fixture.wallets,
            networks: networks,
            session: session,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Use biometrics'));
        await tester.pumpAndSettle();

        expect(service.signCalls, 1);
        expect(service.broadcastCalls, 1);
        expect(service.intentWasDurableBeforeSign, isTrue);
        expect(service.hashWasDurableBeforeBroadcast, isTrue);
        final row = await fixture.wallets.localTransactionById(
          session.localTransactionId!,
        );
        expect(row, isNotNull);
        expect(row!.status, TxStatus.submitted);
        expect(row.hash, _ResponseLostService.localHash);
        expect(row.broadcastAt, isNotNull);
        expect(session.broadcastTxHash, _ResponseLostService.localHash);
        expect(session.broadcastOutcomeUnknown, isTrue);
        expect(find.text('Broadcast result unknown'), findsOneWidget);
        expect(find.textContaining('Do not send it again'), findsOneWidget);
        if (chain == Chain.tron) {
          expect(row.referenceBlockHeight, 4242);
          expect(row.expiresAt, isNotNull);
        }
        if (chain == Chain.solana) {
          expect(row.lastValidBlockHeight, 987654);
        }
      },
    );

    testWidgets('${chain.name}: an intent write failure blocks signing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      final fixture = await _fixture();
      final session = _session(chain);
      final networks = NetworkController(
        initialEnvironment: NetworkEnvironment.testnet,
      );
      final service = _ResponseLostService(
        wallets: fixture.wallets,
        session: session,
      );
      final router = buildRouter(
        initialLocation: '/transfer-auth',
        galleryMode: false,
        walletController: fixture.wallets,
        transferService: service,
        transferSession: session,
      );
      addTearDown(router.dispose);
      // Close only after the wallet metadata exists. The first transaction
      // write now fails exactly where production would hit a full/corrupt DB.
      await fixture.database.close();

      await tester.pumpWidget(
        _app(
          router: router,
          wallets: fixture.wallets,
          networks: networks,
          session: session,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use biometrics'));
      await tester.pumpAndSettle();

      expect(service.signCalls, 0);
      expect(service.broadcastCalls, 0);
      expect(session.broadcastTxHash, isNull);
      expect(find.text('Use biometrics'), findsOneWidget);
      expect(
        find.text('The transaction was not submitted. Try again.'),
        findsOneWidget,
      );
      expect(find.text('Transaction submitted'), findsNothing);
    });
  }
}
