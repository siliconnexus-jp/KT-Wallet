import 'support/e2e_credential_batch.dart';
import 'support/e2e_wallet_cleanup.dart';

import 'dart:async';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/main.dart';
import 'package:kt_wallet/src/data/database_provider.dart';
import 'package:kt_wallet/src/security/biometric_auth.dart';
import 'package:kt_wallet/src/state/networks.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:kt_wallet/src/wallets/wallet_store.dart';
import 'package:wallet_data/wallet_data.dart' show TxStatus;

const _mnemonic = String.fromEnvironment('SEPOLIA_E2E_MNEMONIC');
const _walletId = 'sepolia-ui-transfer-capture-v1';

void main() {
  requireFreshE2eCredentialBatchIfConfigured();
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'normal app UI submits ETH and Test USDT on Sepolia',
    (tester) async {
      expect(_mnemonic, isNotEmpty);
      tester.platformDispatcher.localesTestValue = const [Locale('zh')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      final crypto = MethodChannelCoreCrypto();
      final originalAuth = BiometricAuth.instance;
      BiometricAuth.instance = const FakeBiometricAuth(
        BiometricOutcome.success,
      );
      addTearDown(() => BiometricAuth.instance = originalAuth);
      await crypto.storeWallet(
        walletId: _walletId,
        mnemonic: _mnemonic,
        requireAuth: false,
      );
      registerE2eWalletCleanup(crypto, _walletId);
      final addresses = await crypto.deriveAddresses(_walletId);
      final wallet = HotWallet(
        id: _walletId,
        name: 'Sepolia 实测钱包',
        avatarColor: 0xFF5B86FF,
        addresses: addresses,
        backedUp: true,
      );
      final store = WalletStore(openWalletDatabase());
      await store.delete(_walletId);
      await store.save(wallet);
      final wallets = WalletController(
        WalletManager(initial: [wallet]),
        crypto: crypto,
        store: store,
      );
      addTearDown(wallets.close);
      final networks = NetworkController(
        initialEnvironment: NetworkEnvironment.testnet,
      );

      await binding.convertFlutterSurfaceToImage();
      await tester.pumpWidget(
        KtWalletApp(
          controller: wallets,
          networkController: networks,
          initialLocation: '/home',
        ),
      );
      await _waitUntil(
        tester,
        () => find.text('Sepolia 实测钱包').evaluate().isNotEmpty,
      );
      await _capture(binding, 'UI_CAPTURE_HOME');

      await _submitTransfer(
        binding,
        tester,
        assetSubtitle: 'Sepolia',
        symbol: 'ETH',
        recipient: addresses.eth,
        amount: '0.00001',
        inputMarker: 'UI_CAPTURE_ETH_INPUT',
        confirmMarker: 'UI_CAPTURE_ETH_CONFIRM',
        authMarker: 'UI_CAPTURE_ETH_AUTH',
        resultMarker: 'UI_CAPTURE_ETH_RESULT',
        confirmedMarker: 'UI_CAPTURE_ETH_CONFIRMED',
      );

      await tester.tap(find.text('返回首页'));
      await tester.pumpAndSettle();

      await _submitTransfer(
        binding,
        tester,
        assetSubtitle: 'Sepolia · ERC-20',
        symbol: 'USDT',
        recipient: addresses.eth,
        amount: '1',
        inputMarker: 'UI_CAPTURE_USDT_INPUT',
        confirmMarker: 'UI_CAPTURE_USDT_CONFIRM',
        authMarker: 'UI_CAPTURE_USDT_AUTH',
        resultMarker: 'UI_CAPTURE_USDT_RESULT',
        confirmedMarker: 'UI_CAPTURE_USDT_CONFIRMED',
      );

      final transactions = await wallets.localTransactions(
        networkIds: {ethSepolia.id},
      );
      final usdt = transactions.singleWhere(
        (transaction) => transaction.contract != null,
      );
      expect(usdt.status, TxStatus.confirmed);
      expect(usdt.hash, isNotNull);
      expect(
        usdt.amountRaw,
        '1000000',
        reason: '1 Test USDT on the 6-decimal Sepolia contract',
      );

      await tester.tap(find.text('返回首页'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('记录'));
      await tester.pump();
      final usdtRow = find.byKey(ValueKey('history-record-${usdt.hash}'));
      await _waitUntil(
        tester,
        () => usdtRow.evaluate().isNotEmpty,
        timeout: const Duration(minutes: 1),
      );
      expect(find.textContaining('已确认'), findsWidgets);
      expect(find.text('-1 USDT'), findsWidgets);
      await _capture(binding, 'UI_CAPTURE_USDT_RECORD_CONFIRMED');

      await tester.tap(usdtRow);
      await _waitUntil(
        tester,
        () => find
            .byKey(const ValueKey('transaction-export-receipt'))
            .evaluate()
            .isNotEmpty,
      );
      expect(find.text('已确认'), findsWidgets);
      expect(find.text('-1 USDT'), findsWidgets);
      await _capture(binding, 'UI_CAPTURE_USDT_DETAIL_CONFIRMED');

      // ignore: avoid_print
      print('UI_CAPTURE_FILES_READY');
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

Future<void> _submitTransfer(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester, {
  required String assetSubtitle,
  required String symbol,
  required String recipient,
  required String amount,
  required String inputMarker,
  required String confirmMarker,
  required String authMarker,
  required String resultMarker,
  required String confirmedMarker,
}) async {
  await tester.tap(find.text('转账'));
  await tester.pumpAndSettle();

  // Open the normal asset picker and select the requested Sepolia asset by
  // its network subtitle, avoiding ambiguous repeated token symbols.
  await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
  await tester.pumpAndSettle();
  final networkChoice = find.byWidgetPredicate(
    (widget) =>
        widget is Text && (widget.data ?? '').startsWith('$assetSubtitle · 可用'),
    description: 'asset subtitle starting with "$assetSubtitle · 可用"',
  );
  expect(networkChoice, findsOneWidget);
  await tester.ensureVisible(networkChoice);
  await tester.tap(networkChoice);
  await tester.pumpAndSettle();

  final fields = find.byType(TextField);
  expect(fields, findsNWidgets(2));
  await tester.enterText(fields.at(0), recipient);
  await tester.enterText(fields.at(1), amount);
  await tester.pumpAndSettle();
  expect(find.textContaining('地址格式正确'), findsOneWidget);
  expect(find.text(symbol), findsWidgets);
  await _capture(binding, inputMarker);

  await tester.tap(find.text('下一步'));
  await tester.pumpAndSettle();
  expect(find.text('确认转账'), findsOneWidget);
  await _capture(binding, confirmMarker);

  await tester.tap(find.text('确认转账'));
  await tester.pumpAndSettle();
  expect(find.text('验证以确认转账'), findsOneWidget);
  await _capture(binding, authMarker);

  final authenticate = find.text('使用生物识别验证');
  await tester.ensureVisible(authenticate);
  await tester.pumpAndSettle();
  expect(authenticate.hitTestable(), findsOneWidget);
  await tester.tap(authenticate);
  await _waitForSubmitted(tester, timeout: const Duration(minutes: 2));
  expect(find.text('交易已提交'), findsOneWidget);
  expect(find.textContaining(RegExp(r'\(\d+/\d+\)')), findsNothing);
  await _capture(binding, resultMarker);
  await _waitUntil(
    tester,
    () => find.text('已确认').evaluate().isNotEmpty,
    timeout: const Duration(minutes: 2),
  );
  final confirmationRow = find.byKey(const ValueKey('broadcast-confirmations'));
  expect(confirmationRow, findsOneWidget);
  final confirmationValues = tester
      .widgetList<Text>(
        find.descendant(of: confirmationRow, matching: find.byType(Text)),
      )
      .map((text) => text.data)
      .whereType<String>()
      .where((text) => RegExp(r'^[1-9]\d*$').hasMatch(text));
  expect(confirmationValues, isNotEmpty);
  await _capture(binding, confirmedMarker);
}

Future<void> _waitForSubmitted(
  WidgetTester tester, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (find.text('交易已提交').evaluate().isEmpty) {
    final snackbars = find.byType(SnackBar);
    if (snackbars.evaluate().isNotEmpty) {
      final messages = tester
          .widgetList<Text>(
            find.descendant(of: snackbars, matching: find.byType(Text)),
          )
          .map((text) => text.data)
          .whereType<String>()
          .where((text) => text.isNotEmpty)
          .join(' | ');
      throw TestFailure(
        'transfer failed before the result screen: '
        '${messages.isEmpty ? 'unknown snackbar error' : messages}',
      );
    }
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('transfer result screen was not reached');
    }
    await tester.pump(const Duration(milliseconds: 250));
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
}

Future<void> _waitUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
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

Future<void> _capture(
  IntegrationTestWidgetsFlutterBinding binding,
  String marker,
) async {
  // The host-side runner captures the full Simulator screen at these markers,
  // including native Face ID overlays which a Flutter surface capture omits.
  // ignore: avoid_print
  print(marker);
  await Future<void>.delayed(const Duration(seconds: 8));
}
