import 'package:chains/chains.dart' show Amount, Chain;
import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:wallet_data/wallet_data.dart'
    show CustomToken, TxCheckOutcome, TxOperationKind, TxStatus;

import '../../l10n/app_localizations.dart';
import '../market/asset_ref.dart';
import '../market/balance_service.dart';
import '../market/history_controller.dart';
import '../market/history_asset_policy.dart';
import '../market/history_service.dart';
import '../market/transaction_status_service.dart';
import '../market/market_controller.dart';
import '../market/market_scope.dart';
import '../market/token_balance_service.dart';
import '../widgets/market_offline_banner.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/token_icon.dart';
import '../state/app_prefs.dart';
import '../state/networks.dart';
import '../state/wallet_controller.dart';
import '../state/wallet_scope.dart';
import '../wallets/wallet_model.dart';
import 'wallet_screens.dart' show AddWalletScreen;

/// KT Wallet home screen (Pencil W1/W20). Reads the current wallet from
/// [WalletScope], so switching wallets rebuilds it live; hot vs watch wallets
/// change the action row and the backup banner (ui-m.md §8.1).
/// Stateful shell: the bottom tab bar switches between the three top-level
/// tabs (home / assets / settings) while retaining every tab's scroll state.
/// Transaction history remains a first-class page reached from the home action
/// instead of taking permanent tab-bar space.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.assets});

  /// Demo rows for the gallery and goldens; null uses [demoAssets], which is
  /// no longer const now that an AssetRef carries its deployment list.
  final List<AssetRow>? assets;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// Whether balances are masked, shared by the total and every asset row.
///
/// Seeded from the persisted "privacy mode" preference — which the home screen
/// previously ignored entirely — and flipped for the session by the eye next
/// to the total. Masking the total alone was not privacy: the per-asset
/// amounts underneath it stayed in plain sight.
class BalancePrivacy extends InheritedWidget {
  const BalancePrivacy({
    super.key,
    required this.hidden,
    required this.toggle,
    required super.child,
  });

  final bool hidden;
  final VoidCallback toggle;

  /// False when no scope is present (design gallery, goldens, plain widget
  /// tests), so those renderings are unchanged.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BalancePrivacy>()?.hidden ??
      false;

  static VoidCallback? toggleOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BalancePrivacy>()?.toggle;

  @override
  bool updateShouldNotify(BalancePrivacy oldWidget) =>
      oldWidget.hidden != hidden;
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  /// Session override of the persisted default; null = follow the preference.
  bool? _hiddenOverride;

  /// Last preference value seen. Toggling the eye sets a session override,
  /// and that override used to win forever — so flipping "privacy mode" in
  /// settings afterwards appeared to do nothing. A change to the preference
  /// is an explicit instruction and clears the override.
  bool? _lastPrefPrivacy;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final pref = AppPrefsScope.maybeOf(context)?.privacyMode;
    if (pref != null && pref != _lastPrefPrivacy) {
      _lastPrefPrivacy = pref;
      _hiddenOverride = null;
    }
  }

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

  void _selectTab(int tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) {
    // A production install intentionally has no demo wallet. It must land on
    // the real create/import/pairing entry instead of rendering a home shell
    // that assumes an account exists. This also closes the last-wallet-delete
    // edge case while the /home route is still mounted.
    if (WalletScope.of(context).current == null) {
      return const AddWalletScreen();
    }
    final hidden =
        _hiddenOverride ??
        (AppPrefsScope.maybeOf(context)?.privacyMode ?? false);
    return BalancePrivacy(
      hidden: hidden,
      toggle: () => setState(() => _hiddenOverride = !hidden),
      child: KtWalletBackdrop(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          // Content can scroll beneath the clipped glass; each page reserves
          // the capsule height, margins and the device's bottom safe area.
          body: SafeArea(
            bottom: false,
            child: Stack(
              children: [
                _AnimatedTabStack(
                  selected: _tab,
                  children: [
                    _HomeTab(
                      assets: widget.assets ?? demoAssets,
                      onViewAll: () => context.push('/assets'),
                    ),
                    const RecordsScreen(tabbed: true),
                    const _SettingsTab(),
                  ],
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _TabBar(selected: _tab, onTap: _selectTab),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Room a tab's scroll view must leave at the bottom so its last row is not
/// stuck under the floating tab bar.
const kTabBarInset = 94.4;

double _tabBarInsetFor(BuildContext context) =>
    LiquidWalletTabs.heightFor(context) +
    36 +
    MediaQuery.paddingOf(context).bottom;

const _tabFadeDuration = Duration(milliseconds: 140);
const _tabMotionCurve = Cubic(0.2, 0.8, 0.2, 1);

/// Retains all three top-level surfaces and uses a short crossfade to soften
/// the content swap. Moving the full page as well only makes this
/// high-frequency action feel like it is being thrown sideways.
class _AnimatedTabStack extends StatefulWidget {
  const _AnimatedTabStack({required this.selected, required this.children});

  final int selected;
  final List<Widget> children;

  @override
  State<_AnimatedTabStack> createState() => _AnimatedTabStackState();
}

class _AnimatedTabStackState extends State<_AnimatedTabStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _transitionClock;

  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _transitionClock = AnimationController(
      vsync: this,
      duration: _tabFadeDuration,
    )..addStatusListener(_handleTransitionStatus);
  }

  void _handleTransitionStatus(AnimationStatus status) {
    // The clock only keeps outgoing tabs mounted for their transition.
    // Rebuild once on completion to offstage them instead of rebuilding every
    // wrapper on every animation frame.
    if (status == AnimationStatus.completed && mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _transitionClock.duration = _reduceMotion
        ? const Duration(milliseconds: 100)
        : _tabFadeDuration;
  }

  @override
  void didUpdateWidget(_AnimatedTabStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      _transitionClock.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _transitionClock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final transitioning = _transitionClock.isAnimating;
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final (index, child) in widget.children.indexed)
          AnimatedOpacity(
            key: ValueKey('home-tab-opacity-$index'),
            opacity: index == widget.selected ? 1 : 0,
            duration: _reduceMotion
                ? const Duration(milliseconds: 100)
                : _tabFadeDuration,
            curve: _tabMotionCurve,
            child: Offstage(
              offstage: !transitioning && index != widget.selected,
              child: TickerMode(
                enabled: index == widget.selected,
                child: ExcludeSemantics(
                  excluding: index != widget.selected,
                  child: IgnorePointer(
                    ignoring: index != widget.selected,
                    child: RepaintBoundary(
                      key: ValueKey('home-tab-surface-$index'),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

enum _HomeAssetCategory { coins, networks, custom }

class _HomeTab extends StatefulWidget {
  const _HomeTab({required this.assets, this.onViewAll});
  final List<AssetRow> assets;
  final VoidCallback? onViewAll;

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  _HomeAssetCategory _category = _HomeAssetCategory.coins;
  WalletController? _tokenController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = WalletScope.of(context);
    if (identical(controller, _tokenController)) return;
    _tokenController = controller;
    controller.loadTokens().then((_) {
      if (mounted && identical(controller, _tokenController)) setState(() {});
    });
  }

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
    await showKtModalBottomSheet<void>(
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

  void _selectCategory(_HomeAssetCategory value) {
    if (_category == value) return;
    HapticFeedback.selectionClick();
    setState(() => _category = value);
  }

  Widget _categoryContent(
    BuildContext context, {
    required List<AssetRow> assets,
    required NetworkController networks,
    required WalletController wallets,
  }) {
    final l10n = AppLocalizations.of(context);
    switch (_category) {
      case _HomeAssetCategory.coins:
        return _HomeAssetList(assets: assets);
      case _HomeAssetCategory.networks:
        return _HomeNetworkList(
          networks: [
            for (final chain in Chain.values) networks.activeFor(chain),
          ],
        );
      case _HomeAssetCategory.custom:
        if (wallets.tokens.isEmpty) {
          return _HomeEmptyState(
            icon: Icons.toll_outlined,
            text: l10n.tokensEmpty,
            actionLabel: l10n.settingsTokenManage,
            onAction: () => context.push('/token-manage'),
          );
        }
        return _HomeCustomTokenList(tokens: wallets.tokens);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final wallets = WalletScope.of(context);
    final wallet = wallets.current!;
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
    final portfolioChange = live && !testnet ? market.portfolioChange24h : null;
    final balanceChange = _portfolioChangeDisplay(
      context,
      market: market,
      testnet: testnet,
      change: portfolioChange,
      period: l10n.balanceChangePeriod,
    );
    final networks = NetworkScope.of(context);
    final visibleAssets = live
        ? preferredAssetRows(
            context,
            market,
            liveAssetRows(
              market,
              chainsLabel: l10n.assetOnChains,
              fiatFormatter: (usd) => formatFiatForContext(context, usd),
            ),
          )
        : widget.assets;
    final scrollView = CustomScrollView(
      key: const ValueKey('home-scroll-view'),
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(
                  wallet: wallet,
                  onTapPill: () => context.push('/switcher'),
                ),
                if (offline) ...[
                  const SizedBox(height: 12),
                  const MarketOfflineBanner(),
                ],
                const SizedBox(height: 2),
                _Balance(
                  amount: live
                      ? (testnet || total == null
                            ? '--'
                            : formatFiatForContext(context, total))
                      : r'$862.40',
                  change: balanceChange.text,
                  changeColor: balanceChange.color,
                ),
                if (live && market.isRefreshing && market.hasLiveBalances) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.marketUpdating,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: WalletColors.text3,
                    ),
                  ),
                ],
                if (live && market.showingCachedData) ...[
                  const SizedBox(height: 8),
                  MarketFreshnessLabel(market: market),
                ],
                if (live && testnet) ...[
                  const SizedBox(height: 12),
                  const _FiatHiddenTestnetNote(),
                ],
                const SizedBox(height: 10),
                _ActionRow(onMore: () => _showMore(context)),
                if (isHot && !wallet.backedUp) ...[
                  const SizedBox(height: 10),
                  const _BackupBanner(),
                ],
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _HomeCategoryHeaderDelegate(
            category: _category,
            onSelect: _selectCategory,
            onManage: switch (_category) {
              _HomeAssetCategory.coins => widget.onViewAll,
              _HomeAssetCategory.networks => () => context.push('/network'),
              _HomeAssetCategory.custom => () => context.push('/token-manage'),
            },
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            18,
            0,
            18,
            24 + _tabBarInsetFor(context),
          ),
          sliver: SliverToBoxAdapter(
            child: _categoryContent(
              context,
              assets: visibleAssets,
              networks: networks,
              wallets: wallets,
            ),
          ),
        ),
      ],
    );
    if (market == null) return scrollView;
    return RefreshIndicator(
      color: WalletColors.accent,
      onRefresh: () => market.refresh(),
      child: scrollView,
    );
  }
}

class _HomeCategoryHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _HomeCategoryHeaderDelegate({
    required this.category,
    required this.onSelect,
    required this.onManage,
  });

  final _HomeAssetCategory category;
  final ValueChanged<_HomeAssetCategory> onSelect;
  final VoidCallback? onManage;

  @override
  double get minExtent => 48;

  @override
  double get maxExtent => 48;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final l10n = AppLocalizations.of(context);
    final entries = <(_HomeAssetCategory, String)>[
      (_HomeAssetCategory.coins, l10n.homeCategoryCoins),
      (_HomeAssetCategory.networks, l10n.homeCategoryNetworks),
      (_HomeAssetCategory.custom, l10n.homeCategoryCustom),
    ];
    return Material(
      key: const ValueKey('home-category-header'),
      color: const Color(0xFFF2F5FA),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    for (final (value, label) in entries) ...[
                      if (value != entries.first.$1) const SizedBox(width: 8),
                      _HomeCategoryPill(
                        key: ValueKey('home-category-${value.name}'),
                        label: label,
                        selected: category == value,
                        onTap: () => onSelect(value),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 2),
            IconButton(
              key: const ValueKey('home-category-manage'),
              tooltip: l10n.manage,
              onPressed: onManage,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 48, height: 48),
              icon: const SizedBox.square(
                key: ValueKey('home-category-manage-surface'),
                dimension: 32,
                child: Icon(
                  Icons.tune_rounded,
                  size: 18,
                  color: WalletColors.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_HomeCategoryHeaderDelegate oldDelegate) =>
      category != oldDelegate.category || onManage != oldDelegate.onManage;
}

class _HomeCategoryPill extends StatelessWidget {
  const _HomeCategoryPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        height: 32,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? WalletColors.text : WalletColors.bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.white : WalletColors.text,
          ),
        ),
      ),
    ),
  );
}

class _HomeAssetList extends StatelessWidget {
  const _HomeAssetList({required this.assets});

  final List<AssetRow> assets;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 12),
    child: KtGlassSurface(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        children: [
          for (final asset in assets) ...[
            _PressScale(
              onTap: asset.ref == null
                  ? null
                  : () => context.push('/token', extra: asset.ref),
              semanticLabel: '${asset.name}, ${asset.sub}',
              child: _HomeAssetTile(asset),
            ),
          ],
        ],
      ),
    ),
  );
}

/// W1A's compact asset row. The underlying [AssetRow] remains the same live
/// data object used by the assets tab; home only changes the presentation:
/// identity/network on the left, exact asset amount + fiat value on the right.
/// This keeps amount precision and unknown (`--`) states untouched.
class _HomeAssetTile extends StatelessWidget {
  const _HomeAssetTile(this.asset);

  final AssetRow asset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hidden = BalancePrivacy.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(14) >= 20;
    final parts = asset.sub.split(' · ');
    final amount = parts.first.trim();
    final ref = asset.ref;
    final isMultiChain = (ref?.group.length ?? 0) > 1;
    final symbolLikeName = RegExp(r'^[A-Z0-9]{2,10}$').hasMatch(asset.name);
    final symbol = symbolLikeName ? asset.name : (ref?.symbol ?? asset.name);
    final location = parts.length > 1
        ? parts.skip(1).join(' · ')
        : ref?.network ??
              (ref == null || ref.group.length == 1
                  ? asset.name
                  : '${ref.group.length}');
    Widget nameText() => Text(
      symbol,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: WalletColors.text,
      ),
    );
    Widget multiChainLabel() => Container(
      key: ValueKey('home-asset-multichain-$symbol'),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: const BoxDecoration(color: WalletColors.bg),
      child: Text(
        l10n.multiChainBadge,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: WalletColors.text2,
        ),
      ),
    );

    return SizedBox(
      key: ValueKey('home-asset-$symbol-${ref?.network ?? 'aggregate'}'),
      height: largeText ? (isMultiChain ? 138 : 94) : 70,
      child: Row(
        children: [
          TokenIcon(
            symbol: symbol,
            size: 36,
            fallbackColor: asset.color,
            fallbackInitial: asset.letter,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (largeText && isMultiChain)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      nameText(),
                      const SizedBox(height: 3),
                      Row(children: [Flexible(child: multiChainLabel())]),
                    ],
                  )
                else
                  Row(
                    children: [
                      Flexible(child: nameText()),
                      if (isMultiChain) ...[
                        const SizedBox(width: 6),
                        multiChainLabel(),
                      ],
                    ],
                  ),
                const SizedBox(height: 2),
                Text(
                  location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: WalletColors.text2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                hidden ? '••••' : amount,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: WalletColors.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hidden ? '••••' : asset.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: WalletColors.text,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HomeNetworkList extends StatelessWidget {
  const _HomeNetworkList({required this.networks});

  final List<Network> networks;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        for (final (index, network) in networks.indexed) ...[
          if (index > 0) const SizedBox(height: 8),
          _PressScale(
            onTap: () => context.push('/network'),
            semanticLabel: network.name,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _chainColor(network.chain).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      network.symbol.characters.first,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _chainColor(network.chain),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                network.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: WalletColors.text,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${network.symbol} · ${network.isTestnet ? l10n.testnetBadge : l10n.envMainnet}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: WalletColors.text2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: WalletColors.text3,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _HomeCustomTokenList extends StatelessWidget {
  const _HomeCustomTokenList({required this.tokens});

  final List<CustomToken> tokens;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final (index, token) in tokens.indexed) ...[
        if (index > 0) const SizedBox(height: 8),
        Opacity(
          opacity: token.enabled ? 1 : 0.55,
          child: _PressScale(
            onTap: () => context.push('/token-manage'),
            semanticLabel: '${token.symbol}, ${token.name}',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  TokenIcon(
                    symbol: token.symbol,
                    size: 40,
                    fallbackColor: WalletColors.text2,
                    fallbackInitial: token.symbol.characters.first,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          token.symbol,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: WalletColors.text,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${token.name} · ${token.network}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: WalletColors.text2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    token.enabled
                        ? Icons.check_circle_rounded
                        : Icons.remove_circle_outline_rounded,
                    size: 20,
                    color: token.enabled
                        ? WalletColors.green
                        : WalletColors.text3,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ],
  );
}

class _HomeEmptyState extends StatelessWidget {
  const _HomeEmptyState({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 42),
    child: Column(
      children: [
        Icon(icon, size: 32, color: WalletColors.text3),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: WalletColors.text3),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 12),
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ],
    ),
  );
}

Color _chainColor(Chain chain) => switch (chain) {
  Chain.ethereum => ChainColors.ethereum,
  Chain.polygon => ChainColors.polygon,
  Chain.base => ChainColors.base,
  Chain.arbitrum => ChainColors.arbitrum,
  Chain.avalanche => ChainColors.avalanche,
  Chain.bnb => const Color(0xFFF0B90B),
  Chain.tron => ChainColors.tron,
  Chain.solana => ChainColors.solana,
};

/// Real transaction history. With no [asset], this is the wallet-wide merged
/// list used by the home action. With an [asset], records are restricted to
/// its currently selected deployment (symbol + chain/network).
class RecordsScreen extends StatefulWidget {
  const RecordsScreen({
    super.key,
    this.asset,
    this.embedded = false,
    this.tabbed = false,
  });

  final bool tabbed;

  final AssetRef? asset;

  /// Asset detail pages embed only the section; the home action opens the
  /// standalone page with its own navigation bar.
  final bool embedded;

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

enum _HistoryTypeFilter { all, transfers, other }

class _RecordsScreenState extends State<RecordsScreen> {
  /// Lazily-owned [HistoryController], mounted the first time this tab builds
  /// under a live market context (no `main.dart` wiring). Tests inject their
  /// own controller via [HistoryScope], which always wins over the lazy one.
  HistoryController? _owned;
  HistoryController? _autoRefreshRequestedFor;
  bool _showUnverifiedRecords = false;
  _HistoryTypeFilter _typeFilter = _HistoryTypeFilter.transfers;
  String? _selectedNetworkId;

  @override
  void initState() {
    super.initState();
    if (widget.tabbed) _typeFilter = _HistoryTypeFilter.all;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shared = HistoryScope.maybeOf(context);
    if (shared != null) {
      if (HistoryScope.shouldAutoRefresh(context) &&
          !identical(_autoRefreshRequestedFor, shared)) {
        _autoRefreshRequestedFor = shared;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // Every new records page is an explicit request for current account
          // history. `refreshIfNeeded` used to stop forever after restoring a
          // stale snapshot or completing one failed live attempt.
          if (mounted) shared.refresh();
        });
      }
      return;
    }
    if (_owned == null && MarketScope.maybeOf(context) != null) {
      final networks = NetworkScope.maybeOf(context);
      final controller = HistoryController(
        wallets: WalletScope.of(context),
        networkChanges: networks,
        // Locally recorded rows are filtered to the ACTIVE network instances,
        // re-read on every refresh so an environment switch applies at once.
        activeNetworkIds: networks == null
            ? null
            : () => {for (final c in Chain.values) networks.activeFor(c).id},
        activeNetworkId: networks == null
            ? null
            : (coin) => networks.activeFor(chainOf(coin)).id,
        // TronGrid endpoint: persisted RPC override → ACTIVE tron network's
        // rpcUrl (Nile is TronGrid-compatible, same paths) → builtin default;
        // a configured gateway unlocks eth/polygon/solana history too.
        service: HistoryService(
          endpoints: effectiveRpcEndpoints(
            AppPrefsScope.maybeOf(context),
            NetworkScope.maybeOf(context),
          ),
          gateway: prefsGatewayResolver(AppPrefsScope.maybeOf(context)),
          tokenRegistry: networkTokenRegistry(networks),
        ),
        statusService: TransactionStatusService(
          endpoints: effectiveRpcEndpoints(
            AppPrefsScope.maybeOf(context),
            networks,
          ),
          networkEndpoints: networks == null
              ? null
              : effectiveTransactionRpcEndpoints(
                  AppPrefsScope.maybeOf(context),
                  networks,
                ),
          gateway: prefsGatewayResolver(
            AppPrefsScope.maybeOf(context),
            networks,
          ),
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

  Widget _emptyCard(AppLocalizations l10n, {String? message}) => KtCard(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Text(
          message ?? l10n.historyEmpty,
          style: const TextStyle(fontSize: 13, color: WalletColors.text3),
        ),
      ),
    ),
  );

  /// Quiet structural placeholders that match a real transaction row.
  Widget _loadingCard({bool flat = false}) {
    final rows = ExcludeSemantics(
      child: Column(
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: WalletColors.text.withValues(alpha: 0.055),
              ),
            _HistorySkeletonRow(index: i),
          ],
        ],
      ),
    );
    return KeyedSubtree(
      key: const ValueKey('history-loading-skeleton'),
      child: flat ? rows : KtCard(child: rows),
    );
  }

  Widget _liveCard(
    BuildContext context,
    AppLocalizations l10n,
    HistoryController history,
  ) {
    final records = _visibleRecords(history);
    if (records.isEmpty) {
      return _emptyCard(l10n);
    }
    final customTokens =
        WalletScope.maybeOf(context)?.tokens ?? const <CustomToken>[];
    final classified = [
      for (final record in records)
        (
          record,
          widget.asset == null
              ? classifyHistoryAsset(record, customTokens)
              : HistoryAssetKind.official,
        ),
    ];
    final primary = [
      for (final item in classified)
        if (item.$2.visibleInPrimaryHistory) item,
    ];
    final unverified = [
      for (final item in classified)
        if (!item.$2.visibleInPrimaryHistory) item,
    ];
    return Column(
      children: [
        if (primary.isEmpty)
          _emptyCard(l10n, message: l10n.historyNoRecognizedTransactions)
        else
          _recordsCard(context, l10n, history, primary),
        if (unverified.isNotEmpty) ...[
          const SizedBox(height: 12),
          _unverifiedRecordsCard(context, l10n, history, unverified),
        ],
        if (history.canLoadMore || history.isLoadingMore) ...[
          const SizedBox(height: 12),
          Semantics(
            button: true,
            label: history.isLoadingMore
                ? l10n.historyLoadingMore
                : l10n.historyLoadMore,
            child: TextButton(
              key: const ValueKey('history-load-more'),
              onPressed: history.isLoadingMore
                  ? null
                  : () => history.loadMore(),
              child: Text(
                history.isLoadingMore
                    ? l10n.historyLoadingMore
                    : l10n.historyLoadMore,
              ),
            ),
          ),
        ],
      ],
    );
  }

  List<(ChainTxRecord, HistoryAssetKind)> _classifiedRecords(
    BuildContext context,
    HistoryController history,
  ) {
    final customTokens =
        WalletScope.maybeOf(context)?.tokens ?? const <CustomToken>[];
    return [
      for (final record in _visibleRecords(history))
        (
          record,
          widget.asset == null
              ? classifyHistoryAsset(record, customTokens)
              : HistoryAssetKind.official,
        ),
    ];
  }

  List<_HistoryNetworkOption> _networkOptions(
    BuildContext context,
    List<(ChainTxRecord, HistoryAssetKind)> records,
  ) {
    final options = <String, _HistoryNetworkOption>{};
    final networks = NetworkScope.maybeOf(context);
    final wallet = WalletScope.maybeOf(context)?.current;
    if (networks != null && wallet != null) {
      for (final coin in wallet.addresses.enabledCoins) {
        final network = networks.activeFor(chainOf(coin));
        options.putIfAbsent(
          network.id,
          () => _HistoryNetworkOption(network.id, network.name, network.chain),
        );
      }
    }
    for (final (record, _) in records) {
      final id = record.networkId;
      if (id == null || id.isEmpty) continue;
      options.putIfAbsent(
        id,
        () => _HistoryNetworkOption(
          id,
          networks?.byId(id)?.name ?? _fallbackNetworkName(record.coin),
          networks?.byId(id)?.chain ?? chainOf(record.coin),
        ),
      );
    }
    return options.values.toList();
  }

  String? _effectiveNetworkId(List<_HistoryNetworkOption> options) {
    final selected = _selectedNetworkId;
    if (selected == null || options.any((option) => option.id == selected)) {
      return selected;
    }
    return null;
  }

  String _typeFilterLabel(AppLocalizations l10n) => switch (_typeFilter) {
    _HistoryTypeFilter.all => l10n.historyTypeAll,
    _HistoryTypeFilter.transfers => l10n.historyTypeTransfers,
    _HistoryTypeFilter.other => l10n.historyTypeOther,
  };

  Future<void> _showTypeFilter(AppLocalizations l10n) async {
    final selected = await _showSingleSelectSheet<_HistoryTypeFilter>(
      title: l10n.historyTypeFilterTitle,
      selected: _typeFilter,
      options: [
        _HistoryPickerOption(
          _HistoryTypeFilter.all,
          l10n.historyTypeAll,
          const ValueKey('history-type-option-all'),
        ),
        _HistoryPickerOption(
          _HistoryTypeFilter.transfers,
          l10n.historyTypeTransfers,
          const ValueKey('history-type-option-transfers'),
        ),
        _HistoryPickerOption(
          _HistoryTypeFilter.other,
          l10n.historyTypeOther,
          const ValueKey('history-type-option-other'),
        ),
      ],
    );
    if (selected != null && mounted) {
      setState(() => _typeFilter = selected);
    }
  }

  Future<void> _showNetworkFilter(
    AppLocalizations l10n,
    List<_HistoryNetworkOption> networks,
  ) async {
    final selected = _effectiveNetworkId(networks);
    final value = await _showSingleSelectSheet<String>(
      title: l10n.historyNetworkFilterTitle,
      selected: selected ?? '',
      options: [
        _HistoryPickerOption<String>(
          '',
          l10n.historyAllNetworks,
          const ValueKey('history-network-option-all'),
          leading: Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: WalletColors.bg,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.language_rounded,
              size: 22,
              color: WalletColors.text2,
            ),
          ),
        ),
        for (final network in networks)
          _HistoryPickerOption<String>(
            network.id,
            network.label,
            ValueKey('history-network-option-${network.id}'),
            leading: ChainIcon(chain: network.chain, size: 32),
          ),
      ],
    );
    if (!mounted || value == null) return;
    final normalized = value.isEmpty ? null : value;
    if (normalized != _selectedNetworkId) {
      setState(() => _selectedNetworkId = normalized);
    }
  }

  Future<T?> _showSingleSelectSheet<T>({
    required String title,
    required T selected,
    required List<_HistoryPickerOption<T>> options,
  }) => showKtModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Colors.black.withValues(alpha: 0.36),
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 20),
              decoration: BoxDecoration(
                color: WalletColors.border,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                height: 1.2,
                fontWeight: FontWeight.w700,
                color: WalletColors.text,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: ListView(
              key: const ValueKey('history-filter-options'),
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              children: [
                for (final option in options)
                  Semantics(
                    button: true,
                    selected: option.value == selected,
                    inMutuallyExclusiveGroup: true,
                    child: InkWell(
                      key: option.key,
                      onTap: () => Navigator.of(sheetContext).pop(option.value),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 58),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              if (option.leading != null) ...[
                                ExcludeSemantics(child: option.leading!),
                                const SizedBox(width: 12),
                              ],
                              Expanded(
                                child: Text(
                                  option.label,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    color: WalletColors.text,
                                  ),
                                ),
                              ),
                              if (option.value == selected)
                                Container(
                                  key: const ValueKey(
                                    'history-filter-selected-check',
                                  ),
                                  width: 28,
                                  height: 28,
                                  decoration: const BoxDecoration(
                                    color: WalletColors.text,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.check_rounded,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _historyFilterChip(AppLocalizations l10n) => _filterControl(
    controlKey: const ValueKey('history-type-filter-button'),
    label: _typeFilterLabel(l10n),
    leading: const Icon(
      CupertinoIcons.slider_horizontal_3,
      size: 17,
      color: WalletColors.text2,
    ),
    onTap: () => _showTypeFilter(l10n),
  );

  Widget _filterControl({
    required Key controlKey,
    required String label,
    required Widget leading,
    required VoidCallback onTap,
    String? tooltip,
  }) => Tooltip(
    message: tooltip ?? label,
    child: Semantics(
      button: true,
      label: label,
      child: InkWell(
        key: controlKey,
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xDBFFFFFF),
            border: Border.all(color: Colors.white),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              ExcludeSemantics(child: leading),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: WalletColors.text,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                CupertinoIcons.chevron_down,
                size: 12,
                color: WalletColors.text2,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _filterBar(
    AppLocalizations l10n,
    List<_HistoryNetworkOption> networks,
  ) {
    final selected = _effectiveNetworkId(networks);
    final network = networks.where((n) => n.id == selected).firstOrNull;
    return Row(
      key: const ValueKey('history-filter-bar'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _historyFilterChip(l10n)),
        const SizedBox(width: 10),
        Expanded(
          child: _filterControl(
            controlKey: const ValueKey('history-network-filter-button'),
            label: network?.label ?? l10n.historyAllNetworks,
            tooltip: l10n.historyNetworkFilterTitle,
            leading: network == null
                ? const Icon(
                    CupertinoIcons.globe,
                    size: 18,
                    color: WalletColors.text2,
                  )
                : ChainIcon(chain: network.chain, size: 20),
            onTap: () => _showNetworkFilter(l10n, networks),
          ),
        ),
      ],
    );
  }

  Widget _flatEmptyState(AppLocalizations l10n, {String? message}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 20),
    child: Center(
      child: Column(
        children: [
          const KtGlassSurface(
            radius: 26,
            padding: EdgeInsets.all(22),
            child: Icon(
              CupertinoIcons.clock,
              size: 32,
              color: WalletColors.text2,
            ),
          ),
          const SizedBox(height: 22),
          Text(
            message ?? l10n.historyEmpty,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: WalletColors.text,
            ),
          ),
          if (message == null) ...[
            const SizedBox(height: 8),
            Text(
              l10n.historyEmptyDescription,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: WalletColors.text2,
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _standaloneLiveList(
    BuildContext context,
    AppLocalizations l10n,
    HistoryController history,
    List<(ChainTxRecord, HistoryAssetKind)> allRecords,
    List<_HistoryNetworkOption> networks,
  ) {
    final selectedNetwork = _effectiveNetworkId(networks);
    final records =
        allRecords.where((item) {
          if (selectedNetwork != null && item.$1.networkId != selectedNetwork) {
            return false;
          }
          return switch (_typeFilter) {
            _HistoryTypeFilter.all => true,
            _HistoryTypeFilter.transfers => item.$2.visibleInPrimaryHistory,
            _HistoryTypeFilter.other => !item.$2.visibleInPrimaryHistory,
          };
        }).toList()..sort(
          (left, right) => right.$1.timestamp.compareTo(left.$1.timestamp),
        );
    if (records.isEmpty) return _flatEmptyState(l10n);

    final children = <Widget>[];
    String? previousDay;
    for (final item in records) {
      final localTime = item.$1.timestamp.toLocal();
      final day = _numericRecordDay(localTime);
      if (day != previousDay) {
        if (previousDay != null) {
          children.add(
            Divider(
              height: 1,
              color: WalletColors.text.withValues(alpha: 0.055),
            ),
          );
        }
        children.add(
          Padding(
            key: ValueKey('history-date-$day'),
            padding: EdgeInsets.only(top: previousDay == null ? 18 : 24),
            child: Text(
              day,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: WalletColors.text3,
              ),
            ),
          ),
        );
        previousDay = day;
      }
      children.add(
        _standaloneHistoryRecordRow(context, l10n, history, item.$1, item.$2),
      );
    }
    if (history.canLoadMore || history.isLoadingMore) {
      children.add(const SizedBox(height: 8));
      children.add(
        Semantics(
          button: true,
          label: history.isLoadingMore
              ? l10n.historyLoadingMore
              : l10n.historyLoadMore,
          child: TextButton(
            key: const ValueKey('history-load-more'),
            onPressed: history.isLoadingMore ? null : () => history.loadMore(),
            child: Text(
              history.isLoadingMore
                  ? l10n.historyLoadingMore
                  : l10n.historyLoadMore,
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _standaloneHistoryRecordRow(
    BuildContext context,
    AppLocalizations l10n,
    HistoryController history,
    ChainTxRecord record,
    HistoryAssetKind assetKind,
  ) {
    final local = history.localTransactionForRecord(record);
    final rawAmount = local?.operation == TxOperationKind.approvalRevoke
        ? l10n.approvalRevoke
        : record.amountText ?? '--';
    final participant = record.outgoing ? record.toAddress : record.fromAddress;
    final address = participant == null || participant.trim().isEmpty
        ? l10n.historyAddressUnavailable
        : record.outgoing
        ? l10n.historyToAddress(_abbreviateHistoryAddress(participant))
        : l10n.historyFromAddress(_abbreviateHistoryAddress(participant));
    final localStatusUnknown =
        local != null &&
        (local.status == TxStatus.submitted ||
            local.status == TxStatus.broadcast ||
            local.status == TxStatus.pending) &&
        local.lastCheckOutcome == TxCheckOutcome.unknown;
    final status = _historyStatusSuffix(
      l10n,
      record,
      local?.status,
      localStatusUnknown,
    );
    final subtitleBadge = switch (assetKind) {
      HistoryAssetKind.userAdded => l10n.historyCustomTokenBadge,
      _ => null,
    };
    final dangerBadge = switch (assetKind) {
      HistoryAssetKind.unverified => l10n.historyUnverifiedTokenBadge,
      HistoryAssetKind.risky => l10n.historyRiskTokenBadge,
      _ => null,
    };
    return _FlatHistoryRecordRow(
      key: ValueKey('history-record-${record.id ?? record.hash}'),
      outgoing: record.outgoing,
      title: record.outgoing ? l10n.historySent : l10n.historyReceived,
      subtitle: [address, ?subtitleBadge, ?status].join(' · '),
      dangerBadge: dangerBadge,
      amount: rawAmount,
      symbol: _historyAssetSymbol(record),
      chain: chainOf(record.coin),
      isToken: record.assetContract != null,
      officialAsset: assetKind == HistoryAssetKind.official,
      onTap: () => local == null
          ? context.push('/tx-detail', extra: record)
          : context.push('/tx-detail?id=${Uri.encodeComponent(local.id)}'),
    );
  }

  Widget _recordsCard(
    BuildContext context,
    AppLocalizations l10n,
    HistoryController history,
    List<(ChainTxRecord, HistoryAssetKind)> records,
  ) => KtCard(
    child: Column(
      children: [
        for (final (index, item) in records.indexed) ...[
          if (index > 0)
            Divider(
              height: 1,
              color: WalletColors.text.withValues(alpha: 0.06),
            ),
          _historyRecordRow(context, l10n, history, item.$1, item.$2),
        ],
      ],
    ),
  );

  Widget _historyRecordRow(
    BuildContext context,
    AppLocalizations l10n,
    HistoryController history,
    ChainTxRecord record,
    HistoryAssetKind assetKind,
  ) {
    final local = history.localTransactionForRecord(record);
    final marker = switch (assetKind) {
      HistoryAssetKind.official => '',
      HistoryAssetKind.userAdded => ' · ${l10n.historyCustomTokenBadge}',
      HistoryAssetKind.unverified => ' ⚠',
      HistoryAssetKind.risky => ' · ${l10n.historyRiskTokenBadge}',
    };
    final amount = local?.operation == TxOperationKind.approvalRevoke
        ? l10n.approvalRevoke
        : '${record.amountText ?? '--'}$marker';
    return _RecordRow(
      key: ValueKey('history-record-${record.id ?? record.hash}'),
      record: _TxRecord(
        record.outgoing,
        amount,
        _formatRecordTime(l10n, record.timestamp),
        isTron: record.coin == Coin.tron,
        status: local?.status,
        statusUnknown:
            local != null &&
            (local.status == TxStatus.submitted ||
                local.status == TxStatus.broadcast ||
                local.status == TxStatus.pending) &&
            local.lastCheckOutcome == TxCheckOutcome.unknown,
      ),
      // A row we broadcast ourselves opens its local record; one that only
      // exists on chain travels as `extra`.
      onTap: () => local == null
          ? context.push('/tx-detail', extra: record)
          : context.push('/tx-detail?id=${Uri.encodeComponent(local.id)}'),
    );
  }

  Widget _unverifiedRecordsCard(
    BuildContext context,
    AppLocalizations l10n,
    HistoryController history,
    List<(ChainTxRecord, HistoryAssetKind)> records,
  ) => KtCard(
    child: Column(
      children: [
        Semantics(
          button: true,
          expanded: _showUnverifiedRecords,
          label: '${l10n.historyUnverifiedRecordsTitle}, ${records.length}',
          child: InkWell(
            key: const ValueKey('history-unverified-toggle'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(
              () => _showUnverifiedRecords = !_showUnverifiedRecords,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: WalletColors.amber.withValues(alpha: 0.11),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.gpp_maybe_outlined,
                      size: 20,
                      color: WalletColors.amber,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${l10n.historyUnverifiedRecordsTitle} (${records.length})',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: WalletColors.text,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          l10n.historyUnverifiedRecordsDescription,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: WalletColors.text3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _showUnverifiedRecords ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: WalletColors.text3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_showUnverifiedRecords) ...[
          const SizedBox(height: 8),
          Divider(height: 1, color: WalletColors.text.withValues(alpha: 0.06)),
          for (final (index, item) in records.indexed) ...[
            if (index > 0)
              Divider(
                height: 1,
                color: WalletColors.text.withValues(alpha: 0.06),
              ),
            _historyRecordRow(context, l10n, history, item.$1, item.$2),
          ],
        ],
      ],
    ),
  );

  Widget _cachedHistoryLabel(AppLocalizations l10n, HistoryController history) {
    final timestamp = history.lastUpdatedAt;
    if (!history.showingCachedData || timestamp == null) {
      return const SizedBox.shrink();
    }
    final age = DateTime.now().difference(timestamp);
    final relative = age.inMinutes < 1
        ? l10n.marketCachedJustNow
        : age.inHours < 1
        ? l10n.marketCachedMinutes(age.inMinutes)
        : l10n.marketCachedHours(age.inHours);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        liveRegion: true,
        label: '$relative. ${l10n.historyCachedStale}',
        child: Row(
          key: const ValueKey('history-cached-label'),
          children: [
            const Icon(
              Icons.schedule_rounded,
              size: 14,
              color: WalletColors.text3,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '$relative · ${l10n.historyCachedStale}',
                style: const TextStyle(fontSize: 12, color: WalletColors.text3),
              ),
            ),
            const SizedBox(width: 4),
            if (history.isRefreshing)
              const SizedBox(
                key: ValueKey('history-cache-refreshing'),
                width: 36,
                height: 36,
                child: Padding(
                  padding: EdgeInsets.all(9),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                key: const ValueKey('history-cache-retry'),
                tooltip: l10n.actionRetry,
                visualDensity: VisualDensity.compact,
                onPressed: () => history.refresh(),
                icon: const Icon(Icons.refresh_rounded, size: 19),
                color: WalletColors.text2,
              ),
          ],
        ),
      ),
    );
  }

  /// The home history is the merged list. An asset detail page passes a
  /// narrowed [AssetRef], so both the chain and the contract/mint must match.
  /// This keeps, for example, Ethereum USDT out of Arbitrum USDT and native
  /// ETH out of token history on the same network.
  List<ChainTxRecord> _visibleRecords(HistoryController history) {
    final asset = widget.asset;
    if (asset == null) return history.records;
    final deployment = asset.group[asset.chainIndex];
    return history.records.where((record) {
      if (record.coin != deployment.coin) return false;
      if (!deployment.isToken) return record.assetContract == null;
      final expected = deployment.contract;
      final actual = record.assetContract;
      if (expected == null || actual == null) return false;
      return switch (deployment.coin) {
        Coin.eth ||
        Coin.polygon ||
        Coin.base ||
        Coin.arbitrum ||
        Coin.avalanche ||
        Coin.bnb => expected.toLowerCase() == actual.toLowerCase(),
        Coin.tron || Coin.solana => expected == actual,
      };
    }).toList();
  }

  HistoryStatus? _assetStatus(HistoryController history) {
    final asset = widget.asset;
    return asset == null ? null : history.resultFor(asset.coin).status;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final history = HistoryScope.maybeOf(context) ?? _owned;
    final assetStatus = history == null ? null : _assetStatus(history);
    late final Widget content;
    if (history == null) {
      // No trustworthy history source means no records. Never substitute
      // design fixtures on a wallet-facing surface.
      content = _emptyCard(l10n);
    } else if (assetStatus == HistoryStatus.unsupported ||
        (assetStatus == null && history.allUnsupported)) {
      // No chain in this context has a keyless history API — say so instead
      // of showing demo rows that could pass for live data.
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Text(
            l10n.historyUnsupportedChain,
            style: const TextStyle(fontSize: 13, color: WalletColors.text3),
          ),
        ),
      );
    } else if ((history.isLoading || assetStatus == HistoryStatus.loading) &&
        _visibleRecords(history).isEmpty) {
      content = _loadingCard();
    } else if (assetStatus == HistoryStatus.error ||
        (assetStatus == null && history.isError)) {
      content = Column(
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
      content = _liveCard(context, l10n, history);
    }
    final body = history == null
        ? content
        : Column(children: [_cachedHistoryLabel(l10n, history), content]);
    if (widget.embedded) {
      return Material(
        color: Colors.transparent,
        child: Column(
          key: const ValueKey('asset-history'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.recordsTitle,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: WalletColors.text,
              ),
            ),
            const SizedBox(height: 12),
            body,
          ],
        ),
      );
    }

    final classified = history == null
        ? <(ChainTxRecord, HistoryAssetKind)>[]
        : _classifiedRecords(context, history);
    final networks = _networkOptions(context, classified);
    late final Widget flatContent;
    if (history == null) {
      flatContent = _flatEmptyState(l10n);
    } else if (assetStatus == HistoryStatus.unsupported ||
        (assetStatus == null && history.allUnsupported)) {
      flatContent = _flatEmptyState(
        l10n,
        message: l10n.historyUnsupportedChain,
      );
    } else if ((history.isLoading || assetStatus == HistoryStatus.loading) &&
        _visibleRecords(history).isEmpty) {
      flatContent = _loadingCard(flat: true);
    } else if (assetStatus == HistoryStatus.error ||
        (assetStatus == null && history.isError)) {
      flatContent = Column(
        children: [
          const MarketOfflineBanner(),
          const SizedBox(height: 16),
          Text(
            l10n.walletLoadErrorDesc,
            style: const TextStyle(fontSize: 13, color: WalletColors.text3),
          ),
        ],
      );
    } else {
      flatContent = _standaloneLiveList(
        context,
        l10n,
        history,
        classified,
        networks,
      );
    }

    if (widget.tabbed) {
      final list = ListView(
        key: const PageStorageKey('activity-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + _tabBarInsetFor(context)),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.tabActivity,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: WalletColors.text,
                  ),
                ),
              ),
              const TestnetBadge(),
            ],
          ),
          Text(
            WalletScope.of(context).current?.name ?? '',
            style: const TextStyle(color: WalletColors.text2),
          ),
          const SizedBox(height: 20),
          _filterBar(l10n, networks),
          if (history != null) _cachedHistoryLabel(l10n, history),
          flatContent,
        ],
      );
      return history == null
          ? list
          : RefreshIndicator(onRefresh: history.refresh, child: list);
    }

    return KtScreen(
      backgroundColor: WalletColors.surface,
      padding: EdgeInsets.zero,
      gap: 0,
      navBar: KtNavBar(
        title: l10n.recordsTitle,
        onBack: () => Navigator.of(context).maybePop(),
        leading: Icons.arrow_back_ios_new_rounded,
        trailing: Icons.language_rounded,
        trailingColor: WalletColors.text,
        trailingTooltip: l10n.historyNetworkFilterTitle,
        onTrailing: () => _showNetworkFilter(l10n, networks),
      ),
      onRefresh: history?.refresh,
      children: [
        Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: WalletColors.text.withValues(alpha: 0.065),
              ),
            ),
          ),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.recordsWalletTab,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: WalletColors.text,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  key: const ValueKey('records-wallet-tab-indicator'),
                  width: 42,
                  height: 3,
                  color: WalletColors.text,
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: _historyFilterChip(l10n)),
                  const TestnetBadge(),
                ],
              ),
              if (history != null &&
                  history.showingCachedData &&
                  history.lastUpdatedAt != null) ...[
                const SizedBox(height: 18),
                _cachedHistoryLabel(l10n, history),
              ],
              flatContent,
            ],
          ),
        ),
      ],
    );
  }
}

class _HistoryNetworkOption {
  const _HistoryNetworkOption(this.id, this.label, this.chain);

  final String id;
  final String label;
  final Chain chain;
}

class _HistoryPickerOption<T> {
  const _HistoryPickerOption(this.value, this.label, this.key, {this.leading});

  final T value;
  final String label;
  final Key key;
  final Widget? leading;
}

class _FlatHistoryRecordRow extends StatelessWidget {
  const _FlatHistoryRecordRow({
    super.key,
    required this.outgoing,
    required this.title,
    required this.subtitle,
    this.dangerBadge,
    required this.amount,
    required this.symbol,
    required this.chain,
    required this.isToken,
    required this.officialAsset,
    required this.onTap,
  });

  final bool outgoing;
  final String title;
  final String subtitle;
  final String? dangerBadge;
  final String amount;
  final String symbol;
  final Chain chain;
  final bool isToken;
  final bool officialAsset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unsignedAmount = amount.replaceFirst(RegExp(r'^[+-]'), '');
    final displayAmount = unsignedAmount == '--'
        ? '--'
        : '${outgoing ? '-' : '+'}$unsignedAmount';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 17),
        child: Row(
          children: [
            NetworkAssetIcon(
              chain: chain,
              symbol: symbol,
              isToken: isToken,
              size: 40,
              official: officialAsset,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: WalletColors.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: WalletColors.text3,
                          ),
                        ),
                      ),
                      if (dangerBadge != null) ...[
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 42,
                          height: 16,
                          child: OverflowBox(
                            alignment: Alignment.bottomCenter,
                            minHeight: 43,
                            maxHeight: 43,
                            child: Container(
                              key: const ValueKey('history-danger-token-label'),
                              width: 42,
                              height: 43,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: WalletColors.red,
                              ),
                              child: Text(
                                dangerBadge!,
                                style: const TextStyle(
                                  fontSize: 10,
                                  height: 1.1,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                displayAmount,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: outgoing ? WalletColors.text : WalletColors.green,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _fallbackNetworkName(Coin coin) => switch (coin) {
  Coin.eth => 'Ethereum',
  Coin.polygon => 'Polygon',
  Coin.base => 'Base',
  Coin.arbitrum => 'Arbitrum',
  Coin.avalanche => 'Avalanche',
  Coin.bnb => 'BNB Smart Chain',
  Coin.tron => 'TRON',
  Coin.solana => 'Solana',
};

String _historyAssetSymbol(ChainTxRecord record) {
  final claimed = record.assetSymbol?.trim();
  if (claimed != null && claimed.isNotEmpty) return claimed;
  if (record.assetContract == null) {
    return switch (record.coin) {
      Coin.eth => 'ETH',
      Coin.polygon => 'POL',
      Coin.base => 'ETH',
      Coin.arbitrum => 'ETH',
      Coin.avalanche => 'AVAX',
      Coin.bnb => 'BNB',
      Coin.tron => 'TRX',
      Coin.solana => 'SOL',
    };
  }
  final amount = record.amountText?.trim();
  if (amount != null) {
    final parts = amount.split(RegExp(r'\s+'));
    if (parts.length > 1 &&
        RegExp(r'^[A-Za-z0-9._-]{1,16}$').hasMatch(parts.last)) {
      return parts.last;
    }
  }
  return '?';
}

String _abbreviateHistoryAddress(String address) {
  final value = address.trim();
  if (value.length <= 13) return value;
  return '${value.substring(0, 6)}...${value.substring(value.length - 4)}';
}

String _numericRecordDay(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}/'
    '${value.month.toString().padLeft(2, '0')}/'
    '${value.day.toString().padLeft(2, '0')}';

String? _historyStatusSuffix(
  AppLocalizations l10n,
  ChainTxRecord record,
  TxStatus? localStatus,
  bool localStatusUnknown,
) {
  if (localStatusUnknown) return l10n.txStatusUnknown;
  if (localStatus != null && localStatus != TxStatus.confirmed) {
    return _txStatusLabel(l10n, localStatus);
  }
  return switch (record.status) {
    ChainTxStatus.pending => l10n.txStatusPending,
    ChainTxStatus.failed => l10n.txStatusFailed,
    ChainTxStatus.unknown => l10n.txStatusUnknown,
    ChainTxStatus.confirmed => null,
  };
}

class _HistorySkeletonRow extends StatelessWidget {
  const _HistorySkeletonRow({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final fill = WalletColors.text.withValues(alpha: 0.055);
    final quietFill = WalletColors.text.withValues(alpha: 0.035);
    return Padding(
      key: ValueKey('history-skeleton-row-$index'),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HistorySkeletonBar(
                  width: index.isEven ? 78 : 92,
                  height: 13,
                  color: fill,
                ),
                const SizedBox(height: 8),
                _HistorySkeletonBar(
                  width: index.isEven ? 112 : 96,
                  height: 10,
                  color: quietFill,
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _HistorySkeletonBar(
                width: index.isEven ? 68 : 82,
                height: 13,
                color: fill,
              ),
              const SizedBox(height: 8),
              _HistorySkeletonBar(width: 44, height: 10, color: quietFill),
            ],
          ),
        ],
      ),
    );
  }
}

class _HistorySkeletonBar extends StatelessWidget {
  const _HistorySkeletonBar({
    required this.width,
    required this.height,
    required this.color,
  });

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(height / 2),
    ),
  );
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
  if (day == today.subtract(const Duration(days: 1))) {
    return '${l10n.dateYesterday} $hm';
  }
  return '${l10n.monthDay(t.month, t.day)} $hm';
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({super.key, required this.record, this.onTap});
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
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          sent ? l10n.txSent : l10n.txReceived,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: WalletColors.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    record.statusUnknown
                        ? '${record.time} · ${l10n.txStatusUnknown}'
                        : record.status == null
                        ? record.time
                        : '${record.time} · ${_txStatusLabel(l10n, record.status!)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: WalletColors.text3,
                    ),
                  ),
                ],
              ),
            ),
            // Unparseable live amounts render as a plain '--' (no sign).
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
  const _TxRecord(
    this.outgoing,
    this.amount,
    this.time, {
    this.isTron = false,
    this.status,
    this.statusUnknown = false,
  });
  final bool outgoing;
  final String amount, time;
  final bool isTron;
  final TxStatus? status;
  final bool statusUnknown;
}

String _txStatusLabel(AppLocalizations l10n, TxStatus status) =>
    switch (status) {
      TxStatus.submitted => l10n.txStatusSubmitted,
      TxStatus.pending => l10n.txStatusPending,
      TxStatus.confirmed => l10n.txStatusConfirmed,
      TxStatus.failed => l10n.txStatusFailed,
      TxStatus.dropped => l10n.txStatusDropped,
      TxStatus.replaced => l10n.txStatusReplaced,
      _ => status.name,
    };

class _SettingsTab extends StatelessWidget {
  const _SettingsTab();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = _settingsItems(l10n);
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + _tabBarInsetFor(context)),
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.tabSettings,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: WalletColors.text,
                ),
              ),
            ),
            const TestnetBadge(),
          ],
        ),
        const SizedBox(height: 20),
        KtGlassSurface(
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
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFEDF3FF),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(item.icon, size: 20, color: WalletColors.accent),
          ),
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
    Icons.admin_panel_settings_outlined,
    l10n.settingsApprovals,
    '/approvals',
  ),
  _SettingsItem(
    Icons.contacts_outlined,
    l10n.settingsAddressBook,
    '/address-book',
  ),
  _SettingsItem(Icons.hub_outlined, l10n.settingsNetwork, '/network'),
  _SettingsItem(Icons.toll_outlined, l10n.settingsTokenManage, '/token-manage'),
  _SettingsItem(Icons.info_outline, l10n.settingsAbout, '/about'),
];

/// Fixture rows for the design gallery and golden tests only.
///
/// Production screens always render the controller's last verified values,
/// including the honest unknown state when no snapshot exists.
///
/// The numbers are illustrative, but each row still names the chain it stands
/// for so tapping it opens THAT asset's detail — which then shows '--' for
/// anything it could not fetch, rather than a made-up holding.
final demoAssets = [
  AssetRow(
    Color(0xFF26A17B),
    '₮',
    'USDT',
    '500.00 USDT · TRON',
    r'$500.00',
    '0.0%',
    WalletColors.text3,
    ref: AssetRef.native(coin: Coin.tron, name: 'TRON', symbol: 'TRX'),
  ),
  AssetRow(
    Color(0xFF627EEA),
    'Ξ',
    'Ethereum',
    '0.0842 ETH',
    r'$279.80',
    '+2.4%',
    WalletColors.green,
    ref: AssetRef.native(coin: Coin.eth, name: 'Ethereum', symbol: 'ETH'),
  ),
  AssetRow(
    Color(0xFF9945FF),
    '◎',
    'Solana',
    '0.531 SOL',
    r'$82.60',
    '+5.1%',
    WalletColors.green,
    ref: AssetRef.native(coin: Coin.solana, name: 'Solana', symbol: 'SOL'),
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
  (Coin.bnb, 'BNB Smart Chain', 'BNB', Color(0xFFF3BA2F), 'B'),
  (Coin.tron, 'TRON', 'TRX', Color(0xFF26A17B), '₮'),
  (Coin.solana, 'Solana', 'SOL', Color(0xFF9945FF), '◎'),
];

/// Fallback avatar color + glyph per built-in token symbol ([TokenIcon]
/// renders the bundled brand PNG; these only show for missing assets).
const tokenRowMeta = {
  'USDT': (Color(0xFF26A17B), '₮'),
  'USDC': (Color(0xFF2775CA), r'$'),
  'BUSD': (Color(0xFFF0B90B), 'B'),
  'DAI': (Color(0xFFF5AC37), 'D'),
  'WETH': (Color(0xFF627EEA), 'W'),
  'WBTC': (Color(0xFFF09242), 'W'),
  'LINK': (Color(0xFF2A5ADA), 'L'),
  'UNI': (Color(0xFFFF007A), 'U'),
  'SHIB': (Color(0xFFF00500), 'S'),
  'PEPE': (Color(0xFF4C9540), 'P'),
  'JUP': (Color(0xFF00D18C), 'J'),
  'BONK': (Color(0xFFF5A623), 'B'),
  'PYUSD': (Color(0xFF0070E0), 'P'),
};

/// One live asset row for a registry token, in the demo rows' visual shape
/// ('500.00 USDT · TRON'). Loading/errored tokens render '--' — never a
/// fabricated number.
AssetRow liveTokenRow(MarketController market, TokenInfo token) =>
    liveTokenGroupRow(market, [token]);

/// One row for a symbol, however many chains it is deployed on.
///
/// The registry lists a separate [TokenInfo] per network, and rendering them
/// one-per-row put USDC on screen five times. The row now carries the whole
/// group; the detail screen breaks it down and lets the user pick a chain.
///
/// The amount is the sum of the deployments that LOADED. A chain that failed
/// is left out of the sum and shows as '--' in the per-chain breakdown, so an
/// incomplete total is inspectable rather than silently wrong; when nothing
/// loaded the row itself is '--'.
AssetRow liveTokenGroupRow(
  MarketController market,
  List<TokenInfo> tokens, {
  String Function(int)? chainsLabel,
  String Function(double)? fiatFormatter,
}) => liveAssetGroupRow(
  market,
  AssetRef.tokenGroup(tokens),
  chainsLabel: chainsLabel,
  fiatFormatter: fiatFormatter,
);

/// One row for a symbol, however many chains it is deployed on.
///
/// Native coins go through here too. ETH is native on Ethereum, Base and
/// Arbitrum — one asset in three places, exactly as USDT is in seven — and
/// giving each its own row put "Ethereum 0 ETH", "Base 0 ETH" and "Arbitrum
/// 0 ETH" on screen as if they were different holdings.
///
/// The amount is the sum of the deployments that LOADED. A chain that failed
/// is left out of the sum and shows as '--' in the per-chain breakdown, so an
/// incomplete total is inspectable rather than silently wrong; when nothing
/// loaded the row itself is '--'.
AssetRow liveAssetGroupRow(
  MarketController market,
  AssetRef ref, {

  /// Localized "N chains" label; the plain count is a fallback for callers
  /// without an l10n handy (demo/gallery paths).
  String Function(int)? chainsLabel,
  String Function(double)? fiatFormatter,
}) {
  Amount? total;
  var loaded = 0;
  var fiat = 0.0;
  var anyFiat = false;
  for (final at in ref.group) {
    final result = market.resultFor(at);
    final amount = result.amount;
    if (result.status == BalanceStatus.ok && amount != null) {
      loaded++;
      total = total == null ? amount : total + amount;
    }
    final value = market.fiatFor(at, ref.symbol);
    if (value != null) {
      anyFiat = true;
      fiat += value;
    }
  }
  final (color, glyph) =
      tokenRowMeta[ref.symbol] ??
      (WalletColors.accent, ref.symbol.substring(0, 1));
  // Sub-label: the single network for a one-chain asset, the chain count when
  // the same symbol spans several.
  final where = ref.group.length == 1
      ? ref.group.first.network
      : (chainsLabel?.call(ref.group.length) ?? '${ref.group.length}');
  final change = anyFiat ? market.changeFor(ref.group.first, ref.symbol) : null;
  return AssetRow(
    color,
    glyph,
    ref.name,
    '${loaded == 0 || total == null ? '--' : total.format(maxFraction: 6)} '
    '${ref.symbol} · $where',
    anyFiat ? (fiatFormatter?.call(fiat) ?? formatUsd(fiat)) : '--',
    formatChange24h(change),
    (change ?? 0) < 0 ? WalletColors.red : WalletColors.green,
    ref: ref,
  );
}

/// The native coin of every supported chain, in list order.
///
/// Several chains share one: ETH is the gas coin of Ethereum and of its L2s,
/// which is why these are grouped by symbol rather than listed per chain.
final nativeChains = [
  (Coin.eth, 'ETH', 'Ethereum'),
  (Coin.polygon, 'POL', 'Polygon'),
  (Coin.base, 'ETH', 'Base'),
  (Coin.arbitrum, 'ETH', 'Arbitrum One'),
  (Coin.avalanche, 'AVAX', 'Avalanche C-Chain'),
  (Coin.bnb, 'BNB', 'BNB Smart Chain'),
  (Coin.tron, 'TRX', 'TRON'),
  (Coin.solana, 'SOL', 'Solana'),
];

/// Native coins grouped by symbol, preserving first-seen order.
Map<String, List<AssetDeployment>> nativesBySymbol() {
  final grouped = <String, List<AssetDeployment>>{};
  for (final (coin, symbol, network) in nativeChains) {
    (grouped[symbol] ??= []).add(AssetDeployment.native(coin, network));
  }
  return grouped;
}

/// Groups the registry by symbol, preserving first-seen order.
Map<String, List<TokenInfo>> tokensBySymbol(List<TokenInfo> tokens) {
  final grouped = <String, List<TokenInfo>>{};
  for (final token in tokens) {
    (grouped[token.symbol] ??= []).add(token);
  }
  return grouped;
}

/// Builds the asset rows from live market data: the four native rows, then
/// the registry tokens. Loading and errored chains render '--' (never a
/// fabricated number). The change column uses the live market quote and stays
/// empty when CoinGecko could not calculate a fresh 24h value.
List<AssetRow> liveAssetRows(
  MarketController market, {
  String Function(int)? chainsLabel,
  String Function(double)? fiatFormatter,
}) => [
  for (final entry in nativesBySymbol().entries)
    liveAssetGroupRow(
      market,
      AssetRef.group(name: entry.key, symbol: entry.key, group: entry.value),
      chainsLabel: chainsLabel,
      fiatFormatter: fiatFormatter,
    ),
  for (final group in tokensBySymbol(market.tokens).values)
    liveTokenGroupRow(
      market,
      group,
      chainsLabel: chainsLabel,
      fiatFormatter: fiatFormatter,
    ),
];

/// Applies the persisted asset preferences without ever hiding an unknown
/// balance. Favorites lead; the remaining rows use their real USD holding
/// value when available.
List<AssetRow> preferredAssetRows(
  BuildContext context,
  MarketController market,
  List<AssetRow> source,
) {
  final prefs = AppPrefsScope.maybeOf(context);
  final rows = [
    for (final row in source)
      if (!(prefs?.hideZeroBalances ?? false) ||
          row.ref == null ||
          !market.isDefinitelyZero(row.ref!.group))
        row,
  ];
  rows.sort((left, right) {
    final leftFavorite =
        left.ref != null && (prefs?.isFavoriteAsset(left.ref!.symbol) ?? false);
    final rightFavorite =
        right.ref != null &&
        (prefs?.isFavoriteAsset(right.ref!.symbol) ?? false);
    if (leftFavorite != rightFavorite) return leftFavorite ? -1 : 1;
    final leftValue = left.ref == null
        ? null
        : market.fiatTotalFor(left.ref!.group, left.ref!.symbol);
    final rightValue = right.ref == null
        ? null
        : market.fiatTotalFor(right.ref!.group, right.ref!.symbol);
    if (leftValue == null && rightValue == null) return 0;
    if (leftValue == null) return 1;
    if (rightValue == null) return -1;
    return rightValue.compareTo(leftValue);
  });
  return rows;
}

class AssetRow {
  const AssetRow(
    this.color,
    this.letter,
    this.name,
    this.sub,
    this.value,
    this.change,
    this.changeColor, {
    this.ref,
  });
  final Color color;
  final String letter, name, sub, value, change;
  final Color changeColor;

  /// Which asset this row stands for, so tapping it opens THAT asset's detail
  /// screen. Null on the demo rows (gallery / goldens), which have no real
  /// asset behind them.
  final AssetRef? ref;
}

class _Header extends StatelessWidget {
  const _Header({required this.wallet, this.onTapPill});
  final Wallet wallet;
  final VoidCallback? onTapPill;

  String _shortAddress(String value) {
    if (value.length <= 16) return value;
    return '${value.substring(0, 8)}…${value.substring(value.length - 6)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isHot = wallet is HotWallet;
    return Column(
      key: const ValueKey('home-wallet-header'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _PressScale(
                semanticLabel:
                    '${wallet.name}, ${isHot ? l10n.walletKindHot : l10n.walletKindWatch}',
                onTap: onTapPill,
                child: Row(
                  key: const ValueKey('home-wallet-switcher'),
                  children: [
                    _Avatar(
                      color: Color(wallet.avatarColor),
                      initial: wallet.name.characters.first,
                      size: 40,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  wallet.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w700,
                                    color: WalletColors.text,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 20,
                                color: WalletColors.text2,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          WalletTypeBadge(
                            kind: isHot ? WalletKind.hot : WalletKind.watch,
                            label: isHot
                                ? l10n.walletKindHot
                                : l10n.walletKindWatch,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              key: const ValueKey('home-scan-button'),
              tooltip: l10n.scanAccountQr,
              onPressed: () => context.push('/scan-account'),
              style: IconButton.styleFrom(
                minimumSize: const Size.square(48),
                maximumSize: const Size.square(48),
                padding: EdgeInsets.zero,
                backgroundColor: Colors.white.withValues(alpha: .9),
                foregroundColor: WalletColors.text,
                side: const BorderSide(color: Colors.white),
                shape: const CircleBorder(),
              ),
              icon: const Icon(CupertinoIcons.qrcode, size: 24),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: TextButton(
                key: const ValueKey('home-wallet-addresses-button'),
                onPressed: () => _showWalletAddresses(context, wallet),
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerLeft,
                  foregroundColor: WalletColors.text2,
                ),
                child: Semantics(
                  label: l10n.walletAddressesTitle,
                  excludeSemantics: true,
                  child: Row(
                    children: [
                      const Icon(Icons.list_alt_rounded, size: 17),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _shortAddress(wallet.addresses.eth),
                          key: const ValueKey('home-wallet-address'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right_rounded, size: 17),
                    ],
                  ),
                ),
              ),
            ),
            const TestnetBadge(),
          ],
        ),
      ],
    );
  }
}

class _WalletNetworkAddress {
  const _WalletNetworkAddress({
    required this.network,
    required this.address,
    this.tronActivation,
  });

  final Network network;
  final String address;
  final TronActivationStatus? tronActivation;
}

Chain _chainForWalletCoin(Coin coin) => switch (coin) {
  Coin.eth => Chain.ethereum,
  Coin.polygon => Chain.polygon,
  Coin.base => Chain.base,
  Coin.arbitrum => Chain.arbitrum,
  Coin.avalanche => Chain.avalanche,
  Coin.bnb => Chain.bnb,
  Coin.tron => Chain.tron,
  Coin.solana => Chain.solana,
};

List<_WalletNetworkAddress> _walletNetworkAddresses(
  BuildContext context,
  Wallet wallet,
) {
  final networks = NetworkScope.of(context);
  final isCurrentWallet = WalletScope.of(context).current?.id == wallet.id;
  return <_WalletNetworkAddress>[
    for (final coin in wallet.addresses.enabledCoins)
      if (wallet.addresses.forCoin(coin).trim().isNotEmpty)
        _WalletNetworkAddress(
          network: networks.activeFor(_chainForWalletCoin(coin)),
          address: wallet.addresses.forCoin(coin),
          tronActivation: coin == Coin.tron && !isCurrentWallet
              ? TronActivationStatus.unknown
              : null,
        ),
  ];
}

/// Full-page account-address directory reached from wallet details. It reuses
/// the exact same address derivation, filtering, alphabet index and copy UI as
/// the compact home sheet so those two production entry points cannot drift.
class WalletAddressesScreen extends StatelessWidget {
  const WalletAddressesScreen({super.key, this.walletId});

  final String? walletId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = WalletScope.of(context);
    final wallet = walletId == null
        ? controller.current
        : controller.wallets.where((w) => w.id == walletId).firstOrNull;
    return KtScreen(
      key: const ValueKey('wallet-addresses-screen'),
      backgroundColor: WalletColors.surface,
      navBar: KtNavBar(
        title: l10n.walletAddressesTitle,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      padding: EdgeInsets.zero,
      gap: 0,
      scrollable: false,
      children: [
        if (wallet != null)
          Expanded(
            child: _WalletAddressesDirectory(
              entries: _walletNetworkAddresses(context, wallet),
              showSheetHeader: false,
            ),
          ),
      ],
    );
  }
}

Future<void> _showWalletAddresses(BuildContext context, Wallet wallet) async {
  final entries = _walletNetworkAddresses(context, wallet);
  final maxHeight = MediaQuery.sizeOf(context).height * 0.82;
  final desiredHeight = (146.0 + entries.length * 72.0).clamp(320.0, maxHeight);
  await showKtModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: WalletColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      top: false,
      child: SizedBox(
        height: desiredHeight,
        child: _WalletAddressesDirectory(entries: entries),
      ),
    ),
  );
}

class _WalletAddressesDirectory extends StatefulWidget {
  const _WalletAddressesDirectory({
    required this.entries,
    this.showSheetHeader = true,
  });

  final List<_WalletNetworkAddress> entries;
  final bool showSheetHeader;

  @override
  State<_WalletAddressesDirectory> createState() =>
      _WalletAddressesDirectoryState();
}

class _WalletAddressesDirectoryState extends State<_WalletAddressesDirectory> {
  static const _alphabet = <String>[
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
  ];

  final _search = TextEditingController();
  final _scroll = ScrollController();
  String? _copiedNetworkId;

  bool get _usesLargeText => MediaQuery.textScalerOf(context).scale(14) >= 20;
  double get _rowHeight => _usesLargeText ? 104 : 70;
  double get _sectionHeight => _usesLargeText ? 36 : 24;

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _jumpToLetter(
    String letter,
    Map<String, List<_WalletNetworkAddress>> groups,
  ) {
    if (!_scroll.hasClients || !groups.containsKey(letter)) return;
    var offset = 0.0;
    for (final group in groups.entries) {
      if (group.key == letter) break;
      offset += _sectionHeight + group.value.length * _rowHeight;
    }
    _scroll.animateTo(
      offset.clamp(0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _addressRow(_WalletNetworkAddress entry, AppLocalizations l10n) {
    final copied = _copiedNetworkId == entry.network.id;
    return SizedBox(
      key: ValueKey('wallet-address-row-${entry.network.id}'),
      height: _rowHeight,
      child: Row(
        children: [
          ChainIcon(chain: entry.network.chain, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.network.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: WalletColors.text,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  entry.address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    height: 1.25,
                    color: WalletColors.text3,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey('wallet-address-copy-${entry.network.id}'),
            tooltip: l10n.copyAddress,
            onPressed: () => _copy(entry),
            icon: Icon(
              copied ? Icons.check_rounded : Icons.copy_outlined,
              size: 21,
              color: copied ? WalletColors.green : WalletColors.text,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copy(_WalletNetworkAddress entry) async {
    await Clipboard.setData(ClipboardData(text: entry.address));
    if (!mounted) return;
    setState(() => _copiedNetworkId = entry.network.id);
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.addressCopied),
          duration: const Duration(milliseconds: 1200),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final query = _search.text.trim().toLowerCase();
    final entries =
        <_WalletNetworkAddress>[
          for (final entry in widget.entries)
            if (query.isEmpty ||
                entry.network.name.toLowerCase().contains(query) ||
                entry.network.symbol.toLowerCase().contains(query) ||
                entry.address.toLowerCase().contains(query))
              entry,
        ]..sort(
          (a, b) => a.network.name.toLowerCase().compareTo(
            b.network.name.toLowerCase(),
          ),
        );
    final groups = <String, List<_WalletNetworkAddress>>{};
    for (final entry in entries) {
      final first = entry.network.name.characters.first.toUpperCase();
      final letter = RegExp(r'^[A-Z]$').hasMatch(first) ? first : '#';
      groups.putIfAbsent(letter, () => []).add(entry);
    }
    return Column(
      key: ValueKey(
        widget.showSheetHeader
            ? 'wallet-addresses-sheet'
            : 'wallet-addresses-directory',
      ),
      children: [
        if (widget.showSheetHeader) ...[
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: WalletColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            l10n.walletAddressesTitle,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: WalletColors.text,
            ),
          ),
        ],
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: TextField(
            key: const ValueKey('wallet-address-search-field'),
            controller: _search,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            autocorrect: false,
            decoration: InputDecoration(
              hintText: l10n.walletAddressSearchHint,
              hintStyle: const TextStyle(
                fontSize: 14,
                color: WalletColors.text3,
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                size: 22,
                color: WalletColors.text,
              ),
              filled: true,
              fillColor: WalletColors.bg,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                  color: WalletColors.text,
                  width: 1.2,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    l10n.homeNoMatchingNetworks,
                    style: const TextStyle(
                      fontSize: 14,
                      color: WalletColors.text3,
                    ),
                  ),
                )
              : Stack(
                  children: [
                    ListView(
                      key: const ValueKey('wallet-address-list'),
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(18, 0, 52, 12),
                      children: [
                        for (final group in groups.entries) ...[
                          SizedBox(
                            key: ValueKey(
                              'wallet-address-section-${group.key}',
                            ),
                            height: _sectionHeight,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                group.key,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: WalletColors.text3,
                                ),
                              ),
                            ),
                          ),
                          for (final entry in group.value)
                            _addressRow(entry, l10n),
                        ],
                      ],
                    ),
                    Positioned(
                      key: const ValueKey('wallet-address-alphabet-index'),
                      right: 0,
                      top: 0,
                      bottom: 0,
                      width: 48,
                      child: Semantics(
                        container: true,
                        label: '${l10n.walletAddressesTitle} A–Z',
                        customSemanticsActions: {
                          for (final letter in _alphabet)
                            if (groups.containsKey(letter))
                              CustomSemanticsAction(label: letter): () =>
                                  _jumpToLetter(letter, groups),
                        },
                        child: ExcludeSemantics(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final letterHeight =
                                  (constraints.maxHeight / _alphabet.length)
                                      .clamp(0.0, 14.0);
                              return Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (final letter in _alphabet)
                                      GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: groups.containsKey(letter)
                                            ? () =>
                                                  _jumpToLetter(letter, groups)
                                            : null,
                                        child: SizedBox(
                                          key: ValueKey(
                                            'wallet-address-index-$letter',
                                          ),
                                          width: 48,
                                          height: letterHeight,
                                          child: Center(
                                            child: MediaQuery.withNoTextScaling(
                                              child: Text(
                                                letter,
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w600,
                                                  color:
                                                      groups.containsKey(letter)
                                                      ? WalletColors.text2
                                                      : WalletColors.border,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
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
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(size * 0.31),
    ),
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
    final walletId = WalletScope.of(context).current!.id;
    final largeText = MediaQuery.textScalerOf(context).scale(13) >= 20;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // This banner describes the CURRENT wallet. Starting `/create-warn`
      // generates a different seed and can never back up this wallet. Open
      // its authenticated recovery-phrase action instead.
      onTap: () => context.push('/wallet-detail?id=$walletId'),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E7),
          borderRadius: BorderRadius.circular(10),
        ),
        child: largeText
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.shield_outlined,
                          size: 18,
                          color: WalletColors.amber,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.backupBannerText,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF5C420E),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      l10n.backupNow,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: WalletColors.accent,
                      ),
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  const Icon(
                    Icons.shield_outlined,
                    size: 18,
                    color: WalletColors.amber,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.backupBannerText,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF5C420E),
                      ),
                    ),
                  ),
                  Text(
                    l10n.backupNow,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: WalletColors.accent,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Balance extends StatelessWidget {
  const _Balance({
    required this.amount,
    required this.change,
    required this.changeColor,
  });
  final String amount, change;
  final Color changeColor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hidden = BalancePrivacy.of(context);
    // Absent scope (gallery/goldens): the eye is inert rather than pretending
    // to toggle something nothing else can see.
    final toggle = BalancePrivacy.toggleOf(context);
    return Semantics(
      button: toggle != null,
      enabled: toggle != null,
      label: l10n.privacyMode,
      onTap: toggle,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: toggle,
        child: Container(
          key: const ValueKey('home-balance-card'),
          margin: const EdgeInsets.symmetric(vertical: 12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Color(0xFFE8F0FE)],
            ),
            border: Border.all(color: Colors.white),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                key: const ValueKey('home-balance-amount-row'),
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      key: const ValueKey('home-balance-amount'),
                      hidden ? '••••••' : amount,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: WalletColors.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox.square(
                    key: const ValueKey('home-balance-privacy-button'),
                    dimension: 44,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Icon(
                        hidden
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 16,
                        color: WalletColors.text3,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                key: const ValueKey('home-balance-change'),
                hidden ? '••••' : change,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: changeColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PortfolioChangeDisplay {
  const _PortfolioChangeDisplay(this.text, this.color);

  final String text;
  final Color color;
}

_PortfolioChangeDisplay _portfolioChangeDisplay(
  BuildContext context, {
  required MarketController? market,
  required bool testnet,
  required PortfolioChange24h? change,
  required String period,
}) {
  if (market == null) {
    return _PortfolioChangeDisplay(
      '+\$12.06 (+1.4%) $period',
      WalletColors.green,
    );
  }
  if (testnet) {
    return _PortfolioChangeDisplay('-- (--%) $period', WalletColors.text3);
  }
  if (change == null) {
    if (!market.portfolioBalanceIsDefinitelyZero) {
      return _PortfolioChangeDisplay('-- (--%) $period', WalletColors.text3);
    }
    final zero = formatFiatForContext(context, 0);
    return _PortfolioChangeDisplay(
      zero == '--' ? '-- (--%) $period' : '$zero (0.00%) $period',
      WalletColors.text3,
    );
  }

  final neutral = change.deltaUsd.abs() < 0.005 && change.percent.abs() < 0.005;
  if (neutral) {
    final zero = formatFiatForContext(context, 0);
    return _PortfolioChangeDisplay(
      zero == '--' ? '-- (--%) $period' : '$zero (0.00%) $period',
      WalletColors.text3,
    );
  }
  return _PortfolioChangeDisplay(
    '${formatSignedFiatForContext(context, change.deltaUsd)} '
    '(${formatChange24h(change.percent)}) $period',
    change.deltaUsd < 0 ? WalletColors.red : WalletColors.green,
  );
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({this.onMore});
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final actions = <(String, IconData, String?)>[
      (l10n.actionReceive, Icons.south_west_rounded, '/receive'),
      (l10n.actionSend, Icons.north_east_rounded, '/transfer'),
      (l10n.actionMore, Icons.more_horiz_rounded, null),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (index, item) in actions.indexed) ...[
            if (index > 0) const SizedBox(width: 10),
            Expanded(
              child: _PressScale(
                onTap: item.$3 == null ? onMore : () => context.push(item.$3!),
                semanticLabel: item.$1,
                child: Container(
                  key: ValueKey('home-action-surface-$index'),
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 84),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .9),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white),
                  ),
                  child: Column(
                    children: [
                      Icon(item.$2, size: 25, color: WalletColors.accent),
                      const SizedBox(height: 8),
                      Text(
                        item.$1,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: WalletColors.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Crisp, interruptible press feedback used on the high-frequency home
/// actions. It scales only transform content for 120ms and respects platform
/// haptics; navigation itself is never delayed by the animation.
class _PressScale extends StatefulWidget {
  const _PressScale({
    required this.child,
    required this.onTap,
    required this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String semanticLabel;

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      enabled: widget.onTap != null,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onTap == null ? null : (_) => _setPressed(true),
        onTapCancel: widget.onTap == null ? null : () => _setPressed(false),
        onTapUp: widget.onTap == null ? null : (_) => _setPressed(false),
        onTap: widget.onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                widget.onTap!();
              },
        child: AnimatedScale(
          scale: reduceMotion || !_pressed ? 1 : 0.97,
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Center(child: widget.child),
          ),
        ),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.selected, required this.onTap});
  final int selected;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tabs = <(String, IconData)>[
      (l10n.tabWallet, Icons.account_balance_wallet_outlined),
      (l10n.tabActivity, Icons.history_rounded),
      (l10n.tabSettings, Icons.settings_outlined),
    ];
    return LiquidWalletTabs(items: tabs, selected: selected, onSelected: onTap);
  }
}
