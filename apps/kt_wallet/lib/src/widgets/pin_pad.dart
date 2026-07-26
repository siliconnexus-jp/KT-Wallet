import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

/// Color set for [PinDots] + [PinPad] so the same numpad renders on the
/// light settings sheets (wallet palette) and the dark lock screen (signer
/// palette).
class PinPadColors {
  const PinPadColors({
    required this.digit,
    required this.key,
    required this.icon,
    required this.dotOn,
    required this.dotOff,
    required this.dotBorder,
  });

  /// Light variant for bottom sheets in the wallet UI.
  static const wallet = PinPadColors(
    digit: WalletColors.text,
    key: WalletColors.bg,
    icon: WalletColors.text2,
    dotOn: WalletColors.text,
    dotOff: WalletColors.surface,
    dotBorder: WalletColors.border,
  );

  /// Dark variant for the app-lock screen.
  static const signer = PinPadColors(
    digit: SignerColors.text,
    key: SignerColors.surface2,
    icon: SignerColors.text2,
    dotOn: SignerColors.text,
    dotOff: SignerColors.surface2,
    dotBorder: SignerColors.border,
  );

  final Color digit, key, icon, dotOn, dotOff, dotBorder;
}

/// The 6 entry-progress dots above a [PinPad].
class PinDots extends StatelessWidget {
  const PinDots({
    super.key,
    required this.filled,
    this.colors = PinPadColors.wallet,
  });

  final int filled;
  final PinPadColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 6; i++)
          Container(
            width: 13,
            height: 13,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: i < filled ? colors.dotOn : colors.dotOff,
              shape: BoxShape.circle,
              border: i < filled ? null : Border.all(color: colors.dotBorder),
            ),
          ),
      ],
    );
  }
}

/// 6-digit numpad (same layout/interaction as cold_signer's C14 pad).
/// Emits digit strings '0'–'9' and 'del' via [onKey].
class PinPad extends StatelessWidget {
  const PinPad({
    super.key,
    required this.onKey,
    this.colors = PinPadColors.wallet,
  });

  final ValueChanged<String> onKey;
  final PinPadColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['', '0', 'del'],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final k in row)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: k.isEmpty ? null : () => onKey(k),
                    child: Container(
                      width: 64,
                      height: 64,
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: k.isEmpty || k == 'del' ? null : colors.key,
                        shape: BoxShape.circle,
                      ),
                      child: k == 'del'
                          ? Icon(
                              Icons.backspace_outlined,
                              size: 20,
                              color: colors.icon,
                            )
                          : Text(
                              k,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w500,
                                color: colors.digit,
                              ),
                            ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
