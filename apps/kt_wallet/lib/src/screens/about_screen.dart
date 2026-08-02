import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../l10n/app_localizations.dart';
import '../app_info.dart';
import '../market/market_scope.dart';
import '../observability/diagnostic_bundle.dart';
import '../observability/diagnostic_telemetry.dart';
import '../observability/experience_metrics.dart';
import '../platform/external_actions.dart';
import '../state/app_prefs.dart';
import '../state/networks.dart';

/// W34 关于 — what this app is, which build you are running, and where its
/// source lives.
///
/// The repository row is the point of the screen: a wallet that asks to hold
/// someone's keys should be able to say where its code is, and be checked.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key, this.telemetryUploader});

  /// Test injection only. Production creates a one-shot Gateway uploader when
  /// the user explicitly confirms the disclosure.
  final DiagnosticTelemetryUploader? telemetryUploader;

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  bool _exportingDiagnostics = false;
  bool _uploadingDiagnostics = false;

  Future<void> _openUrl(BuildContext context, String url) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    final opened = await ExternalActions.instance.open(Uri.parse(url));
    if (opened || !context.mounted) return;
    // No browser (or it refused). Falling back to the clipboard keeps every
    // disclosure reachable without adding a second in-app web surface.
    await Clipboard.setData(ClipboardData(text: url));
    messenger.showSnackBar(SnackBar(content: Text(l10n.aboutCopiedLink)));
  }

  Widget _linkRow({
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    Color iconColor = WalletColors.text2,
    IconData trailingIcon = Icons.open_in_new_rounded,
  }) => Semantics(
    button: onTap != null,
    label: '$title. $subtitle',
    child: GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: WalletColors.text,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: WalletColors.text3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(trailingIcon, size: 16, color: WalletColors.text3),
          ],
        ),
      ),
    ),
  );

  Widget _divider() => const Divider(height: 1, color: WalletColors.border);

  Widget _diagnosticDisclosure({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
  }) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: WalletColors.text,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                body,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: WalletColors.text2,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Future<void> _exportDiagnostics() async {
    if (_exportingDiagnostics) return;
    final l10n = AppLocalizations.of(context);
    final localeCode = Localizations.localeOf(context).languageCode;
    final networks = NetworkScope.maybeOf(context);
    final prefs = AppPrefsScope.maybeOf(context);
    final market = MarketScope.maybeOf(context);
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => KtConfirmDialog(
        title: l10n.diagnosticsConfirmTitle,
        message: l10n.diagnosticsConfirmBody,
        cancelLabel: l10n.actionCancel,
        confirmLabel: l10n.diagnosticsExportAction,
        icon: Icons.privacy_tip_outlined,
        iconColor: WalletColors.accent,
        details: Column(
          children: [
            _diagnosticDisclosure(
              icon: Icons.check_circle_outline_rounded,
              color: WalletColors.green,
              title: l10n.diagnosticsIncludesTitle,
              body: l10n.diagnosticsIncludesBody,
            ),
            const SizedBox(height: 10),
            _diagnosticDisclosure(
              icon: Icons.visibility_off_outlined,
              color: WalletColors.text2,
              title: l10n.diagnosticsExcludesTitle,
              body: l10n.diagnosticsExcludesBody,
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _exportingDiagnostics = true);
    String? temporaryPath;
    try {
      final bundle = const DiagnosticBundleBuilder().build(
        localeCode: localeCode,
        networks: networks,
        prefs: prefs,
        market: market,
        metrics: ExperienceMetrics.instance.recent,
      );
      temporaryPath = await DiagnosticBundleFileStore.instance.write(bundle);
      await ExternalActions.instance.shareFile(
        path: temporaryPath,
        mimeType: 'application/json',
        subject: l10n.diagnosticsShareSubject,
        text: l10n.diagnosticsShareText,
      );
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.diagnosticsReady)));
      }
    } on Object {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.diagnosticsFailed)));
      }
    } finally {
      if (temporaryPath != null) {
        try {
          await DiagnosticBundleFileStore.instance.remove(temporaryPath);
        } on Object {
          // The bundle contains no wallet data; stale temporary-file cleanup
          // remains best-effort when the platform has already moved the file.
        }
      }
      if (mounted) setState(() => _exportingDiagnostics = false);
    }
  }

  Future<void> _uploadDiagnostics() async {
    if (_uploadingDiagnostics) return;
    final l10n = AppLocalizations.of(context);
    final localeCode = Localizations.localeOf(context).languageCode;
    final prefs = AppPrefsScope.maybeOf(context);
    final gatewayUrl = prefs == null
        ? AppPrefsController.defaultGatewayUrl
        : prefs.gatewayUrl;
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => KtConfirmDialog(
        title: l10n.diagnosticsUploadConfirmTitle,
        message: l10n.diagnosticsUploadConfirmBody,
        cancelLabel: l10n.actionCancel,
        confirmLabel: l10n.diagnosticsUploadAction,
        icon: Icons.monitor_heart_outlined,
        iconColor: WalletColors.accent,
        details: Column(
          children: [
            _diagnosticDisclosure(
              icon: Icons.check_circle_outline_rounded,
              color: WalletColors.green,
              title: l10n.diagnosticsIncludesTitle,
              body: l10n.diagnosticsUploadIncludesBody,
            ),
            const SizedBox(height: 10),
            _diagnosticDisclosure(
              icon: Icons.visibility_off_outlined,
              color: WalletColors.text2,
              title: l10n.diagnosticsExcludesTitle,
              body: l10n.diagnosticsUploadExcludesBody,
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    if (gatewayUrl == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.diagnosticsUploadGatewayRequired)),
      );
      return;
    }

    setState(() => _uploadingDiagnostics = true);
    try {
      final report = DiagnosticTelemetryReport.fromMetrics(
        samples: ExperienceMetrics.instance.recent,
        localeCode: localeCode,
      );
      final result =
          await (widget.telemetryUploader ??
                  GatewayDiagnosticTelemetryUploader())
              .upload(gatewayBaseUrl: gatewayUrl, report: report);
      if (!mounted) return;
      final message = switch (result) {
        DiagnosticTelemetryUploadResult.sent => l10n.diagnosticsUploadSent,
        DiagnosticTelemetryUploadResult.alreadySent =>
          l10n.diagnosticsUploadAlreadySent,
        DiagnosticTelemetryUploadResult.noSamples =>
          l10n.diagnosticsUploadNoSamples,
      };
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } on Object {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.diagnosticsUploadFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingDiagnostics = false);
    }
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
                width: 72,
                height: 72,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 10),
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
                onTap: () => _openUrl(context, AppInfo.repositoryUrl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.code,
                        size: 19,
                        color: WalletColors.text2,
                      ),
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
              ),
              const SizedBox(height: 10),
              // The URL in full, selectable. A link the user cannot read is a
              // link they have to trust; this one they can type themselves.
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
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
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            l10n.aboutTrustTitle,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: WalletColors.text2,
            ),
          ),
        ),
        KtCard(
          child: Column(
            children: [
              _linkRow(
                key: const ValueKey('about-privacy'),
                icon: Icons.privacy_tip_outlined,
                title: l10n.aboutPrivacyPolicy,
                subtitle: l10n.aboutPrivacyPolicyDesc,
                onTap: () => _openUrl(context, AppInfo.privacyPolicyUrl),
              ),
              _divider(),
              _linkRow(
                key: const ValueKey('about-security-risk'),
                icon: Icons.shield_outlined,
                title: l10n.aboutSecurityRisk,
                subtitle: l10n.aboutSecurityRiskDesc,
                onTap: () => _openUrl(context, AppInfo.securityAndRiskUrl),
              ),
              _divider(),
              _linkRow(
                key: const ValueKey('about-security-policy'),
                icon: Icons.policy_outlined,
                title: l10n.aboutSecurityPolicy,
                subtitle: l10n.aboutSecurityPolicyDesc,
                onTap: () => _openUrl(context, AppInfo.securityPolicyUrl),
              ),
              _divider(),
              _linkRow(
                key: const ValueKey('about-third-party'),
                icon: Icons.account_tree_outlined,
                title: l10n.aboutThirdPartyNotices,
                subtitle: l10n.aboutThirdPartyNoticesDesc,
                onTap: () => _openUrl(context, AppInfo.thirdPartyNoticesUrl),
              ),
            ],
          ),
        ),
        KtCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _linkRow(
                key: const ValueKey('about-report-security'),
                icon: Icons.lock_person_outlined,
                iconColor: WalletColors.accent,
                title: l10n.aboutReportSecurity,
                subtitle: l10n.aboutReportSecurityDesc,
                onTap: () => _openUrl(context, AppInfo.securityReportUrl),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: WalletColors.accent.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  l10n.aboutNeverShareSecrets,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: WalletColors.text2,
                  ),
                ),
              ),
            ],
          ),
        ),
        KtCard(
          child: Column(
            children: [
              _linkRow(
                key: const ValueKey('about-export-diagnostics'),
                icon: Icons.support_agent_rounded,
                iconColor: WalletColors.accent,
                title: l10n.diagnosticsTitle,
                subtitle: l10n.diagnosticsSubtitle,
                onTap: _exportingDiagnostics ? null : _exportDiagnostics,
                trailingIcon: _exportingDiagnostics
                    ? Icons.hourglass_top_rounded
                    : Icons.ios_share_rounded,
              ),
              _divider(),
              _linkRow(
                key: const ValueKey('about-upload-diagnostics'),
                icon: Icons.monitor_heart_outlined,
                iconColor: WalletColors.green,
                title: l10n.diagnosticsUploadTitle,
                subtitle: l10n.diagnosticsUploadSubtitle,
                onTap: _uploadingDiagnostics ? null : _uploadDiagnostics,
                trailingIcon: _uploadingDiagnostics
                    ? Icons.hourglass_top_rounded
                    : Icons.upload_rounded,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
