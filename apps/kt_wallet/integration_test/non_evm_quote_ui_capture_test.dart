import 'dart:typed_data';

import 'package:chains/chains.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:core_crypto/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/screens/transfer_screens.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/state/wallet_scope.dart';
import 'package:kt_wallet/src/transfer/local_transfer_service.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:ui_kit/ui_kit.dart';

const _tronFrom = 'TNXoiAJ3dct8Fjg4M9fkLFh9S2v9TXc32G';
const _tronTo = 'TJRabPrwbZy45sbavfcjinPJC18kjpRTv8';
const _solanaFrom = '2KW2XRd9kwqet15Aha2oK3tYvd3nWbTFH1MBiRAv1BE1';
const _solanaTo = 'GmaDrppBC7P5ARKV8g3djiwP89vz1jLK23V2GBjuAEGB';

class _QuoteService extends LocalTransferService {
  @override
  Future<PreparedTronTransfer> prepareTron({
    required TransferDraft draft,
    required String from,
    required String? expectedNetworkIdentity,
  }) async => PreparedTronTransfer(
    from: from,
    recipient: draft.recipient,
    amountRaw: draft.amount.raw,
    tokenContract: draft.tokenContract,
    maximumFeeSun: BigInt.from(23450000),
    referenceBlockHeight: 987654,
    expiresAt: DateTime.now()
        .add(const Duration(minutes: 10))
        .millisecondsSinceEpoch,
    rawTx: Uint8List.fromList(const [1, 2, 3]),
  );

  @override
  Future<PreparedSolanaTransfer> prepareSolana({
    required TransferDraft draft,
    required String from,
    required String? expectedNetworkIdentity,
  }) async => PreparedSolanaTransfer(
    from: from,
    recipient: draft.recipient,
    amountRaw: draft.amount.raw,
    tokenMint: draft.tokenContract,
    tokenProgram: draft.tokenProgram ?? solanaTokenProgram,
    networkFeeLamports: BigInt.from(5000),
    rentDepositLamports: BigInt.from(2039280),
    lastValidBlockHeight: 123456,
    message: Uint8List.fromList(const [4, 5, 6]),
  );
}

WalletController _wallets() => WalletController(
  WalletManager(
    initial: [
      HotWallet(
        id: 'quote-evidence',
        name: '测试钱包',
        avatarColor: 0xFF3155DD,
        addresses: const ChainAddresses(
          eth: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
          polygon: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
          tron: _tronFrom,
          solana: _solanaFrom,
        ),
        backedUp: true,
      ),
    ],
  ),
  crypto: MockCoreCrypto(),
  allowTestBypass: true,
);

Widget _screen({
  required WalletController wallets,
  required TransferSession session,
}) => MaterialApp(
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
    child: WalletScope(
      controller: wallets,
      child: TransferSessionScope(
        session: session,
        child: TransferConfirmScreen(
          key: ValueKey(session.draft?.chain),
          isHot: true,
          transferService: _QuoteService(),
        ),
      ),
    ),
  ),
);

Future<void> _evidencePause(WidgetTester tester, String marker) async {
  // ignore: avoid_print
  print('NON_EVM_QUOTE_CAPTURE READY=$marker');
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(seconds: 20)),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'capture TRON resources and Solana ATA rent confirmation quotes',
    (tester) async {
      final wallets = _wallets();
      addTearDown(wallets.dispose);
      final session = TransferSession()
        ..draft = TransferDraft(
          symbol: 'USDT',
          networkLabel: 'TRON · TRC-20',
          chain: Chain.tron,
          recipient: _tronTo,
          amount: Amount.parse('10', 6, symbol: 'USDT'),
          feeTier: 1,
          tokenContract: 'TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf',
        );

      await tester.pumpWidget(_screen(wallets: wallets, session: session));
      await tester.pumpAndSettle();
      expect(find.textContaining('23.45 TRX'), findsOneWidget);
      await _evidencePause(tester, 'tron');

      session.begin(
        TransferDraft(
          symbol: 'PYUSD',
          networkLabel: 'Solana · Token-2022',
          chain: Chain.solana,
          recipient: _solanaTo,
          amount: Amount.parse('1.25', 6, symbol: 'PYUSD'),
          feeTier: 1,
          tokenContract: '2b1kV6DkPAnxd5ixfnxCpjxmKwqjjaYmCZfHsFu24GXo',
          tokenProgram: solanaToken2022Program,
        ),
      );
      await tester.pumpWidget(_screen(wallets: wallets, session: session));
      await tester.pumpAndSettle();
      expect(find.text('0.00203928 SOL'), findsOneWidget);
      expect(find.textContaining('0.000005 SOL'), findsOneWidget);
      await _evidencePause(tester, 'solana');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
