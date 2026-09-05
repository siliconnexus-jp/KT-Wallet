import 'dart:ui';

import 'package:flutter/material.dart';

import '../tokens/colors.dart';

ThemeData ktWalletTheme() => ThemeData(
  fontFamily: 'Inter',
  colorScheme: ColorScheme.fromSeed(seedColor: WalletColors.accent),
  scaffoldBackgroundColor: WalletColors.bg,
  splashFactory: InkSparkle.splashFactory,
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xF5FFFFFF),
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: WalletColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: WalletColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: WalletColors.accent, width: 1.5),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      minimumSize: const Size(48, 48),
      foregroundColor: WalletColors.accent,
    ),
  ),
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: Colors.transparent,
    modalBackgroundColor: Colors.transparent,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
    ),
  ),
);

/// Static, low-contrast light behind the wallet. No full-screen blur or motion.
class KtWalletBackdrop extends StatelessWidget {
  const KtWalletBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: WalletColors.bg,
      gradient: MediaQuery.highContrastOf(context)
          ? null
          : const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFEDF3FC), Color(0xFFF5F6F9), Color(0xFFEEF0F7)],
              stops: [0, .5, 1],
            ),
    ),
    child: child,
  );
}

/// One material language: opaque-readable content cards and bounded frosted
/// chrome. Never blur every row of a scrolling list. Accessibility preferences
/// switch to solid material; content, semantics and hit targets stay unchanged.
class KtGlassSurface extends StatelessWidget {
  const KtGlassSurface({
    super.key,
    required this.child,
    this.radius = 24,
    this.blur = false,
    this.padding = EdgeInsets.zero,
    this.borderRadius,
  });

  final Widget child;
  final double radius;
  final bool blur;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final solid =
        MediaQuery.highContrastOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    final corners = borderRadius ?? BorderRadius.circular(radius);
    final material = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: corners,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: solid
              ? const [Colors.white, Colors.white]
              : blur
              ? const [Color(0xF7FFFFFF), Color(0xF2F1F4FB)]
              : const [Color(0xFCFFFFFF), Color(0xF2F9FAFD)],
        ),
        border: Border.all(
          color: solid ? WalletColors.text2 : const Color(0xEFFFFFFF),
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Padding(padding: padding, child: child),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: corners,
        boxShadow: solid
            ? const []
            : [
                BoxShadow(
                  color: const Color(
                    0xFF22365B,
                  ).withValues(alpha: blur ? .09 : .035),
                  blurRadius: blur ? 24 : 16,
                  offset: Offset(0, blur ? 8 : 4),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: corners,
        child: blur && !solid
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: material,
              )
            : material,
      ),
    );
  }
}

/// Touch-down feedback only; activation remains with the native button/InkWell.
class KtPressFeedback extends StatefulWidget {
  const KtPressFeedback({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;
  @override
  State<KtPressFeedback> createState() => _KtPressFeedbackState();
}

class _KtPressFeedbackState extends State<KtPressFeedback> {
  bool _pressed = false;
  void _press(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduced =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    return Listener(
      onPointerDown: widget.enabled ? (_) => _press(true) : null,
      onPointerUp: (_) => _press(false),
      onPointerCancel: (_) => _press(false),
      child: AnimatedScale(
        scale: _pressed && widget.enabled && !reduced ? .98 : 1,
        duration: reduced ? Duration.zero : const Duration(milliseconds: 120),
        curve: const Cubic(.23, 1, .32, 1),
        child: widget.child,
      ),
    );
  }
}

/// Native modal drag/dismiss behavior with the wallet's shared glass material.
class KtGlassSheet extends StatelessWidget {
  const KtGlassSheet({
    super.key,
    required this.child,
    this.scrollable = false,
    this.padding = EdgeInsets.zero,
  });
  final Widget child;
  final bool scrollable;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => KtGlassSurface(
    blur: true,
    borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .92,
      ),
      child: SizedBox(
        width: double.infinity,
        child: scrollable
            ? SingleChildScrollView(padding: padding, child: child)
            : Padding(padding: padding, child: child),
      ),
    ),
  );
}

/// Native modal drag/dismiss behavior with the wallet's shared glass material.
/// Accept legacy surface arguments so callers can migrate without changing
/// their result, authentication, keyboard or dismissal behavior.
Future<T?> showKtModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useRootNavigator = false,
  bool? showDragHandle,
  Color? backgroundColor,
  Color? barrierColor,
  ShapeBorder? shape,
  BoxConstraints? constraints,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: isScrollControlled,
  useSafeArea: useSafeArea,
  isDismissible: isDismissible,
  enableDrag: enableDrag,
  useRootNavigator: useRootNavigator,
  showDragHandle: showDragHandle,
  backgroundColor: Colors.transparent,
  barrierColor: barrierColor ?? const Color(0x59212B40),
  elevation: 0,
  constraints: constraints,
  builder: (context) => KtGlassSurface(
    blur: true,
    borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
    child: builder(context),
  ),
);
