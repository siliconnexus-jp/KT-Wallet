import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../l10n/app_localizations.dart';
import '../state/wallet_scope.dart';
import '../wallets/wallet_manager.dart';
import '../wallets/wallet_model.dart';
import 'camera_screen.dart';

const _mnemonic = ['walnut', 'breeze', 'copper', 'stadium', 'lyric', 'fossil', 'drift', 'mosaic', 'tunnel', 'prairie', 'zebra', 'anchor'];

/// The mnemonic shown in the backup flow: the one just generated during
/// create-onboarding, or the demo constant when the screen is opened standalone
/// (design gallery / goldens / the backup banner path).
List<String> _activeMnemonic(BuildContext context) {
  final pending = WalletScope.of(context).pendingMnemonic;
  if (pending == null) return _mnemonic;
  return pending.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
}

Widget _wordGrid(List<String> words) {
  return Column(children: [
    for (var r = 0; r < (words.length / 2).ceil(); r++)
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          for (var c = 0; c < 2; c++) ...[
            if (c > 0) const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: WalletColors.surface, borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  Text((r * 2 + c + 1).toString().padLeft(2, '0'), style: const TextStyle(fontSize: 12, fontFamily: KtFonts.mono, color: WalletColors.text3)),
                  const SizedBox(width: 10),
                  Text(words[r * 2 + c], style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, fontFamily: KtFonts.mono, color: WalletColors.text)),
                ]),
              ),
            ),
          ],
        ]),
      ),
  ]);
}

/// W10 启动页.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: WalletColors.bg,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 96, height: 96,
            decoration: BoxDecoration(color: WalletColors.accent, borderRadius: BorderRadius.circular(26)),
            child: const Icon(Icons.account_balance_wallet, size: 48, color: Colors.white),
          ),
          const SizedBox(height: 20),
          const Text('KT Wallet', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: WalletColors.text)),
          const SizedBox(height: 8),
          Text(l10n.appTagline, style: const TextStyle(fontSize: 14, color: WalletColors.text2)),
        ]),
      ),
    );
  }
}

/// W22 添加钱包.
class AddWalletScreen extends StatelessWidget {
  const AddWalletScreen({super.key});

  /// Starts the create-onboarding flow: generate a fresh mnemonic, then walk
  /// the backup show → verify screens before the wallet is committed.
  Future<void> _createHotWallet(BuildContext context) async {
    await WalletScope.of(context).beginCreate();
    if (context.mounted) context.push('/create-warn');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget entry(IconData icon, String t, String s, {bool dark = false, VoidCallback? onTap}) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: dark ? const Color(0xFF0C1220) : WalletColors.surface, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: dark ? SignerColors.surface2 : WalletColors.accent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, size: 20, color: dark ? SignerColors.ok : WalletColors.accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: dark ? Colors.white : WalletColors.text)),
                  const SizedBox(height: 3),
                  Text(s, style: TextStyle(fontSize: 12, height: 1.5, color: dark ? SignerColors.text2 : WalletColors.text2)),
                ]),
              ),
              Icon(Icons.chevron_right, size: 18, color: dark ? const Color(0xFF5A616C) : WalletColors.text3),
            ]),
          ),
        );
    return KtScreen(
      gap: 16,
      navBar: KtNavBar(title: l10n.addWalletTitle, onBack: () => Navigator.of(context).maybePop()),
      children: [
        Text(l10n.addWalletStandardSection, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: WalletColors.text2)),
        entry(Icons.add, l10n.createNewWallet, l10n.createNewWalletDesc, onTap: () => _createHotWallet(context)),
        entry(Icons.key, l10n.importMnemonic, l10n.importMnemonicDesc, onTap: () => context.push('/mnemonic-import')),
        Text(l10n.coldWalletSection, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: WalletColors.text2)),
        entry(Icons.verified_user, l10n.connectColdWallet, l10n.connectColdWalletDesc, dark: true, onTap: () => context.push('/connect-cold')),
      ],
    );
  }
}

/// W23 创建钱包安全提示.
class CreateWarnScreen extends StatelessWidget {
  const CreateWarnScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KtScreen(
      navBar: KtNavBar(title: l10n.createWalletTitle, onBack: () => Navigator.of(context).maybePop(), trailingText: '1 / 3'),
      bottom: KtPrimaryButton(label: l10n.showMnemonic, onPressed: () => context.push('/mnemonic-show')),
      children: [
        Column(children: [
          Container(width: 72, height: 72, decoration: BoxDecoration(color: WalletColors.amber.withValues(alpha: 0.08), shape: BoxShape.circle), child: const Icon(Icons.key, size: 34, color: WalletColors.amber)),
          const SizedBox(height: 12),
          Text(l10n.mnemonicWillGenerate, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: WalletColors.text)),
        ]),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: WalletColors.accent.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
          child: Text(l10n.hotWalletNotice,
              style: const TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF1D46B8))),
        ),
        _rule(Icons.workspace_premium, l10n.ruleFullControlTitle, l10n.ruleFullControlDesc),
        _rule(Icons.edit, l10n.ruleHandwriteTitle, l10n.ruleHandwriteDesc),
      ],
    );
  }

  static Widget _rule(IconData icon, String t, String s) => KtCard(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: const Color(0xFFF2F4F7), borderRadius: BorderRadius.circular(10)), child: Icon(icon, size: 18, color: WalletColors.amber)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.4, color: WalletColors.text)),
            const SizedBox(height: 4),
            Text(s, style: const TextStyle(fontSize: 12, height: 1.5, color: WalletColors.text2)),
          ])),
        ]),
      );
}

/// W24 助记词展示.
class MnemonicShowScreen extends StatelessWidget {
  const MnemonicShowScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KtScreen(
      gap: 18,
      navBar: KtNavBar(title: l10n.backupMnemonicTitle, onBack: () => Navigator.of(context).maybePop(), trailingText: '2 / 3'),
      bottom: KtPrimaryButton(label: l10n.mnemonicShowConfirmBtn, onPressed: () => context.push('/mnemonic-verify')),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: WalletColors.red.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.no_photography, size: 18, color: WalletColors.red),
            const SizedBox(width: 10),
            Expanded(child: Text(l10n.mnemonicShowWarning, style: const TextStyle(fontSize: 13, height: 1.5, color: WalletColors.red))),
          ]),
        ),
        _wordGrid(_activeMnemonic(context)),
      ],
    );
  }
}

/// W25 助记词校验.
class MnemonicVerifyScreen extends StatefulWidget {
  const MnemonicVerifyScreen({super.key});
  @override
  State<MnemonicVerifyScreen> createState() => _MnemonicVerifyScreenState();
}

class _MnemonicVerifyScreenState extends State<MnemonicVerifyScreen> {
  // Challenge the 4th word; options are built from the actual mnemonic.
  static const _challengePosition = 4; // 1-based

  String? _selected;

  List<String> _words() => _activeMnemonic(context);
  String _correct() => _words()[_challengePosition - 1];

  /// Correct word + up to 5 distinct distractors from the same mnemonic,
  /// alphabetically ordered for a stable layout.
  List<String> _options() {
    final words = _words();
    final correct = words[_challengePosition - 1];
    final distractors = words.where((w) => w != correct).toSet().take(5);
    return [correct, ...distractors]..sort();
  }

  Future<void> _confirm() async {
    if (_selected == null) return;
    final l10n = AppLocalizations.of(context);
    final controller = WalletScope.of(context);
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    if (_selected != _correct()) {
      setState(() => _selected = null);
      messenger.showSnackBar(SnackBar(content: Text(l10n.verifyWrong)));
      return;
    }
    if (controller.pendingMnemonic != null) {
      // Create-onboarding: commit the new wallet now that backup is verified.
      final name = l10n.walletDefaultName(controller.count + 1);
      await controller.finalizeCreate(name: name);
      messenger.showSnackBar(SnackBar(content: Text(l10n.walletCreatedBackedUp)));
    } else {
      // Standalone backup of the current wallet.
      final current = controller.current;
      if (current != null) controller.markBackedUp(current.id);
      messenger.showSnackBar(SnackBar(content: Text(l10n.backupVerified)));
    }
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = _options();
    return KtScreen(
      gap: 24,
      navBar: KtNavBar(title: l10n.verifyBackupTitle, onBack: () => Navigator.of(context).maybePop(), trailingText: '3 / 3'),
      bottom: KtPrimaryButton(label: l10n.actionConfirm, onPressed: _selected == null ? null : _confirm),
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (final done in [true, false, false]) ...[
            Container(width: 28, height: 4, margin: const EdgeInsets.symmetric(horizontal: 4), decoration: BoxDecoration(color: done ? WalletColors.green : WalletColors.border, borderRadius: BorderRadius.circular(2))),
          ],
        ]),
        Column(children: [
          Text(l10n.mnemonicWordChallenge(_challengePosition), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: WalletColors.text)),
          const SizedBox(height: 8),
          Text(l10n.mnemonicChallengeHint, style: const TextStyle(fontSize: 13, color: WalletColors.text2)),
        ]),
        Column(children: [
          for (var r = 0; r < (options.length / 2).ceil(); r++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                for (var c = 0; c < 2; c++) ...[
                  if (c > 0) const SizedBox(width: 10),
                  Expanded(child: () {
                    final idx = r * 2 + c;
                    if (idx >= options.length) return const SizedBox();
                    final word = options[idx];
                    final sel = word == _selected;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _selected = word),
                      child: Container(
                        height: 48, alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: sel ? WalletColors.green.withValues(alpha: 0.06) : WalletColors.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: sel ? WalletColors.green : WalletColors.border, width: sel ? 1.5 : 1),
                        ),
                        child: Text(word, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, fontFamily: KtFonts.mono, color: sel ? WalletColors.green : WalletColors.text)),
                      ),
                    );
                  }()),
                ],
              ]),
            ),
        ]),
      ],
    );
  }
}

/// W26 助记词输入. Live: 12 editable word fields; import enables once every
/// field is filled, and paste distributes a whole phrase across the fields.
class MnemonicImportScreen extends StatefulWidget {
  const MnemonicImportScreen({super.key});
  @override
  State<MnemonicImportScreen> createState() => _MnemonicImportScreenState();
}

class _MnemonicImportScreenState extends State<MnemonicImportScreen> {
  final _controllers = List.generate(12, (_) => TextEditingController());

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _complete => _controllers.every((c) => c.text.trim().isNotEmpty);

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final words = (data?.text ?? '').trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return;
    setState(() {
      for (var i = 0; i < _controllers.length; i++) {
        _controllers[i].text = i < words.length ? words[i] : '';
      }
    });
    if (mounted) await Clipboard.setData(const ClipboardData(text: ''));
  }

  Future<void> _import() async {
    final l10n = AppLocalizations.of(context);
    final controller = WalletScope.of(context);
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    final mnemonic = _controllers.map((c) => c.text.trim()).join(' ');
    final name = l10n.walletImportedName(controller.count + 1);
    try {
      await controller.importWallet(mnemonic, name: name);
    } on CoreCryptoException catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.mnemonicInvalid)));
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(l10n.mnemonicImported)));
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KtScreen(
      gap: 18,
      navBar: KtNavBar(title: l10n.importMnemonic, onBack: () => Navigator.of(context).maybePop()),
      bottom: KtPrimaryButton(label: l10n.actionImport, onPressed: _complete ? _import : null),
      children: [
        KtSegmented(options: [l10n.wordsCount(12), l10n.wordsCount(18), l10n.wordsCount(24)], selected: 0),
        Column(children: [
          for (var r = 0; r < 6; r++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                for (var c = 0; c < 2; c++) ...[
                  if (c > 0) const SizedBox(width: 10),
                  Expanded(child: () {
                    final idx = r * 2 + c;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: WalletColors.surface, borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: WalletColors.border),
                      ),
                      child: Row(children: [
                        Text((idx + 1).toString().padLeft(2, '0'), style: const TextStyle(fontSize: 12, fontFamily: KtFonts.mono, color: WalletColors.text3)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _controllers[idx],
                            onChanged: (_) => setState(() {}),
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            enableSuggestions: false,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, fontFamily: KtFonts.mono, color: WalletColors.text),
                            decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 8)),
                          ),
                        ),
                      ]),
                    );
                  }()),
                ],
              ]),
            ),
        ]),
        Center(
          child: GestureDetector(
            onTap: _paste,
            child: Text(l10n.pasteMnemonic, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: WalletColors.accent)),
          ),
        ),
      ],
    );
  }
}

/// W11 连接离线钱包.
class ConnectColdScreen extends StatelessWidget {
  const ConnectColdScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KtScreen(
      gap: 24,
      navBar: KtNavBar(title: l10n.connectColdWallet, onBack: () => Navigator.of(context).maybePop()),
      bottom: KtPrimaryButton(label: l10n.scanAccountQr, onPressed: () {}),
      children: [
        Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(width: 72, height: 120, decoration: BoxDecoration(color: const Color(0xFF0C1220), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.qr_code_2, size: 32, color: Colors.white)),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Icon(Icons.arrow_forward, size: 28, color: WalletColors.accent)),
            Container(width: 72, height: 120, decoration: BoxDecoration(color: WalletColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: WalletColors.border, width: 1.5)), child: const Icon(Icons.qr_code_scanner, size: 32, color: WalletColors.accent)),
          ]),
          const SizedBox(height: 12),
          Text(l10n.connectColdWallet, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: WalletColors.text)),
          const SizedBox(height: 8),
          Text(l10n.connectColdSubtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, height: 1.6, color: WalletColors.text2)),
        ]),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: WalletColors.green.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.verified_user, size: 18, color: WalletColors.green),
            const SizedBox(width: 10),
            Expanded(child: Text(l10n.connectColdSafety, style: const TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF0A7A45)))),
          ]),
        ),
      ],
    );
  }
}

/// W12 扫描账户二维码 (dark camera).
class ScanAccountScreen extends StatelessWidget {
  const ScanAccountScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KtCameraScreen(title: l10n.scanAccountQr, hint: l10n.scanAccountHint, onClose: () => Navigator.of(context).maybePop());
  }
}

/// W13 导入确认.
class ImportConfirmScreen extends StatelessWidget {
  const ImportConfirmScreen({super.key});
  static const _nets = [
    (ChainColors.ethereum, 'Ethereum', '0x8f3C2a…7E19bE1'),
    (ChainColors.polygon, 'Polygon', '0x8f3C2a…7E19bE1'),
    (ChainColors.tron, 'TRON', 'TQm9xPa2…Vb7L3kFa'),
    (ChainColors.solana, 'Solana', '6yKpXw…mDqVr2W'),
  ];
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KtScreen(
      gap: 16,
      navBar: KtNavBar(title: l10n.importConfirmTitle, onBack: () => Navigator.of(context).maybePop()),
      bottom: KtPrimaryButton(label: l10n.createWatchWallet, onPressed: () {}),
      children: [
        KtCard(
          child: Row(children: [
            Container(width: 48, height: 48, decoration: BoxDecoration(color: const Color(0xFF0C1220), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.verified_user, size: 24, color: SignerColors.ok)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l10n.walletSeedMain, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: WalletColors.text)),
              const SizedBox(height: 4),
              Text(l10n.walletIdProtocol('WLT-3E8A91', 1), style: const TextStyle(fontSize: 12, fontFamily: KtFonts.mono, color: WalletColors.text3)),
            ])),
          ]),
        ),
        KtCard(
          child: Column(children: [
            for (var i = 0; i < _nets.length; i++) ...[
              if (i > 0) const SizedBox(height: 13),
              Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: _nets[i].$1, shape: BoxShape.circle)),
                const SizedBox(width: 12),
                Expanded(child: Text(_nets[i].$2, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: WalletColors.text))),
                Text(_nets[i].$3, style: const TextStyle(fontSize: 12, fontFamily: KtFonts.mono, color: WalletColors.text2)),
              ]),
            ],
          ]),
        ),
      ],
    );
  }
}

/// W21 钱包切换器 (bottom sheet). Live: reads wallets from [WalletScope] and
/// switches the current wallet on tap, then closes — the home screen rebuilds.
class WalletSwitcherSheet extends StatelessWidget {
  const WalletSwitcherSheet({super.key});

  static const _demoValue = {'daily': r'$862.40', 'savings': r'$3,210.55', 'cold': r'$12,847.32'};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = WalletScope.of(context);
    return Scaffold(
      backgroundColor: WalletColors.text.withValues(alpha: 0.5),
      body: GestureDetector(
        onTap: () => context.pop(),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(color: WalletColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 36, height: 4, decoration: BoxDecoration(color: WalletColors.border, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(l10n.walletsTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: WalletColors.text)),
                  GestureDetector(
                    onTap: () { context.pop(); context.push('/wallet-manage'); },
                    child: Row(children: [const Icon(Icons.settings, size: 15, color: WalletColors.text2), const SizedBox(width: 4), Text(l10n.manage, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: WalletColors.text2))]),
                  ),
                ]),
                const SizedBox(height: 16),
                for (final w in controller.wallets)
                  () {
                    final current = w.id == controller.current?.id;
                    final isHot = w is HotWallet;
                    final unbacked = isHot && !w.backedUp;
                    return GestureDetector(
                      onTap: () { controller.select(w.id); context.pop(); },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: current ? WalletColors.accent.withValues(alpha: 0.04) : WalletColors.bg,
                          borderRadius: BorderRadius.circular(14),
                          border: current ? Border.all(color: WalletColors.accent, width: 1.5) : null,
                        ),
                        child: Row(children: [
                          Stack(clipBehavior: Clip.none, children: [
                            KtAvatar(color: Color(w.avatarColor), initial: w.name.characters.first),
                            if (unbacked) Positioned(right: -2, top: -2, child: Container(width: 12, height: 12, decoration: BoxDecoration(color: WalletColors.red, shape: BoxShape.circle, border: Border.all(color: WalletColors.surface, width: 2)))),
                          ]),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Text(w.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: WalletColors.text)),
                              const SizedBox(width: 8),
                              WalletTypeBadge(
                                kind: isHot ? WalletKind.hot : WalletKind.watch,
                                label: isHot ? l10n.walletKindHot : l10n.walletKindWatch,
                              ),
                            ]),
                            const SizedBox(height: 3),
                            Text(_demoValue[w.id] ?? '\$0.00', style: const TextStyle(fontSize: 12, color: WalletColors.text3)),
                          ])),
                          if (current) const Icon(Icons.check_circle, size: 20, color: WalletColors.accent),
                        ]),
                      ),
                    );
                  }(),
                const SizedBox(height: 8),
                KtPrimaryButton(label: l10n.addWalletTitle, onPressed: () { context.pop(); context.push('/add-wallet'); }),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// W27 钱包管理. Live: reads the wallet list from [WalletScope] and supports
/// deleting a wallet (with confirmation) and adding a new one.
class WalletManageScreen extends StatelessWidget {
  const WalletManageScreen({super.key});

  Future<void> _confirmDelete(BuildContext context, Wallet w) async {
    final l10n = AppLocalizations.of(context);
    final controller = WalletScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteWalletTitle),
        content: Text(l10n.deleteWalletConfirm(w.name)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.actionCancel)),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.actionDelete, style: const TextStyle(color: WalletColors.red)),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      controller.remove(w.id);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l10n.deletedWallet(w.name))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = WalletScope.of(context);
    final wallets = controller.wallets;
    return KtScreen(
      gap: 16,
      navBar: KtNavBar(title: l10n.settingsWalletManage, onBack: () => Navigator.of(context).maybePop(), trailingText: l10n.sortAction),
      bottom: KtPrimaryButton(
        label: l10n.addWalletTitle,
        onPressed: controller.canAddMore ? () => context.push('/add-wallet') : null,
      ),
      children: [
        Text(l10n.walletCountLimit(wallets.length, WalletManager.maxWallets), style: const TextStyle(fontSize: 13, color: WalletColors.text3)),
        for (final w in wallets)
          () {
            final isHot = w is HotWallet;
            final kind = isHot ? WalletKind.hot : WalletKind.watch;
            final unbacked = isHot && !w.backedUp;
            final state = switch (w) {
              HotWallet(backedUp: true) => l10n.walletStateBackedUp,
              HotWallet() => l10n.walletStateNotBackedUp,
              WatchWallet() => 'Cold Signer',
            };
            return KtCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                KtAvatar(color: Color(w.avatarColor), initial: w.name.characters.first),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Flexible(child: Text(w.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: WalletColors.text))), const SizedBox(width: 8), WalletTypeBadge(kind: kind, label: isHot ? l10n.walletKindHot : l10n.walletKindWatch)]),
                  const SizedBox(height: 3),
                  Text(state, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: unbacked ? FontWeight.w600 : FontWeight.w400, color: unbacked ? WalletColors.red : WalletColors.text3)),
                ])),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20, color: WalletColors.text3),
                  onPressed: () => _confirmDelete(context, w),
                ),
              ]),
            );
          }(),
      ],
    );
  }
}

/// W28 钱包详情编辑.
class WalletDetailScreen extends StatelessWidget {
  const WalletDetailScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KtScreen(
      gap: 16,
      navBar: KtNavBar(title: l10n.walletDetailTitle, onBack: () => Navigator.of(context).maybePop()),
      children: [
        Column(children: [
          const KtAvatar(color: Color(0xFFF59E0B), initial: '日', size: 72),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(l10n.walletSeedDaily, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: WalletColors.text)),
            const SizedBox(width: 8),
            const Icon(Icons.edit, size: 16, color: WalletColors.text3),
          ]),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (final (c, sel) in const [(0xFFF59E0B, true), (0xFF8B5CF6, false), (0xFF0EA5E9, false), (0xFF10B981, false), (0xFFEF4444, false)])
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 5),
                width: 26, height: 26,
                decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle, border: sel ? Border.all(color: WalletColors.accent, width: 2) : null),
              ),
          ]),
        ]),
        KtCard(
          child: Column(children: [
            KtDetailRow(label: l10n.walletTypeLabel, value: l10n.standardWallet),
            const SizedBox(height: 14),
            const KtDetailRow(label: 'Wallet ID', value: 'WLT-91A4C7', mono: true),
          ]),
        ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: WalletColors.amber.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, size: 18, color: WalletColors.amber),
            const SizedBox(width: 10),
            Expanded(child: Text(l10n.backupNotYet, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF9A6503)))),
            Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), decoration: BoxDecoration(color: WalletColors.amber, borderRadius: BorderRadius.circular(999)), child: Text(l10n.backupNow, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white))),
          ]),
        ),
        KtCard(child: SecurityRow(Icons.key, l10n.viewMnemonic, l10n.viewMnemonicDesc)),
        KtCard(child: SecurityRow(Icons.delete_outline, l10n.deleteWalletTitle, l10n.deleteWalletDesc, danger: true)),
      ],
    );
  }
}

class SecurityRow extends StatelessWidget {
  const SecurityRow(this.icon, this.label, this.sub, {super.key, this.danger = false});
  final IconData icon;
  final String label, sub;
  final bool danger;
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 19, color: danger ? WalletColors.red : WalletColors.text2),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: danger ? WalletColors.red : WalletColors.text)),
          const SizedBox(height: 2),
          Text(sub, style: const TextStyle(fontSize: 12, color: WalletColors.text3)),
        ])),
        const Icon(Icons.chevron_right, size: 16, color: WalletColors.text3),
      ]);
}
