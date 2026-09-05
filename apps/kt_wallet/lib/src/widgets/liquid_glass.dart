import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui_kit/ui_kit.dart';

/// A bounded backdrop, not a full-screen blur. High contrast uses an opaque
/// material so navigation remains readable independently of content below it.
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({super.key, required this.child, this.radius = 36});

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return KtGlassSurface(radius: radius, blur: true, child: child);
  }
}

class LiquidWalletTabs extends StatelessWidget {
  const LiquidWalletTabs({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
  }) : assert(items.length >= 2),
       assert(selected >= 0 && selected < items.length);

  final List<(String, IconData)> items;
  final int selected;
  final ValueChanged<int> onSelected;

  static double heightFor(BuildContext context) =>
      44 + MediaQuery.textScalerOf(context).scale(12) * 1.2;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context) ||
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: LiquidGlass(
            child: SizedBox(
              key: const ValueKey('home-tab-background'),
              height: heightFor(context) + 12,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AnimatedAlign(
                      alignment: AlignmentDirectional(
                        -1 + 2 * selected / (items.length - 1),
                        0,
                      ),
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      child: FractionallySizedBox(
                        widthFactor: 1 / items.length,
                        heightFactor: 1,
                        child: DecoratedBox(
                          key: const ValueKey('home-tab-indicator'),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(30),
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xFFE9F1FF), Color(0xFFDCE8FD)],
                            ),
                            border: Border.all(color: const Color(0xFFCCDCF6)),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (final (index, item) in items.indexed)
                          Expanded(
                            child: Semantics(
                              selected: index == selected,
                              button: true,
                              label: item.$1,
                              onTap: () => onSelected(index),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  key: ValueKey('home-tab-$index'),
                                  borderRadius: BorderRadius.circular(30),
                                  excludeFromSemantics: true,
                                  onTap: () {
                                    if (selected != index) {
                                      HapticFeedback.selectionClick();
                                    }
                                    onSelected(index);
                                  },
                                  child: ExcludeSemantics(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          item.$2,
                                          size: 25,
                                          color: index == selected
                                              ? WalletColors.accent
                                              : WalletColors.text2,
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          item.$1,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            height: 1.2,
                                            fontWeight: index == selected
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            color: index == selected
                                                ? WalletColors.accent
                                                : WalletColors.text2,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
