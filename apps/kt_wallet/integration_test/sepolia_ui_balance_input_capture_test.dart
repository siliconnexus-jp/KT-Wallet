import 'support/e2e_credential_batch.dart';
import 'support/e2e_wallet_cleanup.dart';

import 'dart:async';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/main.dart';
import 'package:kt_wallet/src/state/networks.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';

const _mnemonic = String.fromEnvironment('SEPOLIA_E2E_MNEMONIC');

void main() {
  requireFreshE2eCredentialBatchIfConfigured();
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture live balance and populated ETH send form', (
    tester,
  ) async {
    final crypto = MethodChannelCoreCrypto();
    const walletId = 'sepolia-ui-balance-input-v1';
    await crypto.storeWallet(
      walletId: walletId,
      mnemonic: _mnemonic,
      requireAuth: false,
    );
    registerE2eWalletCleanup(crypto, walletId);
    final addresses = await crypto.deriveAddresses(walletId);
    final wallets = WalletController(
      WalletManager(
        initial: [
          HotWallet(
            id: walletId,
            name: 'Sepolia 实测钱包',
            avatarColor: 0xFF5B86FF,
            addresses: addresses,
            backedUp: true,
          ),
        ],
      ),
      crypto: crypto,
    );
    tester.platformDispatcher.localesTestValue = const [Locale('zh')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      KtWalletApp(
        controller: wallets,
        networkController: NetworkController(
          initialEnvironment: NetworkEnvironment.testnet,
        ),
        initialLocation: '/home',
      ),
    );

    await _waitUntil(
      tester,
      () => find.textContaining('USDT · Sepolia').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 45),
    );
    // ignore: avoid_print
    print('UI_CAPTURE_LIVE_BALANCES');
    await Future<void>.delayed(const Duration(seconds: 60));

    await tester.tap(find.text('转账'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    await tester.pumpAndSettle();
    final eth = find.byWidgetPredicate(
      (widget) =>
          widget is Text && (widget.data ?? '').startsWith('Sepolia · 可用'),
    );
    expect(eth, findsOneWidget);
    await tester.tap(eth);
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), addresses.eth);
    await tester.enterText(fields.at(1), '0.00001');
    await tester.pumpAndSettle();
    expect(find.textContaining('地址格式正确'), findsOneWidget);
    // ignore: avoid_print
    print('UI_CAPTURE_ETH_FORM');
    await Future<void>.delayed(const Duration(seconds: 60));
  });
}

Future<void> _waitUntil(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('live balance did not load');
    }
    await tester.pump(const Duration(milliseconds: 250));
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
}
