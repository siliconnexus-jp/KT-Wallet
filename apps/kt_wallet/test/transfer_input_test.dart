import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:chains/chains.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/main.dart';
import 'package:kt_wallet/src/app_router.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/wallets/pairing_airgap.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:ui_kit/ui_kit.dart';

import 'support/test_wallet_scope.dart';

/// Opens W4 through the router but WITHOUT any live scope — the standalone
/// design-gallery path, which is the only place the Pencil demo literals
/// (recipient + 120.00) are still seeded and the only place the demo 自定义
/// fee screen is reachable.
Future<void> _openGallery(WidgetTester tester) async {
  tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  final controller = buildTestWalletController();
  await tester.pumpWidget(
    MaterialApp.router(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: buildRouter(
        initialLocation: '/transfer',
        walletController: controller,
      ),
      builder: (context, child) =>
          withTestWalletScope(child!, controller: controller),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens W4 inside the real app (market/network/session scopes mounted).
Future<void> _openLive(
  WidgetTester tester, {
  WalletController? controller,
}) async {
  tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  await tester.pumpWidget(
    KtWalletApp(controller: controller, initialLocation: '/transfer'),
  );
  await tester.pumpAndSettle();
}

/// A paired watch wallet exactly as the four-record demo export produces it:
/// `hasExpandedEvm` is false, which is precisely the shape that used to keep
/// the pre-filled contract address alive on the send screen.
WalletController _pairedWatchController() => WalletController(
  WalletManager(
    initial: [
      WatchWallet(
        id: 'cold',
        name: '主钱包',
        avatarColor: 0xFF0C1220,
        addresses: addressesFromExport(demoAccountExport),
        coldWalletId: 'WLT-3E8A91',
        protocolVersion: 1,
      ),
    ],
  ),
);

bool _nextEnabled(WidgetTester tester) =>
    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '下一步'))
        .onPressed !=
    null;

String _fieldText(WidgetTester tester, int index) =>
    tester.widget<TextField>(find.byType(TextField).at(index)).controller!.text;

void main() {
  testWidgets('transfer input validates address and amount before 下一步', (
    tester,
  ) async {
    await _openGallery(tester);

    // Fields: [address, amount]. Gallery defaults are valid → enabled.
    final fields = find.byType(TextField);
    expect(_nextEnabled(tester), isTrue);

    // Wrong-network (EVM) address is rejected as a mispaste.
    await tester.enterText(
      fields.at(0),
      '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
    );
    await tester.pumpAndSettle();
    expect(_nextEnabled(tester), isFalse);

    // Restore a valid TRON address.
    await tester.enterText(fields.at(0), 'TQm9xPa2Wc8hJdU5eRnT6yGb1sVbAgQs8D');
    await tester.pumpAndSettle();
    expect(_nextEnabled(tester), isTrue);

    // Amount over the available balance shows 余额不足 and disables 下一步.
    await tester.enterText(fields.at(1), '9999');
    await tester.pumpAndSettle();
    expect(find.text('余额不足'), findsOneWidget);
    expect(_nextEnabled(tester), isFalse);

    // A within-balance amount re-enables it.
    await tester.enterText(fields.at(1), '10.5');
    await tester.pumpAndSettle();
    expect(_nextEnabled(tester), isTrue);
  });

  testWidgets('a live send screen starts with empty recipient and amount', (
    tester,
  ) async {
    await _openLive(tester);

    // RELEASE BLOCKER REGRESSION: this screen used to open pre-filled with
    // TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t — the mainnet USDT CONTRACT — and an
    // amount of 120.00, both of which pass validation and enable 下一步.
    expect(_fieldText(tester, 0), isEmpty);
    expect(_fieldText(tester, 1), isEmpty);
    expect(find.text('TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t'), findsNothing);
    expect(_nextEnabled(tester), isFalse);

    // The demo-only 自定义 fee screen (a hardcoded TRON tier list) is not
    // reachable from a live send screen.
    expect(find.text('自定义'), findsNothing);
  });

  testWidgets('a paired watch wallet also starts empty', (tester) async {
    // The paired shape (no expanded EVM addresses) was the exact case the old
    // "clear only when hasExpandedEvm" guard never cleared.
    final controller = _pairedWatchController();
    expect(controller.current!.addresses.hasExpandedEvm, isFalse);

    await _openLive(tester, controller: controller);

    expect(_fieldText(tester, 0), isEmpty);
    expect(_fieldText(tester, 1), isEmpty);
    expect(_nextEnabled(tester), isFalse);
  });

  test('an export carrying every EVM record pairs as expanded EVM', () {
    // addressesFromExport must forward base/arbitrum/avalanche; the payload
    // validator already enforces that they equal the eth address.
    const eth = '0xc71c8B29b3d4b79E19bE1';
    final export = AccountExport(
      walletId: 'WLT-3E8A91',
      walletName: '主钱包',
      accounts: [
        for (final (coin, address, path) in const [
          (60, eth, evmDefaultDerivationPath),
          (966, eth, evmDefaultDerivationPath),
          (8453, eth, evmDefaultDerivationPath),
          (42161, eth, evmDefaultDerivationPath),
          (9000, eth, evmDefaultDerivationPath),
          (195, 'TcPa2Wc8hJdU5eRnT6yGb1sVb7L3kFa', tronDefaultDerivationPath),
          (501, 'cyKpXwMWd4qmDqVr2W', solanaDefaultDerivationPath),
        ])
          AccountRecord(coin: coin, address: address, path: path, index: 0),
      ],
    );

    final addresses = addressesFromExport(export);
    expect(addresses.hasExpandedEvm, isTrue);
    expect(addresses.base, eth);
    expect(addresses.arbitrum, eth);
    expect(addresses.avalanche, eth);

    // A legacy four-record export still pairs, without expanded EVM.
    final legacy = addressesFromExport(demoAccountExport);
    expect(legacy.hasExpandedEvm, isFalse);
    expect(legacy.base, legacy.eth);
  });

  testWidgets('navbar scan opens the mock camera and fills a valid address', (
    tester,
  ) async {
    await _openGallery(tester);

    // Clear the gallery's prefilled address so the scan result is unambiguous.
    await tester.enterText(find.byType(TextField).at(0), '');
    await tester.pumpAndSettle();
    expect(_nextEnabled(tester), isFalse);

    // Navbar scanner icon opens the address scanner screen.
    await tester.tap(find.byIcon(Icons.qr_code_scanner).first);
    await tester.pumpAndSettle();
    expect(find.text('扫描地址二维码'), findsOneWidget);

    // Tapping the viewfinder simulates a successful scan and pops the address.
    await tester.tap(find.byIcon(Icons.qr_code_2));
    await tester.pumpAndSettle();
    expect(find.text('TQm9xPa2Wc8hJdU5eRnT6yGb1sVbAgQs8D'), findsOneWidget);
    expect(find.text('地址格式正确 · TRON 网络'), findsOneWidget);
    expect(_nextEnabled(tester), isTrue);
  });

  testWidgets('token selector switches chain, symbol and available balance', (
    tester,
  ) async {
    await _openGallery(tester);
    expect(find.text('地址格式正确 · TRON 网络'), findsOneWidget);

    // Open the asset sheet from the token card and pick ETH.
    await tester.tap(find.text('TRON · TRC-20'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ETH'));
    await tester.pumpAndSettle();

    // The TRON address is now a wrong-network paste for Ethereum.
    expect(find.text('地址格式正确 · TRON 网络'), findsNothing);
    expect(_nextEnabled(tester), isFalse);
    // Symbol and balance follow the selected asset.
    expect(find.text('可用 0.0842 ETH'), findsOneWidget);
    expect(find.text('ETH'), findsWidgets);

    // A valid Ethereum address is accepted again on the new chain.
    await tester.enterText(
      find.byType(TextField).at(0),
      '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
    );
    await tester.pumpAndSettle();
    expect(find.text('地址格式正确 · Ethereum 网络'), findsOneWidget);
  });

  testWidgets('custom fee screen result maps back onto the segmented tier', (
    tester,
  ) async {
    // Gallery-only affordance (see W31's doc): it serves a hardcoded TRON tier
    // list, so it is hidden on every live path.
    await _openGallery(tester);
    expect(tester.widget<KtSegmented>(find.byType(KtSegmented)).selected, 1);

    // The accessibility-sized action may sit below the 600 px default widget
    // test viewport. Exercise the same scroll-to-action behavior a user gets
    // instead of sending a pointer event to an off-screen render object.
    await tester.ensureVisible(find.text('自定义'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();
    expect(find.text('确认手续费'), findsOneWidget);

    // Pick the fast tier and confirm; the transfer screen mirrors it.
    await tester.tap(find.text('快'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认手续费'));
    await tester.pumpAndSettle();
    expect(tester.widget<KtSegmented>(find.byType(KtSegmented)).selected, 2);
  });
}
