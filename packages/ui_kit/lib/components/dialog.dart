import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/dimens.dart';
import 'screen_kit.dart';

enum KtDialogActionStyle { secondary, primary, destructive }

/// Branded modal surface shared by KT Wallet and KT Wallet Cold Signer.
///
/// The modal intentionally stays centered: unlike a popover, it is not
/// spatially anchored to a trigger. Its restrained shape, spacing and action
/// hierarchy match the rest of the KT design system.
class KtDialog extends StatelessWidget {
  const KtDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
    this.theme = AppTheme.wallet,
    this.icon,
    this.iconColor,
  });

  final String title;
  final Widget content;
  final List<Widget> actions;
  final AppTheme theme;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final effectiveIconColor = iconColor ?? theme.accent;
    return Dialog(
      key: const ValueKey('kt-dialog'),
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Material(
          color: theme.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KtDimens.radiusXl),
            side: BorderSide(color: theme.border),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (icon != null) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: effectiveIconColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(icon, size: 22, color: effectiveIconColor),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: KtFonts.ui,
                    fontSize: 20,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: theme.text,
                  ),
                ),
                const SizedBox(height: 10),
                DefaultTextStyle(
                  style: TextStyle(
                    fontFamily: KtFonts.ui,
                    fontSize: 14,
                    height: 1.55,
                    color: theme.text2,
                  ),
                  child: content,
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    for (var index = 0; index < actions.length; index++) ...[
                      if (index > 0) const SizedBox(width: 10),
                      Expanded(child: actions[index]),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class KtConfirmDialog extends StatelessWidget {
  const KtConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    required this.cancelLabel,
    required this.confirmLabel,
    this.theme = AppTheme.wallet,
    this.icon,
    this.iconColor,
    this.destructive = false,
    this.details,
  });

  final String title;
  final String message;
  final String cancelLabel;
  final String confirmLabel;
  final AppTheme theme;
  final IconData? icon;
  final Color? iconColor;
  final bool destructive;
  final Widget? details;

  @override
  Widget build(BuildContext context) => KtDialog(
    title: title,
    theme: theme,
    icon: icon,
    iconColor: iconColor,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(message),
        if (details != null) ...[const SizedBox(height: 14), details!],
      ],
    ),
    actions: [
      KtDialogAction(
        key: const ValueKey('kt-dialog-cancel'),
        label: cancelLabel,
        theme: theme,
        onPressed: () => Navigator.of(context).pop(false),
      ),
      KtDialogAction(
        key: const ValueKey('kt-dialog-confirm'),
        label: confirmLabel,
        theme: theme,
        style: destructive
            ? KtDialogActionStyle.destructive
            : KtDialogActionStyle.primary,
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ],
  );
}

/// Compact action with interruptible press feedback.
///
/// Emil Kowalski's interaction guideline recommends a subtle 0.97 press scale.
/// The 120 ms ease-out is quick enough to acknowledge touch without delaying
/// a security-sensitive confirmation, and is disabled with reduced motion.
class KtDialogAction extends StatefulWidget {
  const KtDialogAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.theme = AppTheme.wallet,
    this.style = KtDialogActionStyle.secondary,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppTheme theme;
  final KtDialogActionStyle style;

  @override
  State<KtDialogAction> createState() => _KtDialogActionState();
}

class _KtDialogActionState extends State<KtDialogAction> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value || widget.onPressed == null) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    final (background, foreground, border) = switch (widget.style) {
      KtDialogActionStyle.secondary => (
        Colors.transparent,
        widget.theme.text2,
        widget.theme.border,
      ),
      KtDialogActionStyle.primary => (
        widget.theme.accent,
        widget.theme == AppTheme.wallet ? Colors.white : SignerColors.bg,
        widget.theme.accent,
      ),
      KtDialogActionStyle.destructive => (
        widget.theme == AppTheme.wallet
            ? WalletColors.red
            : SignerColors.danger,
        Colors.white,
        widget.theme == AppTheme.wallet
            ? WalletColors.red
            : SignerColors.danger,
      ),
    };

    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 120),
        curve: const Cubic(0.23, 1, 0.32, 1),
        child: SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: widget.onPressed,
            style: FilledButton.styleFrom(
              elevation: 0,
              backgroundColor: background,
              foregroundColor: foreground,
              disabledBackgroundColor: background.withValues(alpha: 0.45),
              disabledForegroundColor: foreground.withValues(alpha: 0.55),
              side: BorderSide(color: border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              textStyle: const TextStyle(
                fontFamily: KtFonts.ui,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}
