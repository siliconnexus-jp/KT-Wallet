import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

import '../state/wallet_scope.dart';
import '../wallets/wallet_manager.dart';
import '../wallets/wallet_model.dart';

const _mnemonic = ['walnut', 'breeze', 'copper', 'stadium', 'lyric', 'fossil', 'drift', 'mosaic', 'tunnel', 'prairie', 'zebra', 'anchor'];

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
  Widget build(BuildContext context) => Scaffold(
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
            const Text('双机离线钱包 · 联网观察端', style: TextStyle(fontSize: 14, color: WalletColors.text2)),
          ]),
        ),
      );
}

/// W22 添加钱包.
class AddWalletScreen extends StatelessWidget {
  const AddWalletScreen({super.key});

  static const _palette = [0xFF0EA5E9, 0xFF10B981, 0xFFEF4444, 0xFFF59E0B, 0xFF8B5CF6, 0xFFEC4899];

  /// Creates a fresh hot wallet in the live controller and returns home. Real
  /// key generation happens natively; here we add the wallet record so the
  /// multi-wallet switcher reflects it immediately.
  void _createHotWallet(BuildContext context) {
    final controller = WalletScope.of(context);
    final n = controller.count + 1;
    final id = 'w${DateTime.now().microsecondsSinceEpoch}';
    controller.add(HotWallet(
      id: id,
      name: '钱包 $n',
      avatarColor: _palette[controller.count % _palette.length],
      addresses: ChainAddresses(
        eth: '0x${id.substring(1, 9)}00000000000000000000000000000000',
        polygon: '0x${id.substring(1, 9)}00000000000000000000000000000000',
        tron: 'T${id.substring(1, 9)}000000000000000000000000000',
        solana: '${id.substring(1, 9)}0000000000000000000000000000',
      ),
      sortOrder: controller.count,
    ));
    controller.select(id);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('新钱包已创建，记得尽快备份助记词')));
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
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
      navBar: KtNavBar(title: '添加钱包', onBack: () => Navigator.of(context).maybePop()),
      children: [
        const Text('普通钱包 · 便捷', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: WalletColors.text2)),
        entry(Icons.add, '创建新钱包', '在本机生成新的助记词，立即可用', onTap: () => _createHotWallet(context)),
        entry(Icons.key, '导入助记词', '已有 12 / 18 / 24 个单词的助记词', onTap: () => context.push('/mnemonic-import')),
        const Text('离线钱包组合 · 高安全', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: WalletColors.text2)),
        entry(Icons.verified_user, '连接离线钱包', '扫码配对 Cold Signer，私钥永不进入本机', dark: true, onTap: () => context.push('/connect-cold')),
      ],
    );
  }
}

/// W23 创建钱包安全提示.
class CreateWarnScreen extends StatelessWidget {
  const CreateWarnScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return KtScreen(
      navBar: KtNavBar(title: '创建普通钱包', onBack: () => Navigator.of(context).maybePop(), trailingText: '1 / 3'),
      bottom: KtPrimaryButton(label: '显示助记词', onPressed: () => context.push('/mnemonic-show')),
      children: [
        Column(children: [
          Container(width: 72, height: 72, decoration: BoxDecoration(color: WalletColors.amber.withValues(alpha: 0.08), shape: BoxShape.circle), child: const Icon(Icons.key, size: 34, color: WalletColors.amber)),
          const SizedBox(height: 12),
          const Text('接下来将生成助记词', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: WalletColors.text)),
        ]),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: WalletColors.accent.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
          child: const Text('这是一个热钱包：助记词保存在本机安全区。适合小额日常使用，大额资产建议使用离线钱包组合。',
              style: TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF1D46B8))),
        ),
        _rule(Icons.workspace_premium, '助记词等于资产的完全控制权', '任何人拿到这 12 个单词，即可转走你的全部资产'),
        _rule(Icons.edit, '只用纸笔手写备份', '不要保存到相册、云盘、备忘录或聊天软件'),
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
    return KtScreen(
      gap: 18,
      navBar: KtNavBar(title: '备份助记词', onBack: () => Navigator.of(context).maybePop(), trailingText: '2 / 3'),
      bottom: KtPrimaryButton(label: '我已手写备份，开始校验', onPressed: () => context.push('/mnemonic-verify')),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: WalletColors.red.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            Icon(Icons.no_photography, size: 18, color: WalletColors.red),
            SizedBox(width: 10),
            Expanded(child: Text('请按顺序手写抄录，请勿截图或拍照。任何人获得助记词即可控制资产。', style: TextStyle(fontSize: 13, height: 1.5, color: WalletColors.red))),
          ]),
        ),
        _wordGrid(_mnemonic),
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
  // Challenge the 4th word; options include the correct one plus distractors.
  static const _challengePosition = 4; // 1-based
  static const _options = ['fossil', 'stadium', 'breeze', 'mosaic', 'anchor', 'copper'];
  String get _correct => _mnemonic[_challengePosition - 1]; // 'stadium'

  String? _selected;

  void _confirm() {
    if (_selected == null) return;
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    if (_selected == _correct) {
      final controller = WalletScope.of(context);
      final current = controller.current;
      if (current != null) controller.markBackedUp(current.id);
      messenger.showSnackBar(const SnackBar(content: Text('备份已验证，助记词记录正确')));
      context.go('/home');
    } else {
      setState(() => _selected = null);
      messenger.showSnackBar(const SnackBar(content: Text('选择有误，请对照您手写的备份重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return KtScreen(
      gap: 24,
      navBar: KtNavBar(title: '校验备份', onBack: () => Navigator.of(context).maybePop(), trailingText: '3 / 3'),
      bottom: KtPrimaryButton(label: '确认', onPressed: _selected == null ? null : _confirm),
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (final done in [true, false, false]) ...[
            Container(width: 28, height: 4, margin: const EdgeInsets.symmetric(horizontal: 4), decoration: BoxDecoration(color: done ? WalletColors.green : WalletColors.border, borderRadius: BorderRadius.circular(2))),
          ],
        ]),
        Column(children: [
          Text('第 $_challengePosition 个单词是？', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: WalletColors.text)),
          const SizedBox(height: 8),
          const Text('从下列单词中选择正确的一项', style: TextStyle(fontSize: 13, color: WalletColors.text2)),
        ]),
        Column(children: [
          for (var r = 0; r < 3; r++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                for (var c = 0; c < 2; c++) ...[
                  if (c > 0) const SizedBox(width: 10),
                  Expanded(child: () {
                    final word = _options[r * 2 + c];
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

/// W26 助记词输入.
class MnemonicImportScreen extends StatelessWidget {
  const MnemonicImportScreen({super.key});
  @override
  Widget build(BuildContext context) {
    const typed = ['gentle', 'harbor', 'planet', 'autumn', 'circle', '', '', '', '', '', '', ''];
    return KtScreen(
      gap: 18,
      navBar: KtNavBar(title: '导入助记词', onBack: () => Navigator.of(context).maybePop()),
      bottom: KtPrimaryButton(label: '导入', onPressed: () {}),
      children: [
        const KtSegmented(options: ['12 个单词', '18 个单词', '24 个单词'], selected: 0),
        Column(children: [
          for (var r = 0; r < 6; r++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                for (var c = 0; c < 2; c++) ...[
                  if (c > 0) const SizedBox(width: 10),
                  Expanded(child: () {
                    final idx = r * 2 + c;
                    final active = idx == 5;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: WalletColors.surface, borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: active ? WalletColors.accent : WalletColors.border, width: active ? 1.5 : 1),
                      ),
                      child: Row(children: [
                        Text((idx + 1).toString().padLeft(2, '0'), style: const TextStyle(fontSize: 12, fontFamily: KtFonts.mono, color: WalletColors.text3)),
                        const SizedBox(width: 10),
                        Text(typed[idx], style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, fontFamily: KtFonts.mono, color: WalletColors.text)),
                      ]),
                    );
                  }()),
                ],
              ]),
            ),
        ]),
        const Center(child: Text('粘贴助记词（解析后自动清空剪贴板）', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: WalletColors.accent))),
      ],
    );
  }
}

/// W11 连接离线钱包.
class ConnectColdScreen extends StatelessWidget {
  const ConnectColdScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return KtScreen(
      gap: 24,
      navBar: KtNavBar(title: '连接离线钱包', onBack: () => Navigator.of(context).maybePop()),
      bottom: KtPrimaryButton(label: '扫描账户二维码', onPressed: () {}),
      children: [
        Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(width: 72, height: 120, decoration: BoxDecoration(color: const Color(0xFF0C1220), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.qr_code_2, size: 32, color: Colors.white)),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Icon(Icons.arrow_forward, size: 28, color: WalletColors.accent)),
            Container(width: 72, height: 120, decoration: BoxDecoration(color: WalletColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: WalletColors.border, width: 1.5)), child: const Icon(Icons.qr_code_scanner, size: 32, color: WalletColors.accent)),
          ]),
          const SizedBox(height: 12),
          const Text('连接离线钱包', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: WalletColors.text)),
          const SizedBox(height: 8),
          const Text('从离线手机导入公开地址，创建观察钱包', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, height: 1.6, color: WalletColors.text2)),
        ]),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: WalletColors.green.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            Icon(Icons.verified_user, size: 18, color: WalletColors.green),
            SizedBox(width: 10),
            Expanded(child: Text('本机永远不会接收或保存助记词、私钥或 Seed。', style: TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF0A7A45)))),
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
  Widget build(BuildContext context) => _CameraScreen(title: '扫描账户二维码', hint: '对准 Cold Signer 的地址二维码', onClose: () => Navigator.of(context).maybePop());
}

class _CameraScreen extends StatelessWidget {
  const _CameraScreen({required this.title, required this.hint, required this.onClose});
  final String title, hint;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: SignerColors.bg,
        body: SafeArea(
          bottom: false,
          child: Column(children: [
            const KtStatusBar(theme: AppTheme.signer),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: KtNavBar(title: title, theme: AppTheme.signer, leading: Icons.close, onBack: onClose)),
            const SizedBox(height: 24),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              height: 400,
              decoration: BoxDecoration(color: SignerColors.surface, borderRadius: BorderRadius.circular(20)),
              child: Center(child: Container(width: 240, height: 240, decoration: BoxDecoration(border: Border.all(color: SignerColors.blue, width: 2), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.qr_code_2, size: 64, color: SignerColors.border))),
            ),
            const SizedBox(height: 24),
            Text(hint, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
          ]),
        ),
      );
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
    return KtScreen(
      gap: 16,
      navBar: KtNavBar(title: '确认导入', onBack: () => Navigator.of(context).maybePop()),
      bottom: KtPrimaryButton(label: '创建观察钱包', onPressed: () {}),
      children: [
        KtCard(
          child: Row(children: [
            Container(width: 48, height: 48, decoration: BoxDecoration(color: const Color(0xFF0C1220), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.verified_user, size: 24, color: SignerColors.ok)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
              Text('主钱包', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: WalletColors.text)),
              SizedBox(height: 4),
              Text('Wallet ID: WLT-3E8A91 · 协议 v1', style: TextStyle(fontSize: 12, fontFamily: KtFonts.mono, color: WalletColors.text3)),
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
                  const Text('钱包', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: WalletColors.text)),
                  GestureDetector(
                    onTap: () { context.pop(); context.push('/wallet-manage'); },
                    child: const Row(children: [Icon(Icons.settings, size: 15, color: WalletColors.text2), SizedBox(width: 4), Text('管理', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: WalletColors.text2))]),
                  ),
                ]),
                const SizedBox(height: 16),
                for (final w in controller.wallets)
                  () {
                    final current = w.id == controller.current?.id;
                    final unbacked = w is HotWallet && !w.backedUp;
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
                              WalletTypeBadge(kind: w is HotWallet ? WalletKind.hot : WalletKind.watch),
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
                KtPrimaryButton(label: '添加钱包', onPressed: () { context.pop(); context.push('/add-wallet'); }),
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
    final controller = WalletScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除钱包'),
        content: Text('确定删除「${w.name}」？此操作仅移除本机记录，不影响链上资产。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除', style: TextStyle(color: WalletColors.red)),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      controller.remove(w.id);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('已删除「${w.name}」')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = WalletScope.of(context);
    final wallets = controller.wallets;
    return KtScreen(
      gap: 16,
      navBar: KtNavBar(title: '钱包管理', onBack: () => Navigator.of(context).maybePop(), trailingText: '排序'),
      bottom: KtPrimaryButton(
        label: '添加钱包',
        onPressed: controller.canAddMore ? () => context.push('/add-wallet') : null,
      ),
      children: [
        Text('共 ${wallets.length} 个钱包 · 上限 ${WalletManager.maxWallets} 个', style: const TextStyle(fontSize: 13, color: WalletColors.text3)),
        for (final w in wallets)
          () {
            final kind = w is HotWallet ? WalletKind.hot : WalletKind.watch;
            final unbacked = w is HotWallet && !w.backedUp;
            final state = switch (w) {
              HotWallet(backedUp: true) => '已备份',
              HotWallet() => '未备份',
              WatchWallet() => 'Cold Signer',
            };
            return KtCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                KtAvatar(color: Color(w.avatarColor), initial: w.name.characters.first),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Flexible(child: Text(w.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: WalletColors.text))), const SizedBox(width: 8), WalletTypeBadge(kind: kind)]),
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
    return KtScreen(
      gap: 16,
      navBar: KtNavBar(title: '钱包详情', onBack: () => Navigator.of(context).maybePop()),
      children: [
        Column(children: [
          const KtAvatar(color: Color(0xFFF59E0B), initial: '日', size: 72),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
            Text('日常钱包', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: WalletColors.text)),
            SizedBox(width: 8),
            Icon(Icons.edit, size: 16, color: WalletColors.text3),
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
          child: Column(children: const [
            KtDetailRow(label: '钱包类型', value: '普通钱包'),
            SizedBox(height: 14),
            KtDetailRow(label: 'Wallet ID', value: 'WLT-91A4C7', mono: true),
          ]),
        ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: WalletColors.amber.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, size: 18, color: WalletColors.amber),
            const SizedBox(width: 10),
            const Expanded(child: Text('尚未备份助记词', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF9A6503)))),
            Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), decoration: BoxDecoration(color: WalletColors.amber, borderRadius: BorderRadius.circular(999)), child: const Text('立即备份', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white))),
          ]),
        ),
        KtCard(child: SecurityRow(Icons.key, '查看助记词', '需要 Face ID 或密码验证')),
        KtCard(child: SecurityRow(Icons.delete_outline, '删除钱包', '需身份验证，删除前将再次确认备份状态', danger: true)),
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
