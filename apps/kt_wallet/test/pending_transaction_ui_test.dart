import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/screens/transfer_screens.dart';
import 'package:kt_wallet/src/state/networks.dart';
import 'package:wallet_data/wallet_data.dart';

Transaction _transaction({
  TxStatus status = TxStatus.pending,
  String? networkId = 'eth-mainnet',
  String? nonce = '7',
  String? maxPriorityFeeRaw = '100',
  String? maxFeeRaw = '200',
  String? gasLimitRaw = '21000',
  String? replacesId,
  String? replacedById,
}) => Transaction(
  id: 'tx-local-1',
  walletId: 'wallet-1',
  coin: 'eth',
  networkId: networkId,
  direction: TxDirection.outgoing,
  fromAddr: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
  toAddr: '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
  amountRaw: '1000000000000000',
  feeRaw: '4200000',
  hash: '0x1234567890abcdef1234567890abcdef1234567890abcdef',
  status: status,
  signMode: SignMode.local,
  createdAt: 1700000000000,
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
}) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: NetworkScope(
    controller: NetworkController(initialEnvironment: environment),
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

  testWidgets(
    'a row from another network never offers speed-up or cancel',
    (tester) async {
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
    },
  );

  testWidgets('a legacy row with no recorded network cannot be replaced', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_transaction(networkId: null)),
    );

    expect(find.text('确认中'), findsOneWidget);
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
}
