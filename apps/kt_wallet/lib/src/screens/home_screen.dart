import 'package:chains/chains.dart' show Chain;
import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../l10n/app_localizations.dart';
import '../market/balance_service.dart';
import '../market/history_controller.dart';
import '../market/history_service.dart';
import '../market/market_controller.dart';
import '../market/market_scope.dart';
import '../market/token_balance_service.dart';
import '../widgets/market_offline_banner.dart';
import '../widgets/token_icon.dart';
import '../state/app_prefs.dart';
import '../state/networks.dart';
import '../state/wallet_scope.dart';
import '../wallets/wallet_model.dart';

/// KT Wallet home screen (Pencil W1/W20). Reads the current wallet from
/// [WalletScope], so switching wallets rebuilds it live; hot vs watch wallets
/// change the action row and the backup banner (ui-m.md §8.1).
/// Stateful shell: the bottom tab bar switches between the four top-level tabs
/// (home / assets / records / settings) via an IndexedStack.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.assets = demoAssets});
  final List<AssetRow> assets;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // First live refresh on home entry (post-frame: refresh() notifies
    // synchronously, which must not happen mid-build). No-op without a
    // MarketScope (gallery/goldens) and after the first refresh.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) MarketScope.read(context)?.refreshIfNeeded();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WalletColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  _HomeTab(
                    assets: widget.assets,
                    onViewAll: () => setState(() => _tab = 1),
                    onOpenSettings: () => setState(() => _tab = 3),
                  ),
                  const _AssetsTab(),
                  const _RecordsTab(),
                  const _SettingsTab(),
                ],
              ),
            ),
            _TabBar(selected: _tab, onTap: (i) => setState(() => _tab = i)),
          ],
        ),
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({required this.assets, this.onViewAll, this.onOpenSettings});
  final List<AssetRow> assets;
  final VoidCallback? onViewAll;
  final VoidCallback? onOpenSettings;

  /// "更多" quick action: bottom sheet with the secondary destinations.
  Future<void> _showMore(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final entries = <(IconData, String, String)>[
      (Icons.qr_code_2, l10n.connectColdWallet, '/connect-cold'),
      (Icons.contacts_outlined, l10n.settingsAddressBook, '/address-book'),
      (
        Icons.account_balance_wallet_outlined,
        l10n.settingsWalletManage,
        '/wallet-manage',
      ),
    ];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: WalletColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: WalletColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    l10n.actionMore,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: WalletColors.text,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            for (final (icon, label, route) in entries)
              ListTile(
                leading: Icon(icon, size: 22, color: WalletColors.accent),
                title: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: WalletColors.text,
                  ),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: WalletColors.text3,
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  context.push(route);
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final wallet = WalletScope.of(context).current!;
    final isHot = wallet is HotWallet;
    // No scope (gallery/goldens) → today's demo constants, byte-for-byte.
    // Scope present but everything errored → demo constants behind an
    // explicit offline banner. Otherwise → live values ('--' while loading).
    final market = MarketScope.maybeOf(context);
    final offline = market?.isOffline ?? false;
    final live = market != null;
    // ANY active chain on a testnet → the fiat total is meaningless (testnet
    // assets have no market price): show '--' plus the explanatory note.
    // Absent scope falls back to the all-mainnet controller → false, so demo
    // and golden renderings are untouched.
    final testnet = NetworkScope.of(context).anyTestnetActive;
    final total = live ? market.totalUsd : null;
    final listView = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        _Header(
          wallet: wallet,
          onTapPill: () => context.push('/switcher'),
          onTapSettings: onOpenSettings,
        ),
        if (offline) ...[
          const SizedBox(height: 12),
          const MarketOfflineBanner(),
        ],
        if (isHot && !wallet.backedUp) ...[
          const SizedBox(height: 20),
          const _BackupBanner(),
        ],
        const SizedBox(height: 24),
        _Balance(
          amount: live
              ? (testnet || total == null ? '--' : formatUsd(total))
              : r'$862.40',
          // No 24h-change source yet — live mode omits the line rather than
          // showing an invented delta.
          change: live ? '' : '+\$12.06 (+1.4%) ${l10n.balanceChangePeriod}',
        ),
        if (live && testnet) ...[
          const SizedBox(height: 12),
          const _FiatHiddenTestnetNote(),
        ],
        const SizedBox(height: 24),
        _ActionRow(isHot: isHot, onMore: () => _showMore(context)),
        const SizedBox(height: 24),
        const _NetworkChips(),
        const SizedBox(height: 24),
        _AssetsCard(
          assets: live ? liveAssetRows(market) : assets,
          onViewAll: onViewAll,
        ),
      ],
    );
    if (market == null) return listView;
    return RefreshIndicator(
      color: WalletColors.accent,
      onRefresh: () => market.refresh(),
      child: listView,
    );
  }
}

class _AssetsTab extends StatelessWidget {
  const _AssetsTab();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final market = MarketScope.maybeOf(context);
    final offline = market?.isOffline ?? false;
    final live = market != null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              l10n.tabAssets,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: WalletColors.text,
              ),
            ),
            const TestnetBadge(),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          l10n.assetsSortByValue,
          style: const TextStyle(fontSize: 13, color: WalletColors.text3),
        ),
        const SizedBox(height: 20),
        if (offline) ...[
          const MarketOfflineBanner(),
          const SizedBox(height: 12),
        ],
        _AssetsCard(assets: live ? liveAssetRows(market) : demoAssets),
      ],
    );
  }
}

class _RecordsTab extends StatefulWidget {
  const _RecordsTab();
  @override
  State<_RecordsTab> createState() => _RecordsTabState();
}

class _RecordsTabState extends State<_RecordsTab> {
  /// Lazily-owned [HistoryController], mounted the first time this tab builds
  /// under a live market context (no `main.dart` wiring). Tests inject their
  /// own controller via [HistoryScope], which always wins over the lazy one.
  HistoryController? _owned;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_owned == null &&
        HistoryScope.maybeOf(context) == null &&
        MarketScope.maybeOf(context) != null) {
      final controller = HistoryController(
        wallets: WalletScope.of(context),
        // TronGrid endpoint: persisted RPC override → ACTIVE tron network's
        // rpcUrl (Nile is TronGrid-compatible, same paths) → builtin default;
        // a configured gateway unlocks eth/polygon/solana history too.
        service: HistoryService(
          endpoints: effectiveRpcEndpoints(
            AppPrefsScope.maybeOf(context),
            NetworkScope.maybeOf(context),
          ),
          gateway: prefsGatewayResolver(AppPrefsScope.maybeOf(context)),
        ),
      );
      _owned = controller..addListener(_onHistoryChanged);
      // Post-frame: refresh() notifies synchronously, never mid-build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) controller.refreshIfNeeded();
      });
    }
  }

  void _onHistoryChanged() => setState(() {});

  @override
  void dispose() {
    _owned?.removeListener(_onHistoryChanged);
    _owned?.dispose();
    super.dispose();
  }

  /// Demo rows exactly as before live wiring existed (gallery/goldens, and
  /// the labeled offline fallback).
  Widget _demoCard(BuildContext context, AppLocalizations l10n) => KtCard(
    child: Column(
      children: [
        for (final (i, r) in _demoRecords(l10n).indexed) ...[
          if (i > 0)
            Divider(
              height: 1,
              color: WalletColors.text.withValues(alpha: 0.06),
            ),
          _RecordRow(record: r, onTap: () => context.push('/tx-detail')),
        ],
      ],
    ),
  );

  /// Loading placeholder: three '--' shimmer rows, mirroring the row layout.
  Widget _loadingCard() => KtCard(
    child: Column(
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              color: WalletColors.text.withValues(alpha: 0.06),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: WalletColors.text3.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '--',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: WalletColors.text3,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '--',
                        style: TextStyle(
                          fontSize: 12,
                          color: WalletColors.text3,
                        ),
                      ),
                    ],
                  ),
                ),
                const Text(
                  '--',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: WalletColors.text3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );

  Widget _liveCard(
    BuildContext context,
    AppLocalizations l10n,
    List<ChainTxRecord> records,
  ) {
    if (records.isEmpty) {
      return KtCard(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              l10n.historyEmpty,
              style: const TextStyle(fontSize: 13, color: WalletColors.text3),
            ),
          ),
        ),
      );
    }
    return KtCard(
      child: Column(
        children: [
          for (final (i, r) in records.indexed) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: WalletColors.text.withValues(alpha: 0.06),
              ),
            _RecordRow(
              record: _TxRecord(
                r.outgoing,
                r.amountText ?? '--',
                _formatRecordTime(l10n, r.timestamp),
              ),
              onTap: () => context.push('/tx-detail'),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final history = HistoryScope.maybeOf(context) ?? _owned;
    final Widget body;
    if (history == null) {
      // No live context (gallery/goldens): demo rows, byte-for-byte.
      body = _demoCard(context, l10n);
    } else if (history.allUnsupported) {
      // No chain in this context has a keyless history API — say so instead
      // of showing demo rows that could pass for live data.
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Text(
            l10n.historyUnsupportedChain,
            style: const TextStyle(fontSize: 13, color: WalletColors.text3),
          ),
        ),
      );
    } else if (history.isLoading) {
      body = _loadingCard();
    } else if (history.isError) {
      body = Column(
        children: [
          const MarketOfflineBanner(),
          const SizedBox(height: 12),
          Center(
            child: Text(
              l10n.walletLoadErrorDesc,
              style: const TextStyle(fontSize: 13, color: WalletColors.text3),
            ),
          ),
        ],
      );
    } else {
      body = _liveCard(context, l10n, history.records);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              l10n.recordsTitle,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: WalletColors.text,
              ),
            ),
            const TestnetBadge(),
          ],
        ),
        const SizedBox(height: 20),
        body,
      ],
    );
  }
}

/// "今天 14:32" / "昨天 09:11" / "7月17日 20:04"-style timestamp, reusing the
/// existing date l10n keys so all three languages come for free.
String _formatRecordTime(AppLocalizations l10n, DateTime t) {
  final now = DateTime.now();
  final day = DateTime(t.year, t.month, t.day);
  final today = DateTime(now.year, now.month, now.day);
  final hm =
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  if (day == today) return '${l10n.dateToday} $hm';
  if (day == today.subtract(const Duration(days: 1)))
    return '${l10n.dateYesterday} $hm';
  return '${l10n.monthDay(t.month, t.day)} $hm';
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record, this.onTap});
  final _TxRecord record;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sent = record.outgoing;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (sent ? WalletColors.text3 : WalletColors.green)
                    .withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                sent ? Icons.arrow_upward : Icons.arrow_downward,
                size: 20,
                color: sent ? WalletColors.text3 : WalletColors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sent ? l10n.txSent : l10n.txReceived,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: WalletColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    record.time,
                    style: const TextStyle(
                      fontSize: 12,
                      color: WalletColors.text3,
                    ),
                  ),
                ],
              ),
            ),
            // Unparseable live amounts render as a plain '--' (no sign);
            // demo rows always carry an amount, so their output is unchanged.
            Text(
              record.amount == '--'
                  ? '--'
                  : '${sent ? '-' : '+'}${record.amount}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: sent ? WalletColors.text : WalletColors.green,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TxRecord {
  const _TxRecord(this.outgoing, this.amount, this.time);
  final bool outgoing;
  final String amount, time;
}

List<_TxRecord> _demoRecords(AppLocalizations l10n) => [
  _TxRecord(true, '120.00 USDT', '${l10n.dateToday} 14:32'),
  _TxRecord(false, '0.05 ETH', '${l10n.dateYesterday} 09:11'),
  _TxRecord(true, '1.2 SOL', '${l10n.monthDay(7, 17)} 20:04'),
  _TxRecord(false, '300.00 USDT', '${l10n.monthDay(7, 15)} 11:47'),
];

class _SettingsTab extends StatelessWidget {
  const _SettingsTab();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = _settingsItems(l10n);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              l10n.tabSettings,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: WalletColors.text,
              ),
            ),
            const TestnetBadge(),
          ],
        ),
        const SizedBox(height: 20),
        KtCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final (i, item) in items.indexed) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    indent: 56,
                    color: WalletColors.text.withValues(alpha: 0.06),
                  ),
                _SettingsRow(item: item, onTap: () => context.push(item.route)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.item, this.onTap});
  final _SettingsItem item;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Icon(item.icon, size: 20, color: WalletColors.accent),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              item.label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: WalletColors.text,
              ),
            ),
          ),
          const Icon(Icons.chevron_right, size: 20, color: WalletColors.text3),
        ],
      ),
    ),
  );
}

class _SettingsItem {
  const _SettingsItem(this.icon, this.label, this.route);
  final IconData icon;
  final String label, route;
}

List<_SettingsItem> _settingsItems(AppLocalizations l10n) => [
  _SettingsItem(
    Icons.account_balance_wallet_outlined,
    l10n.settingsWalletManage,
    '/wallet-manage',
  ),
  _SettingsItem(Icons.shield_outlined, l10n.settingsSecurity, '/security'),
  _SettingsItem(
    Icons.contacts_outlined,
    l10n.settingsAddressBook,
    '/address-book',
  ),
  _SettingsItem(Icons.hub_outlined, l10n.settingsNetwork, '/network'),
  _SettingsItem(Icons.toll_outlined, l10n.settingsTokenManage, '/token-manage'),
];

const demoAssets = [
  AssetRow(
    Color(0xFF26A17B),
    '₮',
    'USDT',
    '500.00 USDT · TRON',
    r'$500.00',
    '0.0%',
    WalletColors.text3,
  ),
  AssetRow(
    Color(0xFF627EEA),
    'Ξ',
    'Ethereum',
    '0.0842 ETH',
    r'$279.80',
    '+2.4%',
    WalletColors.green,
  ),
  AssetRow(
    Color(0xFF9945FF),
    '◎',
    'Solana',
    '0.531 SOL',
    r'$82.60',
    '+5.1%',
    WalletColors.green,
  ),
];

/// Display metadata for the live native-coin rows (token balances arrive with
/// wallet-core): coin, display name, symbol, fallback color + glyph.
const liveChainRows = [
  (Coin.eth, 'Ethereum', 'ETH', Color(0xFF627EEA), 'Ξ'),
  (Coin.polygon, 'Polygon', 'POL', Color(0xFF8247E5), '⬡'),
  (Coin.base, 'Base', 'ETH', Color(0xFF0052FF), 'B'),
  (Coin.arbitrum, 'Arbitrum', 'ETH', Color(0xFF28A0F0), 'A'),
  (Coin.avalanche, 'Avalanche', 'AVAX', Color(0xFFE84142), 'A'),
  (Coin.tron, 'TRON', 'TRX', Color(0xFF26A17B), '₮'),
  (Coin.solana, 'Solana', 'SOL', Color(0xFF9945FF), '◎'),
];

/// Fallback avatar color + glyph per built-in token symbol ([TokenIcon]
/// renders the bundled brand PNG; these only show for missing assets).
const tokenRowMeta = {
  'USDT': (Color(0xFF26A17B), '₮'),
  'USDC': (Color(0xFF2775CA), r'$'),
};

/// One live asset row for a registry token, in the demo rows' visual shape
/// ('500.00 USDT · TRON'). Loading/errored tokens render '--' — never a
/// fabricated number.
AssetRow liveTokenRow(MarketController market, TokenInfo token) {
  final result = market.tokenBalanceFor(token.id);
  final amount = result.amount;
  final ok = result.status == BalanceStatus.ok && amount != null;
  final fiat = market.tokenFiatValueUsd(token);
  final (color, glyph) =
      tokenRowMeta[token.symbol] ??
      (WalletColors.accent, token.symbol.substring(0, 1));
  return AssetRow(
    color,
    glyph,
    token.symbol,
    '${ok ? amount.format(maxFraction: 6) : '--'} ${token.symbol} · ${token.network}',
    fiat == null ? '--' : formatUsd(fiat),
    '',
    WalletColors.text3,
  );
}

/// Builds the asset rows from live market data: the four native rows, then
/// the registry tokens. Loading and errored chains render '--' (never a
/// fabricated number); no 24h-change feed exists yet, so the change column
/// stays empty in live mode.
List<AssetRow> liveAssetRows(MarketController market) => [
  for (final (coin, name, symbol, color, glyph) in liveChainRows)
    () {
      final result = market.balanceFor(coin);
      final amount = result.amount;
      final ok = result.status == BalanceStatus.ok && amount != null;
      final fiat = market.fiatValueUsd(coin);
      return AssetRow(
        color,
        glyph,
        name,
        ok ? '${amount.format(maxFraction: 6)} $symbol' : '-- $symbol',
        fiat == null ? '--' : formatUsd(fiat),
        '',
        WalletColors.text3,
      );
    }(),
  for (final token in market.tokens) liveTokenRow(market, token),
];

class AssetRow {
  const AssetRow(
    this.color,
    this.letter,
    this.name,
    this.sub,
    this.value,
    this.change,
    this.changeColor,
  );
  final Color color;
  final String letter, name, sub, value, change;
  final Color changeColor;
}

class _Header extends StatelessWidget {
  const _Header({required this.wallet, this.onTapPill, this.onTapSettings});
  final Wallet wallet;
  final VoidCallback? onTapPill;
  final VoidCallback? onTapSettings;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isHot = wallet is HotWallet;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
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
                    _Avatar(
                      color: Color(wallet.avatarColor),
                      initial: wallet.name.characters.first,
                      size: 26,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      wallet.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: WalletColors.text,
                      ),
                    ),
                    const SizedBox(width: 8),
                    WalletTypeBadge(
                      kind: isHot ? WalletKind.hot : WalletKind.watch,
                      label: isHot ? l10n.walletKindHot : l10n.walletKindWatch,
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.keyboard_arrow_down,
                      size: 18,
                      color: WalletColors.text2,
                    ),
                  ],
                ),
              ),
            ),
            // Amber testnet pill next to the wallet pill whenever ANY active
            // chain is a testnet; renders nothing (zero-size) on all-mainnet,
            // keeping demo/golden layouts byte-identical.
            const TestnetBadge(),
          ],
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTapSettings,
          child: const Icon(
            Icons.settings_outlined,
            size: 22,
            color: WalletColors.text2,
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.color,
    required this.initial,
    required this.size,
  });
  final Color color;
  final String initial;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    child: Text(
      initial,
      style: TextStyle(
        fontSize: size * 0.46,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),
  );
}

/// Compact amber "TESTNET" pill, visible on every home tab whenever ANY
/// active chain instance is a testnet. Reads the enclosing [NetworkScope]
/// (registering a dependency, so environment switches update it live);
/// without a scope the mainnet-default fallback keeps it zero-size —
/// demo/golden renderings are unchanged.
class TestnetBadge extends StatelessWidget {
  const TestnetBadge({super.key});

  @override
  Widget build(BuildContext context) {
    if (!NetworkScope.of(context).anyTestnetActive) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: WalletColors.amber.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          l10n.testnetBadge,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            color: WalletColors.amber,
          ),
        ),
      ),
    );
  }
}

/// Small "testnet assets have no market price" note under the '--' total,
/// visually consistent with [MarketOfflineBanner] (same strip styling).
class _FiatHiddenTestnetNote extends StatelessWidget {
  const _FiatHiddenTestnetNote();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: WalletColors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.science_outlined,
            size: 14,
            color: WalletColors.amber,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.fiatHiddenTestnet,
              style: const TextStyle(fontSize: 12, color: WalletColors.text3),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupBanner extends StatelessWidget {
  const _BackupBanner();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/create-warn'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: WalletColors.amber.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 16,
              color: WalletColors.amber,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.backupBannerText,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF9A6503),
                ),
              ),
            ),
            Text(
              l10n.backupNow,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: WalletColors.amber,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Balance extends StatefulWidget {
  const _Balance({required this.amount, required this.change});
  final String amount, change;
  @override
  State<_Balance> createState() => _BalanceState();
}

class _BalanceState extends State<_Balance> {
  bool _hidden = false;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.balanceTitle,
              style: const TextStyle(fontSize: 13, color: WalletColors.text2),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _hidden = !_hidden),
              child: Icon(
                _hidden
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 14,
                color: WalletColors.text3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _hidden ? '••••••' : widget.amount,
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: WalletColors.text,
          ),
        ),
        if (widget.change.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            _hidden ? '••••' : widget.change,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: WalletColors.green,
            ),
          ),
        ],
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.isHot, this.onMore});
  final bool isHot;
  final VoidCallback? onMore;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final actions = isHot
        ? <(String, IconData, bool, String?)>[
            (l10n.actionReceive, Icons.qr_code, false, '/receive'),
            (l10n.actionSend, Icons.north_east, true, '/transfer'),
            (l10n.tabRecords, Icons.history, false, '/tx-detail'),
            (l10n.actionMore, Icons.more_horiz, false, null),
          ]
        : <(String, IconData, bool, String?)>[
            (l10n.actionReceive, Icons.qr_code, false, '/receive'),
            (l10n.actionSend, Icons.north_east, true, '/transfer'),
            (l10n.actionScanSign, Icons.qr_code_scanner, false, '/scan-result'),
            (l10n.tabRecords, Icons.history, false, '/tx-detail'),
          ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final (label, icon, primary, route) in actions)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: route == null ? onMore : () => context.push(route),
            child: Column(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: primary ? WalletColors.accent : WalletColors.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 22,
                    color: primary ? Colors.white : WalletColors.accent,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: WalletColors.text2,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _NetworkChips extends StatelessWidget {
  const _NetworkChips();

  static const _chainDots = [
    (Chain.ethereum, ChainColors.ethereum),
    (Chain.polygon, ChainColors.polygon),
    (Chain.tron, ChainColors.tron),
    (Chain.solana, ChainColors.solana),
  ];

  @override
  Widget build(BuildContext context) {
    // Chip labels follow the ACTIVE network per chain (Sepolia / Amoy / Nile /
    // Devnet under the testnet environment). The scope-absent fallback is the
    // all-mainnet profile, whose names are exactly the previous literals —
    // demo/golden renderings unchanged.
    final networks = NetworkScope.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          for (final (i, (chain, dot)) in _chainDots.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            NetworkBadge(label: networks.activeFor(chain).name, dotColor: dot),
          ],
        ],
      ),
    );
  }
}

class _AssetsCard extends StatelessWidget {
  const _AssetsCard({required this.assets, this.onViewAll});
  final List<AssetRow> assets;
  final VoidCallback? onViewAll;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WalletColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.tabAssets,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: WalletColors.text,
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onViewAll,
                child: Row(
                  children: [
                    Text(
                      l10n.viewAll,
                      style: const TextStyle(
                        fontSize: 13,
                        color: WalletColors.text2,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      size: 14,
                      color: WalletColors.text2,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          for (var i = 0; i < assets.length; i++) ...[
            if (i > 0) const SizedBox(height: 18),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.push('/token'),
              child: _AssetTile(assets[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _AssetTile extends StatelessWidget {
  const _AssetTile(this.a);
  final AssetRow a;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      TokenIcon(
        symbol: a.name,
        size: 40,
        fallbackColor: a.color,
        fallbackInitial: a.letter,
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              a.name,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: WalletColors.text,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              a.sub,
              style: const TextStyle(fontSize: 12, color: WalletColors.text2),
            ),
          ],
        ),
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            a.value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: WalletColors.text,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            a.change,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: a.changeColor,
            ),
          ),
        ],
      ),
    ],
  );
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.selected, required this.onTap});
  final int selected;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tabs = <(String, IconData)>[
      (l10n.tabHome, Icons.home_filled),
      (l10n.tabAssets, Icons.pie_chart),
      (l10n.tabRecords, Icons.history),
      (l10n.tabSettings, Icons.settings),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Container(
        height: 56,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: WalletColors.surface,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: WalletColors.text.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            for (final (i, tab) in tabs.indexed)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(i),
                  child: Container(
                    decoration: BoxDecoration(
                      color: i == selected
                          ? WalletColors.accent.withValues(alpha: 0.08)
                          : null,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          tab.$2,
                          size: 22,
                          color: i == selected
                              ? WalletColors.accent
                              : WalletColors.text3,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tab.$1,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: i == selected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: i == selected
                                ? WalletColors.accent
                                : WalletColors.text3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
