import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/dimens.dart';

/// Which app palette a shared screen widget renders for.
enum AppTheme { wallet, signer }

extension AppThemeColors on AppTheme {
  Color get bg => this == AppTheme.wallet ? WalletColors.bg : SignerColors.bg;
  Color get surface =>
      this == AppTheme.wallet ? WalletColors.surface : SignerColors.surface;
  Color get text =>
      this == AppTheme.wallet ? WalletColors.text : SignerColors.text;
  Color get text2 =>
      this == AppTheme.wallet ? WalletColors.text2 : SignerColors.text2;
  Color get border =>
      this == AppTheme.wallet ? WalletColors.border : SignerColors.border;
  Color get accent =>
      this == AppTheme.wallet ? WalletColors.accent : SignerColors.blue;
}

/// Controls whether shared screens render the design-mock device chrome
/// (the iOS-style "9:41" status bar baked into the Pencil design). Absent
/// (design galleries, golden tests) it defaults to true so screens match the
/// mock 1:1; real app entrypoints set [mockStatusBar] to false so the OS
/// status bar isn't duplicated on device.
class KtDeviceChrome extends InheritedWidget {
  const KtDeviceChrome({
    super.key,
    required this.mockStatusBar,
    required super.child,
  });
  final bool mockStatusBar;

  static bool mockStatusBarOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<KtDeviceChrome>()
          ?.mockStatusBar ??
      true;

  @override
  bool updateShouldNotify(KtDeviceChrome oldWidget) =>
      oldWidget.mockStatusBar != mockStatusBar;
}

/// iOS-style status bar (time + indicators). Signer variant swaps Wi-Fi for a
/// green airplane icon (offline emphasis). Collapses to nothing when
/// [KtDeviceChrome] disables mock chrome (i.e. on a real device).
class KtStatusBar extends StatelessWidget {
  const KtStatusBar({super.key, this.theme = AppTheme.wallet});
  final AppTheme theme;
  @override
  Widget build(BuildContext context) {
    if (!KtDeviceChrome.mockStatusBarOf(context)) {
      return const SizedBox.shrink();
    }
    final fg = theme.text;
    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '9:41',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
            Row(
              children: [
                Icon(Icons.signal_cellular_alt, size: 16, color: fg),
                const SizedBox(width: 6),
                Icon(
                  theme == AppTheme.signer
                      ? Icons.airplanemode_active
                      : Icons.wifi,
                  size: 16,
                  color: theme == AppTheme.signer ? SignerColors.ok : fg,
                ),
                const SizedBox(width: 6),
                Icon(Icons.battery_full, size: 20, color: fg),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Top nav row: back/close on the left, centered title, optional right action.
class KtNavBar extends StatelessWidget {
  const KtNavBar({
    super.key,
    required this.title,
    this.theme = AppTheme.wallet,
    this.onBack,
    this.leading = Icons.arrow_back,
    this.trailing,
    this.onTrailing,
    this.trailingText,
    this.trailingTooltip,
  });
  final String title;
  final AppTheme theme;
  final VoidCallback? onBack;
  final IconData leading;
  final IconData? trailing;
  final VoidCallback? onTrailing;
  final String? trailingText;
  final String? trailingTooltip;

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    final leadingLabel = leading == Icons.close
        ? material.closeButtonTooltip
        : material.backButtonTooltip;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        SizedBox(
          width: 48,
          child: onBack == null
              ? const SizedBox()
              : IconButton(
                  onPressed: onBack,
                  tooltip: leadingLabel,
                  icon: Icon(leading, size: 22, color: theme.text),
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerLeft,
                ),
        ),
        Flexible(
          child: Semantics(
            header: true,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: theme.text,
              ),
            ),
          ),
        ),
        // Min 48 wide (mirrors the leading slot and Android accessibility
        // guidance) but grows for longer action
        // labels ("Reorder", "並べ替え") instead of wrapping them.
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48),
          child: trailingText != null
              ? Semantics(
                  button: true,
                  enabled: onTrailing != null,
                  label: trailingText,
                  child: InkWell(
                    onTap: onTrailing,
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: 48,
                        minWidth: 48,
                      ),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          trailingText!,
                          maxLines: 1,
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: theme.text2,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              : SizedBox(
                  width: 48,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: trailing != null
                        ? IconButton(
                            onPressed: onTrailing,
                            tooltip:
                                trailingTooltip ?? material.moreButtonTooltip,
                            icon: Icon(trailing, size: 22, color: theme.text2),
                            padding: EdgeInsets.zero,
                          )
                        : const SizedBox(),
                  ),
                ),
        ),
      ],
    );
  }
}

/// Standard screen scaffold: status bar + optional nav bar + scrollable body +
/// optional pinned bottom.
class KtScreen extends StatelessWidget {
  const KtScreen({
    super.key,
    required this.children,
    this.theme = AppTheme.wallet,
    this.navBar,
    this.bottom,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 24),
    this.gap = 20,
    this.scrollable = true,
    this.backgroundColor,
  });
  final List<Widget> children;
  final AppTheme theme;
  final Widget? navBar;
  final Widget? bottom;
  final EdgeInsets padding;
  final double gap;
  final bool scrollable;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            children[i],
          ],
        ],
      ),
    );
    return Scaffold(
      backgroundColor: backgroundColor ?? theme.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            KtStatusBar(theme: theme),
            if (navBar != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: navBar!,
              ),
            Expanded(
              child: scrollable
                  ? SingleChildScrollView(child: content)
                  : content,
            ),
            if (bottom != null)
              SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: bottom!,
              ),
          ],
        ),
      ),
    );
  }
}

/// Rounded surface card with padding.
class KtCard extends StatelessWidget {
  const KtCard({
    super.key,
    required this.child,
    this.theme = AppTheme.wallet,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final AppTheme theme;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: theme.surface,
      borderRadius: BorderRadius.circular(KtDimens.radiusLg),
    ),
    child: child,
  );
}

/// Circular avatar with an initial (wallet / token / contact).
class KtAvatar extends StatelessWidget {
  const KtAvatar({
    super.key,
    required this.color,
    required this.initial,
    this.size = 40,
  });
  final Color color;
  final String initial;
  final double size;
  @override
  Widget build(BuildContext context) {
    // White only reaches 3:1 against backgrounds at or below ~0.30 relative
    // luminance. Above that, use the dark brand text so initials remain
    // readable on amber, yellow, mint, and other user-selectable colors.
    final foreground = color.computeLuminance() > 0.30
        ? WalletColors.text
        : Colors.white;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size * 0.45,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}

/// Segmented pill selector (fee tiers, filters, mnemonic length).
class KtSegmented extends StatelessWidget {
  const KtSegmented({
    super.key,
    required this.options,
    required this.selected,
    this.theme = AppTheme.wallet,
    this.onChanged,
    this.scrollable = false,
  });
  final List<String> options;
  final int selected;
  final AppTheme theme;
  final ValueChanged<int>? onChanged;

  /// Lay the segments out at their natural width inside a horizontal scroll
  /// view instead of splitting the row evenly.
  ///
  /// The even split is right for the two or three short options this control
  /// was built for. With seven chain names it gave each one a seventh of the
  /// width and the labels wrapped mid-word — "Ethere/um", "Avalan/che".
  final bool scrollable;

  Widget _segment(int i) => Semantics(
    button: true,
    selected: i == selected,
    inMutuallyExclusiveGroup: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onChanged == null ? null : () => onChanged!(i),
      child: Container(
        height: 48,
        alignment: Alignment.center,
        padding: scrollable ? const EdgeInsets.symmetric(horizontal: 14) : null,
        decoration: BoxDecoration(
          color: i == selected ? theme.text : theme.surface,
          borderRadius: BorderRadius.circular(KtDimens.radiusSm),
        ),
        // Only the scrollable variant pins the label to one line — it has the
        // room to honour it. Forcing it on the even split would trade a wrap
        // for a fade-out, which is not an improvement.
        child: Text(
          options[i],
          maxLines: scrollable ? 1 : null,
          softWrap: !scrollable,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: i == selected ? theme.bg : theme.text2,
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          if (scrollable) _segment(i) else Expanded(child: _segment(i)),
        ],
      ],
    );
    if (!scrollable) return row;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: row,
    );
  }
}

/// Placeholder QR block (a checker pattern) for design parity — the real app
/// renders an animated QR.
class KtQrPlaceholder extends StatelessWidget {
  const KtQrPlaceholder({super.key, this.size = 220, this.dark = false});
  final double size;
  final bool dark;
  @override
  Widget build(BuildContext context) {
    const modules = 21;
    final ink = dark ? Colors.white : const Color(0xFF0C1220);
    return Container(
      width: size,
      height: size,
      color: dark ? const Color(0xFF0A0C0F) : Colors.white,
      child: CustomPaint(painter: _QrPainter(modules, ink)),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.modules, this.ink);
  final int modules;
  final Color ink;
  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / modules;
    final p = Paint()..color = ink;
    bool finder(int x, int y) =>
        (x < 7 && y < 7) ||
        (x >= modules - 7 && y < 7) ||
        (x < 7 && y >= modules - 7);
    for (var y = 0; y < modules; y++) {
      for (var x = 0; x < modules; x++) {
        if (finder(x, y)) continue;
        if ((x * 7 + y * 13 + x * y) % 5 < 2) {
          canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), p);
        }
      }
    }
    void drawFinder(int fx, int fy) {
      canvas.drawRect(
        Rect.fromLTWH(fx * cell, fy * cell, 7 * cell, 7 * cell),
        p,
      );
      canvas.drawRect(
        Rect.fromLTWH((fx + 1) * cell, (fy + 1) * cell, 5 * cell, 5 * cell),
        Paint()
          ..color = (ink == Colors.white
              ? const Color(0xFF0A0C0F)
              : Colors.white),
      );
      canvas.drawRect(
        Rect.fromLTWH((fx + 2) * cell, (fy + 2) * cell, 3 * cell, 3 * cell),
        p,
      );
    }

    drawFinder(0, 0);
    drawFinder(modules - 7, 0);
    drawFinder(0, modules - 7);
  }

  @override
  bool shouldRepaint(covariant _QrPainter old) => false;
}

/// Full-width bottom capsule tab bar (home screens).
class KtTabBar extends StatelessWidget {
  const KtTabBar({
    super.key,
    this.selected = 0,
    this.items = const [
      ('首页', Icons.home_filled),
      ('资产', Icons.pie_chart),
      ('记录', Icons.history),
      ('设置', Icons.settings),
    ],
  });
  final int selected;
  final List<(String, IconData)> items;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
    child: Container(
      height: 56,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: WalletColors.surface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: WalletColors.text.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: i == selected
                      ? WalletColors.accent.withValues(alpha: 0.08)
                      : null,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      items[i].$2,
                      size: 22,
                      color: i == selected
                          ? WalletColors.accent
                          : WalletColors.text3,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      items[i].$1,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: i == selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: i == selected
                            ? WalletColors.accent
                            : WalletColors.text3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
