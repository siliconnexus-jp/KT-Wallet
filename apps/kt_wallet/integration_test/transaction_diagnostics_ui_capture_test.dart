import 'package:core_crypto/core_crypto.dart' show ChainAddresses;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/screens/transfer_screens.dart';
import 'package:kt_wallet/src/state/networks.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/state/wallet_scope.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:wallet_data/wallet_data.dart';

const _hash =
    '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef';
const _address = '0x70997970C51812dc3A010C7d01b50e0d17dc79C8';
const _recipient = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';

Transaction _transaction() => Transaction(
  id: 'diagnostic-evidence',
  walletId: 'diagnostic-wallet',
  coin: 'eth',
  networkId: 'eth-sepolia',
  operation: TxOperationKind.transfer,
  direction: TxDirection.outgoing,
  fromAddr: _address,
  toAddr: _recipient,
  amountRaw: '1000000000000000',
  hash: _hash,
  status: TxStatus.pending,
  signMode: SignMode.airgap,
  createdAt: DateTime(2026, 7, 31, 17, 42).millisecondsSinceEpoch,
  broadcastAt: DateTime(2026, 7, 31, 17, 43).millisecondsSinceEpoch,
  lastCheckedAt: DateTime(2026, 7, 31, 17, 45).millisecondsSinceEpoch,
);

WalletController _wallets() => WalletController(
  WalletManager(
    initial: [
      WatchWallet(
        id: 'diagnostic-wallet',
        name: '验收钱包',
        avatarColor: 0xFF3155DD,
        addresses: const ChainAddresses(
          eth: _address,
          polygon: _address,
          base: _address,
          arbitrum: _address,
          avalanche: _address,
          bnb: _address,
          tron: 'TNXoiAJ3dct8Fjg4M9fkLFh9S2v9TXc32G',
          solana: '2KW2XRd9kwqet15Aha2oK3tYvd3nWbTFH1MBiRAv1BE1',
        ),
        coldWalletId: 'diagnostic-cold-wallet',
        protocolVersion: 1,
      ),
    ],
  ),
);

Widget _frame(WalletController wallets) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData(
    fontFamily: 'Inter',
    colorScheme: ColorScheme.fromSeed(seedColor: WalletColors.accent),
    scaffoldBackgroundColor: WalletColors.bg,
  ),
  home: KtDeviceChrome(
    mockStatusBar: false,
    child: NetworkScope(
      controller: NetworkController(
        initialEnvironment: NetworkEnvironment.testnet,
      ),
      child: WalletScope(
        controller: wallets,
        child: TxDetailScreen(transaction: _transaction()),
      ),
    ),
  ),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'transaction diagnostics expose chain-verifiable support evidence',
    (tester) async {
      final wallets = _wallets();
      addTearDown(wallets.dispose);
      await tester.pumpWidget(_frame(wallets));
      await tester.pumpAndSettle();

      expect(find.text('Sepolia'), findsOneWidget);
      expect(find.text('广播时间'), findsOneWidget);
      expect(find.text('最后状态查询'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('copy-transaction-hash')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('view-transaction-in-explorer')),
        findsOneWidget,
      );
      // ignore: avoid_print
      print('TRANSACTION_DIAGNOSTICS_CAPTURE READY=details');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 20)),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
