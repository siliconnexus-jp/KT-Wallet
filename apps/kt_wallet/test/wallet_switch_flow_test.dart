import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/main.dart';

/// Proves the UI and logic are connected: switching wallets in the sheet drives
/// the WalletController and rebuilds the home screen.
void main() {
  testWidgets('wallet switcher changes the current wallet on the home screen',
      (tester) async {
    tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(KtWalletApp());
    await tester.pumpAndSettle();

    // Boot is the gallery; scroll to and open the live home screen.
    await tester.scrollUntilVisible(find.text('W1/W20 首页'), 200);
    await tester.tap(find.text('W1/W20 首页'));
    await tester.pumpAndSettle();

    // Home shows the first seeded wallet (日常钱包, hot, not backed up → banner).
    expect(find.text('日常钱包'), findsOneWidget);
    expect(find.text('尚未备份助记词，存在丢失风险'), findsOneWidget);

    // Tap the wallet pill to open the switcher.
    await tester.tap(find.text('日常钱包'));
    await tester.pumpAndSettle();

    // Switcher lists all seeded wallets; pick the watch wallet.
    expect(find.text('储蓄钱包'), findsOneWidget);
    expect(find.text('主钱包'), findsWidgets);
    await tester.tap(find.text('主钱包').last);
    await tester.pumpAndSettle();

    // Home now reflects the watch wallet: no backup banner, and the watch
    // action row includes 扫签名 instead of 更多.
    expect(find.text('主钱包'), findsOneWidget);
    expect(find.text('尚未备份助记词，存在丢失风险'), findsNothing);
    expect(find.text('扫签名'), findsOneWidget);
  });

  testWidgets('switching to the backed-up hot wallet hides the backup banner',
      (tester) async {
    tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(KtWalletApp());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('W1/W20 首页'), 200);
    await tester.tap(find.text('W1/W20 首页'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('日常钱包'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('储蓄钱包'));
    await tester.pumpAndSettle();

    expect(find.text('储蓄钱包'), findsOneWidget);
    expect(find.text('尚未备份助记词，存在丢失风险'), findsNothing);
    // Backed-up hot wallet still shows the hot action row (更多, not 扫签名).
    expect(find.text('更多'), findsOneWidget);
  });
}
