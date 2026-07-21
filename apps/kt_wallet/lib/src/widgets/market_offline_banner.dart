import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../l10n/app_localizations.dart';

/// Unobtrusive "offline — showing demo data" strip shown when every live
/// balance and price fetch failed, so demo numbers are never mistaken for
/// live ones. Only rendered under a mounted MarketScope; gallery/golden
/// renders never show it.
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
      child: Row(children: [
        const Icon(Icons.cloud_off_outlined, size: 14, color: WalletColors.text3),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            l10n.marketOfflineDemo,
            style: const TextStyle(fontSize: 12, color: WalletColors.text3),
          ),
        ),
      ]),
    );
  }
}
