import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr/qr.dart';
import 'package:ui_kit/ui_kit.dart';

import 'wallet_backup.dart';
import 'wallet_backup_qr.dart';

/// Draws only the encrypted transport and public branding. Passwords, wallet
/// metadata and plaintext key material are deliberately not accepted here.
Future<Uint8List> renderBackupQrPng({
  required String payload,
  required String title,
  required String instruction,
}) async {
  WalletBackupQr.decode(payload);
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
  final brand = text('KT Wallet', 38, WalletColors.text);
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
    Paint()..color = WalletColors.accent,
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

class BackupQrImageReader {
  const BackupQrImageReader();
  static const maxFileBytes = 8 * 1024 * 1024;
  static const maxPixels = 16 * 1024 * 1024;

  /// Local-only image decoding. Bounds compressed bytes AND decoded pixels;
  /// normalizes to PNG and deletes the private temporary copy in all cases.
  Future<String> read(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > maxFileBytes) {
      throw const BackupFormatException('backup image is too large');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    Directory? directory;
    MobileScannerController? scanner;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width * descriptor.height > maxPixels ||
          descriptor.width > 8192 ||
          descriptor.height > 8192) {
        throw const BackupFormatException(
          'backup image dimensions are too large',
        );
      }
      final longest = descriptor.width > descriptor.height
          ? descriptor.width
          : descriptor.height;
      final scale = longest > 2048 ? 2048 / longest : 1.0;
      codec = await descriptor.instantiateCodec(
        targetWidth: (descriptor.width * scale).round(),
        targetHeight: (descriptor.height * scale).round(),
      );
      image = (await codec.getNextFrame()).image;
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) {
        throw const BackupFormatException('invalid backup image');
      }
      directory = await Directory.systemTemp.createTemp('kt-backup-qr-');
      final file = File('${directory.path}/scan.png');
      await file.writeAsBytes(png.buffer.asUint8List(), flush: true);
      scanner = MobileScannerController(autoStart: false);
      final result = await scanner.analyzeImage(
        file.path,
        formats: [BarcodeFormat.qrCode],
      );
      final values =
          result?.barcodes
              .map((b) => b.rawValue)
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .toSet() ??
          <String>{};
      if (values.length != 1) {
        throw const BackupFormatException('ambiguous or missing backup QR');
      }
      final value = values.single;
      WalletBackupQr.decode(value);
      return value;
    } finally {
      try {
        await scanner?.dispose();
      } finally {
        image?.dispose();
        codec?.dispose();
        descriptor?.dispose();
        buffer.dispose();
        if (directory != null && await directory.exists()) {
          await directory.delete(recursive: true);
        }
      }
    }
  }
}
