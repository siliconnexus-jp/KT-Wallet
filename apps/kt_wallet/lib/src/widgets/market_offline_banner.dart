import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../l10n/app_localizations.dart';
import '../market/market_controller.dart';

/// Unobtrusive offline strip. Wallet-facing screens never substitute design
/// fixtures: they either retain a network-scoped last-good snapshot or show
/// unavailable values.
class MarketOfflineBanner extends StatelessWidget {
  const MarketOfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: WalletColors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 14,
            color: WalletColors.text3,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.marketOfflineDemo,
              style: const TextStyle(fontSize: 12, color: WalletColors.text3),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact, non-blocking freshness copy for a retained last-good snapshot.
///
/// A cached balance is still useful, but it must never look as current as a
/// live RPC response. The timestamp is deliberately rounded down so the label
/// remains stable instead of rebuilding every second.
class MarketFreshnessLabel extends StatelessWidget {
  const MarketFreshnessLabel({super.key, required this.market});

  final MarketController market;

  String _relative(AppLocalizations l10n, DateTime timestamp) {
    final age = DateTime.now().difference(timestamp);
    if (age.inMinutes < 1) return l10n.marketCachedJustNow;
    if (age.inHours < 1) return l10n.marketCachedMinutes(age.inMinutes);
    return l10n.marketCachedHours(age.inHours);
  }

  @override
  Widget build(BuildContext context) {
    final timestamp = market.lastUpdatedAt;
    if (!market.showingCachedData || timestamp == null) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    return Semantics(
      liveRegion: true,
      label: '${_relative(l10n, timestamp)}. ${l10n.marketCachedStale}',
      child: Row(
        key: const ValueKey('market-freshness'),
        children: [
          const Icon(
            Icons.schedule_rounded,
            size: 14,
            color: WalletColors.text3,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${_relative(l10n, timestamp)} · ${l10n.marketCachedStale}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: WalletColors.text3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
