import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

Widget _lightHarness(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: WalletColors.bg,
        body: Center(
          child: Padding(padding: const EdgeInsets.all(20), child: child),
        ),
      ),
    );

Widget _darkHarness(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: SignerColors.bg,
        body: Center(
          child: Padding(padding: const EdgeInsets.all(24), child: child),
        ),
      ),
    );

void main() {
  testWidgets('primary buttons golden', (tester) async {
    await tester.pumpWidget(
      _lightHarness(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            KtPrimaryButton(label: '下一步', onPressed: () {}),
            const SizedBox(height: 12),
            KtPrimaryButton(
              label: '继续',
              style: KtButtonStyle.signer,
              onPressed: () {},
            ),
            const SizedBox(height: 12),
            KtPrimaryButton(
              label: '创建新钱包',
              style: KtButtonStyle.signerContrast,
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/primary_buttons.png'),
    );
  });

  testWidgets('badges and detail rows golden (light)', (tester) async {
    await tester.pumpWidget(
      _lightHarness(
        const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                WalletTypeBadge(kind: WalletKind.hot),
                SizedBox(width: 8),
                WalletTypeBadge(kind: WalletKind.watch),
                SizedBox(width: 8),
                NetworkBadge(label: 'Ethereum', dotColor: ChainColors.ethereum),
              ],
            ),
            SizedBox(height: 16),
            SizedBox(
              width: 320,
              child: KtDetailRow(label: '网络', value: 'TRON · TRC-20'),
            ),
            SizedBox(height: 8),
            SizedBox(
              width: 320,
              child: KtDetailRow(
                label: '收款地址',
                value: 'TWd4qCEU…nMxR38uQz',
                mono: true,
              ),
            ),
            SizedBox(height: 16),
            ShardProgressBar(received: 3, total: 8),
          ],
        ),
      ),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/light_components.png'),
    );
  });

  testWidgets('badges and detail rows golden (dark)', (tester) async {
    await tester.pumpWidget(
      _darkHarness(
        const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                WalletTypeBadge(kind: WalletKind.hot, dark: true),
                SizedBox(width: 8),
                WalletTypeBadge(kind: WalletKind.watch, dark: true),
                SizedBox(width: 8),
                NetworkBadge(
                  label: 'Solana',
                  dotColor: ChainColors.solana,
                  dark: true,
                ),
              ],
            ),
            SizedBox(height: 16),
            SizedBox(
              width: 320,
              child: SignerDetailRow(
                label: '收款地址（To）',
                value: 'TWd4qCEUYAJgLtSpQ2dK7wY9nMxR38uQz',
              ),
            ),
            SizedBox(height: 16),
            ShardProgressBar(
              received: 5,
              total: 8,
              color: SignerColors.ok,
              trackColor: SignerColors.border,
            ),
          ],
        ),
      ),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/dark_components.png'),
    );
  });
}
