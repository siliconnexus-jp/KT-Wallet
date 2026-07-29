import 'dart:async';
import 'dart:io';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/market/asset_ref.dart' show chainOf;
import 'package:kt_wallet/src/market/gateway_client.dart';
import 'package:kt_wallet/src/market/history_service.dart';
import 'package:kt_wallet/src/screens/transfer_screens.dart';
import 'package:kt_wallet/src/state/networks.dart';

const _walletId = 'transaction-receipt-ios-e2e-v1';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'exports a live test-account Polygon record to the iOS photo library',
    (tester) async {
      expect(Platform.isIOS, isTrue);
      const mnemonic = String.fromEnvironment('SEPOLIA_E2E_MNEMONIC');
      expect(mnemonic, isNotEmpty);

      final crypto = MethodChannelCoreCrypto();
      await crypto.storeWallet(
        walletId: _walletId,
        mnemonic: mnemonic,
        requireAuth: false,
      );
      final addresses = await crypto.deriveAddresses(_walletId);
      final networks = NetworkController(
        initialEnvironment: NetworkEnvironment.testnet,
      );
      final gateway = GatewayClient(
        baseUrl: 'https://gateway.kt-wallet.com',
        networks: (coin) => networks.activeFor(chainOf(coin)).id,
        timeout: const Duration(seconds: 30),
      );
      final history = HistoryService(
        gateway: () => gateway,
        endpoints: (coin) => networks.activeFor(chainOf(coin)).rpcUrl,
        timeout: const Duration(seconds: 30),
      );
      final result = await tester.runAsync(
        () => history.fetch(Coin.polygon, addresses.polygon),
      );
      expect(result, isNotNull);
      expect(result!.status, HistoryStatus.ok);
      expect(result.records, isNotEmpty);
      final record = result.records.first;

      tester.platformDispatcher.localesTestValue = const [Locale('zh')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(
        NetworkScope(
          controller: networks,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: TxDetailScreen(chainRecord: record),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('交易详情'), findsOneWidget);
      expect(find.text(record.amountText ?? '--'), findsOneWidget);
      await _capture(binding, tester, '01-live-transaction-detail');

      final export = find.byKey(const ValueKey('transaction-export-receipt'));
      expect(export, findsOneWidget);
      await tester.ensureVisible(export);
      await tester.tap(export);
      await tester.pumpAndSettle();
      expect(find.text('导出交易凭证'), findsWidgets);
      expect(find.text('保存到相册'), findsOneWidget);
      expect(find.text('分享凭证图片'), findsOneWidget);
      await _capture(binding, tester, '02-receipt-export-sheet');

      // ignore: avoid_print
      print('TRANSACTION_RECEIPT_IOS WAITING_FOR_PHOTO_PERMISSION');
      await tester.tap(find.byKey(const ValueKey('receipt-save-photos')));
      await _waitUntil(
        tester,
        () => find.text('交易凭证已保存到相册').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 90),
      );
      await _capture(binding, tester, '03-receipt-saved');

      // Leave the success frame visible long enough for visual confirmation.
      // ignore: avoid_print
      print('TRANSACTION_RECEIPT_IOS READY=all');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 20)),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<void> _capture(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
) async {
  final fileName = 'ios-transaction-receipt-$name';
  final bytes = await binding.takeScreenshot(fileName);
  final path = '${Directory.systemTemp.path}/$fileName.png';
  await File(path).writeAsBytes(bytes, flush: true);
  // Public transaction data only.
  // ignore: avoid_print
  print('TRANSACTION_RECEIPT_IOS FILE=$path');
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 750)),
  );
}

Future<void> _waitUntil(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('UI condition was not reached');
    }
    await tester.pump(const Duration(milliseconds: 250));
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
}
