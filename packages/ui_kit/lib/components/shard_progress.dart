import 'package:flutter/material.dart';

import '../tokens/colors.dart';

/// Fragment scan/display progress bar used by air-gap QR screens.
class ShardProgressBar extends StatelessWidget {
  const ShardProgressBar({
    super.key,
    required this.received,
    required this.total,
    this.color = WalletColors.accent,
    this.trackColor = WalletColors.border,
    this.width = 200,
  }) : assert(total > 0, 'total must be positive');

  final int received;
  final int total;
  final Color color;
  final Color trackColor;
  final double width;

  double get fraction => (received / total).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: fraction,
          backgroundColor: trackColor,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ),
    );
  }
}
