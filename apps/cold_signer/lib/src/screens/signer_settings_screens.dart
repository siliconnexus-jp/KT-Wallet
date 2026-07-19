import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

const _t = AppTheme.signer;
Widget _card(Widget child, {EdgeInsets padding = const EdgeInsets.all(16)}) =>
    Container(padding: padding, decoration: BoxDecoration(color: SignerColors.surface, borderRadius: BorderRadius.circular(14)), child: child);

Widget _switch(bool on) => Container(
      width: 44, height: 26, padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: on ? SignerColors.ok : SignerColors.surface2, borderRadius: BorderRadius.circular(13)),
      child: Align(alignment: on ? Alignment.centerRight : Alignment.centerLeft, child: Container(width: 22, height: 22, decoration: BoxDecoration(color: on ? const Color(0xFF0A0C0F) : const Color(0xFF5A616C), shape: BoxShape.circle))),
    );

/// C18 签名记录.
class SignerRecordsScreen extends StatelessWidget {
  const SignerRecordsScreen({super.key});
  static const _rows = [
    (Icons.north_east, 'Token Transfer · TRON', '14:35 · REQ-7F3A2C', '120.00 USDT', '已签名', SignerColors.ok),
    (Icons.north_east, 'Transfer · Ethereum', '09:18 · REQ-8D22E1', '0.25 ETH', '已签名', SignerColors.ok),
    (Icons.block, '未知合约调用 · TRON', '07-08 · REQ-9AB301', '—', '已拒绝', SignerColors.danger),
    (Icons.schedule, 'Token Transfer · Polygon', '07-02 · REQ-1C55A7', '300 USDT', '已过期', SignerColors.text2),
  ];
  @override
  Widget build(BuildContext context) {
    return KtScreen(
      theme: _t,
      gap: 16,
      navBar: KtNavBar(title: '签名记录', theme: _t, onBack: () => Navigator.of(context).maybePop()),
      children: [
        const KtSegmented(theme: _t, options: ['全部', '已签名', '已拒绝', '已过期'], selected: 0),
        _card(Column(children: [
          for (var i = 0; i < _rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            () {
              final (icon, title, sub, amt, state, color) = _rows[i];
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
    return KtScreen(
      theme: _t,
      gap: 16,
      navBar: KtNavBar(title: '钱包管理', theme: _t, onBack: () => Navigator.of(context).maybePop()),
      children: [
        _card(Row(children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(color: SignerColors.surface2, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.wallet, size: 24, color: SignerColors.ok)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            Text('主钱包', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: SignerColors.text)),
            SizedBox(height: 4),
            Text('WLT-3E8A91 · 创建于 2026-06-07', style: TextStyle(fontSize: 12, fontFamily: KtFonts.mono, color: Color(0xFF5A616C))),
          ])),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: SignerColors.ok.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(999)), child: const Text('已备份', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: SignerColors.ok))),
        ])),
        _card(Column(children: [
          _row(Icons.edit, '修改钱包名称', ''),
          const SizedBox(height: 16),
          _row(Icons.checklist, '助记词备份验证', '定期抽查助记词是否仍能正确抄录'),
          const SizedBox(height: 16),
          _row(Icons.qr_code, '导出公开地址', ''),
        ])),
        Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: SignerColors.danger.withValues(alpha: 0.2))),
          child: _card(Column(children: [
            _row(Icons.delete_outline, '删除钱包', '需要密码、生物识别和确认文字', danger: true),
            const SizedBox(height: 16),
            _row(Icons.dangerous, '销毁全部钱包数据', '不可恢复，仅在设备处置前使用', danger: true),
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
      navBar: KtNavBar(title: '安全设置', theme: _t, onBack: () => Navigator.of(context).maybePop()),
      children: [
        const Text('验证策略', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: SignerColors.text2)),
        _card(Column(children: [
          toggleRow(Icons.face, '生物识别', 'Face ID 用于解锁与签名', true),
          const SizedBox(height: 16),
          toggleRow(Icons.edit, '每次签名验证', '不可关闭（V1 强制）', true),
        ])),
        const Text('访问', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: SignerColors.text2)),
        _card(Column(children: [
          Row(children: const [
            Icon(Icons.lock, size: 19, color: SignerColors.text2),
            SizedBox(width: 12),
            Expanded(child: Text('修改 App 密码', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: SignerColors.text))),
            Icon(Icons.chevron_right, size: 16, color: Color(0xFF5A616C)),
          ]),
          const SizedBox(height: 16),
          Row(children: const [
            Icon(Icons.no_photography, size: 19, color: SignerColors.text2),
            SizedBox(width: 12),
            Expanded(child: Text('截图与录屏防护', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: SignerColors.text))),
            Text('已启用', style: TextStyle(fontSize: 13, color: SignerColors.ok)),
          ]),
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
    return KtScreen(
      theme: _t,
      gap: 20,
      navBar: KtNavBar(title: '删除钱包', theme: _t, onBack: () => Navigator.of(context).maybePop()),
      bottom: Column(children: [
        SizedBox(width: double.infinity, height: 52, child: FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFF0A0C0F)), label: const Text('永久删除钱包', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF0A0C0F))), style: FilledButton.styleFrom(backgroundColor: SignerColors.danger, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
        const SizedBox(height: 12),
        const Text('取消', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: SignerColors.text2)),
      ]),
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (final (label, done, n) in const [('密码', true, '1'), ('生物识别', true, '2'), ('确认文字', false, '3')]) ...[
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            Row(children: [Icon(Icons.warning_amber_rounded, size: 18, color: SignerColors.danger), SizedBox(width: 8), Text('此操作不可恢复', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: SignerColors.danger))]),
            SizedBox(height: 10),
            Text('删除后，本机将清除该钱包的全部密钥数据。若助记词未备份或备份遗失，资产将永久无法找回。', style: TextStyle(fontSize: 13, height: 1.6, color: SignerColors.text2)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('请输入「删除钱包」以继续', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: SignerColors.text2)),
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
