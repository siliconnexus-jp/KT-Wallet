import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:qr/qr.dart';
import 'package:ui_kit/ui_kit.dart';

enum TransactionCardTone { success, pending, failed, neutral }

class TransactionCardField {
  const TransactionCardField({
    required this.label,
    required this.value,
    this.mono = false,
  });

  final String label;
  final String value;
  final bool mono;
}

/// Public, already-localized data printed onto a shareable transaction
/// receipt. The QR always carries [explorerUrl], never a payment request.
class TransactionCardData {
  const TransactionCardData({
    required this.title,
    required this.amount,
    required this.direction,
    required this.status,
    required this.transactionTimeLabel,
    required this.transactionTime,
    required this.networkName,
    required this.isTestnet,
    required this.testnetLabel,
    required this.explorerUrl,
    required this.scanLabel,
    required this.footer,
    required this.fields,
    required this.tone,
    this.tokenIconAsset,
    this.networkIconAsset,
  });

  final String title;
  final String amount;
  final String direction;
  final String status;
  final String transactionTimeLabel;
  final String transactionTime;
  final String networkName;
  final bool isTestnet;
  final String testnetLabel;
  final String explorerUrl;
  final String scanLabel;
  final String footer;
  final List<TransactionCardField> fields;
  final TransactionCardTone tone;
  final String? tokenIconAsset;
  final String? networkIconAsset;
}

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
    return _icons[path] = null;
  }
}

/// Renders a high-resolution KT Wallet transaction receipt. Canvas rendering
/// is deterministic and does not depend on a visible widget or screenshot.
Future<Uint8List> renderTransactionCardPng(
  TransactionCardData data, {
  double scale = 3,
}) async {
  if (scale <= 0) throw ArgumentError.value(scale, 'scale');
  if (data.explorerUrl.trim().isEmpty) {
    throw ArgumentError.value(data.explorerUrl, 'explorerUrl');
  }

  const width = 720.0;
  const margin = 48.0;
  const inner = width - margin * 2;
  const qrSize = 286.0;

  final brandIcon = await _loadIcon('assets/brand/app_icon.png');
  final tokenIcon = data.tokenIconAsset == null
      ? null
      : await _loadIcon(
          'assets/tokens/${data.tokenIconAsset}.png',
          targetWidth: 112,
        );
  final networkIcon = data.networkIconAsset == null
      ? null
      : await _loadIcon(
          'assets/tokens/${data.networkIconAsset}.png',
          targetWidth: 72,
        );

  final title = _text(data.title, 16, const ui.Color(0xFF64748B))
    ..layout(maxWidth: 320);
  final amount = _text(
    data.amount,
    42,
    const ui.Color(0xFF111827),
    weight: FontWeight.w700,
    align: TextAlign.center,
  )..layout(maxWidth: inner);
  final status = _text(
    '${data.direction}  ·  ${data.status}',
    16,
    _toneColor(data.tone),
    weight: FontWeight.w600,
  )..layout();
  final network = _text(
    '${data.networkName}'
    '${data.isTestnet ? '  ·  ${data.testnetLabel}' : ''}',
    15,
    const ui.Color(0xFF475569),
    weight: FontWeight.w600,
  )..layout(maxWidth: inner - 52);
  final transactionTime = _text(
    '${data.transactionTimeLabel}  ${data.transactionTime}',
    14,
    const ui.Color(0xFF64748B),
    weight: FontWeight.w500,
    align: TextAlign.center,
  )..layout(maxWidth: inner);
  final scan = _text(
    data.scanLabel,
    16,
    const ui.Color(0xFF334155),
    weight: FontWeight.w600,
    align: TextAlign.center,
  )..layout(maxWidth: inner);
  final footer = _text(
    data.footer,
    13,
    const ui.Color(0xFF94A3B8),
    align: TextAlign.center,
  )..layout(maxWidth: inner);

  final fieldLayouts = <({TransactionCardField field, TextPainter value})>[];
  var detailsHeight = 28.0;
  for (final field in data.fields) {
    final value = _text(
      field.value,
      field.mono ? 14 : 16,
      const ui.Color(0xFF111827),
      weight: field.mono ? FontWeight.w500 : FontWeight.w600,
      mono: field.mono,
    )..layout(maxWidth: inner - 40);
    fieldLayouts.add((field: field, value: value));
    detailsHeight += 18 + 7 + value.height + 22;
  }

  final height =
      48 +
      50 +
      46 +
      amount.height +
      18 +
      36 +
      14 +
      transactionTime.height +
      26 +
      36 +
      24 +
      detailsHeight +
      28 +
      qrSize +
      18 +
      scan.height +
      18 +
      footer.height +
      46;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..scale(scale);
  final background = ui.Rect.fromLTWH(0, 0, width, height);
  canvas.drawRect(background, ui.Paint()..color = const ui.Color(0xFFFFFFFF));

  var y = 48.0;
  _drawBrand(canvas, brandIcon, ui.Offset(margin, y));
  title.paint(canvas, ui.Offset(width - margin - title.width, y + 13));
  canvas.drawLine(
    ui.Offset(margin, y + 74),
    ui.Offset(width - margin, y + 74),
    ui.Paint()
      ..color = const ui.Color(0xFFE5E7EB)
      ..strokeWidth = 1,
  );
  y += 96;

  if (tokenIcon != null) {
    _drawCircularImage(
      canvas,
      tokenIcon,
      ui.Rect.fromLTWH((width - 54) / 2, y, 54, 54),
    );
    y += 68;
  }
  amount.paint(canvas, ui.Offset((width - amount.width) / 2, y));
  y += amount.height + 18;

  final statusPillWidth = status.width + 30;
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH((width - statusPillWidth) / 2, y, statusPillWidth, 36),
      const ui.Radius.circular(18),
    ),
    ui.Paint()..color = _toneColor(data.tone).withValues(alpha: 0.12),
  );
  status.paint(
    canvas,
    ui.Offset((width - status.width) / 2, y + (36 - status.height) / 2),
  );
  y += 50;
  transactionTime.paint(
    canvas,
    ui.Offset((width - transactionTime.width) / 2, y),
  );
  y += transactionTime.height + 26;

  if (networkIcon != null) {
    _drawCircularImage(
      canvas,
      networkIcon,
      ui.Rect.fromLTWH(margin, y, 30, 30),
    );
  } else {
    canvas.drawCircle(
      ui.Offset(margin + 15, y + 15),
      5,
      ui.Paint()..color = const ui.Color(0xFF4F6EF7),
    );
  }
  network.paint(canvas, ui.Offset(margin + 42, y + (30 - network.height) / 2));
  y += 54;

  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(margin, y, inner, detailsHeight),
      const ui.Radius.circular(20),
    ),
    ui.Paint()..color = const ui.Color(0xFFF8FAFC),
  );
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(margin, y, inner, detailsHeight),
      const ui.Radius.circular(20),
    ),
    ui.Paint()
      ..color = const ui.Color(0xFFE5E7EB)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1,
  );
  var detailY = y + 22;
  for (var index = 0; index < fieldLayouts.length; index++) {
    final layout = fieldLayouts[index];
    final label = _text(
      layout.field.label.toUpperCase(),
      12,
      const ui.Color(0xFF94A3B8),
      weight: FontWeight.w600,
      letterSpacing: 1.1,
    )..layout(maxWidth: inner - 40);
    label.paint(canvas, ui.Offset(margin + 20, detailY));
    detailY += label.height + 7;
    layout.value.paint(canvas, ui.Offset(margin + 20, detailY));
    detailY += layout.value.height + 22;
    if (index != fieldLayouts.length - 1) {
      canvas.drawLine(
        ui.Offset(margin + 20, detailY - 1),
        ui.Offset(width - margin - 20, detailY - 1),
        ui.Paint()
          ..color = const ui.Color(0xFFE5E7EB)
          ..strokeWidth = 1,
      );
    }
  }
  y += detailsHeight + 28;

  _paintQr(
    canvas,
    data.explorerUrl,
    ui.Offset((width - qrSize) / 2, y),
    qrSize,
  );
  y += qrSize + 18;
  scan.paint(canvas, ui.Offset((width - scan.width) / 2, y));
  y += scan.height + 18;
  footer.paint(canvas, ui.Offset((width - footer.width) / 2, y));

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

void _drawBrand(ui.Canvas canvas, ui.Image? icon, ui.Offset origin) {
  const size = 50.0;
  final rect = ui.Rect.fromLTWH(origin.dx, origin.dy, size, size);
  final clip = ui.RRect.fromRectAndRadius(rect, const ui.Radius.circular(14));
  if (icon != null) {
    canvas.save();
    canvas.clipRRect(clip);
    canvas.drawImageRect(
      icon,
      ui.Rect.fromLTWH(0, 0, icon.width.toDouble(), icon.height.toDouble()),
      rect,
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    canvas.restore();
  } else {
    canvas.drawRRect(clip, ui.Paint()..color = const ui.Color(0xFF4F6EF7));
  }
  final brand = _text(
    'KT Wallet',
    25,
    const ui.Color(0xFF111827),
    weight: FontWeight.w700,
  )..layout();
  brand.paint(canvas, ui.Offset(origin.dx + size + 14, origin.dy + 8));
}

void _paintQr(ui.Canvas canvas, String payload, ui.Offset origin, double size) {
  final code = QrCode(
    payload: QrPayload.fromString(payload),
    errorCorrectLevel: QrErrorCorrectLevel.medium,
  );
  final image = QrImage(code);
  final modules = image.moduleCount;
  final cell = size / (modules + 6);
  final rect = ui.Rect.fromLTWH(origin.dx, origin.dy, size, size);
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(rect, const ui.Radius.circular(22)),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(rect, const ui.Radius.circular(22)),
    ui.Paint()
      ..color = const ui.Color(0xFFE5E7EB)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1,
  );
  final ink = ui.Paint()..color = const ui.Color(0xFF111827);
  for (var row = 0; row < modules; row++) {
    for (var col = 0; col < modules; col++) {
      if (!image.isDark(row, col)) continue;
      canvas.drawRect(
        ui.Rect.fromLTWH(
          origin.dx + cell * (col + 3),
          origin.dy + cell * (row + 3),
          cell + 0.4,
          cell + 0.4,
        ),
        ink,
      );
    }
  }
}

void _drawCircularImage(ui.Canvas canvas, ui.Image image, ui.Rect rect) {
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

ui.Color _toneColor(TransactionCardTone tone) => switch (tone) {
  TransactionCardTone.success => const ui.Color(0xFF138A63),
  TransactionCardTone.pending => const ui.Color(0xFF3155DD),
  TransactionCardTone.failed => const ui.Color(0xFFD63B4B),
  TransactionCardTone.neutral => const ui.Color(0xFF64748B),
};

TextPainter _text(
  String value,
  double size,
  ui.Color color, {
  FontWeight weight = FontWeight.w400,
  TextAlign align = TextAlign.left,
  bool mono = false,
  double? letterSpacing,
}) => TextPainter(
  text: TextSpan(
    text: value,
    style: TextStyle(
      color: color,
      fontSize: size,
      fontWeight: weight,
      height: 1.42,
      fontFamily: mono ? KtFonts.mono : KtFonts.ui,
      letterSpacing: letterSpacing,
    ),
  ),
  textAlign: align,
  textDirection: TextDirection.ltr,
);
