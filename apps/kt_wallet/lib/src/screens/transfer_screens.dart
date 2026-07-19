import 'package:chains/chains.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

import '../state/wallet_scope.dart';
import '../wallets/wallet_model.dart';

Widget _amberWarn(String text) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: WalletColors.amber.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.warning_amber_rounded, size: 16, color: WalletColors.amber),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF9A6503)))),
      ]),
    );

/// W4 转账输入. Live: recipient address is validated against the token's chain
/// (rejecting mispastes and wrong-network addresses) and the amount is parsed
/// with the tested [Amount] type and checked against the available balance.
class TransferInputScreen extends StatefulWidget {
  const TransferInputScreen({super.key});
  @override
  State<TransferInputScreen> createState() => _TransferInputScreenState();
}

class _TransferInputScreenState extends State<TransferInputScreen> {
  // Sending USDT on TRON (6 decimals). Available balance = 3120.00 USDT.
  static const _chain = Chain.tron;
  static const _decimals = 6;
  static const _availableDisplay = '3120';
  static final _available = Amount.parse('3120.00', _decimals, symbol: 'USDT');

  final _addrController = TextEditingController(text: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t');
  final _amountController = TextEditingController(text: '120.00');
  final _feeTiers = const ['慢', '标准', '快'];
  int _fee = 1;

  @override
  void dispose() {
    _addrController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  AddressValidation get _addrCheck => Addresses.validate(_chain, _addrController.text.trim());

  /// Returns the parsed amount if it is valid and within balance, else null.
  Amount? get _amount {
    final text = _amountController.text.trim();
    if (text.isEmpty) return null;
    try {
      final a = Amount.parse(text, _decimals, symbol: 'USDT');
      if (a.raw == BigInt.zero || !(_available >= a)) return null;
      return a;
    } on AmountError {
      return null;
    }
  }

  String? get _amountError {
    final text = _amountController.text.trim();
    if (text.isEmpty) return null; // don't nag before typing
    try {
      final a = Amount.parse(text, _decimals, symbol: 'USDT');
      if (a.raw == BigInt.zero) return '金额需大于 0';
      if (!(_available >= a)) return '余额不足';
      return null;
    } on AmountError {
      return '金额格式不正确';
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = (data?.text ?? '').trim();
    if (text.isNotEmpty) setState(() => _addrController.text = text);
  }

  @override
  Widget build(BuildContext context) {
    final isHot = WalletScope.of(context).current is HotWallet;
    final addrCheck = _addrCheck;
    final canProceed = addrCheck.isValid && _amount != null;
    return KtScreen(
      gap: 16,
      navBar: KtNavBar(title: '转账', onBack: () => Navigator.of(context).maybePop(), trailing: Icons.qr_code_scanner, onTrailing: () {}),
      bottom: KtPrimaryButton(label: '下一步', onPressed: canProceed ? () => context.push(isHot ? '/confirm-hot' : '/confirm-watch') : null),
      children: [
        KtCard(
          padding: const EdgeInsets.all(14),
          child: Row(children: const [
            KtAvatar(color: Color(0xFF26A17B), initial: '₮', size: 36),
            SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('USDT', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: WalletColors.text)),
                SizedBox(height: 2),
                Text('TRON · TRC-20', style: TextStyle(fontSize: 12, color: WalletColors.text2)),
              ]),
            ),
            Icon(Icons.keyboard_arrow_down, size: 18, color: WalletColors.text3),
          ]),
        ),
        KtCard(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('收款地址', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: WalletColors.text2)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _addrController,
                  onChanged: (_) => setState(() {}),
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLines: null,
                  style: const TextStyle(fontSize: 14, fontFamily: KtFonts.mono, color: WalletColors.text),
                  decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none, hintText: '粘贴或输入地址', hintStyle: TextStyle(color: WalletColors.text3)),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(onTap: _paste, child: const Icon(Icons.content_paste, size: 18, color: WalletColors.accent)),
              const SizedBox(width: 10),
              const Icon(Icons.qr_code_scanner, size: 18, color: WalletColors.accent),
            ]),
            const SizedBox(height: 12),
            if (_addrController.text.trim().isEmpty)
              const Text('请输入 TRON 网络收款地址', style: TextStyle(fontSize: 12, color: WalletColors.text3))
            else if (addrCheck.isValid)
              Row(children: const [
                Icon(Icons.check_circle, size: 14, color: WalletColors.green),
                SizedBox(width: 6),
                Text('地址格式正确 · TRON 网络', style: TextStyle(fontSize: 12, color: WalletColors.green)),
              ])
            else
              Row(children: [
                const Icon(Icons.error_outline, size: 14, color: WalletColors.red),
                const SizedBox(width: 6),
                Expanded(child: Text(addrCheck.reason ?? '地址无效', style: const TextStyle(fontSize: 12, color: WalletColors.red))),
              ]),
          ]),
        ),
        KtCard(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('金额', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: WalletColors.text2)),
              GestureDetector(
                onTap: () => setState(() => _amountController.text = _availableDisplay),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: WalletColors.accent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
                  child: const Text('最大', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: WalletColors.accent)),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: TextField(
                  controller: _amountController,
                  onChanged: (_) => setState(() {}),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: WalletColors.text),
                  decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none, hintText: '0', hintStyle: TextStyle(color: WalletColors.text3)),
                ),
              ),
              const SizedBox(width: 8),
              const Padding(padding: EdgeInsets.only(bottom: 4), child: Text('USDT', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: WalletColors.text2))),
            ]),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(_amountError ?? '≈ \$${_amountController.text.trim().isEmpty ? '0.00' : _amountController.text.trim()}', style: TextStyle(fontSize: 12, color: _amountError == null ? WalletColors.text3 : WalletColors.red)),
              const Text('可用 3,120.00 USDT', style: TextStyle(fontSize: 12, color: WalletColors.text3)),
            ]),
          ]),
        ),
        KtCard(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('网络手续费', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: WalletColors.text2)),
              GestureDetector(onTap: () => context.push('/fee'), child: const Text('自定义', style: TextStyle(fontSize: 12, color: WalletColors.accent))),
            ]),
            const SizedBox(height: 12),
            KtSegmented(options: _feeTiers, selected: _fee, onChanged: (i) => setState(() => _fee = i)),
          ]),
        ),
      ],
    );
  }
}

/// W31 手续费选择.
class FeeSelectScreen extends StatefulWidget {
  const FeeSelectScreen({super.key});
  @override
  State<FeeSelectScreen> createState() => _FeeSelectScreenState();
}

class _FeeSelectScreenState extends State<FeeSelectScreen> {
  static const _tiers = [
    ('慢', '≈ 3-5 分钟', '6.8 TRX', r'$0.94'),
    ('标准', '≈ 1 分钟', '13.7 TRX', r'$1.90'),
    ('快', '≈ 15 秒', '27.4 TRX', r'$3.80'),
  ];
  int _selected = 1; // default 标准

  @override
  Widget build(BuildContext context) {
    return KtScreen(
      navBar: KtNavBar(title: '网络手续费', onBack: () => Navigator.of(context).maybePop()),
      bottom: KtPrimaryButton(label: '确认手续费', onPressed: () => context.pop(_tiers[_selected].$1)),
      children: [
        const Text('手续费越高，交易确认越快。费用支付给网络，不进入本 App。',
            style: TextStyle(fontSize: 13, height: 1.5, color: WalletColors.text2)),
        Column(children: [
          for (final (i, tier) in _tiers.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _selected = i),
                child: () {
                  final sel = i == _selected;
                  final (name, eta, fee, fiat) = tier;
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: sel ? WalletColors.accent.withValues(alpha: 0.04) : WalletColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: sel ? WalletColors.accent : WalletColors.border, width: sel ? 1.5 : 1),
                    ),
                    child: Row(children: [
                      Icon(sel ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20, color: sel ? WalletColors.accent : const Color(0xFFD2D7E0)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: WalletColors.text)),
                          const SizedBox(height: 3),
                          Text(eta, style: const TextStyle(fontSize: 12, color: WalletColors.text3)),
                        ]),
                      ),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(fee, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, fontFamily: KtFonts.mono, color: WalletColors.text)),
                        const SizedBox(height: 3),
                        Text(fiat, style: const TextStyle(fontSize: 12, color: WalletColors.text3)),
                      ]),
                    ]),
                  );
                }(),
              ),
            ),
        ]),
        _amberWarn('手续费过低可能导致交易长时间未确认甚至失败。TRON Energy 不足时将燃烧 TRX 抵扣。'),
      ],
    );
  }
}

/// Shared confirm layout for W5 (watch) / W29 (hot).
class TransferConfirmScreen extends StatelessWidget {
  const TransferConfirmScreen({super.key, required this.isHot});
  final bool isHot;
  @override
  Widget build(BuildContext context) {
    return KtScreen(
      gap: 16,
      navBar: KtNavBar(title: '确认交易', onBack: () => Navigator.of(context).maybePop()),
      bottom: Column(children: [
        KtPrimaryButton(label: isHot ? '确认转账' : '生成待签名二维码', onPressed: () => context.push(isHot ? '/transfer-auth' : '/sign-qr')),
        const SizedBox(height: 10),
        Text(isHot ? '验证身份后本机签名并自动广播' : '二维码中不包含助记词或私钥',
            style: const TextStyle(fontSize: 12, color: WalletColors.text3)),
      ]),
      children: [
        Column(children: const [
          Text('-120.00 USDT', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: WalletColors.text)),
          SizedBox(height: 8),
          Text('≈ \$120.00', style: TextStyle(fontSize: 14, color: WalletColors.text2)),
          SizedBox(height: 8),
          NetworkBadge(label: 'TRON · TRC-20', dotColor: ChainColors.tron),
        ]),
        KtCard(
          child: Column(children: const [
            KtDetailRow(label: '转出地址', value: '主钱包 TQm9…3kFa', mono: true),
            SizedBox(height: 14),
            KtDetailRow(label: '收款地址', value: 'TWd4qCEU…nMxR38uQz', mono: true),
            SizedBox(height: 14),
            KtDetailRow(label: '网络手续费', value: '≈ 13.7 TRX（\$1.90）'),
            SizedBox(height: 14),
            KtDetailRow(label: '总支出', value: '120.00 USDT', valueColor: WalletColors.text),
          ]),
        ),
        if (isHot) _amberWarn('该钱包尚未备份助记词。建议先完成备份，再进行转账。'),
      ],
    );
  }
}

/// W6 待签名二维码.
class SignRequestQrScreen extends StatelessWidget {
  const SignRequestQrScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return KtScreen(
      gap: 16,
      navBar: KtNavBar(title: '待签名交易', onBack: () => Navigator.of(context).maybePop(), trailingText: '取消'),
      children: [
        KtCard(
          padding: const EdgeInsets.all(24),
          child: Column(children: const [
            KtQrPlaceholder(size: 240),
            SizedBox(height: 16),
            Text('动态分片 3 / 8', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: WalletColors.text2)),
            SizedBox(height: 8),
            ShardProgressBar(received: 3, total: 8),
          ]),
        ),
        KtCard(
          child: Column(children: const [
            KtDetailRow(label: '网络', value: 'TRON · TRC-20'),
            SizedBox(height: 14),
            KtDetailRow(label: '金额', value: '120.00 USDT'),
            SizedBox(height: 14),
            KtDetailRow(label: '请求 ID', value: 'REQ-7F3A2C', mono: true),
          ]),
        ),
        const Center(child: Text('请使用离线签名手机扫描此二维码', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: WalletColors.text))),
      ],
    );
  }
}

/// W7 扫描签名结果 (dark camera screen).
class ScanResultScreen extends StatelessWidget {
  const ScanResultScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SignerColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          const KtStatusBar(theme: AppTheme.signer),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: KtNavBar(title: '扫描签名结果', theme: AppTheme.signer, leading: Icons.close, onBack: () => Navigator.of(context).maybePop()),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () => context.push('/broadcast-confirm'),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              height: 380,
              decoration: BoxDecoration(color: SignerColors.surface, borderRadius: BorderRadius.circular(20)),
              child: Center(
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(border: Border.all(color: SignerColors.blue, width: 2), borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.qr_code_2, size: 64, color: SignerColors.border),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text('已识别分片 5 / 12', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
          const SizedBox(height: 10),
          const ShardProgressBar(received: 5, total: 12, color: SignerColors.blue, trackColor: SignerColors.border, width: 240),
        ]),
      ),
    );
  }
}

/// W8 广播确认.
class BroadcastConfirmScreen extends StatelessWidget {
  const BroadcastConfirmScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return KtScreen(
      gap: 16,
      navBar: KtNavBar(title: '广播交易', onBack: () => Navigator.of(context).maybePop()),
      bottom: Column(children: [
        KtPrimaryButton(label: '广播交易', onPressed: () => context.go('/broadcast-result')),
        const SizedBox(height: 12),
        const Text('暂不广播', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: WalletColors.text2)),
      ]),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: WalletColors.green.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
          child: Row(children: const [
            Icon(Icons.verified_user, size: 18, color: WalletColors.green),
            SizedBox(width: 10),
            Expanded(child: Text('签名已验证 · 签名者与钱包地址一致，交易内容未被篡改',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF0A7A45)))),
          ]),
        ),
        Column(children: const [
          Text('-120.00 USDT', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: WalletColors.text)),
          SizedBox(height: 8),
          NetworkBadge(label: 'TRON · TRC-20', dotColor: ChainColors.tron),
        ]),
        KtCard(
          child: Column(children: const [
            KtDetailRow(label: '收款地址', value: 'TWd4qCEU…nMxR38uQz', mono: true),
            SizedBox(height: 14),
            KtDetailRow(label: '签名地址', value: 'TQm9xPa2…Vb7L3kFa', mono: true),
            SizedBox(height: 14),
            KtDetailRow(label: '交易 Hash 预览', value: '8f6d2c…a94e07', mono: true),
          ]),
        ),
      ],
    );
  }
}

/// W9 广播结果.
class BroadcastResultScreen extends StatelessWidget {
  const BroadcastResultScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return KtScreen(
      gap: 24,
      bottom: KtPrimaryButton(label: '返回首页', onPressed: () => context.go('/home')),
      children: [
        const SizedBox(height: 24),
        Center(
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(color: WalletColors.green.withValues(alpha: 0.08), shape: BoxShape.circle),
            child: Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(color: WalletColors.green, shape: BoxShape.circle),
                child: const Icon(Icons.check, size: 32, color: Colors.white),
              ),
            ),
          ),
        ),
        Column(children: const [
          Text('交易已提交', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: WalletColors.text)),
          SizedBox(height: 8),
          Text('-120.00 USDT · TRON', style: TextStyle(fontSize: 14, color: WalletColors.text2)),
        ]),
        KtCard(
          child: Column(children: const [
            KtDetailRow(label: '交易 Hash', value: '8f6d2c…a94e07', mono: true),
            SizedBox(height: 14),
            KtDetailRow(label: '状态', value: '确认中 (3/19)', valueColor: WalletColors.accent),
          ]),
        ),
      ],
    );
  }
}

/// W15 交易详情.
class TxDetailScreen extends StatelessWidget {
  const TxDetailScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return KtScreen(
      gap: 16,
      navBar: KtNavBar(title: '交易详情', onBack: () => Navigator.of(context).maybePop(), trailing: Icons.open_in_new, onTrailing: () {}),
      children: [
        Column(children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(color: WalletColors.green.withValues(alpha: 0.08), shape: BoxShape.circle),
            child: const Icon(Icons.check_circle, size: 28, color: WalletColors.green),
          ),
          const SizedBox(height: 10),
          const Text('-120.00 USDT', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: WalletColors.text)),
          const SizedBox(height: 6),
          const Text('已确认 · 今天 14:38', style: TextStyle(fontSize: 13, color: WalletColors.text3)),
        ]),
        KtCard(
          child: Column(children: const [
            KtDetailRow(label: '网络', value: 'TRON · TRC-20'),
            SizedBox(height: 14),
            KtDetailRow(label: '收款地址', value: 'TWd4qCEU…nMxR38uQz', mono: true),
            SizedBox(height: 14),
            KtDetailRow(label: '网络手续费', value: '13.72 TRX（\$1.91）'),
            SizedBox(height: 14),
            KtDetailRow(label: '确认数', value: '19 / 19'),
            SizedBox(height: 14),
            KtDetailRow(label: '请求 ID', value: 'REQ-7F3A2C', mono: true),
          ]),
        ),
      ],
    );
  }
}

/// W30 转账身份验证 (bottom sheet).
class TransferAuthSheet extends StatelessWidget {
  const TransferAuthSheet({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WalletColors.text.withValues(alpha: 0.5),
      body: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(color: WalletColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4, decoration: BoxDecoration(color: WalletColors.border, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Container(
              width: 88, height: 88,
              decoration: BoxDecoration(color: WalletColors.accent.withValues(alpha: 0.06), shape: BoxShape.circle),
              child: const Icon(Icons.face, size: 44, color: WalletColors.accent),
            ),
            const SizedBox(height: 20),
            const Text('验证以确认转账', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: WalletColors.text)),
            const SizedBox(height: 8),
            const Text('每次转账都需要 Face ID 或密码验证', style: TextStyle(fontSize: 13, color: WalletColors.text2)),
            const SizedBox(height: 20),
            KtPrimaryButton(label: '使用 Face ID 验证', onPressed: () => context.go('/broadcast-result')),
            const SizedBox(height: 12),
            const Text('改用密码', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: WalletColors.text2)),
          ]),
        ),
      ),
    );
  }
}
