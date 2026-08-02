import 'package:flutter/material.dart';

import '../tokens/colors.dart';

/// Wallet kind used across list rows, switcher and confirm screens.
enum WalletKind { hot, watch }

/// Small capsule badge marking wallet type. The label is supplied by the app
/// (localized); when omitted it falls back to the design's Chinese labels so the
/// component stays self-contained for ui_kit's own gallery/goldens.
class WalletTypeBadge extends StatelessWidget {
  const WalletTypeBadge({
    super.key,
    required this.kind,
    this.label,
    this.dark = false,
  });

  final WalletKind kind;

  /// Localized label; defaults to the design's 普通 / 观察 when null.
  final String? label;

  /// Render on dark (Cold Signer / dark cards) background.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final (fallbackLabel, color) = switch (kind) {
      WalletKind.hot => ('普通', dark ? SignerColors.ok : WalletColors.green),
      WalletKind.watch => (
        '观察',
        dark ? SignerColors.blue : WalletColors.accent,
      ),
    };
    final label = this.label ?? fallbackLabel;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// Network chip with brand dot + name (Pencil `Network Chip` component).
class NetworkBadge extends StatelessWidget {
  const NetworkBadge({
    super.key,
    required this.label,
    required this.dotColor,
    this.dark = false,
  });

  final String label;
  final Color dotColor;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: dark ? SignerColors.surface : const Color(0xFFEEF1F6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: dark ? SignerColors.text2 : WalletColors.text2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
