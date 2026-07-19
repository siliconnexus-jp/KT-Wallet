import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

import '../state/wallet_scope.dart';
import '../wallets/wallet_model.dart';

/// KT Wallet home screen (Pencil W1/W20). Reads the current wallet from
/// [WalletScope], so switching wallets rebuilds it live; hot vs watch wallets
/// change the action row and the backup banner (ui-m.md §8.1).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, this.assets = demoAssets});

  final List<AssetRow> assets;

  @override
  Widget build(BuildContext context) {
    final wallet = WalletScope.of(context).current!;
    final isHot = wallet is HotWallet;
    return Scaffold(
      backgroundColor: WalletColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  _Header(wallet: wallet, onTapPill: () => context.push('/switcher')),
                  if (isHot && !wallet.backedUp) ...[
                    const SizedBox(height: 20),
                    const _BackupBanner(),
                  ],
                  const SizedBox(height: 24),
                  const _Balance(amount: r'$862.40', change: '+\$12.06 (+1.4%) 过去24小时'),
                  const SizedBox(height: 24),
                  _ActionRow(isHot: isHot),
                  const SizedBox(height: 24),
                  const _NetworkChips(),
                  const SizedBox(height: 24),
                  _AssetsCard(assets: assets),
                ],
              ),
            ),
            const _TabBar(),
          ],
        ),
      ),
    );
  }
}

const demoAssets = [
  AssetRow(Color(0xFF26A17B), '₮', 'USDT', '500.00 USDT · TRON', r'$500.00', '0.0%', WalletColors.text3),
  AssetRow(Color(0xFF627EEA), 'Ξ', 'Ethereum', '0.0842 ETH', r'$279.80', '+2.4%', WalletColors.green),
  AssetRow(Color(0xFF9945FF), '◎', 'Solana', '0.531 SOL', r'$82.60', '+5.1%', WalletColors.green),
];

class AssetRow {
  const AssetRow(this.color, this.letter, this.name, this.sub, this.value, this.change, this.changeColor);
  final Color color;
  final String letter, name, sub, value, change;
  final Color changeColor;
}

class _Header extends StatelessWidget {
  const _Header({required this.wallet, this.onTapPill});
  final Wallet wallet;
  final VoidCallback? onTapPill;
  @override
  Widget build(BuildContext context) {
    final kind = wallet is HotWallet ? WalletKind.hot : WalletKind.watch;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          onTap: onTapPill,
          child: Container(
          padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
          decoration: BoxDecoration(
            color: WalletColors.surface,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Avatar(color: Color(wallet.avatarColor), initial: wallet.name.characters.first, size: 26),
              const SizedBox(width: 8),
              Text(wallet.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: WalletColors.text)),
              const SizedBox(width: 8),
              WalletTypeBadge(kind: kind),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down, size: 18, color: WalletColors.text2),
            ],
          ),
        ),
        ),
        const Icon(Icons.settings_outlined, size: 22, color: WalletColors.text2),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.color, required this.initial, required this.size});
  final Color color;
  final String initial;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Text(initial, style: TextStyle(fontSize: size * 0.46, fontWeight: FontWeight.w600, color: Colors.white)),
      );
}

class _BackupBanner extends StatelessWidget {
  const _BackupBanner();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: WalletColors.amber.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, size: 16, color: WalletColors.amber),
            const SizedBox(width: 10),
            const Expanded(child: Text('尚未备份助记词，存在丢失风险', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF9A6503)))),
            Text('立即备份', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: WalletColors.amber)),
          ],
        ),
      );
}

class _Balance extends StatelessWidget {
  const _Balance({required this.amount, required this.change});
  final String amount, change;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Text('总资产估值 (USD)', style: TextStyle(fontSize: 13, color: WalletColors.text2)),
            SizedBox(width: 6),
            Icon(Icons.visibility_outlined, size: 14, color: WalletColors.text3),
          ]),
          const SizedBox(height: 6),
          Text(amount, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: WalletColors.text)),
          const SizedBox(height: 6),
          Text(change, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: WalletColors.green)),
        ],
      );
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.isHot});
  final bool isHot;
  @override
  Widget build(BuildContext context) {
    final actions = isHot
        ? const [('收款', Icons.qr_code, false), ('转账', Icons.north_east, true), ('记录', Icons.history, false), ('更多', Icons.more_horiz, false)]
        : const [('收款', Icons.qr_code, false), ('转账', Icons.north_east, true), ('扫签名', Icons.qr_code_scanner, false), ('记录', Icons.history, false)];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final (label, icon, primary) in actions)
          Column(children: [
            Container(
              width: 54,
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: primary ? WalletColors.accent : WalletColors.surface, shape: BoxShape.circle),
              child: Icon(icon, size: 22, color: primary ? Colors.white : WalletColors.accent),
            ),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: WalletColors.text2)),
          ]),
      ],
    );
  }
}

class _NetworkChips extends StatelessWidget {
  const _NetworkChips();
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: const Row(children: [
          NetworkBadge(label: 'Ethereum', dotColor: ChainColors.ethereum),
          SizedBox(width: 8),
          NetworkBadge(label: 'Polygon', dotColor: ChainColors.polygon),
          SizedBox(width: 8),
          NetworkBadge(label: 'TRON', dotColor: ChainColors.tron),
          SizedBox(width: 8),
          NetworkBadge(label: 'Solana', dotColor: ChainColors.solana),
        ]),
      );
}

class _AssetsCard extends StatelessWidget {
  const _AssetsCard({required this.assets});
  final List<AssetRow> assets;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: WalletColors.surface, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('资产', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: WalletColors.text)),
                Row(children: [
                  Text('全部', style: TextStyle(fontSize: 13, color: WalletColors.text2)),
                  Icon(Icons.chevron_right, size: 14, color: WalletColors.text2),
                ]),
              ],
            ),
            const SizedBox(height: 18),
            for (var i = 0; i < assets.length; i++) ...[
              if (i > 0) const SizedBox(height: 18),
              _AssetTile(assets[i]),
            ],
          ],
        ),
      );
}

class _AssetTile extends StatelessWidget {
  const _AssetTile(this.a);
  final AssetRow a;
  @override
  Widget build(BuildContext context) => Row(
        children: [
          _Avatar(color: a.color, initial: a.letter, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: WalletColors.text)),
                const SizedBox(height: 3),
                Text(a.sub, style: const TextStyle(fontSize: 12, color: WalletColors.text2)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(a.value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: WalletColors.text)),
              const SizedBox(height: 3),
              Text(a.change, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: a.changeColor)),
            ],
          ),
        ],
      );
}

class _TabBar extends StatelessWidget {
  const _TabBar();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Container(
          height: 56,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: WalletColors.surface,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [BoxShadow(color: WalletColors.text.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 8))],
          ),
          child: Row(
            children: [
              for (final (label, icon, sel) in const [('首页', Icons.home_filled, true), ('资产', Icons.pie_chart, false), ('记录', Icons.history, false), ('设置', Icons.settings, false)])
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(color: sel ? WalletColors.accent.withValues(alpha: 0.08) : null, borderRadius: BorderRadius.circular(22)),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 22, color: sel ? WalletColors.accent : WalletColors.text3),
                        const SizedBox(height: 2),
                        Text(label, style: TextStyle(fontSize: 10, fontWeight: sel ? FontWeight.w600 : FontWeight.w500, color: sel ? WalletColors.accent : WalletColors.text3)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
}
