import 'package:flutter/material.dart';

import '../tokens/colors.dart';

/// Shared ownership notice for both products; does not replace their licenses.
class KtProductAttribution extends StatelessWidget {
  const KtProductAttribution({
    super.key,
    required this.poweredBy,
    this.dark = false,
  });

  static const copyright = '© 2026 Silicon Nexus LLC';
  final String poweredBy;
  final bool dark;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      children: [
        Text(
          poweredBy,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: dark ? SignerColors.text2 : WalletColors.text2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          copyright,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: dark ? SignerColors.text2 : WalletColors.text2,
          ),
        ),
      ],
    ),
  );
}
