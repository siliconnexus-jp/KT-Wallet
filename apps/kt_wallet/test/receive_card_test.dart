import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/market/receive_card.dart';

/// The saved receive card is drawn straight onto a canvas, so it is a pure
/// function of its inputs and can be pinned down without a widget tree.
ReceiveCardData _data({
  String address = 'TDS2DLBpz9DGruw8yjn8HsYCpWF3Q1tdNt',
  bool isTestnet = false,
  String warning = 'Only TRON network assets are supported.',
  String? tokenIconAsset,
  String? networkIconAsset,
}) => ReceiveCardData(
  address: address,
  assetLabel: 'USDT · TRON',
  networkName: isTestnet ? 'Nile' : 'TRON',
  generatedAt: DateTime.utc(2026, 3, 9, 14, 38),
  isTestnet: isTestnet,
  title: 'Receiving address',
  networkLabel: 'Network',
  generatedLabel: 'Generated',
  warning: warning,
  testnetLabel: 'TESTNET',
  tokenIconAsset: tokenIconAsset,
  networkIconAsset: networkIconAsset,
);

/// Minimal PNG sanity check: signature plus the IHDR width/height, so a
/// regression that produces an empty or zero-sized image is caught.
({int width, int height}) _pngSize(List<int> bytes) {
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  expect(bytes.take(8).toList(), signature, reason: 'not a PNG');
  int be32(int at) =>
      (bytes[at] << 24) |
      (bytes[at + 1] << 16) |
      (bytes[at + 2] << 8) |
      bytes[at + 3];
  return (width: be32(16), height: be32(20));
}

void main() {
  _cardArtwork();

  TestWidgetsFlutterBinding.ensureInitialized();

  test('renders a non-trivial PNG at the requested scale', () async {
    final png = await renderReceiveCardPng(_data(), scale: 2);
    final size = _pngSize(png);

    expect(size.width, 1440); // 720 logical × 2
    expect(size.height, greaterThan(1400));
    // A blank canvas compresses to almost nothing; the QR alone is far bigger.
    expect(png.length, greaterThan(3000));
  });

  test('scale changes the pixel size, not the layout', () async {
    final one = _pngSize(await renderReceiveCardPng(_data(), scale: 1));
    final three = _pngSize(await renderReceiveCardPng(_data(), scale: 3));

    expect(one.width, 720);
    expect(three.width, 2160);
    // Same aspect: the layout is scale-independent.
    expect((three.height / one.height).round(), 3);
  });

  test('the card grows for a longer warning instead of clipping it', () async {
    final short = _pngSize(await renderReceiveCardPng(_data(), scale: 1));
    final long = _pngSize(
      await renderReceiveCardPng(
        _data(
          warning:
              'Only TRON network (TRC-20) assets are supported. Sending from '
              'other networks will lose funds, and the loss is not '
              'recoverable by anyone including us.',
        ),
        scale: 1,
      ),
    );
    expect(long.height, greaterThan(short.height));
  });

  test('a testnet card differs from the mainnet one', () async {
    final mainnet = await renderReceiveCardPng(_data(), scale: 1);
    final testnet = await renderReceiveCardPng(
      _data(isTestnet: true),
      scale: 1,
    );
    // The testnet badge is extra ink; identical bytes would mean the flag was
    // being ignored.
    expect(testnet, isNot(equals(mainnet)));
  });

  test('a different address produces a different QR', () async {
    final a = await renderReceiveCardPng(_data(), scale: 1);
    final b = await renderReceiveCardPng(
      _data(address: '0xb787f3C2F96403B5a73DC66dE68e4a6395D4e632'),
      scale: 1,
    );
    expect(a, isNot(equals(b)));
  });
}

/// The card is what a recipient looks at before sending. Naming the asset and
/// chain in words alone asks them to read carefully; the marks let them
/// recognise it. Two chains that used to draw as the same letter "A"
/// (Arbitrum, Avalanche) are exactly the case this protects.
void _cardArtwork() {
  test('the token and network marks change the rendered card', () async {
    final plain = await renderReceiveCardPng(_data(), scale: 1);
    final withArt = await renderReceiveCardPng(
      _data(tokenIconAsset: 'usdt', networkIconAsset: 'arb'),
      scale: 1,
    );
    expect(withArt, isNot(plain));
  });

  test('two chains no longer render an identical card', () async {
    final onArbitrum = await renderReceiveCardPng(
      _data(tokenIconAsset: 'usdt', networkIconAsset: 'arb'),
      scale: 1,
    );
    final onAvalanche = await renderReceiveCardPng(
      _data(tokenIconAsset: 'usdt', networkIconAsset: 'avax'),
      scale: 1,
    );
    expect(onArbitrum, isNot(onAvalanche));
  });

  test('an unknown mark degrades to text instead of failing', () async {
    // A user-added token has no bundled artwork; the card must still render.
    final png = await renderReceiveCardPng(
      _data(tokenIconAsset: 'no-such-token'),
      scale: 1,
    );
    expect(png.length, greaterThan(1000));
  });
}
