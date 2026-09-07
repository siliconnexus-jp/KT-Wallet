import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../l10n/app_localizations.dart';
import '../widgets/signer_brand_mark.dart';

/// Offline product information. Links are displayed/copied, never opened.
class SignerAboutScreen extends StatelessWidget {
  const SignerAboutScreen({super.key});

  // Kept in sync with pubspec by signer_about_test.dart, like online AppInfo.
  static const version = '1.0.0';
  static const repositoryUrl = 'https://github.com/siliconnexus-jp/KT-Wallet';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KtScreen(
      theme: AppTheme.signer,
      navBar: KtNavBar(
        title: l10n.aboutTitle,
        theme: AppTheme.signer,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      children: [
        Column(
          children: [
            const SignerBrandMark(size: 72),
            const SizedBox(height: 16),
            Text(
              l10n.appName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: SignerColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.introRole,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: SignerColors.text2,
              ),
            ),
          ],
        ),
        KtCard(
          theme: AppTheme.signer,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.aboutVersion,
                  style: const TextStyle(color: SignerColors.text2),
                ),
              ),
              const Text(version, style: TextStyle(color: SignerColors.text)),
            ],
          ),
        ),
        KtCard(
          theme: AppTheme.signer,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.aboutOpenSource,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: SignerColors.text,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                repositoryUrl,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: SignerColors.text2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.aboutOfflineNote,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: SignerColors.text2,
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                key: const ValueKey('signer-about-copy-source'),
                style: TextButton.styleFrom(
                  foregroundColor: SignerColors.ok,
                  minimumSize: const Size(48, 48),
                ),
                onPressed: () async {
                  await Clipboard.setData(
                    const ClipboardData(text: repositoryUrl),
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                    ..clearSnackBars()
                    ..showSnackBar(SnackBar(content: Text(l10n.introCopied)));
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: Text(l10n.introCopyLink),
              ),
            ],
          ),
        ),
        KtProductAttribution(poweredBy: l10n.aboutPoweredBy, dark: true),
      ],
    );
  }
}
