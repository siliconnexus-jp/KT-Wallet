import 'dart:io';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/market/history_service.dart'
    show ChainTxRecord, ChainTxStatus;
import 'package:kt_wallet/src/market/transaction_card.dart';
import 'package:kt_wallet/src/platform/external_actions.dart';
import 'package:kt_wallet/src/platform/media_gallery.dart';
import 'package:kt_wallet/src/screens/transfer_screens.dart';
import 'package:kt_wallet/src/state/networks.dart';

import 'support/test_wallet_scope.dart';

/// The detail route had the same defect as the token detail screen: with no
/// local row it rendered a hardcoded demo transaction, and the records tab
/// pushed it with no arguments for every on-chain row this wallet did not
/// broadcast itself — i.e. every incoming transfer.
Widget _app(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: withTestWalletScope(child),
);

void main() {
  testWidgets(
    'chain history keeps its original network after environment switch',
    (tester) async {
      final external = FakeExternalActions();
      final previousExternal = ExternalActions.instance;
      ExternalActions.instance = external;
      addTearDown(() => ExternalActions.instance = previousExternal);
      final networks = NetworkController(); // mainnet remains active

      await tester.pumpWidget(
        _app(
          NetworkScope(
            controller: networks,
            child: TxDetailScreen(
              chainRecord: ChainTxRecord(
                coin: Coin.eth,
                networkId: 'eth-sepolia',
                hash: '0xsepolia-history',
                outgoing: true,
                amountText: '0.01 ETH',
                timestamp: DateTime(2026, 8, 3),
                confirmed: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sepolia'), findsOneWidget);
      expect(find.text('Ethereum'), findsNothing);
      final explorer = find.byIcon(Icons.open_in_new);
      expect(explorer, findsOneWidget);
      await tester.tap(explorer);
      await tester.pumpAndSettle();
      expect(
        external.opened.single.toString(),
        'https://sepolia.etherscan.io/tx/0xsepolia-history',
      );
    },
  );

  testWidgets(
    'legacy or cross-family network identity never guesses an explorer',
    (tester) async {
      Future<void> pump(ChainTxRecord record) async {
        await tester.pumpWidget(_app(TxDetailScreen(chainRecord: record)));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.open_in_new), findsNothing);
        expect(
          find.byKey(const ValueKey('transaction-export-receipt')),
          findsNothing,
        );
      }

      await pump(
        ChainTxRecord(
          coin: Coin.eth,
          hash: 'legacy-without-network',
          outgoing: false,
          amountText: '1 ETH',
          timestamp: DateTime(2026, 8, 3),
          confirmed: true,
        ),
      );
      await pump(
        ChainTxRecord(
          coin: Coin.tron,
          networkId: 'eth-mainnet',
          hash: 'cross-family-network',
          outgoing: false,
          amountText: '1 TRX',
          timestamp: DateTime(2026, 8, 3),
          confirmed: true,
        ),
      );
    },
  );

  testWidgets('an on-chain record renders ITS own values', (tester) async {
    await tester.pumpWidget(
      _app(
        TxDetailScreen(
          chainRecord: ChainTxRecord(
            coin: Coin.tron,
            networkId: 'tron-mainnet',
            hash: 'abc123def456',
            outgoing: false,
            fromAddress: 'TUQQ9bYZNGPhzFTSKvqxYkAvgQQD2Ha9uT',
            toAddress: 'TQm9xPa2Wc8hJdU5eRnT6yGb1sVb7L3kFa',
            amountText: '88.5 USDT',
            timestamp: DateTime(2026, 3, 9, 20, 4),
            confirmed: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('88.5 USDT'), findsOneWidget);
    expect(find.text('收款'), findsWidgets); // direction: incoming
    // The demo transaction must not survive anywhere on this screen.
    expect(find.text('-120.00 USDT'), findsNothing);
  });

  testWidgets('a failed record is not shown as confirmed', (tester) async {
    await tester.pumpWidget(
      _app(
        TxDetailScreen(
          chainRecord: ChainTxRecord(
            coin: Coin.eth,
            hash: 'deadbeef',
            outgoing: true,
            amountText: '1 ETH',
            timestamp: DateTime(2026, 3, 9),
            confirmed: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('失败'), findsWidgets);
    expect(find.text('-120.00 USDT'), findsNothing);
  });

  testWidgets('an unknown record is honest and not shown as failed', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        TxDetailScreen(
          chainRecord: ChainTxRecord(
            coin: Coin.eth,
            hash: 'status-missing',
            outgoing: true,
            amountText: '1 ETH',
            timestamp: DateTime(2026, 3, 9),
            status: ChainTxStatus.unknown,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('状态暂不可用'), findsWidgets);
    expect(find.text('失败'), findsNothing);
    expect(find.text('已确认'), findsNothing);
  });

  testWidgets('an unverified token shows its contract and warning', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        TxDetailScreen(
          chainRecord: ChainTxRecord(
            coin: Coin.eth,
            hash: 'spoof',
            outgoing: false,
            amountText: '10 USDT',
            assetContract: '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            assetSymbol: 'USDT',
            assetVerified: false,
            timestamp: DateTime(2026, 3, 9),
            confirmed: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        '⚠️ 名称显示为 USDT，但此合约不在 KT Wallet 验证的官方 USDT '
        '地址列表中。它可能是同名或桥接资产，请勿仅凭名称转账。',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(
      find.text('0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
      findsOneWidget,
    );
  });

  testWidgets('an unparseable amount stays -- instead of a number', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        TxDetailScreen(
          chainRecord: ChainTxRecord(
            coin: Coin.solana,
            hash: 'sig',
            outgoing: false,
            timestamp: DateTime(2026, 3, 9),
            confirmed: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('--'), findsWidgets);
    expect(find.text('-120.00 USDT'), findsNothing);
  });

  testWidgets('no record and no id keeps the gallery snapshot', (tester) async {
    await tester.pumpWidget(_app(const TxDetailScreen()));
    await tester.pumpAndSettle();
    expect(find.text('-120.00 USDT'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('transaction-export-receipt')),
      findsNothing,
    );
  });

  testWidgets('incoming chain record exports a verifiable receipt image', (
    tester,
  ) async {
    final external = FakeExternalActions();
    final previousExternal = ExternalActions.instance;
    ExternalActions.instance = external;
    addTearDown(() => ExternalActions.instance = previousExternal);
    final directory = Directory.systemTemp.createTempSync('kt-receipt-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    TransactionCardData? rendered;

    await tester.pumpWidget(
      _app(
        TxDetailScreen(
          chainRecord: ChainTxRecord(
            coin: Coin.tron,
            networkId: 'tron-mainnet',
            hash: 'abc123def456',
            outgoing: false,
            fromAddress: 'TUQQ9bYZNGPhzFTSKvqxYkAvgQQD2Ha9uT',
            toAddress: 'TQm9xPa2Wc8hJdU5eRnT6yGb1sVb7L3kFa',
            amountText: '88.5 USDT',
            timestamp: DateTime(2026, 3, 9, 20, 4),
            confirmed: true,
          ),
          tempDirectory: () async => directory,
          cardRenderer: (data) async {
            rendered = data;
            return Uint8List.fromList(const [0x89, 0x50, 0x4E, 0x47]);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final export = find.byKey(const ValueKey('transaction-export-receipt'));
    expect(export, findsOneWidget);
    await tester.ensureVisible(export);
    await tester.tap(export);
    await tester.pumpAndSettle();
    expect(find.text('分享凭证图片'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('receipt-share-image')));
    await tester.pumpAndSettle();

    expect(rendered?.amount, '88.5 USDT');
    expect(rendered?.direction, '收款');
    expect(rendered?.transactionTimeLabel, '交易时间');
    expect(rendered?.transactionTime, '2026-03-09 20:04');
    expect(rendered?.explorerUrl, contains('abc123def456'));
    expect(
      rendered?.fields.any(
        (field) =>
            field.label == '来源地址' &&
            field.value == 'TUQQ9bYZNGPhzFTSKvqxYkAvgQQD2Ha9uT',
      ),
      isTrue,
    );
    expect(
      rendered?.fields.any(
        (field) =>
            field.label == '到账账户' &&
            field.value == '日常钱包\nTQm9xPa2Wc8hJdU5eRnT6yGb1sVb7L3kFa',
      ),
      isTrue,
    );
    expect(external.sharedFiles, hasLength(1));
    expect(external.sharedFiles.single.text, rendered?.explorerUrl);
    expect(File(external.sharedFiles.single.path).readAsBytesSync(), const [
      0x89,
      0x50,
      0x4E,
      0x47,
    ]);
  });

  testWidgets('receipt can be saved to the photo library', (tester) async {
    final gallery = FakeMediaGallery();
    final previousGallery = MediaGallery.instance;
    MediaGallery.instance = gallery;
    addTearDown(() => MediaGallery.instance = previousGallery);

    await tester.pumpWidget(
      _app(
        TxDetailScreen(
          chainRecord: ChainTxRecord(
            coin: Coin.eth,
            networkId: 'eth-mainnet',
            hash: '0xreceipt',
            outgoing: true,
            amountText: '0.01 ETH',
            timestamp: DateTime(2026, 3, 9),
            confirmed: true,
          ),
          cardRenderer: (_) async => Uint8List.fromList(const [1, 2, 3]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final export = find.byKey(const ValueKey('transaction-export-receipt'));
    await tester.ensureVisible(export);
    await tester.tap(export);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('receipt-save-photos')));
    await tester.pumpAndSettle();

    expect(gallery.saved, hasLength(1));
    expect(gallery.saved.single.name, 'kt-wallet-transaction');
    expect(find.text('交易凭证已保存到相册'), findsOneWidget);
  });
}
