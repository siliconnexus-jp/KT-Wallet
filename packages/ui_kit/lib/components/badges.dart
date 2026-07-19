import 'package:flutter/material.dart';

import '../tokens/colors.dart';

/// Wallet kind used across list rows, switcher and confirm screens.
enum WalletKind { hot, watch }

/// Small capsule badge marking wallet type (普通 / 观察).
class WalletTypeBadge extends StatelessWidget {
  const WalletTypeBadge({super.key, required this.kind, this.dark = false});

  final WalletKind kind;

  /// Render on dark (Cold Signer / dark cards) background.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (kind) {
      WalletKind.hot => ('普通', dark ? SignerColors.ok : WalletColors.green),
      WalletKind.watch => ('观察', dark ? SignerColors.blue : WalletColors.accent),
    };
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
  const NetworkBadge({super.key, required this.label, required this.dotColor, this.dark = false});

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
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: dark ? SignerColors.text2 : WalletColors.text2,
            ),
          ),
        ],
      ),
    );
  }
}
