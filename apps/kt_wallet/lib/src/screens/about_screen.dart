import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../l10n/app_localizations.dart';
import '../app_info.dart';
import '../platform/external_actions.dart';

/// W34 关于 — what this app is, which build you are running, and where its
/// source lives.
///
/// The repository row is the point of the screen: a wallet that asks to hold
/// someone's keys should be able to say where its code is, and be checked.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<void> _openRepository(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    final opened = await ExternalActions.instance.open(
      Uri.parse(AppInfo.repositoryUrl),
    );
    if (opened || !context.mounted) return;
    // No browser (or it refused). Falling back to the clipboard beats a dead
    // end — the user can still get to the source, just by hand.
    await Clipboard.setData(const ClipboardData(text: AppInfo.repositoryUrl));
    messenger.showSnackBar(SnackBar(content: Text(l10n.aboutCopiedLink)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KtScreen(
      navBar: KtNavBar(
        title: l10n.aboutTitle,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      children: [
        Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/brand/app_icon.png',
                width: 88,
                height: 88,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              l10n.appName,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: WalletColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                l10n.aboutTagline,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: WalletColors.text2,
                ),
              ),
            ),
          ],
        ),
        KtCard(
          child: Column(
            children: [
              KtDetailRow(label: l10n.aboutVersion, value: AppInfo.version),
              const SizedBox(height: 14),
              GestureDetector(
                key: const ValueKey('about-repository'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _openRepository(context),
                child: Row(
                  children: [
                    const Icon(Icons.code, size: 19, color: WalletColors.text2),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.aboutOpenSource,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: WalletColors.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l10n.aboutOpenSourceDesc,
                            style: const TextStyle(
                              fontSize: 12,
                              color: WalletColors.text3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(
                      Icons.open_in_new,
                      size: 16,
                      color: WalletColors.text3,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // The URL in full, selectable. A link the user cannot read is a
              // link they have to trust; this one they can type themselves.
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  AppInfo.repositoryUrl,
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: WalletColors.accent,
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
