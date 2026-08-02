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
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final KtButtonStyle style;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final (background, foreground, radius) = switch (style) {
      KtButtonStyle.wallet => (WalletColors.accent, Colors.white, 14.0),
      KtButtonStyle.signer => (SignerColors.blue, SignerColors.bg, 12.0),
      KtButtonStyle.signerContrast => (
        SignerColors.text,
        SignerColors.bg,
        12.0,
      ),
    };
    return Semantics(
      button: true,
      enabled: onPressed != null && !loading,
      liveRegion: loading,
      label: label,
      child: SizedBox(
        height: KtDimens.buttonHeight,
        width: double.infinity,
        child: FilledButton(
          onPressed: loading ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: background,
            foregroundColor: foreground,
            disabledBackgroundColor: loading
                ? background.withValues(alpha: 0.72)
                : null,
            disabledForegroundColor: loading ? foreground : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontFamily: KtFonts.ui,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedOpacity(
                opacity: loading ? 0 : 1,
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    key: const ValueKey('kt-primary-button-content'),
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
              ),
              IgnorePointer(
                child: AnimatedOpacity(
                  key: const ValueKey('kt-primary-button-loading-layer'),
                  opacity: loading ? 1 : 0,
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 140),
                  curve: Curves.easeOutCubic,
                  child: AnimatedScale(
                    scale: loading ? 1 : 0.96,
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 140),
                    curve: Curves.easeOutCubic,
                    child: TickerMode(
                      enabled: loading,
                      child: SizedBox(
                        key: const ValueKey('kt-primary-button-loading'),
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: foreground,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
