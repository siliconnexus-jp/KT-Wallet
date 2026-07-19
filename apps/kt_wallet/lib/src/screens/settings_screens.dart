import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

Widget _switch(bool on) => Container(
      width: 44, height: 26,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: on ? WalletColors.accent : const Color(0xFFE1E4EA), borderRadius: BorderRadius.circular(13)),
      child: Align(
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(width: 22, height: 22, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
      ),
    );

/// W16 地址管理.
class AddressBookScreen extends StatelessWidget {
  const AddressBookScreen({super.key});
  static const _contacts = [
    ('A', 'Alice', '0x71c8B2…9F3dA24', 'Ethereum', ChainColors.ethereum),
    ('B', 'Bob 交易所', 'TWd4qCEU…nMxR38uQz', 'TRON', ChainColors.tron),
    ('冷', '冷钱包备份', '0x8f3C2a…7E19bE1', 'Polygon', ChainColors.polygon),
    ('D', 'Dana', '6yKp…Vr2W', 'Solana', ChainColors.solana),
  ];
  @override
  Widget build(BuildContext context) {
    return KtScreen(
      gap: 16,
      navBar: KtNavBar(title: '地址管理', onBack: () => Navigator.of(context).maybePop(), trailing: Icons.add, onTrailing: () {}),
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: WalletColors.surface, borderRadius: BorderRadius.circular(12)),
          child: const Row(children: [Icon(Icons.search, size: 18, color: WalletColors.text3), SizedBox(width: 8), Text('搜索名称或地址', style: TextStyle(fontSize: 14, color: WalletColors.text3))]),
        ),
        KtCard(
          child: Column(children: [
            for (var i = 0; i < _contacts.length; i++) ...[
              if (i > 0) const SizedBox(height: 16),
              Row(children: [
                KtAvatar(color: const Color(0xFFF2F4F7), initial: _contacts[i].$1, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(_contacts[i].$2, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: WalletColors.text)),
                      const SizedBox(width: 8),
                      NetworkBadge(label: _contacts[i].$4, dotColor: _contacts[i].$5),
                    ]),
                    const SizedBox(height: 3),
                    Text(_contacts[i].$3, style: const TextStyle(fontSize: 12, fontFamily: KtFonts.mono, color: WalletColors.text3)),
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
class TokenManageScreen extends StatelessWidget {
  const TokenManageScreen({super.key});
  static const _tokens = [
    (Color(0xFF26A17B), '₮', 'USDT', 'TRON · TRC-20', true),
    (Color(0xFF26A17B), '₮', 'USDT', 'Ethereum · ERC-20', true),
    (Color(0xFF2775CA), r'$', 'USDC', 'Solana · SPL', true),
    (Color(0xFFF0B90B), 'B', 'BUSD', 'Ethereum · ERC-20', false),
    (Color(0xFFFF007A), 'U', 'UNI', 'Ethereum · ERC-20', false),
  ];
  @override
  Widget build(BuildContext context) {
    return KtScreen(
      gap: 16,
      navBar: KtNavBar(title: 'Token 管理', onBack: () => Navigator.of(context).maybePop(), trailing: Icons.add, onTrailing: () {}),
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
                _switch(_tokens[i].$5),
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
  static const _nets = [
    (ChainColors.ethereum, 'Ethereum', 'eth-mainnet.g.alchemy.com', '86 ms', true),
    (ChainColors.polygon, 'Polygon', 'polygon-rpc.com', '112 ms', true),
    (ChainColors.tron, 'TRON', 'api.trongrid.io', '64 ms', true),
    (ChainColors.solana, 'Solana', 'api.mainnet-beta.solana.com', '超时', false),
  ];
  @override
  Widget build(BuildContext context) {
    return KtScreen(
      gap: 16,
      navBar: KtNavBar(title: '网络设置', onBack: () => Navigator.of(context).maybePop()),
      children: [
        for (final (color, name, rpc, ms, ok) in _nets)
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
                    const Text('RPC 节点', style: TextStyle(fontSize: 12, color: WalletColors.text3)),
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
class SecuritySettingsScreen extends StatelessWidget {
  const SecuritySettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return KtScreen(
      gap: 16,
      navBar: KtNavBar(title: '安全设置', onBack: () => Navigator.of(context).maybePop()),
      children: [
        const Text('访问控制', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: WalletColors.text2)),
        KtCard(
          child: Column(children: [
            _row(Icons.lock_outline, 'App 锁', '打开 App 时需要 Face ID', _switch(true)),
            const SizedBox(height: 16),
            _row(Icons.timer_outlined, '自动锁定', '后台超过时限后重新锁定', const Row(mainAxisSize: MainAxisSize.min, children: [Text('1 分钟', style: TextStyle(fontSize: 13, color: WalletColors.text2)), Icon(Icons.chevron_right, size: 16, color: WalletColors.text3)])),
            const SizedBox(height: 16),
            _row(Icons.visibility_off_outlined, '隐私模式', '首页默认隐藏余额', _switch(false)),
          ]),
        ),
        const Text('数据', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: WalletColors.text2)),
        KtCard(
          child: Column(children: const [
            _SimpleRow(Icons.attach_money, '法币单位', 'USD'),
            SizedBox(height: 16),
            _SimpleRow(Icons.language, '显示语言', '简体中文'),
          ]),
        ),
        KtCard(
          child: _row(Icons.delete_outline, '删除观察钱包', '仅移除公开地址与本地记录，不影响资产', const Icon(Icons.chevron_right, size: 16, color: WalletColors.text3), danger: true),
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
  const _SimpleRow(this.icon, this.label, this.value);
  final IconData icon;
  final String label, value;
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 19, color: WalletColors.text2),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: WalletColors.text))),
        Text(value, style: const TextStyle(fontSize: 13, color: WalletColors.text2)),
        const Icon(Icons.chevron_right, size: 16, color: WalletColors.text3),
      ]);
}
