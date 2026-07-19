import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/dimens.dart';

enum KtButtonStyle {
  /// KT Wallet light-theme primary (blue, white label).
  wallet,

  /// Cold Signer dark-theme primary (blue, near-black label).
  signer,

  /// Cold Signer high-emphasis (white surface, dark label) — welcome screen.
  signerContrast,
}

/// Full-width primary button matching the Pencil `W Button` / `C Button`
/// components.
class KtPrimaryButton extends StatelessWidget {
  const KtPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.style = KtButtonStyle.wallet,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final KtButtonStyle style;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, radius) = switch (style) {
      KtButtonStyle.wallet => (WalletColors.accent, Colors.white, 14.0),
      KtButtonStyle.signer => (SignerColors.blue, SignerColors.bg, 12.0),
      KtButtonStyle.signerContrast => (SignerColors.text, SignerColors.bg, 12.0),
    };
    return SizedBox(
      height: KtDimens.buttonHeight,
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: KtFonts.ui,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18),
              const SizedBox(width: 8),
            ],
            Text(label),
          ],
        ),
      ),
    );
  }
}
