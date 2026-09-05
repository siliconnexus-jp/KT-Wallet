import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:chains/chains.dart';
import 'package:core_crypto/core_crypto.dart' show ChainAddresses, Coin;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/main.dart';
import 'package:kt_wallet/src/app_router.dart';
import 'package:kt_wallet/src/market/token_balance_service.dart'
    show usdcPolygonToken, usdtTronToken;
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/wallets/pairing_airgap.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:kt_wallet/src/wallets/wallet_store.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:wallet_data/wallet_data.dart'
    show SignMode, TxStatus, WalletDatabase;

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
      theme: ktWalletTheme(),
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
  testWidgets(
    'live fee waiting state explains insufficient balance and disables tiers',
    (tester) async {
      await _openLive(tester, controller: _pairedWatchController());
      final tiers = find.byKey(const ValueKey('transfer-fee-tiers'));
      expect(tester.widget<KtSegmented>(tiers).onChanged, isNull);
      expect(find.text('填写有效收款地址后估算手续费'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('transfer-recipient-input')),
        'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
      );
      await tester.pumpAndSettle();
      expect(find.text('输入有效转账金额后估算手续费'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('transfer-amount-input')),
        '10',
      );
      await tester.pumpAndSettle();
      expect(find.text('余额不足，暂无法估算手续费'), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('transfer-network-fee-fiat')),
            )
            .data,
        '待估算',
      );
      expect(tester.widget<KtSegmented>(tiers).onChanged, isNull);
      await tester.ensureVisible(tiers);
      await tester.pumpAndSettle();
      await tester.tap(find.text('快'));
      await tester.pumpAndSettle();
      expect(tester.widget<KtSegmented>(tiers).selected, 1);
      expect(_nextEnabled(tester), isFalse);

      await tester.enterText(
        find.byKey(const ValueKey('transfer-amount-input')),
        '',
      );
      await tester.pumpAndSettle();
      expect(find.text('余额不足，暂无法估算手续费'), findsNothing);
      expect(find.text('输入有效转账金额后估算手续费'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'recipient and amount are single-layer fields in the real theme',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _openGallery(tester);
      for (final key in ['transfer-recipient-input', 'transfer-amount-input']) {
        final field = tester.widget<TextField>(find.byKey(ValueKey(key)));
        final decoration = field.decoration!;
        expect(decoration.filled, false);
        expect(decoration.enabledBorder, InputBorder.none);
        expect(decoration.focusedBorder, InputBorder.none);
      }
      final recipient = find.byKey(const ValueKey('transfer-recipient-input'));
      final actions = find.byKey(const ValueKey('transfer-address-actions'));
      expect(tester.getSize(recipient).width, greaterThan(300));
      expect(
        tester.getTopLeft(actions).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(recipient).dy),
      );
      expect(find.text('粘贴'), findsOneWidget);
      expect(find.text('扫码'), findsOneWidget);
    },
  );
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

  testWidgets('home send defaults to the latest successfully sent asset', (
    tester,
  ) async {
    final database = WalletDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final wallet = HotWallet(
      id: 'recent-send-wallet',
      name: 'Recent send',
      avatarColor: 0xFF2557E8,
      addresses: const ChainAddresses(
        eth: '0x85f6be9460291e86e0fb49b07d0a83cc5f7206cd',
        polygon: '0x85f6be9460291e86e0fb49b07d0a83cc5f7206cd',
        base: '0x85f6be9460291e86e0fb49b07d0a83cc5f7206cd',
        arbitrum: '0x85f6be9460291e86e0fb49b07d0a83cc5f7206cd',
        avalanche: '0x85f6be9460291e86e0fb49b07d0a83cc5f7206cd',
        bnb: '0x85f6be9460291e86e0fb49b07d0a83cc5f7206cd',
        tron: 'TQm9xPa2Wc8hJdU5eRnT6yGb1sVb7L3kFa',
        solana: '6yKpXwMWd4qmDqVr2W1111111111111111111111',
      ),
      backedUp: true,
    );
    final store = WalletStore(database);
    await store.save(wallet);
    final controller = WalletController(
      WalletManager(initial: [wallet]),
      store: store,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    await controller.saveOutgoingTransaction(
      id: 'confirmed-polygon-usdc',
      coin: Coin.polygon,
      networkId: 'polygon-mainnet',
      contract: usdcPolygonToken.contract,
      from: wallet.addresses.polygon,
      to: '0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed',
      amountRaw: '1000000',
      hash:
          '0x1111111111111111111111111111111111111111111111111111111111111111',
      status: TxStatus.confirmed,
      signMode: SignMode.local,
      createdAt: now - 1000,
    );
    // A newer failed attempt is not a successfully sent asset and must not
    // replace the last real transfer default.
    await controller.saveOutgoingTransaction(
      id: 'failed-tron-usdt',
      coin: Coin.tron,
      networkId: 'tron-mainnet',
      contract: usdtTronToken.contract,
      from: wallet.addresses.tron,
      to: 'TWd4qCEUf3aVpXe2HKk9gJt6nMxR38uQz',
      amountRaw: '1000000',
      hash:
          '0x2222222222222222222222222222222222222222222222222222222222222222',
      status: TxStatus.failed,
      signMode: SignMode.local,
      createdAt: now,
    );

    await _openLive(tester, controller: controller);

    expect(find.text('USDC'), findsWidgets);
    expect(find.text('Polygon · ERC-20'), findsOneWidget);
    expect(find.text('TRON · TRC-20'), findsNothing);
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
    await tester.tap(find.byTooltip('扫描地址二维码'));
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

    // Open the asset sheet, choose Ethereum first, then its native ETH.
    await tester.tap(find.text('TRON · TRC-20'));
    await tester.pumpAndSettle();
    expect(find.text('选择网络'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('transfer-network-eth')));
    await tester.pumpAndSettle();
    expect(find.text('选择资产'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('transfer-asset-option-ethereum:native')),
    );
    await tester.pumpAndSettle();

    // The TRON address is now a wrong-network paste for Ethereum.
    expect(find.text('地址格式正确 · TRON 网络'), findsNothing);
    expect(find.text('地址不合法'), findsOneWidget);
    expect(find.text('not a 20-byte hex address'), findsNothing);
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

  testWidgets('recipient card is followed by the selected network card', (
    tester,
  ) async {
    await _openGallery(tester);

    final card = find.byKey(const ValueKey('transfer-network-card'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('网络')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('TRON')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.byKey(const ValueKey('transfer-network-card-icon')),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('transfer-asset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('transfer-network-eth')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('transfer-asset-option-ethereum:native')),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: card, matching: find.text('Ethereum')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('TRON')),
      findsNothing,
    );
  });

  testWidgets('fee card stays two rows and reveals native units from info', (
    tester,
  ) async {
    await _openGallery(tester);
    expect(tester.widget<KtSegmented>(find.byType(KtSegmented)).selected, 1);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('transfer-network-fee-fiat')))
          .data,
      r'≈ $1.90',
    );
    expect(
      find.byKey(const ValueKey('transfer-network-fee-icon')),
      findsOneWidget,
    );

    final info = find.byKey(const ValueKey('transfer-network-fee-info'));
    await tester.ensureVisible(info);
    await tester.pumpAndSettle();
    await tester.tap(info);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('transfer-network-fee-details')),
      findsOneWidget,
    );
    expect(find.text('13.7 TRX'), findsOneWidget);
  });
}
