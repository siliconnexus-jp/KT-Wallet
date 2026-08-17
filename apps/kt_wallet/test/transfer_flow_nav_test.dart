import 'dart:async';
import 'dart:typed_data';

import 'package:chains/chains.dart' show Amount;
import 'package:core_crypto/core_crypto.dart' show ChainAddresses, Coin;
import 'package:core_crypto/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/main.dart';
import 'package:kt_wallet/src/market/balance_service.dart';
import 'package:kt_wallet/src/market/market_controller.dart';
import 'package:kt_wallet/src/market/price_service.dart';
import 'package:kt_wallet/src/market/token_balance_service.dart';
import 'package:kt_wallet/src/security/biometric_auth.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/transfer/local_transfer_service.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';

class _FundedBalances extends BalanceService {
  @override
  Future<Map<Coin, BalanceResult>> fetchAll(
    ChainAddresses addresses, {
    BalanceResultCallback? onResult,
  }) async {
    final results = {
      for (final coin in Coin.values)
        coin: BalanceResult.ok(
          Amount(
            raw: BigInt.from(1000000000),
            decimals: BalanceService.decimalsFor[coin]!,
            symbol: BalanceService.symbolFor[coin]!,
          ),
        ),
    };
    for (final entry in results.entries) {
      onResult?.call(entry.key, entry.value);
    }
    return results;
  }
}

class _FundedTokens extends TokenBalanceService {
  @override
  Future<Map<String, BalanceResult>> fetchAll(ChainAddresses addresses) async =>
      {
        'usdt-tron': BalanceResult.ok(
          Amount(raw: BigInt.from(25000000), decimals: 6, symbol: 'USDT'),
        ),
      };
}

class _TestPrices extends PriceService {
  _TestPrices({this.tronPrice = 0.2});

  final double tronPrice;

  @override
  Future<Map<Coin, double>?> fetchUsdPrices() async => {
    for (final coin in Coin.values) coin: coin == Coin.tron ? tronPrice : 1.0,
  };
}

class _TronQuoteService extends LocalTransferService {
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
    maximumFeeSun: BigInt.from(1250000),
    referenceBlockHeight: 42,
    expiresAt: DateTime.now()
        .add(const Duration(minutes: 10))
        .millisecondsSinceEpoch,
    rawTx: Uint8List.fromList(const [1, 2, 3]),
  );
}

class _InsufficientTronQuoteService extends LocalTransferService {
  @override
  Future<PreparedTronTransfer> prepareTron({
    required TransferDraft draft,
    required String from,
    required String? expectedNetworkIdentity,
  }) async => throw TransferInsufficientFunds(
    'TRX',
    maximumNetworkFeeRaw: BigInt.from(1250000),
  );
}

class _DelayedTronQuoteService extends LocalTransferService {
  final Completer<PreparedTronTransfer> _quote =
      Completer<PreparedTronTransfer>();

  @override
  Future<PreparedTronTransfer> prepareTron({
    required TransferDraft draft,
    required String from,
    required String? expectedNetworkIdentity,
  }) => _quote.future;

  void completeQuote() {
    _quote.complete(
      PreparedTronTransfer(
        from: 'TFrom',
        recipient: 'TRecipient',
        amountRaw: BigInt.one,
        tokenContract: null,
        maximumFeeSun: BigInt.from(1250000),
        referenceBlockHeight: 42,
        expiresAt: DateTime.now()
            .add(const Duration(minutes: 10))
            .millisecondsSinceEpoch,
        rawTx: Uint8List.fromList(const [1, 2, 3]),
      ),
    );
  }
}

ChainAddresses _addresses(String seed) => ChainAddresses(
  eth: '0x${seed}71c8B29b3d4b79E19bE1',
  polygon: '0x${seed}71c8B29b3d4b79E19bE1',
  base: '0x${seed}71c8B29b3d4b79E19bE1',
  arbitrum: '0x${seed}71c8B29b3d4b79E19bE1',
  avalanche: '0x${seed}71c8B29b3d4b79E19bE1',
  bnb: '0x${seed}71c8B29b3d4b79E19bE1',
  tron: 'T${seed}Pa2Wc8hJdU5eRnT6yGb1sVb7L3kFa',
  solana: '${seed}yKpXwMWd4qmDqVr2W',
);

WalletController _wallets() => WalletController(
  WalletManager(
    initial: [
      HotWallet(
        id: 'daily',
        name: '日常钱包',
        avatarColor: 0xFFF59E0B,
        addresses: _addresses('a'),
        backedUp: true,
      ),
      WatchWallet(
        id: 'cold',
        name: '主钱包',
        avatarColor: 0xFF0C1220,
        addresses: _addresses('c'),
        sortOrder: 1,
        coldWalletId: 'WLT-3E8A91',
        protocolVersion: 1,
      ),
    ],
  ),
  crypto: MockCoreCrypto(),
  allowTestBypass: true,
);

/// Walks the full transfer navigation, proving the screens are wired into one
/// flow driven by the current wallet type.
Future<void> _open(
  WidgetTester tester,
  String galleryEntry, {
  LocalTransferService? transferService,
  double tronPrice = 0.2,
}) async {
  tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  final wallets = _wallets();
  final market = MarketController(
    wallets: wallets,
    balances: _FundedBalances(),
    tokens: _FundedTokens(),
    prices: _TestPrices(tronPrice: tronPrice),
  );
  addTearDown(market.dispose);
  await tester.pumpWidget(
    KtWalletApp(
      controller: wallets,
      marketController: market,
      transferService: transferService ?? _TronQuoteService(),
      galleryMode: true,
    ),
  );
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text(galleryEntry), 200);
  await tester.tap(find.text(galleryEntry));
  await tester.pumpAndSettle();
}

Future<void> _openHome(
  WidgetTester tester, {
  LocalTransferService? transferService,
  double tronPrice = 0.2,
}) => _open(
  tester,
  'W1/W20 首页',
  transferService: transferService,
  tronPrice: tronPrice,
);

/// The send screen no longer pre-fills anything on a live path, so every flow
/// test types the transfer it wants to walk through. Address is a real,
/// checksum-valid TRON account (NOT the USDT contract that used to be seeded).
Future<void> _enterTransfer(WidgetTester tester) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), 'TQm9xPa2Wc8hJdU5eRnT6yGb1sVbAgQs8D');
  await tester.enterText(fields.at(1), '12.5');
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'screen reader path names home, confirmation details and authentication',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _openHome(tester);

      expect(tester.getSemantics(find.text('转账').first).label, contains('转账'));
      await tester.tap(find.text('转账'));
      await tester.pumpAndSettle();
      await _enterTransfer(tester);
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel(RegExp(r'^转出地址,')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^收款地址,')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^网络手续费,')), findsOneWidget);

      await tester.tap(find.text('确认转账'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('使用生物识别验证'), findsWidgets);
      expect(find.bySemanticsLabel('改用密码'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets('hot wallet: home → transfer → confirm → auth → result → home', (
    tester,
  ) async {
    final originalAuth = BiometricAuth.instance;
    BiometricAuth.instance = const FakeBiometricAuth(BiometricOutcome.success);
    addTearDown(() => BiometricAuth.instance = originalAuth);
    await _openHome(tester);
    // Default wallet 日常钱包 is hot.
    await tester.tap(find.text('转账'));
    await tester.pumpAndSettle();
    expect(find.text('USDT'), findsWidgets); // transfer input
    await _enterTransfer(tester);

    // 1.25 TRX maximum fee × the injected $0.20 live price. The compact card
    // keeps native units behind the info control instead of adding a third
    // visible row.
    expect(find.text(r'≈ $0.25'), findsOneWidget);
    final feeInfo = find.byKey(const ValueKey('transfer-network-fee-info'));
    await tester.ensureVisible(feeInfo);
    await tester.pumpAndSettle();
    await tester.tap(feeInfo);
    await tester.pumpAndSettle();
    expect(find.text('网络手续费估算'), findsOneWidget);
    expect(find.textContaining('费用支付给网络'), findsNothing);
    expect(find.text('1.25 TRX'), findsOneWidget);
    Navigator.of(
      tester.element(
        find.byKey(const ValueKey('transfer-network-fee-details')),
      ),
    ).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    // Hot confirm shows 确认转账.
    expect(find.text('确认转账'), findsOneWidget);

    await tester.tap(find.text('确认转账'));
    await tester.pumpAndSettle();
    expect(find.text('验证以确认转账'), findsOneWidget); // auth sheet

    await tester.tap(find.text('使用生物识别验证'));
    await tester.pumpAndSettle();
    expect(find.text('正在转账 12.5 USDT'), findsOneWidget); // result
    expect(find.text('处理中'), findsOneWidget);

    await tester.tap(find.text('返回首页'));
    await tester.pumpAndSettle();
    expect(find.text('日常钱包'), findsOneWidget); // back on home
  });

  testWidgets(
    'tiny network-fee fiat stays visible and confirm value is flush right',
    (tester) async {
      await _openHome(tester, tronPrice: 0.0003);
      await tester.tap(find.text('转账'));
      await tester.pumpAndSettle();
      await _enterTransfer(tester);

      expect(find.text(r'≈ $0.0004'), findsOneWidget);
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();

      final value = find.byKey(const ValueKey('confirm-network-fee-value'));
      final row = find.byKey(const ValueKey('confirm-network-fee-row'));
      expect(find.text('≈ 1.25 TRX（\$0.0004）'), findsOneWidget);
      expect(
        tester.getTopRight(value).dx,
        closeTo(tester.getTopRight(row).dx, 1),
      );
    },
  );

  testWidgets('insufficient balance keeps the real fee estimate and warns', (
    tester,
  ) async {
    await _openHome(tester, transferService: _InsufficientTronQuoteService());
    await tester.tap(find.text('转账'));
    await tester.pumpAndSettle();
    await _enterTransfer(tester);

    final feeCard = find.byKey(const ValueKey('transfer-network-fee-card'));
    expect(
      find.descendant(of: feeCard, matching: find.text(r'≈ $0.25')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: feeCard, matching: find.text('余额不足，请检查 TRX 是否足够')),
      findsOneWidget,
    );

    final feeInfo = find.byKey(const ValueKey('transfer-network-fee-info'));
    await tester.ensureVisible(feeInfo);
    await tester.tap(feeInfo);
    await tester.pumpAndSettle();
    expect(find.text('1.25 TRX'), findsOneWidget);
  });

  testWidgets('open fee details refreshes when an in-flight quote arrives', (
    tester,
  ) async {
    final service = _DelayedTronQuoteService();
    await _openHome(tester, transferService: service);
    await tester.tap(find.text('转账'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'TQm9xPa2Wc8hJdU5eRnT6yGb1sVbAgQs8D');
    await tester.enterText(fields.at(1), '1');
    await tester.pump(const Duration(milliseconds: 550));

    final feeInfo = find.byKey(const ValueKey('transfer-network-fee-info'));
    await tester.ensureVisible(feeInfo);
    await tester.tap(feeInfo);
    await tester.pumpAndSettle();
    expect(find.text('-- TRX'), findsOneWidget);

    service.completeQuote();
    await tester.pumpAndSettle();
    expect(find.text('-- TRX'), findsNothing);
    expect(find.text('1.25 TRX'), findsOneWidget);
  });

  testWidgets('watch wallet: transfer confirm generates a sign-request QR', (
    tester,
  ) async {
    await _openHome(tester);
    // Switch to the watch wallet (主钱包).
    await tester.tap(find.text('日常钱包'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('主钱包').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('转账'));
    await tester.pumpAndSettle();
    await _enterTransfer(tester);
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    // Watch confirm shows the air-gap button, not local sign.
    expect(find.text('生成待签名二维码'), findsOneWidget);

    // The QR screen runs a periodic frame-cycling timer, so pumpAndSettle
    // would never settle; pump discrete frames instead.
    await tester.tap(find.text('生成待签名二维码'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('待签名交易'), findsOneWidget); // W6 QR screen
  });

  // These used to open /token straight from the design gallery, which worked
  // only because the screen ignored its arguments and rendered one fixed
  // token. Go in the way a user does — through an asset row — so the route
  // actually carries an asset.
  Future<void> openEthDetail(WidgetTester tester) async {
    await _openHome(tester);
    // ETH is one row across Ethereum, Base and Arbitrum, so the row is named
    // by the SYMBOL. 'Ethereum' now only names the network chip above it.
    final row = find.text('ETH').last;
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
  }

  testWidgets('token detail: send opens the transfer input screen', (
    tester,
  ) async {
    await openEthDetail(tester);
    await tester.tap(find.text('转账'));
    await tester.pumpAndSettle();
    expect(find.text('收款地址'), findsOneWidget); // W4 transfer input
  });

  testWidgets('token detail: receive opens the receive screen', (tester) async {
    await openEthDetail(tester);
    await tester.tap(find.text('收款'));
    await tester.pumpAndSettle();
    // Receive opens on the chain the user came from. It used to ignore that
    // and always show its own default (USDT on TRON), so arriving from an
    // Ethereum asset offered a TRON address.
    expect(find.text('ETH · Ethereum'), findsOneWidget);
    expect(find.text('USDT · TRON'), findsNothing);
    expect(find.text('0xa71c8B29b3d4b79E19bE1'), findsOneWidget);
  });
}
