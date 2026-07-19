import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

const _t = AppTheme.signer;
const _mnemonic = ['ripple', 'canyon', 'script', 'harbor', 'velvet', 'noble', 'orbit', 'meadow', 'signal', 'pledge', 'quartz', 'ember'];

Widget _signerBtn(String label, {bool contrast = false, VoidCallback? onPressed}) =>
    KtPrimaryButton(label: label, style: contrast ? KtButtonStyle.signerContrast : KtButtonStyle.signer, onPressed: onPressed ?? () {});

Widget _wordGrid(List<String> words) => Column(children: [
      for (var r = 0; r < (words.length / 2).ceil(); r++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            for (var c = 0; c < 2; c++) ...[
              if (c > 0) const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(color: SignerColors.surface, borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    Text((r * 2 + c + 1).toString().padLeft(2, '0'), style: const TextStyle(fontSize: 12, fontFamily: KtFonts.mono, color: Color(0xFF5A616C))),
                    const SizedBox(width: 10),
                    Text(words[r * 2 + c], style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, fontFamily: KtFonts.mono, color: SignerColors.text)),
                  ]),
                ),
              ),
            ],
          ]),
        ),
    ]);

/// C11 启动页.
class SignerSplashScreen extends StatelessWidget {
  const SignerSplashScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: SignerColors.bg,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 96, height: 96, decoration: BoxDecoration(color: SignerColors.surface, borderRadius: BorderRadius.circular(26), border: Border.all(color: SignerColors.border)), child: const Icon(Icons.verified_user, size: 48, color: SignerColors.ok)),
            const SizedBox(height: 20),
            const Text('Cold Signer', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: SignerColors.text)),
            const SizedBox(height: 8),
            const Text('双机离线钱包 · 离线签名端', style: TextStyle(fontSize: 14, color: SignerColors.text2)),
          ]),
        ),
      );
}

/// C1 欢迎.
class SignerWelcomeScreen extends StatelessWidget {
  const SignerWelcomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    Widget feat(IconData icon, String t, String s) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: SignerColors.surface, borderRadius: BorderRadius.circular(14)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: SignerColors.surface2, borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 20, color: SignerColors.blue)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: SignerColors.text)),
              const SizedBox(height: 4),
              Text(s, style: const TextStyle(fontSize: 13, height: 1.5, color: SignerColors.text2)),
            ])),
          ]),
        );
    return KtScreen(
      theme: _t,
      gap: 24,
      bottom: Column(children: [_signerBtn('创建新钱包', contrast: true, onPressed: () => context.push('/mnemonic-warn')), const SizedBox(height: 12), _signerBtn('导入已有钱包', onPressed: () => context.push('/mnemonic-import'))]),
      children: [
        const SizedBox(height: 8),
        Column(children: [
          Container(width: 88, height: 88, decoration: BoxDecoration(color: SignerColors.surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: SignerColors.border)), child: const Icon(Icons.verified_user, size: 44, color: SignerColors.ok)),
          const SizedBox(height: 20),
          const Text('Cold Signer', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: SignerColors.text)),
          const SizedBox(height: 10),
          const Text('离线签名 · 助记词永不触网', style: TextStyle(fontSize: 15, color: SignerColors.text2)),
        ]),
        feat(Icons.airplanemode_active, '完全离线运行', '本机不请求任何网络接口，建议全程开启飞行模式'),
        feat(Icons.key, '助记词只存在本机', '在本设备生成和加密保存，绝不进入联网手机'),
      ],
    );
  }
}

/// C12 助记词安全提示.
class SignerMnemonicWarnScreen extends StatelessWidget {
  const SignerMnemonicWarnScreen({super.key});
  @override
  Widget build(BuildContext context) {
    Widget rule(IconData icon, String t, String s) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: SignerColors.surface, borderRadius: BorderRadius.circular(14)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 36, height: 36, decoration: BoxDecoration(color: SignerColors.surface2, borderRadius: BorderRadius.circular(10)), child: Icon(icon, size: 18, color: SignerColors.warn)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.4, color: SignerColors.text)),
              const SizedBox(height: 4),
              Text(s, style: const TextStyle(fontSize: 12, height: 1.5, color: SignerColors.text2)),
            ])),
          ]),
        );
    return KtScreen(
      theme: _t,
      navBar: KtNavBar(title: '安全提示', theme: _t, onBack: () => Navigator.of(context).maybePop(), trailingText: '1 / 4'),
      bottom: _signerBtn('显示助记词', onPressed: () => context.push('/mnemonic-show')),
      children: [
        Column(children: [
          Container(width: 72, height: 72, decoration: BoxDecoration(color: SignerColors.danger.withValues(alpha: 0.08), shape: BoxShape.circle), child: const Icon(Icons.key, size: 34, color: SignerColors.danger)),
          const SizedBox(height: 12),
          const Text('接下来将生成助记词', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: SignerColors.text)),
        ]),
        rule(Icons.workspace_premium, '助记词等于资产的完全控制权', '任何人拿到这 12 个单词，即可在任何设备恢复并转走你的全部资产'),
        rule(Icons.edit, '只用纸笔手写备份', '抄写两份，分开存放在安全的物理位置'),
        rule(Icons.block, '永不拍照、截图或输入联网设备', '不要保存到相册、云盘或聊天软件，本 App 已禁用截图'),
      ],
    );
  }
}

/// C3 助记词展示.
class SignerMnemonicShowScreen extends StatelessWidget {
  const SignerMnemonicShowScreen({super.key});
  @override
  Widget build(BuildContext context) => KtScreen(
        theme: _t,
        gap: 18,
        navBar: KtNavBar(title: '备份助记词', theme: _t, onBack: () => Navigator.of(context).maybePop(), trailingText: '2 / 4'),
        bottom: _signerBtn('我已手写备份，开始验证', onPressed: () => context.push('/mnemonic-verify')),
        children: [
          const Text('请按顺序手写抄录以下 12 个单词，并保存在安全的物理位置。', style: TextStyle(fontSize: 14, height: 1.6, color: SignerColors.text2)),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: SignerColors.danger.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: const [
              Icon(Icons.no_photography, size: 18, color: SignerColors.danger),
              SizedBox(width: 10),
              Expanded(child: Text('请勿截图、拍照或抄录到任何联网设备。', style: TextStyle(fontSize: 13, height: 1.5, color: SignerColors.danger))),
            ]),
          ),
          _wordGrid(_mnemonic),
        ],
      );
}

/// C4 助记词校验.
class SignerMnemonicVerifyScreen extends StatefulWidget {
  const SignerMnemonicVerifyScreen({super.key});
  @override
  State<SignerMnemonicVerifyScreen> createState() => _SignerMnemonicVerifyScreenState();
}

class _SignerMnemonicVerifyScreenState extends State<SignerMnemonicVerifyScreen> {
  static const _challengePosition = 9; // 1-based
  static const _options = ['harbor', 'signal', 'quartz', 'meadow', 'orbit', 'pledge'];
  String get _correct => _mnemonic[_challengePosition - 1]; // 'signal'

  String? _selected;

  void _confirm() {
    if (_selected == null) return;
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    if (_selected == _correct) {
      context.push('/set-password');
    } else {
      setState(() => _selected = null);
      messenger.showSnackBar(const SnackBar(content: Text('选择有误，请对照您手写的备份重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return KtScreen(
      theme: _t,
      gap: 24,
      navBar: KtNavBar(title: '验证备份', theme: _t, onBack: () => Navigator.of(context).maybePop(), trailingText: '3 / 4'),
      bottom: _signerBtn('确认', onPressed: _selected == null ? null : _confirm),
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (final done in [true, true, false])
            Container(width: 28, height: 4, margin: const EdgeInsets.symmetric(horizontal: 4), decoration: BoxDecoration(color: done ? SignerColors.ok : SignerColors.border, borderRadius: BorderRadius.circular(2))),
        ]),
        Column(children: [
          Text('第 $_challengePosition 个单词是？', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: SignerColors.text)),
          const SizedBox(height: 8),
          const Text('从下列单词中选择正确的一项', style: TextStyle(fontSize: 13, color: SignerColors.text2)),
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
                          color: sel ? SignerColors.ok.withValues(alpha: 0.08) : SignerColors.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: sel ? SignerColors.ok : SignerColors.border, width: sel ? 1.5 : 1),
                        ),
                        child: Text(word, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, fontFamily: KtFonts.mono, color: sel ? SignerColors.ok : SignerColors.text)),
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

/// C13 助记词输入.
class SignerMnemonicImportScreen extends StatelessWidget {
  const SignerMnemonicImportScreen({super.key});
  @override
  Widget build(BuildContext context) {
    const typed = ['ripple', 'canyon', 'script', 'harbor', 'velvet', 'noble', 'orbit', '', '', '', '', ''];
    return KtScreen(
      theme: _t,
      gap: 18,
      navBar: KtNavBar(title: '导入钱包', theme: _t, onBack: () => Navigator.of(context).maybePop()),
      bottom: _signerBtn('导入', onPressed: () => context.push('/set-password')),
      children: [
        const KtSegmented(theme: _t, options: ['12 个单词', '18 个单词', '24 个单词'], selected: 0),
        Column(children: [
          for (var r = 0; r < 6; r++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                for (var c = 0; c < 2; c++) ...[
                  if (c > 0) const SizedBox(width: 10),
                  Expanded(child: () {
                    final idx = r * 2 + c;
                    final active = idx == 7;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(color: SignerColors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: active ? SignerColors.blue : SignerColors.border, width: active ? 1.5 : 1)),
                      child: Row(children: [
                        Text((idx + 1).toString().padLeft(2, '0'), style: const TextStyle(fontSize: 12, fontFamily: KtFonts.mono, color: Color(0xFF5A616C))),
                        const SizedBox(width: 10),
                        Text(typed[idx], style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, fontFamily: KtFonts.mono, color: SignerColors.text)),
                      ]),
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

/// C14 设置密码 (numpad).
class SignerSetPasswordScreen extends StatelessWidget {
  const SignerSetPasswordScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return KtScreen(
      theme: _t,
      gap: 28,
      navBar: KtNavBar(title: '设置解锁密码', theme: _t, onBack: () => Navigator.of(context).maybePop(), trailingText: '4 / 4'),
      children: [
        Column(children: const [
          SizedBox(height: 8),
          Text('设置 6 位密码', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: SignerColors.text)),
          SizedBox(height: 8),
          Text('用于解锁 App 和确认签名。密码仅保存在本机安全区域。', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, height: 1.6, color: SignerColors.text2)),
        ]),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < 6; i++)
            Container(width: 14, height: 14, margin: const EdgeInsets.symmetric(horizontal: 7), decoration: BoxDecoration(color: i < 3 ? SignerColors.text : SignerColors.surface2, shape: BoxShape.circle, border: i < 3 ? null : Border.all(color: SignerColors.border))),
        ]),
        Column(children: [
          for (final row in const [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9'], ['', '0', 'del']])
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (final k in row)
                  Container(
                    width: 72, height: 72, margin: const EdgeInsets.symmetric(horizontal: 10), alignment: Alignment.center,
                    decoration: BoxDecoration(color: k.isEmpty || k == 'del' ? null : SignerColors.surface, shape: BoxShape.circle),
                    child: k == 'del' ? const Icon(Icons.backspace_outlined, size: 22, color: SignerColors.text2) : Text(k, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w500, color: SignerColors.text)),
                  ),
              ]),
            ),
        ]),
      ],
    );
  }
}

/// C15 生物识别设置.
class SignerBiometricScreen extends StatelessWidget {
  const SignerBiometricScreen({super.key});
  @override
  Widget build(BuildContext context) => KtScreen(
        theme: _t,
        gap: 28,
        navBar: KtNavBar(title: '生物识别', theme: _t),
        bottom: Column(children: [_signerBtn('启用 Face ID', onPressed: () => context.push('/created')), const SizedBox(height: 12), const Text('暂不启用，仅使用密码', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: SignerColors.text2))]),
        children: [
          const SizedBox(height: 24),
          Center(child: Container(width: 120, height: 120, decoration: BoxDecoration(color: SignerColors.surface, borderRadius: BorderRadius.circular(60), border: Border.all(color: SignerColors.border)), child: const Icon(Icons.face, size: 60, color: SignerColors.blue))),
          Column(children: const [
            Text('启用 Face ID', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: SignerColors.text)),
            SizedBox(height: 10),
            Text('每次签名前都需要验证身份。启用 Face ID 可以更快完成验证，也可以随时改用设备密码。', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, height: 1.7, color: SignerColors.text2)),
          ]),
        ],
      );
}

/// C16 创建成功.
class SignerCreatedScreen extends StatelessWidget {
  const SignerCreatedScreen({super.key});
  @override
  Widget build(BuildContext context) => KtScreen(
        theme: _t,
        gap: 24,
        bottom: Column(children: [_signerBtn('导出公开地址', onPressed: () => context.push('/export')), const SizedBox(height: 12), const Text('稍后再说', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: SignerColors.text2))]),
        children: [
          const SizedBox(height: 48),
          Center(child: Container(width: 96, height: 96, decoration: BoxDecoration(color: SignerColors.ok.withValues(alpha: 0.08), shape: BoxShape.circle), child: Center(child: Container(width: 68, height: 68, decoration: const BoxDecoration(color: SignerColors.ok, shape: BoxShape.circle), child: const Icon(Icons.check, size: 34, color: Color(0xFF0A0C0F)))))),
          Column(children: const [
            Text('钱包创建完成', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: SignerColors.text)),
            SizedBox(height: 8),
            Text('助记词已备份并通过验证', style: TextStyle(fontSize: 14, color: SignerColors.text2)),
          ]),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: SignerColors.surface, borderRadius: BorderRadius.circular(14)),
            child: Column(children: const [
              _KvRow('钱包名称', '主钱包'),
              SizedBox(height: 12),
              _KvRow('助记词备份', '已验证', ok: true),
              SizedBox(height: 12),
              _KvRow('支持网络', 'ETH · POL · TRX · SOL'),
            ]),
          ),
        ],
      );
}

class _KvRow extends StatelessWidget {
  const _KvRow(this.k, this.v, {this.ok = false});
  final String k, v;
  final bool ok;
  @override
  Widget build(BuildContext context) => Row(children: [
        Text(k, style: const TextStyle(fontSize: 13, color: SignerColors.text2)),
        const SizedBox(width: 16),
        Expanded(child: Text(v, textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: ok ? SignerColors.ok : SignerColors.text))),
      ]);
}
