import 'dart:convert';
import 'dart:typed_data';

import 'package:chains/chains.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:go_router/go_router.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/market/gateway_client.dart';
import 'package:kt_wallet/src/screens/approval_screen.dart';
import 'package:kt_wallet/src/security/transaction_auth.dart';
import 'package:kt_wallet/src/state/app_prefs.dart';
import 'package:kt_wallet/src/state/networks.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/state/wallet_scope.dart';
import 'package:kt_wallet/src/transfer/airgap_codec.dart';
import 'package:kt_wallet/src/transfer/local_transfer_service.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:kt_wallet/src/wallets/wallet_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallet_data/wallet_data.dart';

const _owner = '0x85f6be9460291e86e0fb49b07d0a83cc5f7206cd';

HotWallet _hotWallet() => HotWallet(
  id: 'wallet-1',
  name: 'Audit wallet',
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

WatchWallet _watchWallet() => WatchWallet(
  id: 'watch-1',
  name: 'Paired cold wallet',
  avatarColor: 0xFF2557E8,
  addresses: _hotWallet().addresses,
  coldWalletId: 'cold-1',
  protocolVersion: 1,
);

WalletController _wallet() =>
    WalletController(WalletManager(initial: [_hotWallet()]));

Widget _app({
  required AppPrefsController prefs,
  required NetworkController networks,
  required GatewayClient gateway,
  TextScaler textScaler = TextScaler.noScaling,
  WalletController? wallet,
  LocalTransferService? transferService,
  TransactionAuthGate authGate = const LocalTransactionAuthGate(),
  DateTime Function()? clock,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: textScaler),
    child: child!,
  ),
  home: WalletScope(
    controller: wallet ?? _wallet(),
    child: NetworkScope(
      controller: networks,
      child: AppPrefsScope(
        controller: prefs,
        child: TokenApprovalsScreen(
          gateway: gateway,
          transferService: transferService,
          authGate: authGate,
          clock: clock,
        ),
      ),
    ),
  ),
);

class _FakeRevokeService extends LocalTransferService {
  _FakeRevokeService({this.broadcastError});

  final Object? broadcastError;
  TransferDraft? draft;
  int signCalls = 0;
  int broadcastCalls = 0;

  @override
  Future<PreparedEvmTransfer> prepareEvm({
    required TransferDraft draft,
    required String from,
    required int evmChainId,
  }) async {
    this.draft = draft;
    final unsigned = rawTxFor(
      draft,
      from: from,
      nonce: BigInt.from(7),
      maxPriorityFeePerGas: BigInt.from(2),
      maxFeePerGas: BigInt.from(30),
      gasLimit: BigInt.from(50000),
      evmChainId: evmChainId,
    );
    return PreparedEvmTransfer(
      chain: draft.chain,
      evmChainId: evmChainId,
      coin: Coin.eth,
      operation: draft.operation,
      from: from,
      recipient: draft.recipient,
      amountRaw: draft.amount.raw,
      tokenContract: draft.tokenContract,
      nonce: BigInt.from(7),
      maxPriorityFeePerGas: BigInt.from(2),
      maxFeePerGas: BigInt.from(30),
      gasLimit: BigInt.from(50000),
      unsignedTx: unsigned,
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
      signedTx: prepared.unsignedTx,
      txHash: '0x${'1' * 64}',
    );
  }

  @override
  Future<String> broadcastSigned(Chain chain, Uint8List signedTx) async {
    broadcastCalls++;
    final error = broadcastError;
    if (error != null) throw error;
    return '0x${'1' * 64}';
  }
}

GatewayClient _gateway(
  Future<http.Response> Function(http.Request request) handler,
) => GatewayClient(
  baseUrl: 'https://gateway.example',
  client: MockClient(handler),
  networks: (_) => 'eth-mainnet',
  advertisedNetworks: const {'eth-mainnet'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('does not disclose the public address until explicit consent', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = AppPrefsController();
    await prefs.load();
    var requests = 0;
    Map<String, dynamic>? body;
    final gateway = _gateway((request) async {
      requests++;
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': body!['id'],
          'result': {
            'status': 'ok',
            'source': 'goplus',
            'network': 'eth-mainnet',
            'approvals': <Object?>[],
          },
        }),
        200,
      );
    });

    await tester.pumpWidget(
      _app(prefs: prefs, networks: NetworkController(), gateway: gateway),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('approval-consent')), findsOneWidget);
    expect(requests, 0);
    expect(prefs.externalApprovalScanConsent, isFalse);

    await tester.tap(find.byKey(const ValueKey('approval-consent-action')));
    await tester.pumpAndSettle();

    expect(requests, 1);
    expect(prefs.externalApprovalScanConsent, isTrue);
    final params = body!['params'] as Map<String, dynamic>;
    expect(params, {
      'chain': 'eth',
      'network': 'eth-mainnet',
      'address': _owner,
      'privacyConsent': true,
    });
    expect(find.byKey(const ValueKey('approval-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('approval-unavailable')), findsNothing);
  });

  testWidgets(
    'consent storage failure sends no address and leaves consent disabled',
    (tester) async {
      final prefs = AppPrefsController(
        preferencesProvider: () async => throw StateError('storage offline'),
      );
      var requests = 0;
      final gateway = _gateway((request) async {
        requests++;
        return http.Response('{}', 500);
      });

      await tester.pumpWidget(
        _app(prefs: prefs, networks: NetworkController(), gateway: gateway),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('approval-consent-action')));
      await tester.pumpAndSettle();

      expect(requests, 0);
      expect(prefs.externalApprovalScanConsent, isFalse);
      expect(find.byKey(const ValueKey('approval-consent')), findsOneWidget);
      expect(
        find.text(
          'Changes could not be saved. Nothing was changed; try again.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('provider failure is unavailable and never an empty result', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'prefs.security.externalApprovalScanConsent': true,
    });
    final prefs = AppPrefsController();
    await prefs.load();
    final gateway = _gateway((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': body['id'],
          'error': {
            'code': -32000,
            'message': 'upstream_error',
            'data': {
              'upstream': 'goplus-approvals',
              'message': 'request failed',
            },
          },
        }),
        200,
      );
    });

    await tester.pumpWidget(
      _app(prefs: prefs, networks: NetworkController(), gateway: gateway),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('approval-scan-action')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('approval-unavailable')), findsOneWidget);
    expect(find.byKey(const ValueKey('approval-empty')), findsNothing);
  });

  testWidgets('testnet is explicitly unsupported without contacting provider', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'prefs.security.externalApprovalScanConsent': true,
    });
    final prefs = AppPrefsController();
    await prefs.load();
    var requests = 0;
    final gateway = _gateway((request) async {
      requests++;
      return http.Response('{}', 500);
    });
    final networks = NetworkController(
      initialEnvironment: NetworkEnvironment.testnet,
    );

    await tester.pumpWidget(
      _app(prefs: prefs, networks: networks, gateway: gateway),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('approval-scan-action')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('approval-unsupported')), findsOneWidget);
    expect(find.byKey(const ValueKey('approval-empty')), findsNothing);
    expect(requests, 0);
  });

  testWidgets('unsafe unlimited approval is rendered as a risk, not trusted', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'prefs.security.externalApprovalScanConsent': true,
    });
    final prefs = AppPrefsController();
    await prefs.load();
    final gateway = _gateway((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': body['id'],
          'result': {
            'status': 'ok',
            'source': 'goplus',
            'network': 'eth-mainnet',
            'approvals': [
              {
                'tokenAddress': '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                'tokenName': 'Risk Token',
                'tokenSymbol': 'RISK',
                'decimals': 18,
                'balance': '0',
                'spender': '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
                'spenderName': 'Unknown Router',
                'spenderTag': '',
                'spenderTrusted': false,
                'amount': 'Unlimited',
                'unlimited': true,
                'approvedAt': 1700000000,
                'transaction': '',
                'risk': 'unsafe',
              },
            ],
          },
        }),
        200,
      );
    });

    await tester.pumpWidget(
      _app(prefs: prefs, networks: NetworkController(), gateway: gateway),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('approval-scan-action')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('approval-results')), findsOneWidget);
    expect(find.text('Risk signal found'), findsOneWidget);
    expect(find.text('No outstanding approvals found'), findsNothing);
  });

  testWidgets(
    'consented result remains usable at 200% text on a compact phone',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({
        'prefs.security.externalApprovalScanConsent': true,
      });
      final prefs = AppPrefsController();
      await prefs.load();
      final gateway = _gateway((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': body['id'],
            'result': {
              'status': 'ok',
              'source': 'goplus',
              'network': 'eth-mainnet',
              'approvals': [
                {
                  'tokenAddress': '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                  'tokenName': 'A deliberately long suspicious token name',
                  'tokenSymbol': 'RISK-LONG',
                  'decimals': 18,
                  'balance': '0',
                  'spender': '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
                  'spenderName': 'A deliberately long unknown router identity',
                  'spenderTag': '',
                  'spenderTrusted': false,
                  'amount': 'Unlimited',
                  'unlimited': true,
                  'approvedAt': 1700000000,
                  'transaction': '',
                  'risk': 'unsafe',
                },
              ],
            },
          }),
          200,
        );
      });

      await tester.pumpWidget(
        _app(
          prefs: prefs,
          networks: NetworkController(),
          gateway: gateway,
          textScaler: const TextScaler.linear(2),
        ),
      );
      await tester.pumpAndSettle();
      final scan = find.byKey(const ValueKey('approval-scan-action'));
      await tester.ensureVisible(scan);
      await tester.pumpAndSettle();
      await tester.tap(scan);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('approval-results')), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('approval-disable-consent')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'hot-wallet revoke signs only approve(spender, 0) and persists Pending',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({
        'prefs.security.externalApprovalScanConsent': true,
      });
      final prefs = AppPrefsController();
      await prefs.load();
      final database = WalletDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final store = WalletStore(database);
      final hot = _hotWallet();
      await store.save(hot);
      final wallet = WalletController(
        WalletManager(initial: [hot]),
        store: store,
      );
      final service = _FakeRevokeService();
      const token = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      const spender = '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      final gateway = _gateway((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': body['id'],
            'result': {
              'status': 'ok',
              'source': 'goplus',
              'network': 'eth-mainnet',
              'approvals': [
                {
                  'tokenAddress': token,
                  'tokenName': 'Token',
                  'tokenSymbol': 'TOK',
                  'decimals': 18,
                  'balance': '1',
                  'spender': spender,
                  'spenderName': 'Router',
                  'spenderTag': '',
                  'spenderTrusted': false,
                  'amount': 'Unlimited',
                  'unlimited': true,
                  'approvedAt': 0,
                  'transaction': '',
                  'risk': 'unsafe',
                },
              ],
            },
          }),
          200,
        );
      });

      await tester.pumpWidget(
        _app(
          prefs: prefs,
          networks: NetworkController(),
          gateway: gateway,
          wallet: wallet,
          transferService: service,
          authGate: const FakeTransactionAuthGate(true),
          clock: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('approval-scan-action')));
      await tester.pumpAndSettle();

      final revoke = find.byKey(
        const ValueKey('approval-revoke-$token-$spender'),
      );
      await tester.ensureVisible(revoke);
      await tester.tap(revoke);
      // The background card deliberately keeps an indeterminate preparation
      // spinner alive while the confirmation dialog is open.
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Revoke this token approval?'), findsOneWidget);
      expect(find.textContaining('approve(spender, 0)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('kt-dialog-confirm')));
      await tester.pumpAndSettle();

      expect(service.signCalls, 1);
      expect(service.draft?.operation, TxOperation.approvalRevoke);
      expect(service.draft?.amount.raw, BigInt.zero);
      final rows = await wallet.localTransactions();
      expect(rows, hasLength(1));
      expect(rows.single.operation, TxOperationKind.approvalRevoke);
      expect(rows.single.toAddr, spender);
      expect(rows.single.contract, token);
      expect(rows.single.amountRaw, '0');
      expect(rows.single.status, TxStatus.pending);
      expect(rows.single.hash, '0x${'1' * 64}');
      expect(find.text('Revocation pending'), findsOneWidget);
    },
  );

  testWidgets('response-lost revoke stays submitted and cannot be sent twice', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    SharedPreferences.setMockInitialValues({
      'prefs.security.externalApprovalScanConsent': true,
    });
    final prefs = AppPrefsController();
    await prefs.load();
    final database = WalletDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = WalletStore(database);
    final hot = _hotWallet();
    await store.save(hot);
    final wallet = WalletController(
      WalletManager(initial: [hot]),
      store: store,
    );
    final service = _FakeRevokeService(
      broadcastError: const LocalTransferUncertainException('response lost'),
    );
    const token = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const spender = '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    final gateway = _gateway((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': body['id'],
          'result': {
            'status': 'ok',
            'source': 'goplus',
            'network': 'eth-mainnet',
            'approvals': [
              {
                'tokenAddress': token,
                'tokenName': 'Token',
                'tokenSymbol': 'TOK',
                'decimals': 18,
                'balance': '1',
                'spender': spender,
                'spenderName': 'Router',
                'spenderTag': '',
                'spenderTrusted': false,
                'amount': 'Unlimited',
                'unlimited': true,
                'approvedAt': 0,
                'transaction': '',
                'risk': 'unsafe',
              },
            ],
          },
        }),
        200,
      );
    });

    await tester.pumpWidget(
      _app(
        prefs: prefs,
        networks: NetworkController(),
        gateway: gateway,
        wallet: wallet,
        transferService: service,
        authGate: const FakeTransactionAuthGate(true),
        clock: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('approval-scan-action')));
    await tester.pumpAndSettle();
    final revoke = find.byKey(
      const ValueKey('approval-revoke-$token-$spender'),
    );
    await tester.ensureVisible(revoke);
    await tester.tap(revoke);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('kt-dialog-confirm')));
    await tester.pumpAndSettle();

    final rows = await wallet.localTransactions();
    expect(rows, hasLength(1));
    expect(rows.single.status, TxStatus.submitted);
    expect(rows.single.hash, '0x${'1' * 64}');
    expect(rows.single.broadcastAt, 1700000000000);
    expect(service.signCalls, 1);
    expect(service.broadcastCalls, 1);
    expect(find.text('Revocation pending'), findsOneWidget);
    expect(find.textContaining('Do not send it again'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(revoke).onPressed, isNull);
    await tester.tap(revoke, warnIfMissed: false);
    await tester.pump();
    expect(service.broadcastCalls, 1);
  });

  testWidgets('pending revoke is restored after reopening and cannot repeat', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'prefs.security.externalApprovalScanConsent': true,
    });
    final prefs = AppPrefsController();
    await prefs.load();
    final database = WalletDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = WalletStore(database);
    final hot = _hotWallet();
    await store.save(hot);
    const token = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const spender = '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    await store.upsertTransaction(
      id: 'approval-revoke-existing',
      walletId: hot.id,
      coin: Coin.eth,
      networkId: 'eth-mainnet',
      contract: token,
      operation: TxOperationKind.approvalRevoke,
      from: _owner,
      to: spender,
      amountRaw: '0',
      feeRaw: '1500000',
      hash: '0x${'2' * 64}',
      status: TxStatus.pending,
      signMode: SignMode.local,
      createdAt: 1700000000000,
      broadcastAt: 1700000000001,
      nonce: '7',
      maxPriorityFeeRaw: '2',
      maxFeeRaw: '30',
      gasLimitRaw: '50000',
    );
    final wallet = WalletController(
      WalletManager(initial: [hot]),
      store: store,
    );
    final service = _FakeRevokeService();
    final gateway = _gateway((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': body['id'],
          'result': {
            'status': 'ok',
            'source': 'goplus',
            'network': 'eth-mainnet',
            'approvals': [
              {
                'tokenAddress': token,
                'tokenName': 'Token',
                'tokenSymbol': 'TOK',
                'decimals': 18,
                'balance': '1',
                'spender': spender,
                'spenderName': 'Router',
                'spenderTag': '',
                'spenderTrusted': false,
                'amount': 'Unlimited',
                'unlimited': true,
                'approvedAt': 0,
                'transaction': '',
                'risk': 'unsafe',
              },
            ],
          },
        }),
        200,
      );
    });

    await tester.pumpWidget(
      _app(
        prefs: prefs,
        networks: NetworkController(),
        gateway: gateway,
        wallet: wallet,
        transferService: service,
        authGate: const FakeTransactionAuthGate(true),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('approval-scan-action')));
    await tester.pumpAndSettle();

    final revoke = find.byKey(
      const ValueKey('approval-revoke-$token-$spender'),
    );
    expect(find.text('Revocation pending'), findsOneWidget);
    final button = tester.widget<OutlinedButton>(revoke);
    expect(button.onPressed, isNull);
    await tester.tap(revoke, warnIfMissed: false);
    await tester.pump();
    expect(service.signCalls, 0);
    expect(await wallet.localTransactions(), hasLength(1));
  });

  testWidgets('watch-wallet revoke enters the paired QR signing flow', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'prefs.security.externalApprovalScanConsent': true,
    });
    final prefs = AppPrefsController();
    await prefs.load();
    final wallet = WalletController(WalletManager(initial: [_watchWallet()]));
    final networks = NetworkController();
    final session = TransferSession();
    const token = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const spender = '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    final gateway = _gateway((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': body['id'],
          'result': {
            'status': 'ok',
            'source': 'goplus',
            'network': 'eth-mainnet',
            'approvals': [
              {
                'tokenAddress': token,
                'tokenName': 'Token',
                'tokenSymbol': 'TOK',
                'decimals': 18,
                'balance': '1',
                'spender': spender,
                'spenderName': 'Router',
                'spenderTag': '',
                'spenderTrusted': false,
                'amount': 'Unlimited',
                'unlimited': true,
                'approvedAt': 0,
                'transaction': '',
                'risk': 'unsafe',
              },
            ],
          },
        }),
        200,
      );
    });
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => TokenApprovalsScreen(gateway: gateway),
        ),
        GoRoute(
          path: '/confirm-watch',
          builder: (_, _) => const Scaffold(body: Text('QR review route')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
        builder: (context, child) => WalletScope(
          controller: wallet,
          child: NetworkScope(
            controller: networks,
            child: AppPrefsScope(
              controller: prefs,
              child: TransferSessionScope(session: session, child: child!),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('approval-scan-action')));
    await tester.pumpAndSettle();
    final revoke = find.byKey(
      const ValueKey('approval-revoke-$token-$spender'),
    );
    await tester.ensureVisible(revoke);
    await tester.tap(revoke);
    await tester.pumpAndSettle();

    expect(find.text('QR review route'), findsOneWidget);
    expect(session.draft?.operation, TxOperation.approvalRevoke);
    expect(session.draft?.recipient, spender);
    expect(session.draft?.tokenContract, token);
    expect(session.draft?.amount.raw, BigInt.zero);
  });

  testWidgets('approval privacy and risk states have reviewed phone goldens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferences.setMockInitialValues({});
    final prefs = AppPrefsController();
    await prefs.load();
    final gateway = _gateway((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': body['id'],
          'result': {
            'status': 'ok',
            'source': 'goplus',
            'network': 'eth-mainnet',
            'approvals': [
              {
                'tokenAddress': '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                'tokenName': 'Suspicious Token',
                'tokenSymbol': 'RISK',
                'decimals': 18,
                'balance': '0',
                'spender': '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
                'spenderName': 'Unknown Router',
                'spenderTag': '',
                'spenderTrusted': false,
                'amount': 'Unlimited',
                'unlimited': true,
                'approvedAt': 0,
                'transaction': '',
                'risk': 'unsafe',
              },
            ],
          },
        }),
        200,
      );
    });

    await tester.pumpWidget(
      _app(prefs: prefs, networks: NetworkController(), gateway: gateway),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/approvals/privacy-en.png'),
    );

    await tester.tap(find.byKey(const ValueKey('approval-consent-action')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/approvals/risk-en.png'),
    );
  });
}
