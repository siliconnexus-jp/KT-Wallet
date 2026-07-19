import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

/// W2 资产列表 — search + network filter + full asset list.
class AssetsListScreen extends StatelessWidget {
  const AssetsListScreen({super.key});

  static const _assets = [
    (Color(0xFF627EEA), 'Ξ', 'Ethereum', '2.4805 ETH', r'$8,241.60', '+2.4%', WalletColors.green),
    (Color(0xFF26A17B), '₮', 'USDT', '3,120.00 USDT · TRON', r'$3,120.00', '0.0%', WalletColors.text3),
    (Color(0xFF8247E5), '⬡', 'POL', '2,860.5 POL · Polygon', r'$986.87', '-1.2%', WalletColors.red),
    (Color(0xFF9945FF), '◎', 'Solana', '3.208 SOL', r'$498.85', '+5.1%', WalletColors.green),
    (Color(0xFF2775CA), r'$', 'USDC', '120.00 USDC · Solana', r'$120.00', '0.0%', WalletColors.text3),
  ];

  @override
  Widget build(BuildContext context) {
    return KtScreen(
      navBar: KtNavBar(title: '资产', onBack: () => Navigator.of(context).maybePop(), trailing: Icons.add, onTrailing: () {}),
      children: [
        _SearchBar(),
        const KtSegmented(options: ['全部', 'Ethereum', 'Polygon', 'TRON', 'Solana'], selected: 0),
        KtCard(
          child: Column(children: [
            for (var i = 0; i < _assets.length; i++) ...[
              if (i > 0) const SizedBox(height: 18),
              _AssetTile(_assets[i]),
            ],
          ]),
        ),
      ],
    );
  }
}

class _SearchBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(color: WalletColors.surface, borderRadius: BorderRadius.circular(12)),
        child: const Row(children: [
          Icon(Icons.search, size: 18, color: WalletColors.text3),
          SizedBox(width: 8),
          Text('搜索名称 / Symbol / 合约地址', style: TextStyle(fontSize: 14, color: WalletColors.text3)),
        ]),
      );
}

class _AssetTile extends StatelessWidget {
  const _AssetTile(this.a);
  final (Color, String, String, String, String, String, Color) a;
  @override
  Widget build(BuildContext context) => Row(children: [
        KtAvatar(color: a.$1, initial: a.$2),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.$3, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: WalletColors.text)),
            const SizedBox(height: 3),
            Text(a.$4, style: const TextStyle(fontSize: 12, color: WalletColors.text2)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(a.$5, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: WalletColors.text)),
          const SizedBox(height: 3),
          Text(a.$6, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: a.$7)),
        ]),
      ]);
}

/// W3 Token 详情 — hero balance + info card + recent tx.
class TokenDetailScreen extends StatelessWidget {
  const TokenDetailScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return KtScreen(
      navBar: KtNavBar(title: 'USDT', onBack: () => Navigator.of(context).maybePop(), trailing: Icons.open_in_new, onTrailing: () {}),
      children: [
        Column(children: [
          const KtAvatar(color: Color(0xFF26A17B), initial: '₮', size: 56),
          const SizedBox(height: 10),
          const Text('3,120.00 USDT', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: WalletColors.text)),
          const SizedBox(height: 6),
          const Text('≈ \$3,120.00', style: TextStyle(fontSize: 15, color: WalletColors.text2)),
          const SizedBox(height: 10),
          const NetworkBadge(label: 'TRON · TRC-20', dotColor: ChainColors.tron),
        ]),
        Row(children: [
          Expanded(child: KtPrimaryButton(label: '转账', icon: Icons.north_east, onPressed: () {})),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.qr_code, size: 18, color: WalletColors.accent),
                label: const Text('收款', style: TextStyle(color: WalletColors.accent, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(backgroundColor: WalletColors.surface, side: BorderSide.none, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              ),
            ),
          ),
        ]),
        KtCard(
          child: Column(children: const [
            KtDetailRow(label: '价格', value: r'$1.00'),
            SizedBox(height: 14),
            KtDetailRow(label: '24h 涨跌', value: '+0.02%'),
            SizedBox(height: 14),
            KtDetailRow(label: '合约地址', value: 'TR7NHq…gjLj6t', mono: true),
          ]),
        ),
      ],
    );
  }
}

/// W14 收款 — token selector + QR + address + warning.
class ReceiveScreen extends StatelessWidget {
  const ReceiveScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return KtScreen(
      navBar: KtNavBar(title: '收款', onBack: () => Navigator.of(context).maybePop(), trailing: Icons.ios_share, onTrailing: () {}),
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: WalletColors.surface, borderRadius: BorderRadius.circular(999)),
            child: Row(mainAxisSize: MainAxisSize.min, children: const [
              KtAvatar(color: Color(0xFF26A17B), initial: '₮', size: 24),
              SizedBox(width: 8),
              Text('USDT · TRON', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: WalletColors.text)),
              SizedBox(width: 8),
              Icon(Icons.keyboard_arrow_down, size: 16, color: WalletColors.text3),
            ]),
          ),
        ),
        KtCard(
          padding: const EdgeInsets.all(24),
          child: Column(children: const [
            KtQrPlaceholder(size: 220),
            SizedBox(height: 18),
            Text('TQm9xPa2Wc8hJdU5eRnT6yGb1sVb7L3kFa',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 14, fontFamily: KtFonts.mono, height: 1.6, color: WalletColors.text)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: WalletColors.amber.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            Icon(Icons.warning_amber_rounded, size: 16, color: WalletColors.amber),
            SizedBox(width: 10),
            Expanded(child: Text('仅支持接收 TRON 网络（TRC-20）资产。从其他网络转入将导致资产丢失。',
                style: TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF9A6503)))),
          ]),
        ),
      ],
    );
  }
}
