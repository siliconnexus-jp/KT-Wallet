import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../l10n/app_localizations.dart';
import '../state/locale_controller.dart';

const _t = AppTheme.signer;
Widget _card(Widget child, {EdgeInsets padding = const EdgeInsets.all(16)}) =>
    Container(padding: padding, decoration: BoxDecoration(color: SignerColors.surface, borderRadius: BorderRadius.circular(14)), child: child);

Widget _switch(bool on) => Container(
      width: 44, height: 26, padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: on ? SignerColors.ok : SignerColors.surface2, borderRadius: BorderRadius.circular(13)),
      child: Align(alignment: on ? Alignment.centerRight : Alignment.centerLeft, child: Container(width: 22, height: 22, decoration: BoxDecoration(color: on ? const Color(0xFF0A0C0F) : const Color(0xFF5A616C), shape: BoxShape.circle))),
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
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 12),
        Container(width: 36, height: 4, decoration: BoxDecoration(color: SignerColors.border, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            Text(l10n.displayLanguage, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: SignerColors.text)),
          ]),
        ),
        const SizedBox(height: 8),
        for (final (label, locale) in options)
          ListTile(
            title: Text(label, style: const TextStyle(fontSize: 15, color: SignerColors.text)),
            trailing: (locale?.languageCode == current)
                ? const Icon(Icons.check, size: 20, color: SignerColors.ok)
                : null,
            onTap: () {
              controller.setLocale(locale);
              Navigator.of(ctx).pop();
            },
          ),
        const SizedBox(height: 12),
      ]),
    ),
  );
}

/// Confirms leaving signer mode; on confirm the combined installer returns to
/// the device-mode picker. Only reachable when a [DeviceModeScope] is present
/// (i.e. embedded in the single-installer app — never in the standalone build).
Future<void> _confirmDeviceModeSwitch(BuildContext context, DeviceModeScope scope) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: SignerColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(l10n.deviceModeSwitchTitle, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: SignerColors.text)),
      content: Text(l10n.deviceModeSwitchDesc, style: const TextStyle(fontSize: 14, height: 1.6, color: SignerColors.text2)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.actionCancel, style: const TextStyle(color: SignerColors.text2)),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.actionConfirm, style: const TextStyle(color: SignerColors.danger)),
        ),
      ],
    ),
  );
  if (confirmed == true) scope.exitMode();
}

/// C18 签名记录.
class SignerRecordsScreen extends StatelessWidget {
  const SignerRecordsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rows = <(IconData, String, String, String, String, Color)>[
      (Icons.north_east, 'Token Transfer · TRON', '14:35 · REQ-7F3A2C', '120.00 USDT', l10n.stateSigned, SignerColors.ok),
      (Icons.north_east, 'Transfer · Ethereum', '09:18 · REQ-8D22E1', '0.25 ETH', l10n.stateSigned, SignerColors.ok),
      (Icons.block, '${l10n.unknownContractCallLabel} · TRON', '07-08 · REQ-9AB301', '—', l10n.stateRejected, SignerColors.danger),
      (Icons.schedule, 'Token Transfer · Polygon', '07-02 · REQ-1C55A7', '300 USDT', l10n.stateExpired, SignerColors.text2),
    ];
    return KtScreen(
      theme: _t,
      gap: 16,
      navBar: KtNavBar(title: l10n.signRecords, theme: _t, onBack: () => Navigator.of(context).maybePop()),
      children: [
        KtSegmented(theme: _t, options: [l10n.filterAll, l10n.stateSigned, l10n.stateRejected, l10n.stateExpired], selected: 0),
        _card(Column(children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            () {
              final (icon, title, sub, amt, state, color) = rows[i];
              return Row(children: [
                Container(width: 34, height: 34, decoration: BoxDecoration(color: SignerColors.surface2, borderRadius: BorderRadius.circular(17)), child: Icon(icon, size: 15, color: color)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: SignerColors.text)),
                  const SizedBox(height: 3),
                  Text(sub, style: const TextStyle(fontSize: 11, fontFamily: KtFonts.mono, color: Color(0xFF5A616C))),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(amt, style: const TextStyle(fontSize: 12, fontFamily: KtFonts.mono, color: SignerColors.text)),
                  const SizedBox(height: 3),
                  Text(state, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color)),
                ]),
              ]);
            }(),
          ],
        ])),
      ],
    );
  }
}

/// C19 钱包管理.
class SignerWalletManageScreen extends StatelessWidget {
  const SignerWalletManageScreen({super.key});
  Widget _row(IconData icon, String label, String sub, {bool danger = false}) => Row(children: [
        Icon(icon, size: 19, color: danger ? SignerColors.danger : SignerColors.text2),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: danger ? SignerColors.danger : SignerColors.text)),
          if (sub.isNotEmpty) ...[const SizedBox(height: 2), Text(sub, style: const TextStyle(fontSize: 12, color: Color(0xFF5A616C)))],
        ])),
        const Icon(Icons.chevron_right, size: 16, color: Color(0xFF5A616C)),
      ]);
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KtScreen(
      theme: _t,
      gap: 16,
      navBar: KtNavBar(title: l10n.walletManage, theme: _t, onBack: () => Navigator.of(context).maybePop()),
      children: [
        _card(Row(children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(color: SignerColors.surface2, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.wallet, size: 24, color: SignerColors.ok)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l10n.walletMainName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: SignerColors.text)),
            const SizedBox(height: 4),
            Text('WLT-3E8A91 · ${l10n.walletCreatedOn('2026-06-07')}', style: const TextStyle(fontSize: 12, fontFamily: KtFonts.mono, color: Color(0xFF5A616C))),
          ])),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: SignerColors.ok.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(999)), child: Text(l10n.backedUp, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: SignerColors.ok))),
        ])),
        _card(Column(children: [
          _row(Icons.edit, l10n.editWalletName, ''),
          const SizedBox(height: 16),
          _row(Icons.checklist, l10n.mnemonicBackupCheck, l10n.mnemonicBackupCheckDesc),
          const SizedBox(height: 16),
          _row(Icons.qr_code, l10n.exportPublicAddress, ''),
        ])),
        Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: SignerColors.danger.withValues(alpha: 0.2))),
          child: _card(Column(children: [
            _row(Icons.delete_outline, l10n.deleteWallet, l10n.deleteWalletReqDesc, danger: true),
            const SizedBox(height: 16),
            _row(Icons.dangerous, l10n.destroyAllData, l10n.destroyAllDataDesc, danger: true),
          ])),
        ),
      ],
    );
  }
}

/// C20 安全设置.
class SignerSecuritySettingsScreen extends StatelessWidget {
  const SignerSecuritySettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeController = LocaleScope.of(context);
    final modeScope = DeviceModeScope.maybeOf(context);
    Widget toggleRow(IconData icon, String label, String sub, bool on) => Row(children: [
          Icon(icon, size: 19, color: SignerColors.text2),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: SignerColors.text)),
            if (sub.isNotEmpty) ...[const SizedBox(height: 2), Text(sub, style: const TextStyle(fontSize: 12, color: Color(0xFF5A616C)))],
          ])),
          _switch(on),
        ]);
    return KtScreen(
      theme: _t,
      gap: 16,
      navBar: KtNavBar(title: l10n.securitySettingsTitle, theme: _t, onBack: () => Navigator.of(context).maybePop()),
      children: [
        Text(l10n.verificationPolicy, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: SignerColors.text2)),
        _card(Column(children: [
          toggleRow(Icons.face, l10n.checkBiometric, l10n.biometricUsageDesc, true),
          const SizedBox(height: 16),
          toggleRow(Icons.edit, l10n.verifyEverySign, l10n.verifyEverySignDesc, true),
        ])),
        Text(l10n.accessSection, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: SignerColors.text2)),
        _card(Column(children: [
          Row(children: [
            const Icon(Icons.lock, size: 19, color: SignerColors.text2),
            const SizedBox(width: 12),
            Expanded(child: Text(l10n.changeAppPassword, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: SignerColors.text))),
            const Icon(Icons.chevron_right, size: 16, color: Color(0xFF5A616C)),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            const Icon(Icons.no_photography, size: 19, color: SignerColors.text2),
            const SizedBox(width: 12),
            Expanded(child: Text(l10n.screenCaptureProtection, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: SignerColors.text))),
            Text(l10n.statusEnabled, style: const TextStyle(fontSize: 13, color: SignerColors.ok)),
          ]),
          const SizedBox(height: 16),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _pickLanguage(context),
            child: Row(children: [
              const Icon(Icons.language, size: 19, color: SignerColors.text2),
              const SizedBox(width: 12),
              Expanded(child: Text(l10n.displayLanguage, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: SignerColors.text))),
              Text(_languageLabel(l10n, localeController.locale), style: const TextStyle(fontSize: 13, color: SignerColors.text2)),
              const Icon(Icons.chevron_right, size: 16, color: Color(0xFF5A616C)),
            ]),
          ),
          // Only when embedded in the combined single-installer app: switch
          // back to the device-mode picker. Absent in the standalone build.
          if (modeScope != null) ...[
            const SizedBox(height: 16),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _confirmDeviceModeSwitch(context, modeScope),
              child: Row(children: [
                const Icon(Icons.devices_outlined, size: 19, color: SignerColors.text2),
                const SizedBox(width: 12),
                Expanded(child: Text(l10n.deviceMode, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: SignerColors.text))),
                Text(l10n.deviceModeSigner, style: const TextStyle(fontSize: 13, color: SignerColors.text2)),
                const Icon(Icons.chevron_right, size: 16, color: Color(0xFF5A616C)),
              ]),
            ),
          ],
        ])),
      ],
    );
  }
}

/// C21 删除钱包.
class SignerDeleteScreen extends StatelessWidget {
  const SignerDeleteScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KtScreen(
      theme: _t,
      gap: 20,
      navBar: KtNavBar(title: l10n.deleteWallet, theme: _t, onBack: () => Navigator.of(context).maybePop()),
      bottom: Column(children: [
        SizedBox(width: double.infinity, height: 52, child: FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFF0A0C0F)), label: Text(l10n.permanentlyDeleteWallet, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF0A0C0F))), style: FilledButton.styleFrom(backgroundColor: SignerColors.danger, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
        const SizedBox(height: 12),
        Text(l10n.actionCancel, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: SignerColors.text2)),
      ]),
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (final (label, done, n) in [(l10n.stepPassword, true, '1'), (l10n.checkBiometric, true, '2'), (l10n.stepConfirmText, false, '3')]) ...[
            Row(children: [
              Container(width: 20, height: 20, alignment: Alignment.center, decoration: BoxDecoration(color: done ? SignerColors.ok : SignerColors.surface2, shape: BoxShape.circle), child: done ? const Icon(Icons.check, size: 11, color: Color(0xFF0A0C0F)) : Text(n, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: SignerColors.text2))),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: done ? SignerColors.ok : SignerColors.text2)),
            ]),
            if (n != '3') Container(width: 20, height: 1.5, margin: const EdgeInsets.symmetric(horizontal: 6), color: SignerColors.border),
          ],
        ]),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: SignerColors.danger.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [const Icon(Icons.warning_amber_rounded, size: 18, color: SignerColors.danger), const SizedBox(width: 8), Text(l10n.irreversibleAction, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: SignerColors.danger))]),
            const SizedBox(height: 10),
            Text(l10n.deleteWalletWarningDesc, style: const TextStyle(fontSize: 13, height: 1.6, color: SignerColors.text2)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l10n.typeToConfirmDelete, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: SignerColors.text2)),
          const SizedBox(height: 8),
          Container(
            height: 50, padding: const EdgeInsets.symmetric(horizontal: 14), alignment: Alignment.centerLeft,
            decoration: BoxDecoration(color: SignerColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: SignerColors.danger, width: 1.5)),
            child: const Text('删除钱', style: TextStyle(fontSize: 15, color: SignerColors.text)),
          ),
        ]),
      ],
    );
  }
}
