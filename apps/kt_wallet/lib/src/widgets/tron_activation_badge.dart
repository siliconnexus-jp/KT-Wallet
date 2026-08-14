import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../l10n/app_localizations.dart';
import '../market/balance_service.dart';
import '../market/market_scope.dart';

/// One wallet-wide, network-scoped presentation of the current TRON account
/// state. Callers decide whether the surrounding row refers to TRON; the
/// status itself always comes from [MarketController] unless explicitly
/// injected by a test.
class TronActivationBadge extends StatelessWidget {
  const TronActivationBadge({super.key, this.status});

  final TronActivationStatus? status;

  TronActivationStatus _status(BuildContext context) =>
      status ??
      MarketScope.maybeOf(context)?.tronActivationStatus ??
      TronActivationStatus.unknown;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final value = _status(context);
    final (label, icon, foreground, background) = switch (value) {
      TronActivationStatus.checking => (
        l10n.tronActivationChecking,
        Icons.sync_rounded,
        WalletColors.text2,
        WalletColors.bg,
      ),
      TronActivationStatus.activated => (
        l10n.tronActivated,
        Icons.check_circle_outline_rounded,
        WalletColors.green,
        WalletColors.green.withValues(alpha: 0.10),
      ),
      TronActivationStatus.unactivated => (
        l10n.tronUnactivated,
        Icons.error_outline_rounded,
        WalletColors.amber,
        WalletColors.amber.withValues(alpha: 0.13),
      ),
      TronActivationStatus.unknown => (
        l10n.tronActivationUnknown,
        Icons.help_outline_rounded,
        WalletColors.text3,
        WalletColors.bg,
      ),
    };
    return Semantics(
      label: '${l10n.tronAccountStatus}: $label',
      excludeSemantics: true,
      child: Container(
        key: ValueKey('tron-activation-${value.name}'),
        constraints: const BoxConstraints(minHeight: 24),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 4),
            Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Detailed action guidance shown on receive/send surfaces while a TRON
/// address has token holdings but cannot yet originate transactions.
class TronActivationNotice extends StatelessWidget {
  const TronActivationNotice({super.key, this.status});

  final TronActivationStatus? status;

  @override
  Widget build(BuildContext context) {
    final value =
        status ??
        MarketScope.maybeOf(context)?.tronActivationStatus ??
        TronActivationStatus.unknown;
    if (value != TronActivationStatus.unactivated) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    return Container(
      key: const ValueKey('tron-activation-notice'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WalletColors.amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: WalletColors.amber,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              l10n.tronActivationRequiredHint,
              style: const TextStyle(
                fontSize: 12,
                height: 1.45,
                fontWeight: FontWeight.w500,
                color: WalletColors.text2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
