import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/market/history_service.dart' show ChainTxRecord;
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
  });
}
