import 'dart:ui' as ui;
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:qr/qr.dart';
import '../tokens/colors.dart';
import '../tokens/dimens.dart';

/// Draws only the encrypted transport and public branding. Passwords, wallet
/// metadata and plaintext key material are deliberately not accepted here.
Future<Uint8List> renderBrandedQrPng({
  required String payload,
  required String title,
  required String instruction,
  String brandName = 'KT Wallet',
  Color accent = WalletColors.accent,
}) async {
  const width = 960.0;
  const margin = 64.0;
  TextPainter text(String value, double size, Color color) => TextPainter(
    text: TextSpan(
      text: value,
      style: TextStyle(
        fontFamily: KtFonts.ui,
        fontSize: size,
        height: 1.45,
        color: color,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: width - margin * 2);
  final brand = text(brandName, 38, WalletColors.text);
  final heading = text(title, 28, WalletColors.text);
  final footer = text(instruction, 24, WalletColors.text2);
  final version = text('ENCRYPTED BACKUP · v2', 18, WalletColors.text2);
  final qr = QrImage(
    QrCode(
      payload: QrPayload.fromString(payload),
      errorCorrectLevel: QrErrorCorrectLevel.high,
    ),
  );
  // Integer pixels, four-module quiet zone, no logo over the QR modules.
  final cell = ((width - margin * 2) / (qr.moduleCount + 8)).floor();
  final qrExtent = (qr.moduleCount + 8) * cell.toDouble();
  final qrTop = 180 + heading.height;
  final footerTop = qrTop + qrExtent + 24;
  final height = (footerTop + footer.height + 84 + version.height).ceil();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xFFFFFFFF), BlendMode.src);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, width, 12),
    Paint()..color = accent,
  );
  final bytes = await rootBundle.load('assets/brand/app_icon.png');
  final codec = await ui.instantiateImageCodec(
    bytes.buffer.asUint8List(),
    targetWidth: 80,
  );
  final icon = (await codec.getNextFrame()).image;
  canvas.drawImageRect(
    icon,
    Rect.fromLTWH(0, 0, icon.width.toDouble(), icon.height.toDouble()),
    const Rect.fromLTWH(margin, 48, 72, 72),
    Paint(),
  );
  icon.dispose();
  codec.dispose();
  brand.paint(canvas, const Offset(margin + 92, 54));
  heading.paint(canvas, const Offset(margin, 144));
  final left = ((width - qrExtent) / 2).floorToDouble() + cell * 4;
  final top = qrTop.ceilToDouble() + cell * 4;
  final ink = Paint()
    ..color = const Color(0xFF0C1220)
    ..isAntiAlias = false;
  for (var row = 0; row < qr.moduleCount; row++) {
    for (var col = 0; col < qr.moduleCount; col++) {
      if (qr.isDark(row, col)) {
        canvas.drawRect(
          Rect.fromLTWH(
            left + col * cell,
            top + row * cell,
            cell.toDouble(),
            cell.toDouble(),
          ),
          ink,
        );
      }
    }
  }
  footer.paint(canvas, Offset(margin, footerTop));
  version.paint(canvas, Offset(margin, height - margin - version.height));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width.toInt(), height);
  try {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) throw StateError('backup image unavailable');
    return png.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
    brand.dispose();
    heading.dispose();
    footer.dispose();
    version.dispose();
  }
}
