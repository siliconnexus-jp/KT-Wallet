import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:qr/qr.dart';
import 'package:ui_kit/ui_kit.dart';

/// Everything printed on a saved receive card. Only public data: the address,
/// which network it is on, and when the image was made.
class ReceiveCardData {
  const ReceiveCardData({
    required this.address,
    required this.assetLabel,
    required this.networkName,
    required this.generatedAt,
    required this.isTestnet,
    required this.title,
    required this.networkLabel,
    required this.generatedLabel,
    required this.warning,
    required this.testnetLabel,
    this.tokenIconAsset,
    this.networkIconAsset,
  });

  /// The receiving address, and the payload encoded in the QR.
  final String address;

  /// Asset the address is for ("USDT · TRON").
  final String assetLabel;

  /// Bundled artwork names (see [TokenIcon.assetFor]) for the token and the
  /// chain. The card is the thing a recipient actually looks at before
  /// sending, so it should show what they are sending and where — a saved
  /// image that names "USDT · Ethereum" in text alone asks them to read
  /// carefully; the two marks let them recognise it at a glance. Null falls
  /// back to text only, which is what a custom token with no artwork gets.
  final String? tokenIconAsset;
  final String? networkIconAsset;

  /// Active network instance ("Ethereum", "Sepolia").
  final String networkName;

  final DateTime generatedAt;
  final bool isTestnet;

  // Localized chrome, resolved by the caller so this stays a pure function.
  final String title;
  final String networkLabel;
  final String generatedLabel;
  final String warning;
  final String testnetLabel;
}

/// Bundled artwork, decoded once each. Drawing the real marks matters: a
/// stand-in tile with "KT" in it is not the brand the recipient sees on the
/// App Store or their home screen, and a card that names its chain only in
/// words makes the reader parse rather than recognise.
final _icons = <String, ui.Image?>{};
Future<ui.Image?> _loadIcon(String path, {int targetWidth = 144}) async {
  if (_icons.containsKey(path)) return _icons[path];
  try {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: targetWidth,
    );
    return _icons[path] = (await codec.getNextFrame()).image;
  } on Object {
    // Missing or undecodable asset: fall back to text/tile rather than
    // failing the whole card. Cached as null so it is not retried per render.
    return _icons[path] = null;
  }
}

Future<ui.Image?> _loadBrandIcon() => _loadIcon('assets/brand/app_icon.png');

Future<ui.Image?> _loadTokenIcon(String? name) => name == null
    ? Future.value()
    : _loadIcon('assets/tokens/$name.png', targetWidth: 96);

/// Renders the shareable receive card as PNG bytes.
///
/// Drawn straight onto a canvas rather than captured from a widget: there is
/// no offscreen-render timing to get wrong, and the result is a pure function
/// of its inputs, so it can be tested without a widget tree.
Future<Uint8List> renderReceiveCardPng(
  ReceiveCardData data, {
  double scale = 3,
}) async {
  const width = 720.0;
  const margin = 56.0;
  const qrSize = 420.0;

  final icon = await _loadBrandIcon();
  final tokenIcon = await _loadTokenIcon(data.tokenIconAsset);
  final networkIcon = await _loadTokenIcon(data.networkIconAsset);

  // The token mark sits beside the asset line, the chain mark beside the
  // network line; each row grows to whichever is taller.
  const tokenMark = 44.0;
  const netMark = 26.0;
  final assetIndent = tokenIcon == null ? 0.0 : tokenMark + 14;
  final netIndent = networkIcon == null ? 0.0 : netMark + 10;

  // Lay the text out first: the card grows to fit a long address or a
  // translated warning instead of clipping them.
  final brand = _painter(
    'KT Wallet',
    size: 30,
    weight: FontWeight.w700,
    color: WalletColors.text,
  )..layout();
  final title = _painter(data.title, size: 17, color: WalletColors.text2)
    ..layout();
  final asset = _painter(
    data.assetLabel,
    size: 22,
    weight: FontWeight.w600,
    color: WalletColors.text,
  )..layout(maxWidth: width - margin * 2 - assetIndent);
  final address = _painter(
    data.address,
    size: 19,
    color: WalletColors.text,
    mono: true,
    align: TextAlign.center,
    // Keep the painter at the width of its longest rendered line, then place
    // that block from the card centre below. This makes both short EVM
    // addresses and wrapped, longer formats visibly centred.
    widthBasis: TextWidthBasis.longestLine,
  )..layout(maxWidth: width - margin * 2);
  final network = _painter(
    '${data.networkLabel}  ${data.networkName}'
    '${data.isTestnet ? '  ·  ${data.testnetLabel}' : ''}',
    size: 16,
    color: WalletColors.text2,
  )..layout(maxWidth: width - margin * 2 - netIndent);
  final generated = _painter(
    '${data.generatedLabel}  ${_stamp(data.generatedAt)}',
    size: 16,
    color: WalletColors.text2,
  )..layout(maxWidth: width - margin * 2);
  final warning = _painter(
    data.warning,
    size: 15,
    color: const Color(0xFF9A6503),
    align: TextAlign.left,
  )..layout(maxWidth: width - margin * 2 - 28);

  final warnBoxHeight = warning.height + 28;
  final height =
      margin +
      48 + // brand row
      28 +
      title.height +
      10 +
      math.max(asset.height, tokenIcon == null ? 0.0 : tokenMark) +
      28 +
      qrSize +
      26 +
      address.height +
      24 +
      math.max(network.height, networkIcon == null ? 0.0 : netMark) +
      8 +
      generated.height +
      24 +
      warnBoxHeight +
      margin;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.scale(scale);

  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, width, 4000),
    ui.Paint()..color = WalletColors.surface,
  );

  var y = margin;

  // Brand: the shipped app icon + wordmark.
  const markSize = 48.0;
  final markRect = ui.Rect.fromLTWH(margin, y, markSize, markSize);
  final markClip = ui.RRect.fromRectAndRadius(
    markRect,
    const ui.Radius.circular(13),
  );
  if (icon != null) {
    canvas.save();
    canvas.clipRRect(markClip);
    canvas.drawImageRect(
      icon,
      ui.Rect.fromLTWH(0, 0, icon.width.toDouble(), icon.height.toDouble()),
      markRect,
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    canvas.restore();
  } else {
    // Asset unavailable: an accent tile still reads as a mark.
    canvas.drawRRect(markClip, ui.Paint()..color = WalletColors.accent);
    final mark = _painter(
      'KT',
      size: 20,
      weight: FontWeight.w700,
      color: WalletColors.surface,
    )..layout();
    mark.paint(
      canvas,
      ui.Offset(
        margin + (markSize - mark.width) / 2,
        y + (markSize - mark.height) / 2,
      ),
    );
  }
  brand.paint(canvas, ui.Offset(margin + markSize + 14, y + 9));
  y += markSize + 28;

  title.paint(canvas, ui.Offset(margin, y));
  y += title.height + 10;
  final assetRowHeight = math.max(
    asset.height,
    tokenIcon == null ? 0.0 : tokenMark,
  );
  if (tokenIcon != null) {
    _drawCircularIcon(
      canvas,
      tokenIcon,
      ui.Rect.fromLTWH(
        margin,
        y + (assetRowHeight - tokenMark) / 2,
        tokenMark,
        tokenMark,
      ),
    );
  }
  asset.paint(
    canvas,
    ui.Offset(margin + assetIndent, y + (assetRowHeight - asset.height) / 2),
  );
  y += assetRowHeight + 28;

  _paintQr(canvas, data.address, ui.Offset((width - qrSize) / 2, y), qrSize);
  y += qrSize + 26;

  address.paint(canvas, ui.Offset((width - address.width) / 2, y));
  y += address.height + 24;

  final netRowHeight = math.max(
    network.height,
    networkIcon == null ? 0.0 : netMark,
  );
  if (networkIcon != null) {
    _drawCircularIcon(
      canvas,
      networkIcon,
      ui.Rect.fromLTWH(
        margin,
        y + (netRowHeight - netMark) / 2,
        netMark,
        netMark,
      ),
    );
  }
  network.paint(
    canvas,
    ui.Offset(margin + netIndent, y + (netRowHeight - network.height) / 2),
  );
  y += netRowHeight + 8;
  generated.paint(canvas, ui.Offset(margin, y));
  y += generated.height + 24;

  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(margin, y, width - margin * 2, warnBoxHeight),
      const ui.Radius.circular(14),
    ),
    ui.Paint()..color = const ui.Color(0x14E8930C),
  );
  warning.paint(canvas, ui.Offset(margin + 14, y + 14));

  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (width * scale).round(),
    (height * scale).round(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  return bytes!.buffer.asUint8List();
}

void _paintQr(ui.Canvas canvas, String payload, ui.Offset origin, double size) {
  final code = QrCode(
    payload: QrPayload.fromString(payload),
    errorCorrectLevel: QrErrorCorrectLevel.medium,
  );
  final image = QrImage(code);
  final modules = image.moduleCount;
  // One module of quiet zone per side, matching KtQrCode on screen.
  final cell = size / (modules + 2);
  canvas.drawRect(
    ui.Rect.fromLTWH(origin.dx, origin.dy, size, size),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  final ink = ui.Paint()..color = WalletColors.text;
  for (var row = 0; row < modules; row++) {
    for (var col = 0; col < modules; col++) {
      if (!image.isDark(row, col)) continue;
      canvas.drawRect(
        ui.Rect.fromLTWH(
          origin.dx + cell * (col + 1),
          origin.dy + cell * (row + 1),
          // A hair of overdraw keeps neighbouring modules from showing seams
          // once the whole card is scaled up.
          cell + 0.5,
          cell + 0.5,
        ),
        ink,
      );
    }
  }
}

TextPainter _painter(
  String text, {
  required double size,
  required Color color,
  FontWeight weight = FontWeight.w400,
  bool mono = false,
  TextAlign align = TextAlign.left,
  TextWidthBasis widthBasis = TextWidthBasis.parent,
}) => TextPainter(
  text: TextSpan(
    text: text,
    style: TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: 1.45,
      fontFamily: mono ? KtFonts.mono : null,
    ),
  ),
  textAlign: align,
  textDirection: TextDirection.ltr,
  textWidthBasis: widthBasis,
);

/// `YYYY-MM-DD HH:MM` in the device's own time zone — no seconds, no locale
/// formatting to go stale in a saved image.
String _stamp(DateTime at) {
  final t = at.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
}

/// Draws [image] clipped to a circle inside [rect], matching how TokenIcon
/// renders the same artwork on screen so the saved card and the live UI show
/// the identical mark.
void _drawCircularIcon(ui.Canvas canvas, ui.Image image, ui.Rect rect) {
  canvas.save();
  canvas.clipPath(ui.Path()..addOval(rect));
  canvas.drawImageRect(
    image,
    ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    rect,
    ui.Paint()..filterQuality = ui.FilterQuality.high,
  );
  canvas.restore();
}
