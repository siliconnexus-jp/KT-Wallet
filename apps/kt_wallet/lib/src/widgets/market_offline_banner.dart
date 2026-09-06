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
/// Do not infer device connectivity from a provider error, or describe mixed
/// fresh/cached balances using one wallet-wide "verified" timestamp.
class MarketFreshnessLabel extends StatelessWidget {
  const MarketFreshnessLabel({super.key, required this.market});

  final MarketController market;

  @override
  Widget build(BuildContext context) {
    if (!market.hasFreshnessNotice) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final message = market.isRefreshing
        ? l10n.marketRefreshing
        : market.priceRefreshIncomplete && !market.balanceRefreshIncomplete
        ? l10n.marketPricesIncomplete
        : market.balanceRefreshIncomplete && !market.priceRefreshIncomplete
        ? l10n.marketBalancesIncomplete
        : l10n.marketCachedStale;
    return Semantics(
      liveRegion: true,
      label: message,
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
              message,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: WalletColors.text3,
              ),
            ),
          ),
          if (!market.isRefreshing)
            IconButton(
              key: const ValueKey('market-freshness-retry'),
              tooltip: l10n.actionRetry,
              onPressed: market.refresh,
              icon: const Icon(Icons.refresh_rounded, size: 19),
              color: WalletColors.text2,
            ),
        ],
      ),
    );
  }
}
