import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/dimens.dart';

/// Horizontal label/value row used on confirm & info cards
/// (Pencil `W Detail Row`).
class KtDetailRow extends StatelessWidget {
  const KtDetailRow({
    super.key,
    required this.label,
    required this.value,
    this.mono = false,
    this.dark = false,
    this.valueColor,
  });

  final String label;
  final String value;

  /// Render value in monospace (addresses, hashes, request IDs).
  final bool mono;
  final bool dark;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontFamily: KtFonts.ui,
            color: dark ? SignerColors.text2 : WalletColors.text2,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: mono ? 13 : 14,
              fontWeight: FontWeight.w500,
              fontFamily: mono ? KtFonts.mono : KtFonts.ui,
              color:
                  valueColor ?? (dark ? SignerColors.text : WalletColors.text),
            ),
          ),
        ),
      ],
    );
  }
}

/// Stacked label-above-value row for full-width mono values
/// (Pencil `C Detail Row`, used on Cold Signer confirm screens).
class SignerDetailRow extends StatelessWidget {
  const SignerDetailRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.6,
            color: SignerColors.text2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontFamily: KtFonts.mono,
            color: SignerColors.text,
          ),
        ),
      ],
    );
  }
}
