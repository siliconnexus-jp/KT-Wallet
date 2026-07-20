import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../l10n/app_localizations.dart';
import '../security/device_probe.dart';
import '../security/security_check.dart';

const _t = AppTheme.signer;

Widget _kv(String k, String v, {bool mono = false, Color? color}) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k, style: const TextStyle(fontSize: 14, color: SignerColors.text2)),
        const SizedBox(width: 16),
        Expanded(child: Text(v, textAlign: TextAlign.right, style: TextStyle(fontSize: mono ? 13 : 14, fontWeight: FontWeight.w500, fontFamily: mono ? KtFonts.mono : KtFonts.ui, color: color ?? SignerColors.text))),
      ],
    );

Widget _card(Widget child) => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: SignerColors.surface, borderRadius: BorderRadius.circular(14)), child: child);

/// C5 离线首页.
class SignerHomeScreen extends StatelessWidget {
  const SignerHomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KtScreen(
      theme: _t,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l10n.walletMainName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: SignerColors.text)),
            const SizedBox(height: 4),
            Row(children: [
              const _Dot(SignerColors.ok),
              const SizedBox(width: 6),
              Text(l10n.offlineForDays(42), style: const TextStyle(fontSize: 13, color: SignerColors.ok)),
            ]),
          ]),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => context.push('/security'),
            child: const Icon(Icons.settings_outlined, size: 22, color: SignerColors.text2),
          ),
        ]),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.push('/security-check'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: SignerColors.ok.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.verified_user, size: 18, color: SignerColors.ok),
              const SizedBox(width: 10),
              Expanded(child: Text(l10n.securityCheckPassed, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: SignerColors.ok))),
              const Icon(Icons.chevron_right, size: 16, color: SignerColors.ok),
            ]),
          ),
        ),
        GestureDetector(
          onTap: () => context.push('/scan'),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            decoration: BoxDecoration(color: SignerColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: SignerColors.border)),
            child: Column(children: [
              Container(width: 64, height: 64, decoration: BoxDecoration(color: SignerColors.blue.withValues(alpha: 0.12), shape: BoxShape.circle), child: const Icon(Icons.qr_code_scanner, size: 30, color: SignerColors.blue)),
              const SizedBox(height: 12),
              Text(l10n.scanPendingTx, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: SignerColors.text)),
              const SizedBox(height: 6),
              Text(l10n.scanPendingTxDesc, style: const TextStyle(fontSize: 13, color: SignerColors.text2)),
            ]),
          ),
        ),
        Row(children: [
          for (final (icon, label, route) in [(Icons.qr_code, l10n.exportAddress, '/export'), (Icons.history, l10n.signRecords, '/records'), (Icons.shield_outlined, l10n.securityCheck, '/security-check'), (Icons.wallet, l10n.walletManage, '/wallet')]) ...[
            Expanded(child: GestureDetector(onTap: () => context.push(route), child: Container(margin: const EdgeInsets.symmetric(horizontal: 4), padding: const EdgeInsets.symmetric(vertical: 14), decoration: BoxDecoration(color: SignerColors.surface, borderRadius: BorderRadius.circular(12)), child: Column(children: [Icon(icon, size: 20, color: SignerColors.text), const SizedBox(height: 8), Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: SignerColors.text2))])))),
          ],
        ]),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.color, {this.size = 7});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

/// C2 离线安全检查 — runs the real [SecurityChecks] engine over a device probe
/// and renders one row per [CheckResult], plus an aggregate verdict header.
class SignerSecurityCheckScreen extends StatefulWidget {
  const SignerSecurityCheckScreen({super.key, this.probe = probeDeviceState});

  /// Injectable device probe; tests supply a fixed [DeviceState].
  final Future<DeviceState> Function() probe;

  @override
  State<SignerSecurityCheckScreen> createState() => _SignerSecurityCheckScreenState();
}

class _SignerSecurityCheckScreenState extends State<SignerSecurityCheckScreen> {
  SecurityVerdict? _verdict; // null while a probe is in flight

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    if (_verdict != null) setState(() => _verdict = null); // re-run: back to checking
    final state = await widget.probe();
    if (!mounted) return;
    setState(() => _verdict = SecurityChecks.verdict(state));
  }

  static IconData _checkIcon(String id) => switch (id) {
        'network' => Icons.wifi,
        'airplane' => Icons.airplanemode_active,
        'bluetooth' => Icons.bluetooth,
        'passcode' => Icons.lock,
        'biometric' => Icons.face,
        'screen_capture' => Icons.screenshot_monitor,
        'integrity' => Icons.verified_user,
        _ => Icons.shield_outlined,
      };

  /// Engine check ids → localized labels (the engine has no BuildContext).
  static String _checkLabel(AppLocalizations l10n, String id) => switch (id) {
        'network' => l10n.checkNetwork,
        'airplane' => l10n.checkAirplaneMode,
        'bluetooth' => l10n.checkBluetooth,
        'passcode' => l10n.checkDevicePasscode,
        'biometric' => l10n.checkBiometric,
        'screen_capture' => l10n.checkScreenRecording,
        'integrity' => l10n.checkIntegrity,
        _ => id,
      };

  Widget _resultRow(AppLocalizations l10n, CheckResult r) {
    final (color, icon, levelLabel) = switch (r.level) {
      CheckLevel.pass => (SignerColors.ok, Icons.check_circle, l10n.checkLevelPass),
      CheckLevel.warn => (SignerColors.warn, Icons.error, l10n.checkLevelWarn),
      CheckLevel.block => (SignerColors.danger, Icons.cancel, l10n.checkLevelBlock),
    };
    return Row(children: [
      Icon(_checkIcon(r.id), size: 18, color: r.level == CheckLevel.pass ? SignerColors.text2 : color),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_checkLabel(l10n, r.id), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: SignerColors.text)),
        if (r.detail != null) ...[
          const SizedBox(height: 2),
          // Engine diagnostics are untranslated; surfaced as-is.
          Text(r.detail!, style: const TextStyle(fontSize: 11, color: Color(0xFF5A616C))),
        ],
      ])),
      Text(levelLabel, style: TextStyle(fontSize: 13, color: color)),
      const SizedBox(width: 8),
      Icon(icon, size: 16, color: color),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final verdict = _verdict;
    final (headBg, headColor, headIcon, headTitle) = switch (verdict?.overall) {
      null => (SignerColors.surface, SignerColors.text2, Icons.shield_outlined, l10n.securityChecking),
      CheckLevel.pass => (SignerColors.ok.withValues(alpha: 0.10), SignerColors.ok, Icons.verified_user, l10n.securityOverallPass),
      CheckLevel.warn => (SignerColors.warn.withValues(alpha: 0.10), SignerColors.warn, Icons.warning_amber_rounded, l10n.securityOverallWarn),
      CheckLevel.block => (SignerColors.danger.withValues(alpha: 0.10), SignerColors.danger, Icons.dangerous, l10n.securityOverallBlock),
    };
    return KtScreen(
      theme: _t,
      navBar: KtNavBar(title: l10n.offlineSecurityCheck, theme: _t, onBack: () => Navigator.of(context).maybePop()),
      bottom: KtPrimaryButton(label: l10n.securityRecheck, style: KtButtonStyle.signer, onPressed: verdict == null ? null : _run),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: headBg, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Icon(headIcon, size: 22, color: headColor),
            const SizedBox(width: 12),
            Expanded(child: Text(headTitle, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: headColor))),
          ]),
        ),
        if (verdict != null)
          _card(Column(children: [
            for (var i = 0; i < verdict.results.length; i++) ...[
              if (i > 0) const SizedBox(height: 13),
              _resultRow(l10n, verdict.results[i]),
            ],
          ])),
      ],
    );
  }
}

/// Design-snapshot variant of C2 with the canned rows from the original
/// ui-m.md mock. Kept solely as the dev-gallery / golden baseline (the
/// registry builds this so existing goldens stay byte-identical); the app
/// route '/security-check' serves the live [SignerSecurityCheckScreen].
class SignerSecurityCheckPreviewScreen extends StatelessWidget {
  const SignerSecurityCheckPreviewScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = <(IconData, String, String, String)>[
      (Icons.airplanemode_active, l10n.checkAirplaneMode, l10n.statusOn, 'ok'),
      (Icons.wifi_off, 'Wi-Fi', l10n.statusOff, 'ok'),
      (Icons.signal_cellular_alt, l10n.checkCellular, l10n.statusOff, 'ok'),
      (Icons.bluetooth, l10n.checkBluetooth, l10n.statusDetectedOn, 'warn'),
      (Icons.lock, l10n.checkDevicePasscode, l10n.statusEnabled, 'ok'),
      (Icons.face, l10n.checkBiometric, l10n.statusEnabled, 'ok'),
      (Icons.screenshot_monitor, l10n.checkScreenRecording, l10n.statusNotDetected, 'ok'),
    ];
    return KtScreen(
      theme: _t,
      navBar: KtNavBar(title: l10n.offlineSecurityCheck, theme: _t, onBack: () => Navigator.of(context).maybePop()),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: SignerColors.warn.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.warning_amber_rounded, size: 22, color: SignerColors.warn),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l10n.riskCannotSign, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: SignerColors.warn)),
              const SizedBox(height: 4),
              Text(l10n.bluetoothWarning, style: const TextStyle(fontSize: 13, height: 1.5, color: SignerColors.text2)),
            ])),
          ]),
        ),
        _card(Column(children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 13),
            () {
              final (icon, label, val, s) = items[i];
              final ok = s == 'ok';
              return Row(children: [
                Icon(icon, size: 18, color: ok ? SignerColors.text2 : SignerColors.warn),
                const SizedBox(width: 12),
                Expanded(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: SignerColors.text))),
                Text(val, style: TextStyle(fontSize: 13, color: ok ? SignerColors.ok : SignerColors.warn)),
                const SizedBox(width: 8),
                Icon(ok ? Icons.check_circle : Icons.error, size: 16, color: ok ? SignerColors.ok : SignerColors.warn),
              ]);
            }(),
          ],
        ])),
      ],
    );
  }
}

/// Dark camera scaffold shared by C6.
class SignerScanScreen extends StatelessWidget {
  const SignerScanScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: SignerColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          const KtStatusBar(theme: _t),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: KtNavBar(title: l10n.scanPendingTx, theme: _t, leading: Icons.close, onBack: () => Navigator.of(context).maybePop())),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () => context.push('/parse'),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              height: 360,
              decoration: BoxDecoration(color: SignerColors.surface, borderRadius: BorderRadius.circular(20)),
              child: Center(child: Container(width: 240, height: 240, decoration: BoxDecoration(border: Border.all(color: SignerColors.ok, width: 2), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.qr_code_2, size: 64, color: SignerColors.border))),
            ),
          ),
          const SizedBox(height: 24),
          Text(l10n.receivingShard(5, 8), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: SignerColors.text)),
          const SizedBox(height: 10),
          const ShardProgressBar(received: 5, total: 8, color: SignerColors.ok, trackColor: SignerColors.border, width: 240),
        ]),
      ),
    );
  }
}

/// C7 交易解析确认.
class SignerParseScreen extends StatelessWidget {
  const SignerParseScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KtScreen(
      theme: _t,
      gap: 16,
      navBar: KtNavBar(title: l10n.confirmTxContent, theme: _t, leading: Icons.close, onBack: () => Navigator.of(context).maybePop()),
      bottom: Row(children: [
        SizedBox(width: 120, height: 52, child: OutlinedButton(onPressed: () => context.pop(), style: OutlinedButton.styleFrom(backgroundColor: SignerColors.surface, side: const BorderSide(color: SignerColors.border), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text(l10n.reject, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: SignerColors.danger)))),
        const SizedBox(width: 12),
        Expanded(child: SizedBox(height: 52, child: FilledButton.icon(onPressed: () => context.push('/auth'), icon: const Icon(Icons.edit, size: 18, color: Color(0xFF0A0C0F)), label: Text(l10n.confirmSign, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF0A0C0F))), style: FilledButton.styleFrom(backgroundColor: SignerColors.ok, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))))),
      ]),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: SignerColors.surface, borderRadius: BorderRadius.circular(12)),
          child: Row(children: const [
            _Dot(ChainColors.tron, size: 8),
            SizedBox(width: 10),
            Expanded(child: Text('TRON · Token Transfer（TRC-20）', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: SignerColors.text))),
            Text('REQ-7F3A2C', style: TextStyle(fontSize: 11, fontFamily: KtFonts.mono, color: Color(0xFF5A616C))),
          ]),
        ),
        _card(Column(children: [
          const Text('120.00 USDT', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, fontFamily: KtFonts.mono, color: SignerColors.text)),
          const SizedBox(height: 6),
          Text(l10n.rawAmountPrecision('120,000,000', 6), style: const TextStyle(fontSize: 12, fontFamily: KtFonts.mono, color: SignerColors.text2)),
        ])),
        _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SignerDetailRow(label: l10n.fromAccount, value: 'TQm9xPa2Wc8hJdU5eRnT6yGb1sVb7L3kFa'),
          const SizedBox(height: 16),
          SignerDetailRow(label: l10n.toAddress, value: 'TWd4qCEUYAJgLtSpQ2dK7wY9nMxR38uQz'),
        ])),
      ],
    );
  }
}

/// C17 风险警告.
class SignerRiskScreen extends StatelessWidget {
  const SignerRiskScreen({super.key});

  /// The rejected request's raw payload (canned demo data, hex-encoded).
  static const _rawTxHex =
      '0a021f8b220899c14e3b5d2a77e340b8b2d8a8f1335a760802126e0a3174797065'
      '2e676f6f676c65617069732e636f6d2f70726f746f636f6c2e54726967676572'
      '536d617274436f6e747261637412390a15419f2d3c7a44e1b06f8c55d2e4a97b'
      '318d6fa02c1e1215418b44f7d21c39aa66e05f2b90d34c7e81a5f30d6b188094'
      'ebdc0370d8b2d4a8f133';

  Future<void> _showRawTx(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: SignerColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: SignerColors.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 14),
            Text(l10n.viewRawTxData, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: SignerColors.text)),
            const SizedBox(height: 6),
            const Text('REQ-9AB301 · TRON', style: TextStyle(fontSize: 12, fontFamily: KtFonts.mono, color: Color(0xFF5A616C))),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: SignerColors.surface2, borderRadius: BorderRadius.circular(12)),
              child: const SelectableText(_rawTxHex, style: TextStyle(fontSize: 12, height: 1.6, fontFamily: KtFonts.mono, color: SignerColors.text2)),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KtScreen(
      theme: _t,
      gap: 24,
      navBar: KtNavBar(title: l10n.riskWarningTitle, theme: _t, leading: Icons.close, onBack: () => Navigator.of(context).maybePop()),
      bottom: Column(children: [
        SizedBox(width: double.infinity, height: 52, child: OutlinedButton(onPressed: () => context.go('/home'), style: OutlinedButton.styleFrom(backgroundColor: SignerColors.surface, side: const BorderSide(color: SignerColors.border), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text(l10n.backToHome, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: SignerColors.text)))),
        const SizedBox(height: 12),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _showRawTx(context),
          child: Text(l10n.viewRawTxData, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: SignerColors.text2)),
        ),
      ]),
      children: [
        const SizedBox(height: 8),
        Center(child: Container(width: 96, height: 96, decoration: BoxDecoration(color: SignerColors.danger.withValues(alpha: 0.08), shape: BoxShape.circle), child: const Icon(Icons.dangerous, size: 48, color: SignerColors.danger))),
        Column(children: [
          Text(l10n.signingBlocked, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: SignerColors.danger)),
          const SizedBox(height: 8),
          Text(l10n.signingBlockedDesc, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, height: 1.6, color: SignerColors.text2)),
        ]),
        _card(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.description, size: 18, color: SignerColors.danger),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l10n.unknownContractCallDetected('approve'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: SignerColors.text)),
            const SizedBox(height: 4),
            Text(l10n.unknownContractCallDesc, style: const TextStyle(fontSize: 12, height: 1.5, color: SignerColors.text2)),
          ])),
        ])),
      ],
    );
  }
}

/// C8 身份验证.
class SignerAuthScreen extends StatelessWidget {
  const SignerAuthScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KtScreen(
      theme: _t,
      gap: 28,
      navBar: KtNavBar(title: l10n.authTitle, theme: _t, onBack: () => Navigator.of(context).maybePop()),
      bottom: Column(children: [
        KtPrimaryButton(label: l10n.useFaceIdVerify, style: KtButtonStyle.signer, onPressed: () => context.push('/result-qr')),
        const SizedBox(height: 12),
        // Alternate auth path: same destination as the Face ID button.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.push('/result-qr'),
          child: Text(l10n.useDevicePasscode, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: SignerColors.text2)),
        ),
      ]),
      children: [
        const SizedBox(height: 24),
        Center(child: Container(width: 112, height: 112, decoration: BoxDecoration(color: SignerColors.surface, borderRadius: BorderRadius.circular(56), border: Border.all(color: SignerColors.border)), child: const Icon(Icons.face, size: 56, color: SignerColors.blue))),
        Column(children: [
          Text(l10n.verifyToSign, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: SignerColors.text)),
          const SizedBox(height: 10),
          Text(l10n.verifyToSignDesc, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, height: 1.6, color: SignerColors.text2)),
        ]),
        _card(Column(children: [_kv(l10n.amountLabel, '120.00 USDT', mono: true), const SizedBox(height: 8), _kv(l10n.requestId, 'REQ-7F3A2C', mono: true)])),
      ],
    );
  }
}

/// C9 签名结果二维码.
class SignerResultQrScreen extends StatelessWidget {
  const SignerResultQrScreen({super.key});

  /// Destructive confirm: voiding invalidates the shown signature QR, then
  /// returns to the offline home with a confirmation snackbar.
  Future<void> _confirmVoid(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SignerColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.voidSignatureTitle, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: SignerColors.text)),
        content: Text(l10n.voidSignatureDesc, style: const TextStyle(fontSize: 14, height: 1.6, color: SignerColors.text2)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.actionCancel, style: const TextStyle(color: SignerColors.text2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.voidThisSignature, style: const TextStyle(color: SignerColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.signatureVoided)));
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KtScreen(
      theme: _t,
      gap: 16,
      navBar: KtNavBar(title: l10n.signComplete, theme: _t),
      bottom: Column(children: [
        KtPrimaryButton(label: l10n.done, style: KtButtonStyle.signer, onPressed: () => context.go('/home')),
        const SizedBox(height: 12),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _confirmVoid(context),
          child: Text(l10n.voidThisSignature, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: SignerColors.danger)),
        ),
      ]),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: Column(children: [
            const KtQrPlaceholder(size: 220),
            const SizedBox(height: 14),
            Text(l10n.dynamicShard(2, 6), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF626B7A))),
            const SizedBox(height: 8),
            const ShardProgressBar(received: 2, total: 6, color: WalletColors.green, trackColor: WalletColors.border),
          ]),
        ),
        Center(child: Text(l10n.scanResultInstruction, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: SignerColors.text2))),
      ],
    );
  }
}

/// C10 地址导出.
class SignerAddressExportScreen extends StatefulWidget {
  const SignerAddressExportScreen({super.key});
  @override
  State<SignerAddressExportScreen> createState() => _SignerAddressExportScreenState();
}

class _SignerAddressExportScreenState extends State<SignerAddressExportScreen> {
  static const _addrs = [
    (ChainColors.ethereum, 'Ethereum', '0x8f3C2a…7E19bE1', "m/44'/60'/0'/0/0"),
    (ChainColors.polygon, 'Polygon', '0x8f3C2a…7E19bE1', "m/44'/60'/0'/0/0"),
    (ChainColors.tron, 'TRON', 'TQm9…L3kFa', "m/44'/195'/0'/0/0"),
    (ChainColors.solana, 'Solana', '6yKp…Vr2W', "m/44'/501'/0'"),
  ];

  int _seg = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = [l10n.allAddresses, 'Ethereum', 'Polygon'];
    final visible = _seg == 0 ? _addrs : _addrs.where((a) => a.$2 == options[_seg]).toList();
    return KtScreen(
      theme: _t,
      gap: 16,
      navBar: KtNavBar(title: l10n.exportPublicAddress, theme: _t, onBack: () => Navigator.of(context).maybePop()),
      bottom: KtPrimaryButton(label: l10n.done, style: KtButtonStyle.signer, onPressed: () => context.go('/home')),
      children: [
        KtSegmented(theme: _t, options: options, selected: _seg, onChanged: (i) => setState(() => _seg = i)),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: Column(children: [
            const KtQrPlaceholder(size: 200),
            const SizedBox(height: 12),
            Text(l10n.exportQrCaption(visible.length), style: const TextStyle(fontSize: 12, color: Color(0xFF626B7A))),
          ]),
        ),
        _card(Column(children: [
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            Row(children: [
              _Dot(visible[i].$1, size: 8),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(visible[i].$2, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: SignerColors.text)),
                const SizedBox(height: 3),
                Text(visible[i].$4, style: const TextStyle(fontSize: 11, fontFamily: KtFonts.mono, color: Color(0xFF5A616C))),
              ])),
              Text(visible[i].$3, style: const TextStyle(fontSize: 12, fontFamily: KtFonts.mono, color: SignerColors.text2)),
              const SizedBox(width: 8),
              const Icon(Icons.qr_code, size: 16, color: SignerColors.text2),
            ]),
          ],
        ])),
      ],
    );
  }
}
