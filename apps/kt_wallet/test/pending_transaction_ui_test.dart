import 'package:chains/chains.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/platform/external_actions.dart';
import 'package:kt_wallet/src/screens/transfer_screens.dart';
import 'package:kt_wallet/src/state/networks.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallet_data/wallet_data.dart';

Transaction _transaction({
  String coin = 'eth',
  TxStatus status = TxStatus.pending,
  TxOperationKind operation = TxOperationKind.transfer,
  String? contract,
  String amountRaw = '1000000000000000',
  String? networkId = 'eth-mainnet',
  String? nonce = '7',
  String? maxPriorityFeeRaw = '100',
  String? maxFeeRaw = '200',
  String? gasLimitRaw = '21000',
  String? replacesId,
  String? replacedById,
  int? broadcastAt = 1700000100000,
  int? lastCheckedAt = 1700000200000,
  TxCheckOutcome? lastCheckOutcome,
}) => Transaction(
  id: 'tx-local-1',
  walletId: 'wallet-1',
  coin: coin,
  networkId: networkId,
  contract: contract,
  operation: operation,
  direction: TxDirection.outgoing,
  fromAddr: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
  toAddr: '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
  amountRaw: amountRaw,
  feeRaw: '4200000',
  hash: '0x1234567890abcdef1234567890abcdef1234567890abcdef',
  status: status,
  signMode: SignMode.local,
  createdAt: 1700000000000,
  broadcastAt: broadcastAt,
  lastCheckedAt: lastCheckedAt,
  lastCheckOutcome: lastCheckOutcome,
  nonce: nonce,
  maxPriorityFeeRaw: maxPriorityFeeRaw,
  maxFeeRaw: maxFeeRaw,
  gasLimitRaw: gasLimitRaw,
  replacesId: replacesId,
  replacedById: replacedById,
);

/// [environment] selects which network is ACTIVE while the row is displayed;
/// replacement is only offered while the ROW's own network is the active one.
Widget _app(
  Transaction transaction, {
  NetworkEnvironment environment = NetworkEnvironment.mainnet,
  NetworkController? controller,
}) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: NetworkScope(
    controller:
        controller ?? NetworkController(initialEnvironment: environment),
    child: TxDetailScreen(transaction: transaction),
  ),
);

void main() {
  testWidgets('pending local EVM row exposes speed-up and cancel actions', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_transaction()));

    expect(find.text('确认中'), findsOneWidget);
    expect(find.text('加速交易'), findsOneWidget);
    expect(find.text('取消交易'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('广播时间'), findsOneWidget);
    expect(find.text('最后状态查询'), findsOneWidget);
    expect(find.byKey(const ValueKey('copy-transaction-hash')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('view-transaction-in-explorer')),
      findsOneWidget,
    );

    await tester.tap(find.text('加速交易'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('kt-dialog')), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('确认替换交易'), findsOneWidget);
    expect(find.text('将使用相同 nonce 和更高网络费重新发送。原收款地址与金额不会改变。'), findsOneWidget);
    expect(find.text('Nonce'), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('kt-dialog')),
        matching: find.text('0.001 ETH'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
  });

  testWidgets('approval revoke is never presented as a zero token transfer', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _transaction(
          operation: TxOperationKind.approvalRevoke,
          contract: '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          amountRaw: '0',
        ),
      ),
    );

    expect(find.text('撤销授权'), findsWidgets);
    expect(find.text('被授权合约'), findsOneWidget);
    expect(find.textContaining('Token (raw)'), findsNothing);
    expect(find.text('加速交易'), findsOneWidget);

    await tester.tap(find.text('加速交易'));
    await tester.pumpAndSettle();
    expect(find.text('撤销授权'), findsWidgets);
    expect(find.textContaining('0 Token'), findsNothing);
  });

  testWidgets('transaction diagnostics copy full hash and open explorer', (
    tester,
  ) async {
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
          return null;
        }
        if (call.method == 'Clipboard.getData') {
          return <String, Object?>{'text': clipboardText};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final external = FakeExternalActions();
    final previous = ExternalActions.instance;
    ExternalActions.instance = external;
    addTearDown(() => ExternalActions.instance = previous);
    final transaction = _transaction();
    await tester.pumpWidget(_app(transaction));

    final copy = find.byKey(const ValueKey('copy-transaction-hash'));
    await tester.ensureVisible(copy);
    await tester.tap(copy);
    await tester.pump();
    expect(clipboardText, transaction.hash);
    expect(find.text('交易 Hash 已复制'), findsOneWidget);

    final explorer = find.byKey(const ValueKey('view-transaction-in-explorer'));
    await tester.ensureVisible(explorer);
    await tester.tap(explorer);
    await tester.pump();
    expect(external.opened, hasLength(1));
    expect(external.opened.single.toString(), contains(transaction.hash!));
  });

  testWidgets(
    'custom network without explorer hides explorer and QR receipt actions',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final networks = NetworkController();
      final custom = await networks.addCustom(
        chain: Chain.ethereum,
        name: 'Private EVM',
        rpcUrl: 'https://rpc.private.example',
        symbol: 'ETH',
        evmChainId: 31337,
      );
      await networks.setOverride(Chain.ethereum, custom.id);

      await tester.pumpWidget(
        _app(_transaction(networkId: custom.id), controller: networks),
      );

      expect(
        find.byKey(const ValueKey('view-transaction-in-explorer')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('transaction-export-receipt')),
        findsNothing,
      );
      expect(find.byIcon(Icons.open_in_new), findsNothing);
    },
  );

  testWidgets('never-checked transaction says so instead of inventing a time', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_transaction(broadcastAt: null, lastCheckedAt: null)),
    );

    expect(find.text('尚未查询'), findsOneWidget);
    expect(find.text('--'), findsOneWidget);
  });

  testWidgets(
    'unknown chain evidence is honest and disables unsafe replacement',
    (tester) async {
      await tester.pumpWidget(
        _app(_transaction(lastCheckOutcome: TxCheckOutcome.unknown)),
      );

      expect(find.text('状态暂不可用'), findsWidgets);
      expect(find.text('确认中'), findsNothing);
      expect(find.text('加速交易'), findsNothing);
      expect(find.text('取消交易'), findsNothing);
      expect(find.byIcon(Icons.help_outline_rounded), findsOneWidget);
    },
  );

  testWidgets('finalized transaction never exposes replacement actions', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_transaction(status: TxStatus.confirmed)));

    expect(find.text('已确认'), findsOneWidget);
    expect(find.text('加速交易'), findsNothing);
    expect(find.text('取消交易'), findsNothing);
  });

  testWidgets('missing persisted EVM parameters closes replacement path', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_transaction(gasLimitRaw: null)));

    expect(find.text('确认中'), findsOneWidget);
    expect(find.text('加速交易'), findsNothing);
    expect(find.text('取消交易'), findsNothing);
  });

  testWidgets('a row from another network never offers speed-up or cancel', (
    tester,
  ) async {
    // A Sepolia row while Ethereum MAINNET is the active network: rebuilding
    // it against the active network would sign a real chainId-1 transaction
    // carrying the Sepolia recipient. The actions must not be offered, and
    // the row keeps its own network's name.
    await tester.pumpWidget(_app(_transaction(networkId: 'eth-sepolia')));

    expect(find.text('确认中'), findsOneWidget);
    expect(find.text('Sepolia'), findsOneWidget);
    expect(find.text('Ethereum'), findsNothing);
    expect(find.text('加速交易'), findsNothing);
    expect(find.text('取消交易'), findsNothing);

    // Switching the environment to testnet makes the row's own network
    // active again and the actions come back.
    await tester.pumpWidget(
      _app(
        _transaction(networkId: 'eth-sepolia'),
        environment: NetworkEnvironment.testnet,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('加速交易'), findsOneWidget);
    expect(find.text('取消交易'), findsOneWidget);
  });

  testWidgets('a legacy row with no recorded network cannot be replaced', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_transaction(networkId: null)));

    expect(find.text('确认中'), findsOneWidget);
    expect(find.text('加速交易'), findsNothing);
    expect(find.text('取消交易'), findsNothing);
  });

  testWidgets('Arbitrum sequencer row does not offer misleading replacement', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _transaction(coin: 'arbitrum', networkId: 'arbitrum-sepolia'),
        environment: NetworkEnvironment.testnet,
      ),
    );

    expect(find.text('确认中'), findsOneWidget);
    expect(find.text('Arbitrum Sepolia'), findsOneWidget);
    expect(find.text('加速交易'), findsNothing);
    expect(find.text('取消交易'), findsNothing);
  });

  testWidgets('replaced transaction displays replacement lineage', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _transaction(
          status: TxStatus.replaced,
          replacedById: 'replacement-transaction-2',
        ),
      ),
    );

    expect(find.text('已替换'), findsOneWidget);
    expect(find.text('已由交易替换'), findsOneWidget);
    expect(find.text('加速交易'), findsNothing);
  });

  testWidgets(
    'broadcast replacement remains pending and hides duplicate actions',
    (tester) async {
      await tester.pumpWidget(
        _app(_transaction(replacedById: 'replacement-transaction-2')),
      );

      expect(find.text('确认中'), findsOneWidget);
      expect(find.text('竞争中的替换交易'), findsOneWidget);
      expect(find.text('加速交易'), findsNothing);
      expect(find.text('取消交易'), findsNothing);
      expect(find.text('已替换'), findsNothing);
    },
  );
}
