import 'package:chains/chains.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/widgets/token_icon.dart';
import 'package:ui_kit/ui_kit.dart';

void main() {
  test('all built-in native and token brands resolve to bundled artwork', () {
    const expected = {
      'BNB': 'bnb',
      'DAI': 'dai',
      'WETH': 'weth',
      'WBTC': 'wbtc',
      'LINK': 'link',
      'SHIB': 'shib',
      'PEPE': 'pepe',
      'PYUSD': 'pyusd',
      'JUP': 'jup',
      'BONK': 'bonk',
    };

    for (final MapEntry(:key, :value) in expected.entries) {
      expect(TokenIcon.assetFor(key), value, reason: key);
    }
    expect(ChainIcon.assetFor(Chain.bnb), 'bnb');
  });

  testWidgets('unverified lookalike never receives official brand artwork', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: TokenIcon(symbol: 'USDT', official: false, fallbackInitial: 'U'),
      ),
    );

    expect(TokenIcon.assetFor('USDT', official: false), isNull);
    expect(find.byType(Image), findsNothing);
    expect(find.byType(KtAvatar), findsOneWidget);
  });
}
