import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../l10n/app_localizations.dart';

/// Shared full-screen dark mock camera. The demo has no camera hardware, so
/// tapping the viewfinder box fires [onSimulatedScan] to simulate a successful
/// scan (same pattern as the signer's scan screens).
class KtCameraScreen extends StatelessWidget {
  const KtCameraScreen({super.key, required this.title, required this.hint, required this.onClose, this.onSimulatedScan});
  final String title, hint;
  final VoidCallback onClose;
  final VoidCallback? onSimulatedScan;
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: SignerColors.bg,
        body: SafeArea(
          bottom: false,
          child: Column(children: [
            const KtStatusBar(theme: AppTheme.signer),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: KtNavBar(title: title, theme: AppTheme.signer, leading: Icons.close, onBack: onClose)),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: onSimulatedScan,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                height: 400,
                decoration: BoxDecoration(color: SignerColors.surface, borderRadius: BorderRadius.circular(20)),
                child: Center(child: Container(width: 240, height: 240, decoration: BoxDecoration(border: Border.all(color: SignerColors.blue, width: 2), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.qr_code_2, size: 64, color: SignerColors.border))),
              ),
            ),
            const SizedBox(height: 24),
            Text(hint, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
          ]),
        ),
      );
}

/// Address scanner pushed from the transfer screen ('/scan-address'; not part
/// of the gallery registry). The simulated scan pops with a demo TRON address.
class ScanAddressScreen extends StatelessWidget {
  const ScanAddressScreen({super.key});

  /// Demo TRON address returned by the mock scan (passes base58check).
  static const demoAddress = 'TQm9xPa2Wc8hJdU5eRnT6yGb1sVbAgQs8D';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KtCameraScreen(
      title: l10n.scanAddressTitle,
      hint: l10n.scanAddressHint,
      onClose: () => Navigator.of(context).maybePop(),
      onSimulatedScan: () => context.pop(demoAddress),
    );
  }
}
