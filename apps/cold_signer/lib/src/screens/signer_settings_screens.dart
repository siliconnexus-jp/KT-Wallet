import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../l10n/app_localizations.dart';
import '../security/biometric_auth.dart';
import 'signer_signing_screens.dart' show SignerPinEntrySheet;
import '../state/locale_controller.dart';
import '../state/signer_wallet_controller.dart';

const _t = AppTheme.signer;
Widget _card(Widget child, {EdgeInsets padding = const EdgeInsets.all(16)}) =>
    Container(
      padding: padding,
      decoration: BoxDecoration(
        color: SignerColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );

Widget _switch(bool on) => Container(
  width: 44,
  height: 26,
  padding: const EdgeInsets.all(2),
  decoration: BoxDecoration(
    color: on ? SignerColors.ok : SignerColors.surface2,
    borderRadius: BorderRadius.circular(13),
  ),
  child: Align(
    alignment: on ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: on ? const Color(0xFF0A0C0F) : const Color(0xFF5A616C),
        shape: BoxShape.circle,
      ),
    ),
  ),
);

/// Native display name for each supported language (shown in its own script,
/// the platform convention). "System" is localized.
String _languageLabel(AppLocalizations l10n, Locale? locale) {
  switch (locale?.languageCode) {
    case 'zh':
      return '简体中文';
    case 'en':
      return 'English';
    case 'ja':
      return '日本語';
    default:
      return l10n.languageSystem;
  }
}

/// Language picker bottom sheet, driving [LocaleScope]/[LocaleController].
Future<void> _pickLanguage(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final controller = LocaleScope.of(context);
  final current = controller.locale?.languageCode;
  final options = <(String, Locale?)>[
    (l10n.languageSystem, null),
    ('简体中文', const Locale('zh')),
    ('English', const Locale('en')),
    ('日本語', const Locale('ja')),
  ];
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: SignerColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: SignerColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  l10n.displayLanguage,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: SignerColors.text,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final (label, locale) in options)
            ListTile(
              title: Text(
                label,
                style: const TextStyle(fontSize: 15, color: SignerColors.text),
              ),
              trailing: (locale?.languageCode == current)
                  ? const Icon(Icons.check, size: 20, color: SignerColors.ok)
                  : null,
              onTap: () async {
                try {
                  await controller.setLocale(locale);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                } on Object {
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(l10n.settingsSaveFailed)),
                  );
                }
              },
            ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}

/// Confirms leaving signer mode; on confirm the combined installer returns to
/// the device-mode picker. Only reachable when a [DeviceModeScope] is present
/// (i.e. embedded in the single-installer app — never in the standalone build).
Future<void> _confirmDeviceModeSwitch(
  BuildContext context,
  DeviceModeScope scope,
) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => KtConfirmDialog(
      title: l10n.deviceModeSwitchTitle,
      message: l10n.deviceModeSwitchDesc,
      cancelLabel: l10n.actionCancel,
      confirmLabel: l10n.actionConfirm,
      theme: AppTheme.signer,
      icon: Icons.phonelink_setup_rounded,
      iconColor: SignerColors.warn,
    ),
  );
  if (confirmed != true) return;
  try {
    await scope.exitMode();
  } on Object {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.deviceModeSaveFailed)));
  }
}

/// C18 签名记录.
class SignerRecordsScreen extends StatefulWidget {
  const SignerRecordsScreen({super.key});
  @override
  State<SignerRecordsScreen> createState() => _SignerRecordsScreenState();
}

class _SignerRecordsScreenState extends State<SignerRecordsScreen> {
  int _filter = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = [
      l10n.filterAll,
      l10n.stateSigned,
      l10n.stateRejected,
      l10n.stateExpired,
    ];
    final all = <(IconData, String, String, String, String, Color)>[
      (
        Icons.north_east,
        'Token Transfer · TRON',
        '14:35 · REQ-7F3A2C',
        '120.00 USDT',
        l10n.stateSigned,
        SignerColors.ok,
      ),
      (
        Icons.north_east,
        'Transfer · Ethereum',
        '09:18 · REQ-8D22E1',
        '0.25 ETH',
        l10n.stateSigned,
        SignerColors.ok,
      ),
      (
        Icons.block,
        '${l10n.unknownContractCallLabel} · TRON',
        '07-08 · REQ-9AB301',
        '—',
        l10n.stateRejected,
        SignerColors.danger,
      ),
      (
        Icons.schedule,
        'Token Transfer · Polygon',
        '07-02 · REQ-1C55A7',
        '300 USDT',
        l10n.stateExpired,
        SignerColors.text2,
      ),
    ];
    final rows = _filter == 0
        ? all
        : all.where((r) => r.$5 == options[_filter]).toList();
    final compactLarge =
        MediaQuery.sizeOf(context).width < 360 &&
        MediaQuery.textScalerOf(context).scale(12) >= 20;
    return KtScreen(
      theme: _t,
      gap: 16,
      navBar: KtNavBar(
        title: l10n.signRecords,
        theme: _t,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      children: [
        KtSegmented(
          theme: _t,
          options: options,
          selected: _filter,
          onChanged: (i) => setState(() => _filter = i),
        ),
        _card(
          Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                () {
                  final (icon, title, sub, amt, state, color) = rows[i];
                  return Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: SignerColors.surface2,
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: Icon(icon, size: 15, color: color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: SignerColors.text,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              sub,
                              style: const TextStyle(
                                fontSize: 11,
                                fontFamily: KtFonts.mono,
                                color: SignerColors.text2,
                              ),
                            ),
                            if (compactLarge) ...[
                              const SizedBox(height: 6),
                              Text(
                                amt,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontFamily: KtFonts.mono,
                                  color: SignerColors.text,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                state,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: color,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (!compactLarge)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              amt,
                              style: const TextStyle(
                                fontSize: 12,
                                fontFamily: KtFonts.mono,
                                color: SignerColors.text,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              state,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: color,
                              ),
                            ),
                          ],
                        ),
                    ],
                  );
                }(),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// C19 钱包管理.
class SignerWalletManageScreen extends StatefulWidget {
  const SignerWalletManageScreen({super.key});
  @override
  State<SignerWalletManageScreen> createState() =>
      _SignerWalletManageScreenState();
}

class _SignerWalletManageScreenState extends State<SignerWalletManageScreen> {
  /// Gallery-only rename fallback when no live wallet controller is present.
  String? _name;
  bool _reviewingBackup = false;

  Widget _row(
    IconData icon,
    String label,
    String sub, {
    bool danger = false,
    VoidCallback? onTap,
  }) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          Icon(
            icon,
            size: 19,
            color: danger ? SignerColors.danger : SignerColors.text2,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: danger ? SignerColors.danger : SignerColors.text,
                  ),
                ),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: const TextStyle(
                      fontSize: 12,
                      color: SignerColors.text2,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 16, color: SignerColors.text2),
        ],
      ),
    ),
  );

  Future<void> _editName() async {
    final l10n = AppLocalizations.of(context);
    // Not disposed on purpose: the dialog's exit animation still reads it
    // after pop (disposing here crashes mid-animation); it is GC'd with the
    // route.
    final controller = TextEditingController(
      text: _name ?? l10n.walletMainName,
    );
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => KtDialog(
        title: l10n.editWalletName,
        theme: AppTheme.signer,
        icon: Icons.edit_outlined,
        iconColor: SignerColors.ok,
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          style: const TextStyle(fontSize: 15, color: SignerColors.text),
          decoration: const InputDecoration(
            counterStyle: TextStyle(fontSize: 11, color: Color(0xFF5A616C)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: SignerColors.border),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: SignerColors.ok),
            ),
          ),
        ),
        actions: [
          KtDialogAction(
            key: const ValueKey('kt-dialog-cancel'),
            label: l10n.actionCancel,
            theme: AppTheme.signer,
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          KtDialogAction(
            key: const ValueKey('kt-dialog-confirm'),
            label: l10n.actionSave,
            theme: AppTheme.signer,
            style: KtDialogActionStyle.primary,
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && mounted) {
      final wallet = SignerWalletScope.maybeOf(context);
      if (wallet?.hasWallet ?? false) {
        await wallet!.renameWallet(result);
      } else {
        setState(() => _name = result);
      }
    }
  }

  Future<void> _reviewBackup() async {
    if (_reviewingBackup) return;
    final wallet = SignerWalletScope.maybeOf(context);
    if (wallet == null || !wallet.hasWallet) {
      // Explicit debug gallery snapshot only.
      await context.push('/mnemonic-show');
      return;
    }
    setState(() => _reviewingBackup = true);
    try {
      final flow = await wallet.exportMnemonicForReview();
      if (!mounted) return;
      await context.push('/mnemonic-show', extra: flow);
    } catch (_) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l10n.mnemonicReviewFailed)));
    } finally {
      if (mounted) setState(() => _reviewingBackup = false);
    }
  }

  String _walletIdLabel(String? walletId) {
    if (walletId == null || walletId.isEmpty) return 'WLT-3E8A91';
    if (walletId.length <= 14) return walletId;
    return '${walletId.substring(0, 8)}…${walletId.substring(walletId.length - 4)}';
  }

  String _createdDate(int? epochSeconds) {
    if (epochSeconds == null) return '2026-06-07';
    return DateFormat('yyyy-MM-dd').format(
      DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000).toLocal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final wallet = SignerWalletScope.maybeOf(context);
    final metadata = wallet?.metadata;
    final largeText = MediaQuery.textScalerOf(context).scale(12) >= 20;
    return KtScreen(
      theme: _t,
      gap: 16,
      navBar: KtNavBar(
        title: l10n.walletManage,
        theme: _t,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      children: [
        _card(
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: SignerColors.surface2,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.wallet,
                  size: 24,
                  color: SignerColors.ok,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _name ?? metadata?.name ?? l10n.walletMainName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: SignerColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_walletIdLabel(metadata?.walletId)} · '
                      '${l10n.walletCreatedOn(_createdDate(metadata?.createdAt))}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: KtFonts.mono,
                        color: SignerColors.text2,
                      ),
                    ),
                    if (largeText) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: SignerColors.ok.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            l10n.backedUp,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: SignerColors.ok,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!largeText)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: SignerColors.ok.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    l10n.backedUp,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: SignerColors.ok,
                    ),
                  ),
                ),
            ],
          ),
        ),
        _card(
          Column(
            children: [
              _row(Icons.edit, l10n.editWalletName, '', onTap: _editName),
              const SizedBox(height: 16),
              // Backup spot-check re-enters the mnemonic show → verify flow.
              _row(
                Icons.checklist,
                l10n.mnemonicBackupCheck,
                _reviewingBackup
                    ? l10n.authTitle
                    : l10n.mnemonicBackupCheckDesc,
                onTap: _reviewingBackup ? null : _reviewBackup,
              ),
              const SizedBox(height: 16),
              _row(
                Icons.qr_code,
                l10n.exportPublicAddress,
                '',
                onTap: () => context.push('/export'),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: SignerColors.danger.withValues(alpha: 0.2),
            ),
          ),
          child: _card(
            Column(
              children: [
                _row(
                  Icons.delete_outline,
                  l10n.deleteWallet,
                  l10n.deleteWalletReqDesc,
                  danger: true,
                  onTap: () => context.push('/delete'),
                ),
                const SizedBox(height: 16),
                // No dedicated destroy-everything flow exists; the C21 delete flow
                // is the closest destructive path in the demo signer.
                _row(
                  Icons.dangerous,
                  l10n.destroyAllData,
                  l10n.destroyAllDataDesc,
                  danger: true,
                  onTap: () => context.push('/delete'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// C20 安全设置.
class SignerSecuritySettingsScreen extends StatefulWidget {
  const SignerSecuritySettingsScreen({super.key});
  @override
  State<SignerSecuritySettingsScreen> createState() =>
      _SignerSecuritySettingsScreenState();
}

class _SignerSecuritySettingsScreenState
    extends State<SignerSecuritySettingsScreen> {
  bool _biometricOn = true;
  bool _loadedPolicy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadedPolicy) return;
    _loadedPolicy = true;
    final controller = SignerWalletScope.maybeOf(context);
    if (controller?.hasWallet == true) {
      _biometricOn = controller!.biometricEnabled;
    }
  }

  Future<void> _toggleBiometric() async {
    final controller = SignerWalletScope.maybeOf(context);
    final next = !_biometricOn;
    if (controller?.hasWallet != true) {
      setState(() => _biometricOn = next);
      return;
    }
    final changed = await controller!.setBiometricEnabled(next);
    if (!mounted) return;
    if (changed) {
      setState(() => _biometricOn = next);
    } else {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).biometricUnavailable),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeController = LocaleScope.of(context);
    final modeScope = DeviceModeScope.maybeOf(context);
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    Widget toggleRow(
      IconData icon,
      String label,
      String sub,
      bool on, {
      Key? key,
      VoidCallback? onTap,
    }) => GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Icon(icon, size: 19, color: SignerColors.text2),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: SignerColors.text,
                    ),
                  ),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF5A616C),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _switch(on),
          ],
        ),
      ),
    );
    return KtScreen(
      theme: _t,
      gap: 16,
      navBar: KtNavBar(
        title: l10n.securitySettingsTitle,
        theme: _t,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      children: [
        Text(
          l10n.verificationPolicy,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            color: SignerColors.text2,
          ),
        ),
        _card(
          Column(
            children: [
              toggleRow(
                Icons.face,
                l10n.checkBiometric,
                l10n.biometricUsageDesc,
                _biometricOn,
                key: const ValueKey('toggle-biometric'),
                onTap: _toggleBiometric,
              ),
              const SizedBox(height: 16),
              // Per-sign verification is mandatory in V1 ("不可关闭"): the switch is
              // real but policy-locked — tapping it explains instead of toggling.
              toggleRow(
                Icons.edit,
                l10n.verifyEverySign,
                l10n.verifyEverySignDesc,
                true,
                key: const ValueKey('toggle-verify-every-sign'),
                onTap: () => ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(
                    SnackBar(content: Text(l10n.verifyEverySignDesc)),
                  ),
              ),
            ],
          ),
        ),
        Text(
          l10n.accessSection,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            color: SignerColors.text2,
          ),
        ),
        _card(
          Column(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => context.push('/set-password'),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.lock,
                        size: 19,
                        color: SignerColors.text2,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.changeAppPassword,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: SignerColors.text,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: SignerColors.text2,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(
                    Icons.no_photography,
                    size: 19,
                    color: SignerColors.text2,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.screenCaptureProtection,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: SignerColors.text,
                      ),
                    ),
                  ),
                  Text(
                    l10n.statusEnabled,
                    style: const TextStyle(
                      fontSize: 13,
                      color: SignerColors.ok,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _pickLanguage(context),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: largeText
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.language,
                                  size: 19,
                                  color: SignerColors.text2,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    l10n.displayLanguage,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: SignerColors.text,
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right,
                                  size: 16,
                                  color: SignerColors.text2,
                                ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 31, top: 6),
                              child: Text(
                                _languageLabel(l10n, localeController.locale),
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: SignerColors.text2,
                                ),
                              ),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            const Icon(
                              Icons.language,
                              size: 19,
                              color: SignerColors.text2,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                l10n.displayLanguage,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: SignerColors.text,
                                ),
                              ),
                            ),
                            Text(
                              _languageLabel(l10n, localeController.locale),
                              style: const TextStyle(
                                fontSize: 13,
                                color: SignerColors.text2,
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              size: 16,
                              color: SignerColors.text2,
                            ),
                          ],
                        ),
                ),
              ),
              // Only when embedded in the combined single-installer app: switch
              // back to the device-mode picker. Absent in the standalone build.
              if (modeScope != null) ...[
                const SizedBox(height: 16),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _confirmDeviceModeSwitch(context, modeScope),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.devices_outlined,
                          size: 19,
                          color: SignerColors.text2,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            l10n.deviceMode,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: SignerColors.text,
                            ),
                          ),
                        ),
                        Text(
                          l10n.deviceModeSigner,
                          style: const TextStyle(
                            fontSize: 13,
                            color: SignerColors.text2,
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: SignerColors.text2,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// C21 删除钱包.
class SignerDeleteScreen extends StatefulWidget {
  const SignerDeleteScreen({super.key, this.auth});

  final BiometricAuth? auth;

  @override
  State<SignerDeleteScreen> createState() => _SignerDeleteScreenState();
}

class _SignerDeleteScreenState extends State<SignerDeleteScreen> {
  final _confirmationController = TextEditingController();
  bool _pinVerified = false;
  bool _deviceVerified = false;
  bool _busy = false;

  @override
  void dispose() {
    _confirmationController.dispose();
    super.dispose();
  }

  bool _phraseMatches(AppLocalizations l10n) =>
      _confirmationController.text.trim() ==
      l10n.deleteWalletConfirmationPhrase;

  Future<bool> _verifyPin(SignerWalletController controller) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SignerColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SignerPinEntrySheet(
        pinLock: controller.pinLock,
        title: l10n.enterPinToDelete,
      ),
    );
    if (!mounted || ok != true) return false;
    setState(() => _pinVerified = true);
    return true;
  }

  Future<bool> _verifyDevice(SignerWalletController controller) async {
    if (!controller.biometricEnabled) return true;
    final l10n = AppLocalizations.of(context);
    final outcome = await (widget.auth ?? BiometricAuth.instance).authenticate(
      reason: l10n.verifyToDeleteWallet,
    );
    if (!mounted) return false;
    if (outcome != BiometricOutcome.success) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(l10n.deleteAuthenticationFailed)),
        );
      return false;
    }
    setState(() => _deviceVerified = true);
    return true;
  }

  /// Destructive confirmation. In the live flow the confirm wipes the secure
  /// vault (mnemonic, metadata, PIN, lockout) and the anti-replay records;
  /// without a scope (gallery/goldens) it just returns to onboarding.
  Future<void> _confirmDelete() async {
    final l10n = AppLocalizations.of(context);
    final scopedController = SignerWalletScope.maybeOf(context);
    final controller = scopedController?.hasWallet == true
        ? scopedController
        : null;
    if (controller != null) {
      if (!_phraseMatches(l10n) || _busy) return;
      setState(() => _busy = true);
      final pinOk = await _verifyPin(controller);
      if (!mounted) return;
      if (!pinOk) {
        setState(() => _busy = false);
        return;
      }
      final deviceOk = await _verifyDevice(controller);
      if (!mounted) return;
      if (!deviceOk) {
        setState(() => _busy = false);
        return;
      }
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => KtConfirmDialog(
        title: l10n.irreversibleAction,
        message: l10n.deleteWalletWarningDesc,
        cancelLabel: l10n.actionCancel,
        confirmLabel: l10n.permanentlyDeleteWallet,
        theme: AppTheme.signer,
        icon: Icons.delete_forever_outlined,
        iconColor: SignerColors.danger,
        destructive: true,
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      if (controller != null) setState(() => _busy = false);
      return;
    }
    if (controller != null) {
      try {
        await controller.deleteWallet();
      } catch (_) {
        if (!mounted) return;
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(l10n.deleteWalletFailed)));
        return;
      }
    }
    if (!mounted) return;
    context.go('/welcome');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final scopedController = SignerWalletScope.maybeOf(context);
    final controller = scopedController?.hasWallet == true
        ? scopedController
        : null;
    final live = controller != null;
    final phraseMatches = _phraseMatches(l10n);
    final requiresDeviceAuth = controller?.biometricEnabled ?? false;
    return KtScreen(
      theme: _t,
      gap: 20,
      navBar: KtNavBar(
        title: l10n.deleteWallet,
        theme: _t,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      bottom: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: live && (!phraseMatches || _busy)
                  ? null
                  : _confirmDelete,
              icon: const Icon(
                Icons.delete_outline,
                size: 18,
                color: Color(0xFF0A0C0F),
              ),
              label: Text(
                l10n.permanentlyDeleteWallet,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0A0C0F),
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: SignerColors.danger,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).maybePop(),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Center(
                child: Text(
                  l10n.actionCancel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: SignerColors.text2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: largeText ? 12 : 0,
          runSpacing: 8,
          children: [
            for (final (label, done, n) in [
              (l10n.stepPassword, _pinVerified, '1'),
              if (requiresDeviceAuth)
                (l10n.checkBiometric, _deviceVerified, '2'),
              (
                l10n.stepConfirmText,
                phraseMatches,
                requiresDeviceAuth ? '3' : '2',
              ),
            ]) ...[
              Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: done ? SignerColors.ok : SignerColors.surface2,
                      shape: BoxShape.circle,
                    ),
                    child: done
                        ? const Icon(
                            Icons.check,
                            size: 11,
                            color: Color(0xFF0A0C0F),
                          )
                        : Text(
                            n,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: SignerColors.text2,
                            ),
                          ),
                  ),
                  const SizedBox(width: 6),
                  if (largeText)
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: done ? SignerColors.ok : SignerColors.text2,
                        ),
                      ),
                    )
                  else
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: done ? SignerColors.ok : SignerColors.text2,
                      ),
                    ),
                ],
              ),
              if (!largeText && n != (requiresDeviceAuth ? '3' : '2'))
                Container(
                  width: 20,
                  height: 1.5,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: SignerColors.border,
                ),
            ],
          ],
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: SignerColors.danger.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: SignerColors.danger,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.irreversibleAction,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: SignerColors.danger,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                l10n.deleteWalletWarningDesc,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: SignerColors.text2,
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.typeToConfirmDelete,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: SignerColors.text2,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('delete-confirmation-input'),
              controller: _confirmationController,
              enabled: live && !_busy,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(fontSize: 15, color: SignerColors.text),
              decoration: InputDecoration(
                hintText: l10n.deleteWalletConfirmationPhrase,
                filled: true,
                fillColor: SignerColors.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: SignerColors.danger),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: SignerColors.danger,
                    width: 1.5,
                  ),
                ),
              ),
              onChanged: (_) => setState(() {
                _pinVerified = false;
                _deviceVerified = false;
              }),
            ),
          ],
        ),
      ],
    );
  }
}
