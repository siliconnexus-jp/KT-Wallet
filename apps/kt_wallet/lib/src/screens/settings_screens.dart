import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../l10n/app_localizations.dart';
import '../state/locale_controller.dart';

Widget _switch(bool on, {VoidCallback? onTap}) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        width: 44, height: 26,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(color: on ? WalletColors.accent : const Color(0xFFE1E4EA), borderRadius: BorderRadius.circular(13)),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(width: 22, height: 22, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
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

/// W16 地址管理.
class AddressBookScreen extends StatefulWidget {
  const AddressBookScreen({super.key});
  @override
  State<AddressBookScreen> createState() => _AddressBookScreenState();
}

class _AddressBookScreenState extends State<AddressBookScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final contacts = <(String, String, String, String, Color)>[
      ('A', 'Alice', '0x71c8B2…9F3dA24', 'Ethereum', ChainColors.ethereum),
      ('B', l10n.contactBobExchange, 'TWd4qCEU…nMxR38uQz', 'TRON', ChainColors.tron),
      ('冷', l10n.contactColdBackup, '0x8f3C2a…7E19bE1', 'Polygon', ChainColors.polygon),
      ('D', 'Dana', '6yKp…Vr2W', 'Solana', ChainColors.solana),
    ];
    final q = _query.trim().toLowerCase();
    final results = q.isEmpty
        ? contacts
        : contacts.where((c) => c.$2.toLowerCase().contains(q) || c.$3.toLowerCase().contains(q) || c.$4.toLowerCase().contains(q)).toList();
    return KtScreen(
      gap: 16,
      navBar: KtNavBar(title: l10n.addressBookTitle, onBack: () => Navigator.of(context).maybePop(), trailing: Icons.add, onTrailing: () {}),
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: WalletColors.surface, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Icon(Icons.search, size: 18, color: WalletColors.text3),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(fontSize: 14, color: WalletColors.text),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: l10n.searchNameOrAddress,
                  hintStyle: const TextStyle(fontSize: 14, color: WalletColors.text3),
                ),
              ),
            ),
          ]),
        ),
        if (results.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text(l10n.noMatchingContacts, style: const TextStyle(fontSize: 14, color: WalletColors.text3))),
          )
        else
          KtCard(
            child: Column(children: [
              for (var i = 0; i < results.length; i++) ...[
                if (i > 0) const SizedBox(height: 16),
                Row(children: [
                  KtAvatar(color: const Color(0xFFF2F4F7), initial: results[i].$1, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(results[i].$2, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: WalletColors.text)),
                        const SizedBox(width: 8),
                        NetworkBadge(label: results[i].$4, dotColor: results[i].$5),
                      ]),
                      const SizedBox(height: 3),
                      Text(results[i].$3, style: const TextStyle(fontSize: 12, fontFamily: KtFonts.mono, color: WalletColors.text3)),
                    ]),
                  ),
                  const Icon(Icons.more_vert, size: 18, color: WalletColors.text3),
                ]),
              ],
            ]),
          ),
      ],
    );
  }
}

/// W17 Token 管理.
class TokenManageScreen extends StatefulWidget {
  const TokenManageScreen({super.key});
  @override
  State<TokenManageScreen> createState() => _TokenManageScreenState();
}

class _TokenManageScreenState extends State<TokenManageScreen> {
  static const _tokens = [
    (Color(0xFF26A17B), '₮', 'USDT', 'TRON · TRC-20'),
    (Color(0xFF26A17B), '₮', 'USDT', 'Ethereum · ERC-20'),
    (Color(0xFF2775CA), r'$', 'USDC', 'Solana · SPL'),
    (Color(0xFFF0B90B), 'B', 'BUSD', 'Ethereum · ERC-20'),
    (Color(0xFFFF007A), 'U', 'UNI', 'Ethereum · ERC-20'),
  ];
  final _enabled = [true, true, true, false, false];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KtScreen(
      gap: 16,
      navBar: KtNavBar(title: l10n.tokenManageTitle, onBack: () => Navigator.of(context).maybePop(), trailing: Icons.add, onTrailing: () {}),
      children: [
        KtCard(
          child: Column(children: [
            for (var i = 0; i < _tokens.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              Row(children: [
                KtAvatar(color: _tokens[i].$1, initial: _tokens[i].$2, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_tokens[i].$3, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: WalletColors.text)),
                    const SizedBox(height: 3),
                    Text(_tokens[i].$4, style: const TextStyle(fontSize: 12, color: WalletColors.text3)),
                  ]),
                ),
                _switch(_enabled[i], onTap: () => setState(() => _enabled[i] = !_enabled[i])),
              ]),
            ],
          ]),
        ),
      ],
    );
  }
}

/// W18 网络设置.
class NetworkSettingsScreen extends StatelessWidget {
  const NetworkSettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nets = <(Color, String, String, String, bool)>[
      (ChainColors.ethereum, 'Ethereum', 'eth-mainnet.g.alchemy.com', '86 ms', true),
      (ChainColors.polygon, 'Polygon', 'polygon-rpc.com', '112 ms', true),
      (ChainColors.tron, 'TRON', 'api.trongrid.io', '64 ms', true),
      (ChainColors.solana, 'Solana', 'api.mainnet-beta.solana.com', l10n.rpcTimeout, false),
    ];
    return KtScreen(
      gap: 16,
      navBar: KtNavBar(title: l10n.networkSettingsTitle, onBack: () => Navigator.of(context).maybePop()),
      children: [
        for (final (color, name, rpc, ms, ok) in nets)
          KtCard(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: WalletColors.text))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: (ok ? WalletColors.green : WalletColors.red).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(999)),
                  child: Text(ms, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: ok ? WalletColors.green : WalletColors.red)),
                ),
              ]),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l10n.rpcNode, style: const TextStyle(fontSize: 12, color: WalletColors.text3)),
                    const SizedBox(height: 2),
                    Text(rpc, style: const TextStyle(fontSize: 12, fontFamily: KtFonts.mono, color: WalletColors.text)),
                  ]),
                ),
                const Icon(Icons.chevron_right, size: 16, color: WalletColors.text3),
              ]),
            ]),
          ),
      ],
    );
  }
}

/// W19 安全设置.
class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});
  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  bool _appLock = true;
  bool _privacy = false;

  Future<void> _pickLanguage() async {
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
      backgroundColor: WalletColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(width: 36, height: 4, decoration: BoxDecoration(color: WalletColors.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Text(l10n.displayLanguage, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: WalletColors.text)),
            ]),
          ),
          const SizedBox(height: 8),
          for (final (label, locale) in options)
            ListTile(
              title: Text(label, style: const TextStyle(fontSize: 15, color: WalletColors.text)),
              trailing: (locale?.languageCode == current)
                  ? const Icon(Icons.check, size: 20, color: WalletColors.accent)
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

  /// Confirms leaving wallet mode; on confirm the combined installer returns
  /// to the device-mode picker. Only reachable when a [DeviceModeScope] is
  /// present (i.e. running inside the single-installer app).
  Future<void> _confirmDeviceModeSwitch(DeviceModeScope scope) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WalletColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.deviceModeSwitchTitle, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: WalletColors.text)),
        content: Text(l10n.deviceModeSwitchDesc, style: const TextStyle(fontSize: 14, height: 1.5, color: WalletColors.text2)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.actionCancel, style: const TextStyle(color: WalletColors.text2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.actionConfirm, style: const TextStyle(color: WalletColors.accent)),
          ),
        ],
      ),
    );
    if (confirmed == true) scope.exitMode();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeController = LocaleScope.of(context);
    final modeScope = DeviceModeScope.maybeOf(context);
    return KtScreen(
      gap: 16,
      navBar: KtNavBar(title: l10n.settingsSecurity, onBack: () => Navigator.of(context).maybePop()),
      children: [
        Text(l10n.accessControl, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: WalletColors.text2)),
        KtCard(
          child: Column(children: [
            _row(Icons.lock_outline, l10n.appLock, l10n.appLockDesc, _switch(_appLock, onTap: () => setState(() => _appLock = !_appLock))),
            const SizedBox(height: 16),
            _row(Icons.timer_outlined, l10n.autoLock, l10n.autoLockDesc, Row(mainAxisSize: MainAxisSize.min, children: [Text(l10n.autoLockValue, style: const TextStyle(fontSize: 13, color: WalletColors.text2)), const Icon(Icons.chevron_right, size: 16, color: WalletColors.text3)])),
            const SizedBox(height: 16),
            _row(Icons.visibility_off_outlined, l10n.privacyMode, l10n.privacyModeDesc, _switch(_privacy, onTap: () => setState(() => _privacy = !_privacy))),
          ]),
        ),
        Text(l10n.dataSection, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: WalletColors.text2)),
        KtCard(
          child: Column(children: [
            _SimpleRow(Icons.attach_money, l10n.fiatUnit, 'USD'),
            const SizedBox(height: 16),
            _SimpleRow(Icons.language, l10n.displayLanguage, _languageLabel(l10n, localeController.locale), onTap: _pickLanguage),
            // Only in the combined single-installer app: switch back to the
            // device-mode picker. Hidden in standalone/test setups.
            if (modeScope != null) ...[
              const SizedBox(height: 16),
              _SimpleRow(Icons.devices_outlined, l10n.deviceMode, l10n.modeWalletTitle, onTap: () => _confirmDeviceModeSwitch(modeScope)),
            ],
          ]),
        ),
        KtCard(
          child: _row(Icons.delete_outline, l10n.deleteWatchWallet, l10n.deleteWatchWalletDesc, const Icon(Icons.chevron_right, size: 16, color: WalletColors.text3), danger: true),
        ),
      ],
    );
  }

  static Widget _row(IconData icon, String label, String sub, Widget trailing, {bool danger = false}) => Row(children: [
        Icon(icon, size: 19, color: danger ? WalletColors.red : WalletColors.text2),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: danger ? WalletColors.red : WalletColors.text)),
            const SizedBox(height: 2),
            Text(sub, style: const TextStyle(fontSize: 12, color: WalletColors.text3)),
          ]),
        ),
        trailing,
      ]);
}

class _SimpleRow extends StatelessWidget {
  const _SimpleRow(this.icon, this.label, this.value, {this.onTap});
  final IconData icon;
  final String label, value;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(children: [
          Icon(icon, size: 19, color: WalletColors.text2),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: WalletColors.text))),
          Text(value, style: const TextStyle(fontSize: 13, color: WalletColors.text2)),
          const Icon(Icons.chevron_right, size: 16, color: WalletColors.text3),
        ]),
      );
}
