import 'dart:ui' as ui;

import 'package:chains/chains.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    const chainAssets = {
      Chain.ethereum: 'eth',
      Chain.polygon: 'matic',
      Chain.base: 'base',
      Chain.arbitrum: 'arb',
      Chain.avalanche: 'avax',
      Chain.bnb: 'bnb',
      Chain.tron: 'trx',
      Chain.solana: 'sol',
    };
    for (final MapEntry(:key, :value) in chainAssets.entries) {
      expect(ChainIcon.assetFor(key), value, reason: key.name);
    }
  });

  test(
    'Solana artwork is black-backed with the official gradient mark',
    () async {
      final data = await rootBundle.load('assets/tokens/sol.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      final image = frame.image;
      addTearDown(() {
        image.dispose();
        codec.dispose();
      });
      expect(image.width, 128);
      expect(image.height, 128);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(bytes, isNotNull);

      List<int> pixel(int x, int y) {
        final offset = (y * image.width + x) * 4;
        return List<int>.generate(
          4,
          (index) => bytes!.getUint8(offset + index),
        );
      }

      expect(pixel(0, 0)[3], 0); // transparent outside the circular token
      expect(pixel(64, 4), [0, 0, 0, 255]);
      final green = pixel(64, 30);
      final purple = pixel(64, 98);
      expect(green[1], greaterThan(green[0]));
      expect(green[1], greaterThan(green[2]));
      expect(purple[2], greaterThan(purple[0]));
      expect(purple[2], greaterThan(purple[1]));
    },
  );

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
