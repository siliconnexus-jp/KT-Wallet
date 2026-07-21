import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

/// A real, scannable QR code rendered in the design system's flat module
/// style (same ink/background treatment as [KtQrPlaceholder], which remains
/// for design-gallery fidelity). Pure Dart encoding via package:qr — works
/// fully offline, which the air-gap flows require.
class KtQrCode extends StatelessWidget {
  const KtQrCode({
    super.key,
    required this.data,
    this.size = 220,
    this.dark = false,
  });

  /// Payload to encode (e.g. an airgap_protocol fragment or an address URI).
  final String data;
  final double size;

  /// Dark style: white modules on the signer's near-black surface.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final ink = dark ? Colors.white : const Color(0xFF0C1220);
    final bg = dark ? const Color(0xFF0A0C0F) : Colors.white;
    return Container(
      width: size,
      height: size,
      color: bg,
      child: CustomPaint(painter: _KtQrCodePainter(data, ink)),
    );
  }
}

class _KtQrCodePainter extends CustomPainter {
  _KtQrCodePainter(this.data, this.ink) : _image = _encode(data);

  final String data;
  final Color ink;
  final QrImage _image;

  // Encoding is deterministic and cheap relative to frame budget, but avoid
  // redoing it for repaints of the same payload.
  static final _cache = <String, QrImage>{};
  static QrImage _encode(String data) => _cache.putIfAbsent(data, () {
        final code = QrCode(
          payload: QrPayload.fromString(data),
          errorCorrectLevel: QrErrorCorrectLevel.medium,
        );
        return QrImage(code);
      });

  @override
  void paint(Canvas canvas, Size size) {
    final modules = _image.moduleCount;
    // One-module quiet zone on each side keeps the code scannable against
    // surrounding UI.
    final cell = size.width / (modules + 2);
    final origin = cell;
    final p = Paint()..color = ink;
    for (var y = 0; y < modules; y++) {
      for (var x = 0; x < modules; x++) {
        if (_image.isDark(y, x)) {
          canvas.drawRect(
            Rect.fromLTWH(origin + x * cell, origin + y * cell, cell + 0.5, cell + 0.5),
            p,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _KtQrCodePainter old) =>
      old.data != data || old.ink != ink;
}
