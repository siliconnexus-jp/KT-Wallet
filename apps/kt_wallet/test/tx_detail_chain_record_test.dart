import 'dart:io';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/market/history_service.dart' show ChainTxRecord;
import 'package:kt_wallet/src/market/transaction_card.dart';
import 'package:kt_wallet/src/platform/external_actions.dart';
import 'package:kt_wallet/src/platform/media_gallery.dart';
import 'package:kt_wallet/src/screens/transfer_screens.dart';

/// The detail route had the same defect as the token detail screen: with no
/// local row it rendered a hardcoded demo transaction, and the records tab
/// pushed it with no arguments for every on-chain row this wallet did not
/// broadcast itself — i.e. every incoming transfer.
Widget _app(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

void main() {
  testWidgets('an on-chain record renders ITS own values', (tester) async {
    await tester.pumpWidget(
      _app(
        TxDetailScreen(
          chainRecord: ChainTxRecord(
            coin: Coin.tron,
            hash: 'abc123def456',
            outgoing: false,
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
            hash: 'abc123def456',
            outgoing: false,
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
