import 'package:core_crypto/core_crypto.dart';
import 'package:core_crypto/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/main.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:ui_kit/ui_kit.dart';

/// Proves the wallet-detail screen (W28) is bound to the live controller:
/// rename and color changes mutate the controller, the backup sheet marks the
/// wallet backed up, and the manage list navigates into the detail screen.

// 12 words from the mock wordlist so MockCoreCrypto accepts and stores it.
const _mnemonic =
    'abandon ability able about above absent absorb abstract absurd abuse access accident';

class _DeleteFailingCrypto extends MockCoreCrypto {
  @override
  Future<void> deleteWallet(String walletId) =>
      Future<void>.error(const AuthFailedException());
}

/// Controller with one real hot wallet whose key material lives in the mock
/// CoreCrypto (so exportMnemonic works like production).
Future<WalletController> _controller({
  bool backedUp = false,
  MockCoreCrypto? crypto,
}) async {
  crypto ??= MockCoreCrypto();
  final controller = WalletController(WalletManager(), crypto: crypto);
  await crypto.storeWallet(walletId: 'w1', mnemonic: _mnemonic);
  final addresses = await crypto.deriveAddresses('w1');
  await controller.add(
    HotWallet(
      id: 'w1',
      name: '日常钱包',
      avatarColor: 0xFFF59E0B,
      addresses: addresses,
      backedUp: backedUp,
    ),
  );
  return controller;
}

Future<void> _pump(
  WidgetTester tester,
  WalletController controller,
  String location,
) async {
  tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  await tester.pumpWidget(
    KtWalletApp(controller: controller, initialLocation: location),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('manage list row opens the wallet detail screen', (tester) async {
    final controller = await _controller();
    await _pump(tester, controller, '/wallet-manage');

    await tester.tap(find.text('日常钱包'));
    await tester.pumpAndSettle();

    expect(find.text('钱包详情'), findsOneWidget);
    expect(find.text('w1'), findsOneWidget); // real wallet id row
  });

  testWidgets('rename dialog updates the wallet name in the controller', (
    tester,
  ) async {
    final controller = await _controller();
    await _pump(tester, controller, '/wallet-detail?id=w1');

    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();
    expect(find.text('重命名钱包'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '旅行钱包');
    await tester.tap(find.byKey(const ValueKey('kt-dialog-confirm')));
    await tester.pumpAndSettle();

    expect(controller.wallets.single.name, '旅行钱包');
    expect(find.text('旅行钱包'), findsOneWidget);
  });

  testWidgets('detail uses the flat OKX-aligned visual hierarchy', (
    tester,
  ) async {
    final controller = await _controller(backedUp: true);
    await _pump(tester, controller, '/wallet-detail?id=w1');

    final screen = tester.widget<KtScreen>(
      find.byKey(const ValueKey('wallet-detail-screen')),
    );
    expect(screen.backgroundColor, WalletColors.surface);

    final avatar = tester.widget<Container>(
      find.byKey(const ValueKey('wallet-detail-avatar')),
    );
    final avatarDecoration = avatar.decoration! as BoxDecoration;
    expect(avatarDecoration.shape, BoxShape.rectangle);
    expect(avatarDecoration.borderRadius, BorderRadius.circular(72 * 0.31));

    final infoCard = tester.widget<Container>(
      find.byKey(const ValueKey('wallet-detail-info-card')),
    );
    expect((infoCard.decoration! as BoxDecoration).color, WalletColors.bg);

    expect(
      find.byKey(const ValueKey('wallet-detail-action-list')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('wallet-detail-account-addresses')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('wallet-detail-view-mnemonic')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('wallet-detail-view-private-key')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('wallet-detail-delete')), findsOneWidget);
    expect(find.byIcon(Icons.key), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    expect(find.byType(Divider), findsNWidgets(4));
  });

  testWidgets('account-address row opens the shared full-page directory', (
    tester,
  ) async {
    final controller = await _controller(backedUp: true);
    await _pump(tester, controller, '/wallet-detail?id=w1');

    await tester.tap(
      find.byKey(const ValueKey('wallet-detail-account-addresses')),
    );
    await tester.pumpAndSettle();

    expect(find.text('账户地址'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('wallet-addresses-screen')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('wallet-addresses-directory')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('wallet-address-search-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('wallet-address-alphabet-index')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('wallet-address-row-eth-mainnet')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('wallet-address-search-field')),
      'sol',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('wallet-address-row-sol-mainnet')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('wallet-address-row-eth-mainnet')),
      findsNothing,
    );
  });

  testWidgets('tapping a palette color applies it to the wallet', (
    tester,
  ) async {
    final controller = await _controller();
    await _pump(tester, controller, '/wallet-detail?id=w1');

    expect(controller.wallets.single.avatarColor, 0xFFF59E0B);
    await tester.tap(find.byKey(const ValueKey('palette-${0xFF8B5CF6}')));
    await tester.pumpAndSettle();

    expect(controller.wallets.single.avatarColor, 0xFF8B5CF6);
  });

  testWidgets('backup banner sheet shows the mnemonic and marks backed up', (
    tester,
  ) async {
    final controller = await _controller();
    await _pump(tester, controller, '/wallet-detail?id=w1');

    // Unbacked hot wallet shows the banner; tapping opens the mnemonic sheet.
    await tester.tap(find.text('立即备份'));
    await tester.pumpAndSettle();
    expect(find.text('abandon'), findsOneWidget); // real exported mnemonic
    expect(find.text('accident'), findsOneWidget);

    await tester.tap(find.text('我已抄写'));
    await tester.pumpAndSettle();

    final wallet = controller.wallets.single as HotWallet;
    expect(wallet.backedUp, isTrue);
    expect(find.text('立即备份'), findsNothing); // banner gone
    expect(find.text('备份已验证，助记词记录正确'), findsOneWidget); // snackbar
  });

  testWidgets('backed-up wallet: view-mnemonic sheet has no confirm button', (
    tester,
  ) async {
    final controller = await _controller(backedUp: true);
    await _pump(tester, controller, '/wallet-detail?id=w1');

    expect(find.text('立即备份'), findsNothing);
    await tester.tap(find.text('查看助记词'));
    await tester.pumpAndSettle();
    expect(find.text('abandon'), findsOneWidget);
    expect(find.text('我已抄写'), findsNothing);
  });

  testWidgets('delete row removes the wallet after confirmation', (
    tester,
  ) async {
    final controller = await _controller();
    await _pump(tester, controller, '/wallet-detail?id=w1');

    final deleteRow = find.byKey(const ValueKey('wallet-detail-delete'));
    await tester.ensureVisible(deleteRow);
    await tester.tap(deleteRow);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('kt-dialog-confirm')));
    await tester.pumpAndSettle();

    expect(controller.wallets, isEmpty);
    expect(find.text('已删除「日常钱包」'), findsOneWidget); // snackbar
  });

  testWidgets('native delete failure keeps the wallet and explains retry', (
    tester,
  ) async {
    final controller = await _controller(crypto: _DeleteFailingCrypto());
    await _pump(tester, controller, '/wallet-detail?id=w1');

    final deleteRow = find.byKey(const ValueKey('wallet-detail-delete'));
    await tester.ensureVisible(deleteRow);
    await tester.tap(deleteRow);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('kt-dialog-confirm')));
    await tester.pumpAndSettle();

    expect(controller.wallets, hasLength(1));
    expect(find.text('无法安全删除钱包，当前内容未被移除，请重试。'), findsOneWidget);
    expect(find.text('钱包详情'), findsOneWidget);
  });
}
