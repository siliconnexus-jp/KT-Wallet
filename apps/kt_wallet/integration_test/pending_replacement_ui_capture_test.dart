import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/screens/transfer_screens.dart';
import 'package:kt_wallet/src/state/networks.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:wallet_data/wallet_data.dart';

Transaction _transaction({
  TxStatus status = TxStatus.pending,
  String? gasLimitRaw = '21000',
  String? replacedById,
}) => Transaction(
  id: 'pending-ui-original',
  walletId: 'pending-ui-wallet',
  coin: 'eth',
  direction: TxDirection.outgoing,
  fromAddr: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
  toAddr: '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
  amountRaw: '1000000000000000',
  feeRaw: '42000000000000',
  hash: '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
  status: status,
  signMode: SignMode.local,
  createdAt: 1785031200000,
  broadcastAt: 1785031205000,
  nonce: '7',
  maxPriorityFeeRaw: '2000000000',
  maxFeeRaw: '2000000000',
  gasLimitRaw: gasLimitRaw,
  replacedById: replacedById,
);

Widget _app(Transaction transaction) => NetworkScope(
  controller: NetworkController(initialEnvironment: NetworkEnvironment.testnet),
  child: KtDeviceChrome(
    mockStatusBar: false,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        fontFamily: 'Inter',
        colorScheme: ColorScheme.fromSeed(seedColor: WalletColors.accent),
        scaffoldBackgroundColor: WalletColors.bg,
      ),
      home: TxDetailScreen(transaction: transaction),
    ),
  ),
);

Future<void> _captureStage(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String marker,
  String fileName,
) async {
  // Host automation waits for this marker and takes a system-level simulator
  // screenshot. The pause keeps dialogs/native composition visible.
  final png = await binding.takeScreenshot(fileName);
  final path = '${Directory.systemTemp.path}/$fileName.png';
  await File(path).writeAsBytes(png, flush: true);
  // ignore: avoid_print
  print('$marker FILE=$path');
  await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 8)));
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'pending replacement details and guards render on a real simulator',
    (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('zh')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      if (Platform.isAndroid) {
        await binding.convertFlutterSurfaceToImage();
      }

      await tester.pumpWidget(_app(_transaction()));
      await tester.pumpAndSettle();
      expect(find.text('加速交易'), findsOneWidget);
      expect(find.text('取消交易'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      await _captureStage(
        binding,
        tester,
        'PENDING_UI_CAPTURE_01_DETAILS',
        'pending-ui-01-details',
      );

      await tester.tap(find.text('加速交易'));
      await tester.pumpAndSettle();
      expect(find.text('确认替换交易'), findsOneWidget);
      expect(find.textContaining('相同 nonce 和更高网络费'), findsOneWidget);
      await _captureStage(
        binding,
        tester,
        'PENDING_UI_CAPTURE_02_SPEED_CONFIRM',
        'pending-ui-02-speed-confirm',
      );

      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消交易'));
      await tester.pumpAndSettle();
      expect(find.text('确认替换交易'), findsOneWidget);
      expect(find.textContaining('向自己发送 0 金额交易'), findsOneWidget);
      await _captureStage(
        binding,
        tester,
        'PENDING_UI_CAPTURE_03_CANCEL_CONFIRM',
        'pending-ui-03-cancel-confirm',
      );

      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();
      await tester.pumpWidget(_app(_transaction(status: TxStatus.confirmed)));
      await tester.pumpAndSettle();
      expect(find.text('已确认'), findsOneWidget);
      expect(find.text('加速交易'), findsNothing);
      expect(find.text('取消交易'), findsNothing);
      await _captureStage(
        binding,
        tester,
        'PENDING_UI_CAPTURE_04_CONFIRMED_GUARD',
        'pending-ui-04-confirmed-guard',
      );

      await tester.pumpWidget(_app(_transaction(gasLimitRaw: null)));
      await tester.pumpAndSettle();
      expect(find.text('确认中'), findsOneWidget);
      expect(find.text('加速交易'), findsNothing);
      expect(find.text('取消交易'), findsNothing);
      await _captureStage(
        binding,
        tester,
        'PENDING_UI_CAPTURE_05_MISSING_PARAMS_GUARD',
        'pending-ui-05-missing-params',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
