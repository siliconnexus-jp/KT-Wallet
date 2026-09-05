import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../l10n/app_localizations.dart';

enum SecretAccessKind { mnemonic, privateKey }

/// Shared, concise disclosure shown before any native secret access.
/// This widget does not read a secret or replace device authentication.
class SecretAccessRisk extends StatelessWidget {
  const SecretAccessRisk({super.key, required this.kind});

  final SecretAccessKind kind;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: WalletColors.accent.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(
            Icons.shield_outlined,
            size: 28,
            color: WalletColors.accent,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          l10n.secretAccessRiskTitle,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: WalletColors.text,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          kind == SecretAccessKind.mnemonic
              ? l10n.mnemonicAccessRisk
              : l10n.privateKeyAccessRisk,
          style: const TextStyle(
            fontSize: 15,
            height: 1.6,
            color: WalletColors.text2,
          ),
        ),
      ],
    );
  }
}
