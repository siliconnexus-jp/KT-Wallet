import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:ui_kit/ui_kit.dart';

import 'wallet_backup.dart';
import 'wallet_backup_qr.dart';

/// The shared renderer only receives encrypted transport and public branding.
Future<Uint8List> renderBackupQrPng({
  required String payload,
  required String title,
  required String instruction,
}) {
  WalletBackupQr.decode(payload);
  return renderBrandedQrPng(
    payload: payload,
    title: title,
    instruction: instruction,
  );
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
