import 'dart:io';
import 'dart:typed_data';

import 'package:chains/chains.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:core_crypto/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/screens/transfer_screens.dart';
import 'package:kt_wallet/src/security/biometric_auth.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/state/wallet_scope.dart';
import 'package:kt_wallet/src/transfer/local_transfer_service.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:ui_kit/ui_kit.dart';

const _from = 'TNXoiAJ3dct8Fjg4M9fkLFh9S2v9TXc32G';
const _to = 'TJRabPrwbZy45sbavfcjinPJC18kjpRTv8';

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
}

WalletController _wallets() => WalletController(
  WalletManager(
    initial: [
      HotWallet(
        id: 'accessibility-evidence',
        name: '日常钱包',
        avatarColor: 0xFF3155DD,
        addresses: const ChainAddresses(
          eth: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
          polygon: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
          tron: _from,
          solana: '2KW2XRd9kwqet15Aha2oK3tYvd3nWbTFH1MBiRAv1BE1',
        ),
        backedUp: true,
      ),
    ],
  ),
  crypto: MockCoreCrypto(),
  allowTestBypass: true,
);

TransferSession _session() => TransferSession()
  ..draft = TransferDraft(
    symbol: 'USDT',
    networkLabel: 'TRON · TRC-20',
    chain: Chain.tron,
    recipient: _to,
    amount: Amount.parse('10', 6, symbol: 'USDT'),
    feeTier: 1,
    tokenContract: 'TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf',
  );

Widget _frame({
  required WalletController wallets,
  required TransferSession session,
  required Widget child,
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
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(2),
        disableAnimations: true,
      ),
      child: KtDeviceChrome(
        mockStatusBar: false,
        child: WalletScope(
          controller: wallets,
          child: TransferSessionScope(session: session, child: child),
        ),
      ),
    ),
  ),
);

Future<void> _capture(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
) async {
  final platform = Platform.isIOS ? 'ios' : 'android';
  final fileName = '$platform-$name';
  final bytes = await binding.takeScreenshot(fileName);
  final path = '${Directory.systemTemp.path}/$fileName.png';
  await File(path).writeAsBytes(bytes, flush: true);
  // ignore: avoid_print
  print('ACCESSIBILITY_CAPTURE READY=$name FILE=$path');
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(seconds: 30)),
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    '200 percent text and reduced motion preserve confirmation and auth',
    (tester) async {
      if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
      final wallets = _wallets();
      final session = _session();
      addTearDown(wallets.dispose);

      await tester.pumpWidget(
        _frame(
          wallets: wallets,
          session: session,
          child: TransferConfirmScreen(
            isHot: true,
            transferService: _QuoteService(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('确认交易'), findsOneWidget);
      expect(find.text('确认转账'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(binding, tester, '17-large-text-confirm');

      await tester.pumpWidget(
        _frame(
          wallets: wallets,
          session: session,
          child: const TransferAuthSheet(
            auth: FakeBiometricAuth(BiometricOutcome.success),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('验证以确认转账'), findsOneWidget);
      expect(find.text('改用密码'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(binding, tester, '18-large-text-auth');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
