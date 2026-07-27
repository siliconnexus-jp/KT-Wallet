import 'package:chains/chains.dart' show Amount, Chain;
import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/material.dart';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../l10n/app_localizations.dart';
import '../market/airdrop_service.dart';
import '../market/asset_ref.dart';
import '../market/balance_service.dart';
import '../market/explorer_links.dart';
import '../market/price_service.dart';
import '../market/receive_card.dart';
import '../market/market_controller.dart';
import '../market/market_scope.dart';
import '../market/token_balance_service.dart' show TokenInfo;
import '../platform/external_actions.dart';
import '../platform/media_gallery.dart';
import '../transfer/airgap_codec.dart' show truncateMiddle;
import 'home_screen.dart' show liveTokenGroupRow, tokensBySymbol;
import '../widgets/market_offline_banner.dart';
import '../widgets/token_icon.dart';
import '../state/networks.dart';
import '../state/wallet_scope.dart';

/// W2 资产列表 — search + network filter + full asset list. Live: the search
/// field and network segments filter the (demo) asset rows; tapping a row
/// opens the token detail screen.
class AssetsListScreen extends StatefulWidget {
  const AssetsListScreen({super.key});
  @override
  State<AssetsListScreen> createState() => _AssetsListScreenState();
}

class _AssetsListScreenState extends State<AssetsListScreen> {
  // (color, symbol glyph, name, holdings, value, change, change color,
  //  network, assetRef) — assetRef is null on the demo rows, which stand
  //  for no real asset.
  static const _assets = [
    (
      Color(0xFF627EEA),
      'Ξ',
      'Ethereum',
      '2.4805 ETH',
      r'$8,241.60',
      '+2.4%',
      WalletColors.green,
      'Ethereum',
      null,
    ),
    (
      Color(0xFF26A17B),
      '₮',
      'USDT',
      '3,120.00 USDT · TRON',
      r'$3,120.00',
      '0.0%',
      WalletColors.text3,
      'TRON',
      null,
    ),
    (
      Color(0xFF8247E5),
      '⬡',
      'POL',
      '2,860.5 POL · Polygon',
      r'$986.87',
      '-1.2%',
      WalletColors.red,
      'Polygon',
      null,
    ),
    (
      Color(0xFF9945FF),
      '◎',
      'Solana',
      '3.208 SOL',
      r'$498.85',
      '+5.1%',
      WalletColors.green,
      'Solana',
      null,
    ),
    (
      Color(0xFF2775CA),
      r'$',
      'USDC',
      '120.00 USDC · Solana',
      r'$120.00',
      '0.0%',
      WalletColors.text3,
      'Solana',
      null,
    ),
  ];
  static const _networks = [
    'Ethereum',
    'Polygon',
    'Base',
    'Arbitrum One',
    'Avalanche C-Chain',
    'TRON',
    'Solana',
  ];
  static const _legacyNetworks = ['Ethereum', 'Polygon', 'TRON', 'Solana'];

  /// Sentinel network for a row that spans several chains, so the per-network
  /// filter never hides it.
  static const _allNetworks = '*';

  String _query = '';
  int _net = 0; // 0 = all

  @override
  void initState() {
    super.initState();
    // Live refresh on entry (post-frame — refresh() notifies synchronously).
    // No-op without a MarketScope (gallery/goldens) or after the first one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) MarketScope.read(context)?.refreshIfNeeded();
    });
  }

  /// Live rows in the same tuple shape as the demo list: the four native
  /// coins, then the built-in registry tokens. Loading and errored items show
  /// '--' — never an invented number; the change column is empty because
  /// there is no 24h-change feed yet.
  List<
    (Color, String, String, String, String, String, Color, String, AssetRef?)
  >
  _liveRows(MarketController market, AppLocalizations l10n) {
    return [
      for (final (coin, name, symbol, color, glyph, network) in const [
        (Coin.eth, 'Ethereum', 'ETH', Color(0xFF627EEA), 'Ξ', 'Ethereum'),
        (Coin.polygon, 'POL', 'POL', Color(0xFF8247E5), '⬡', 'Polygon'),
        (Coin.base, 'Base', 'ETH', Color(0xFF0052FF), 'B', 'Base'),
        (
          Coin.arbitrum,
          'Arbitrum',
          'ETH',
          Color(0xFF28A0F0),
          'A',
          'Arbitrum One',
        ),
        (
          Coin.avalanche,
          'Avalanche',
          'AVAX',
          Color(0xFFE84142),
          'A',
          'Avalanche C-Chain',
        ),
        (Coin.tron, 'TRON', 'TRX', Color(0xFF26A17B), '₮', 'TRON'),
        (Coin.solana, 'Solana', 'SOL', Color(0xFF9945FF), '◎', 'Solana'),
      ])
        () {
          final result = market.balanceFor(coin);
          final amount = result.amount;
          final ok = result.status == BalanceStatus.ok && amount != null;
          final fiat = market.fiatValueUsd(coin);
          return (
            color,
            glyph,
            name,
            ok ? '${amount.format(maxFraction: 6)} $symbol' : '-- $symbol',
            fiat == null ? '--' : formatUsd(fiat),
            '',
            WalletColors.text3,
            network,
            AssetRef.native(coin: coin, name: name, symbol: symbol),
          );
        }(),
      // One row per SYMBOL, not per deployment: the registry lists USDC on
      // five chains and this list showed it five times. Reuses the home
      // aggregation so both surfaces agree.
      for (final group in tokensBySymbol(market.tokens).values)
        () {
          final row = liveTokenGroupRow(
            market,
            group,
            chainsLabel: l10n.assetOnChains,
          );
          return (
            row.color,
            row.letter,
            row.name,
            row.sub,
            row.value,
            row.change,
            row.changeColor,
            // Network filter: a multi-chain row belongs to every network it is
            // deployed on, so it survives any of their filters.
            group.length == 1 ? group.first.network : _allNetworks,
            row.ref,
          );
        }(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // No scope (gallery/goldens) → demo rows byte-for-byte; scope with all
    // fetches failed → demo rows behind the offline banner; else live rows.
    final market = MarketScope.maybeOf(context);
    final offline = market?.isOffline ?? false;
    final live = market != null && !offline;
    final rows = live ? _liveRows(market, l10n) : _assets;
    final networks = market == null ? _legacyNetworks : _networks;
    final q = _query.trim().toLowerCase();
    final results = [
      for (final a in rows)
        if ((_net == 0 || a.$8 == networks[_net - 1]) &&
            (q.isEmpty ||
                a.$3.toLowerCase().contains(q) ||
                a.$4.toLowerCase().contains(q)))
          a,
    ];
    return KtScreen(
      navBar: KtNavBar(
        title: l10n.tabAssets,
        onBack: () => Navigator.of(context).maybePop(),
        trailing: Icons.add,
        onTrailing: () => context.push('/token-manage'),
      ),
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: WalletColors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.search, size: 18, color: WalletColors.text3),
              const SizedBox(width: 8),
              Expanded(
                // The placeholder is drawn as a plain Text (not the TextField's
                // hint) so the idle screen renders exactly like the design.
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    if (_query.isEmpty)
                      Text(
                        l10n.searchAssetHint,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 14,
                          color: WalletColors.text3,
                        ),
                      ),
                    TextField(
                      onChanged: (v) => setState(() => _query = v),
                      style: const TextStyle(
                        fontSize: 14,
                        color: WalletColors.text,
                      ),
                      decoration: const InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        KtSegmented(
          // Same reason as the add-network family picker: under a NetworkScope
          // this is "All" plus seven network names, and an even split shreds
          // "Avalanche C-Chain" across lines.
          scrollable: true,
          options: [l10n.viewAll, ...networks],
          selected: _net,
          onChanged: (i) => setState(() => _net = i),
        ),
        if (offline) const MarketOfflineBanner(),
        if (results.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                l10n.noMatchingAssets,
                style: const TextStyle(fontSize: 14, color: WalletColors.text3),
              ),
            ),
          )
        else
          KtCard(
            child: Column(
              children: [
                for (var i = 0; i < results.length; i++) ...[
                  if (i > 0) const SizedBox(height: 18),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    // The row's own asset rides along as `extra`; without it
                    // the detail route rendered one fixed token for every row.
                    onTap: () => context.push('/token', extra: results[i].$9),
                    child: _AssetTile(results[i]),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _AssetTile extends StatelessWidget {
  const _AssetTile(this.a);
  final (
    Color,
    String,
    String,
    String,
    String,
    String,
    Color,
    String,
    AssetRef?,
  )
  a;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      TokenIcon(
        symbol: a.$3,
        size: 40,
        fallbackColor: a.$1,
        fallbackInitial: a.$2,
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              a.$3,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: WalletColors.text,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              a.$4,
              style: const TextStyle(fontSize: 12, color: WalletColors.text2),
            ),
          ],
        ),
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            a.$5,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: WalletColors.text,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            a.$6,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: a.$7,
            ),
          ),
        ],
      ),
    ],
  );
}

/// Brand dot per protocol family, for the network badge on the detail screen.
const _chainDot = {
  Chain.ethereum: ChainColors.ethereum,
  Chain.polygon: ChainColors.polygon,
  Chain.base: ChainColors.base,
  Chain.arbitrum: ChainColors.arbitrum,
  Chain.avalanche: ChainColors.avalanche,
  Chain.tron: ChainColors.tron,
  Chain.solana: ChainColors.solana,
};

/// W3 Token 详情 — hero balance + info card.
///
/// [asset] says WHICH asset to render; it arrives as the route's `extra` from
/// the tapped row. Before it existed this screen took no arguments at all and
/// hardcoded one token's balance, so every row in the home list and the assets
/// tab opened the same "3,120.00 USDT" page — a balance the user did not hold.
///
/// The design gallery and the goldens have no [MarketScope] and no asset; they
/// keep rendering the original demo snapshot so those references stay
/// comparable.
class TokenDetailScreen extends StatefulWidget {
  const TokenDetailScreen({super.key, this.asset});

  final AssetRef? asset;

  /// Demo USDT TRC-20 contract, shown only in the scope-absent snapshot.
  static const _contract = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';

  @override
  State<TokenDetailScreen> createState() => _TokenDetailScreenState();
}

class _TokenDetailScreenState extends State<TokenDetailScreen> {
  /// Which deployment of a multi-chain token the actions apply to. Defaults
  /// to the chain holding the most, which is what the user usually means.
  int _chainIndex = 0;
  bool _pickedDefault = false;

  AssetRef? get asset => widget.asset;

  void _pickDefaultChain(MarketController market, AssetRef ref) {
    if (_pickedDefault || !ref.isMultiChain) return;
    _pickedDefault = true;
    var best = 0;
    BigInt bestRaw = BigInt.zero;
    for (final (i, token) in ref.group.indexed) {
      final result = market.tokenBalanceFor(token.id);
      final amount = result.amount;
      if (result.status != BalanceStatus.ok || amount == null) continue;
      if (amount.raw > bestRaw) {
        bestRaw = amount.raw;
        best = i;
      }
    }
    _chainIndex = best;
  }

  @override
  Widget build(BuildContext context) {
    final market = MarketScope.maybeOf(context);
    if (market == null) return _demoSnapshot(context);
    final ref = asset;
    // Live, but nothing to show: a deep link straight to /token, or a row
    // whose asset went away. Say so instead of inventing a holding.
    if (ref == null) return _unavailable(context);
    _pickDefaultChain(market, ref);
    return _live(context, market, ref);
  }

  Widget _unavailable(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KtScreen(
      navBar: KtNavBar(
        title: l10n.tabAssets,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Center(
            child: Text(
              l10n.assetUnavailable,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: WalletColors.text3),
            ),
          ),
        ),
      ],
    );
  }

  Widget _live(BuildContext context, MarketController market, AssetRef ref) {
    final l10n = AppLocalizations.of(context);
    // For a multi-chain token every action applies to the SELECTED chain;
    // the hero above them still shows the combined holding.
    final selected = ref.isMultiChain ? ref.group[_chainIndex] : null;
    final actionCoin = selected?.chain ?? ref.coin;
    final network = NetworkScope.of(context).activeFor(chainOf(actionCoin));

    final (total, loadedAll) = _totalFor(market, ref);
    // A balance that has not loaded, or failed, renders '--'. It must never
    // fall back to a number.
    final balance = total == null
        ? '-- ${ref.symbol}'
        : '${total.format(maxFraction: 6)} ${ref.symbol}';

    final fiat = ref.isToken
        ? _tokenFiat(market, ref)
        : market.fiatValueUsd(ref.coin);
    final price = ref.isToken
        ? PriceService.peggedUsdBySymbol[ref.symbol]
        : market.priceUsd(ref.coin);

    final contract = selected?.contract ?? ref.contract;
    final wallet = WalletScope.of(context).current;
    final address = wallet?.addresses.forCoin(actionCoin);
    // Tokens link to the contract, native coins to this wallet's account.
    final explorer = contract != null
        ? explorerTokenUrl(network, contract)
        : (address == null || address.isEmpty
              ? null
              : explorerAddressUrl(network, address));

    return KtScreen(
      navBar: KtNavBar(
        title: ref.name,
        onBack: () => Navigator.of(context).maybePop(),
        trailing: explorer == null ? null : Icons.open_in_new,
        onTrailing: explorer == null
            ? null
            : () async {
                final opened = await ExternalActions.instance.open(
                  Uri.parse(explorer),
                );
                if (!opened && context.mounted) {
                  ScaffoldMessenger.of(context)
                    ..clearSnackBars()
                    ..showSnackBar(
                      SnackBar(content: Text(l10n.externalActionFailed)),
                    );
                }
              },
      ),
      children: [
        Column(
          children: [
            TokenIcon(symbol: ref.symbol, size: 56),
            const SizedBox(height: 10),
            Text(
              balance,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: WalletColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              fiat == null ? '--' : '≈ ${formatUsd(fiat)}',
              style: const TextStyle(fontSize: 15, color: WalletColors.text2),
            ),
            const SizedBox(height: 10),
            NetworkBadge(
              label: ref.isMultiChain
                  ? l10n.assetOnChains(ref.group.length)
                  : (ref.network ?? network.name),
              dotColor: _chainDot[chainOf(actionCoin)]!,
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: KtPrimaryButton(
                label: l10n.actionSend,
                icon: Icons.north_east,
                onPressed: () => context.push('/transfer'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  // Carries the chain the user is looking at; without it the
                  // receive screen always opened on its own default (USDT on
                  // TRON), whatever asset you came from.
                  onPressed: () => context.push('/receive', extra: actionCoin),
                  icon: const Icon(
                    Icons.qr_code,
                    size: 18,
                    color: WalletColors.accent,
                  ),
                  label: Text(
                    l10n.actionReceive,
                    style: const TextStyle(
                      color: WalletColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: WalletColors.surface,
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (ref.isMultiChain) _chainPicker(context, market, ref),
        KtCard(
          child: Column(
            children: [
              KtDetailRow(
                label: l10n.price,
                value: price == null ? '--' : formatUsd(price),
              ),
              const SizedBox(height: 14),
              // There is no 24h-change feed yet; '--' is the honest value.
              KtDetailRow(label: l10n.change24h, value: '--'),
              if (contract != null) ...[
                const SizedBox(height: 14),
                KtDetailRow(
                  label: l10n.contractAddress,
                  value: truncateMiddle(contract),
                  mono: true,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Per-chain breakdown for a symbol deployed on several chains. Selecting a
  /// row re-points Send / Receive / the explorer at that chain.
  Widget _chainPicker(
    BuildContext context,
    MarketController market,
    AssetRef ref,
  ) {
    final l10n = AppLocalizations.of(context);
    return KtCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.chooseNetwork,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: WalletColors.text2,
            ),
          ),
          for (final (i, token) in ref.group.indexed) ...[
            const SizedBox(height: 12),
            GestureDetector(
              key: ValueKey('chain-option-${token.id}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _chainIndex = i),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _chainDot[chainOf(token.chain)]!,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      token.network,
                      style: const TextStyle(
                        fontSize: 14,
                        color: WalletColors.text,
                      ),
                    ),
                  ),
                  Text(
                    _amountTextFor(market, token),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: WalletColors.text,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    i == _chainIndex
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: i == _chainIndex
                        ? WalletColors.accent
                        : WalletColors.text3,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// A deployment's balance, or '--' when that chain has not loaded.
  String _amountTextFor(MarketController market, TokenInfo token) {
    final result = market.tokenBalanceFor(token.id);
    final amount = result.amount;
    return result.status == BalanceStatus.ok && amount != null
        ? amount.format(maxFraction: 6)
        : '--';
  }

  /// Combined holding across every deployment, plus whether they all loaded.
  /// A chain that failed is excluded from the sum and shows '--' in the
  /// breakdown, so a partial total is visible rather than silently wrong.
  (Amount?, bool) _totalFor(MarketController market, AssetRef ref) {
    if (!ref.isToken) {
      final result = market.balanceFor(ref.coin);
      final amount = result.amount;
      final ok = result.status == BalanceStatus.ok && amount != null;
      return (ok ? amount : null, ok);
    }
    final tokens = ref.group.isEmpty ? const <TokenInfo>[] : ref.group;
    if (tokens.isEmpty) {
      final result = market.tokenBalanceFor(ref.tokenId!);
      final amount = result.amount;
      final ok = result.status == BalanceStatus.ok && amount != null;
      return (ok ? amount : null, ok);
    }
    Amount? total;
    var all = true;
    for (final token in tokens) {
      final result = market.tokenBalanceFor(token.id);
      final amount = result.amount;
      if (result.status == BalanceStatus.ok && amount != null) {
        total = total == null ? amount : total + amount;
      } else {
        all = false;
      }
    }
    return (total, all);
  }

  /// USD value of a token holding, keyed off the registry entry the ref came
  /// from (the controller needs the [TokenInfo], not just the symbol).
  double? _tokenFiat(MarketController market, AssetRef ref) {
    if (ref.group.isNotEmpty) {
      double? total;
      for (final token in ref.group) {
        final value = market.tokenFiatValueUsd(token);
        if (value != null) total = (total ?? 0) + value;
      }
      return total;
    }
    for (final token in market.tokens) {
      if (token.id == ref.tokenId) return market.tokenFiatValueUsd(token);
    }
    return null;
  }

  Widget _demoSnapshot(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KtScreen(
      navBar: KtNavBar(
        title: 'USDT',
        onBack: () => Navigator.of(context).maybePop(),
        trailing: Icons.open_in_new,
        onTrailing: () async {
          final opened = await ExternalActions.instance.open(
            Uri.parse(
              'https://tronscan.org/#/token20/'
              '${TokenDetailScreen._contract}',
            ),
          );
          if (!opened && context.mounted) {
            ScaffoldMessenger.of(context)
              ..clearSnackBars()
              ..showSnackBar(
                SnackBar(content: Text(l10n.externalActionFailed)),
              );
          }
        },
      ),
      children: [
        Column(
          children: [
            const TokenIcon(symbol: 'USDT', size: 56),
            const SizedBox(height: 10),
            const Text(
              '3,120.00 USDT',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: WalletColors.text,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '≈ \$3,120.00',
              style: TextStyle(fontSize: 15, color: WalletColors.text2),
            ),
            const SizedBox(height: 10),
            const NetworkBadge(
              label: 'TRON · TRC-20',
              dotColor: ChainColors.tron,
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: KtPrimaryButton(
                label: l10n.actionSend,
                icon: Icons.north_east,
                onPressed: () => context.push('/transfer'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/receive'),
                  icon: const Icon(
                    Icons.qr_code,
                    size: 18,
                    color: WalletColors.accent,
                  ),
                  label: Text(
                    l10n.actionReceive,
                    style: const TextStyle(
                      color: WalletColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: WalletColors.surface,
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        KtCard(
          child: Column(
            children: [
              KtDetailRow(label: l10n.price, value: r'$1.00'),
              const SizedBox(height: 14),
              KtDetailRow(label: l10n.change24h, value: '+0.02%'),
              const SizedBox(height: 14),
              KtDetailRow(
                label: l10n.contractAddress,
                value: 'TR7NHq…gjLj6t',
                mono: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A chain selectable on the receive screen: coin, network name, pill label,
/// token glyph + color, and the ChainColors dot shown in the picker sheet.
class _ReceiveChain {
  const _ReceiveChain(
    this.coin,
    this.network,
    this.pillLabel,
    this.glyph,
    this.tokenColor,
    this.dotColor,
  );
  final Coin coin;
  final String network, pillLabel, glyph;
  final Color tokenColor, dotColor;
}

/// W14 收款 — chain selector + QR + address + warning. Live: the pill opens a
/// chain picker; the displayed address (and what copy/share puts on the
/// clipboard) is the current wallet's address for the selected chain.
class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({
    super.key,
    this.airdropClient,
    this.clock,
    this.tempDirectory,
    this.cardRenderer,
    this.initialCoin,
  });

  /// Chain to open on, passed by whatever the user tapped "receive" from.
  /// Without it this screen always opened on its own default (USDT on TRON)
  /// no matter which asset you arrived from.
  final Coin? initialCoin;

  /// Injectable http client for the devnet airdrop faucet (tests); null in
  /// production (the [AirdropService] creates and closes its own).
  final http.Client? airdropClient;

  /// Stamp printed on the saved receive card; injectable so tests are not
  /// wall-clock dependent.
  final DateTime Function()? clock;

  /// Where the shared card is staged before the share sheet picks it up;
  /// injectable because path_provider has no implementation in widget tests.
  final Future<Directory> Function()? tempDirectory;

  /// Renders the card. Injectable because the real one goes through
  /// `Picture.toImage`, which cannot complete inside a widget test's fake
  /// async zone; [renderReceiveCardPng] is covered directly as a pure
  /// function instead, and widget tests stub this to check the wiring.
  final Future<Uint8List> Function(ReceiveCardData)? cardRenderer;

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  static const _chains = [
    _ReceiveChain(
      Coin.eth,
      'Ethereum',
      'ETH · Ethereum',
      'Ξ',
      Color(0xFF627EEA),
      ChainColors.ethereum,
    ),
    _ReceiveChain(
      Coin.polygon,
      'Polygon',
      'POL · Polygon',
      '⬡',
      Color(0xFF8247E5),
      ChainColors.polygon,
    ),
    _ReceiveChain(
      Coin.base,
      'Base',
      'ETH · Base',
      'B',
      Color(0xFF0052FF),
      Color(0xFF0052FF),
    ),
    _ReceiveChain(
      Coin.arbitrum,
      'Arbitrum One',
      'ETH · Arbitrum',
      'A',
      Color(0xFF28A0F0),
      Color(0xFF28A0F0),
    ),
    _ReceiveChain(
      Coin.avalanche,
      'Avalanche C-Chain',
      'AVAX · Avalanche',
      'A',
      Color(0xFFE84142),
      Color(0xFFE84142),
    ),
    _ReceiveChain(
      Coin.tron,
      'TRON',
      'USDT · TRON',
      '₮',
      Color(0xFF26A17B),
      ChainColors.tron,
    ),
    _ReceiveChain(
      Coin.solana,
      'Solana',
      'SOL · Solana',
      '◎',
      Color(0xFF9945FF),
      ChainColors.solana,
    ),
  ];

  // Default TRON, matching the design; overridden by [widget.initialCoin].
  int _selected = 2;

  /// The caller's chain is applied once, after the first dependency
  /// resolution (the available list needs a WalletScope).
  bool _appliedInitial = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_appliedInitial) return;
    _appliedInitial = true;
    final wanted = widget.initialCoin;
    if (wanted == null) return;
    final index = _availableChains.indexWhere((c) => c.coin == wanted);
    if (index >= 0) _selected = index;
  }

  /// True while a devnet airdrop request is in flight (guards double-taps).
  bool _airdropping = false;

  /// True while the receive card is being rendered (guards double-taps).
  bool _savingImage = false;
  bool _sharing = false;

  List<_ReceiveChain> get _availableChains {
    final expanded =
        WalletScope.of(context).current?.addresses.hasExpandedEvm ?? false;
    return expanded
        ? [
            _chains[0],
            _chains[1],
            _chains[5],
            _chains[6],
            _chains[2],
            _chains[3],
            _chains[4],
          ]
        : [_chains[0], _chains[1], _chains[5], _chains[6]];
  }

  _ReceiveChain get _chain => _availableChains[_selected];

  /// Protocol family of the selected coin (Coin is the derivation-level enum,
  /// Chain the network-level one; they map 1:1).
  static Chain _familyOf(Coin coin) => switch (coin) {
    Coin.eth => Chain.ethereum,
    Coin.polygon => Chain.polygon,
    Coin.base => Chain.base,
    Coin.arbitrum => Chain.arbitrum,
    Coin.avalanche => Chain.avalanche,
    Coin.tron => Chain.tron,
    Coin.solana => Chain.solana,
  };

  String _address(BuildContext context) {
    final wallet = WalletScope.of(context).current;
    return wallet == null ? '' : wallet.addresses.forCoin(_chain.coin);
  }

  /// Faucet tap. Solana testnets request a real one-tap airdrop through RPC.
  /// Other testnets open their official faucet in the system browser.
  Future<void> _faucet(Network net) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    if (net.chain == Chain.solana) {
      final address = _address(context);
      if (address.isEmpty || _airdropping) return;
      setState(() => _airdropping = true);
      messenger.showSnackBar(SnackBar(content: Text(l10n.airdropRequesting)));
      final service = AirdropService(client: widget.airdropClient);
      try {
        await service.requestAirdrop(rpcUrl: net.rpcUrl, address: address);
        messenger
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(l10n.airdropOk)));
      } on AirdropException catch (e) {
        final faucetUrl = net.faucetUrl;
        final opened =
            widget.airdropClient == null &&
            faucetUrl != null &&
            await ExternalActions.instance.open(Uri.parse(faucetUrl));
        if (!mounted) return;
        messenger
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(
                opened ? l10n.faucetOpened : l10n.airdropFailed(e.message),
              ),
            ),
          );
      } finally {
        if (widget.airdropClient == null) service.close();
        if (mounted) setState(() => _airdropping = false);
      }
      return;
    }
    final url = net.faucetUrl;
    if (url == null) return;
    final opened = await ExternalActions.instance.open(Uri.parse(url));
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(opened ? l10n.faucetOpened : l10n.externalActionFailed),
      ),
    );
  }

  /// Testnet-only faucet row under the address card: the action label, an
  /// amber dot + the active network's name (honest about where funds land).
  Widget _faucetRow(AppLocalizations l10n, Network net) => GestureDetector(
    key: const ValueKey('faucet-action'),
    behavior: HitTestBehavior.opaque,
    onTap: () => _faucet(net),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: WalletColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.water_drop_outlined,
            size: 18,
            color: WalletColors.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.faucetAction,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: WalletColors.accent,
              ),
            ),
          ),
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: WalletColors.amber,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            net.name,
            style: const TextStyle(fontSize: 12, color: WalletColors.text3),
          ),
        ],
      ),
    ),
  );

  Future<void> _pickChain() async {
    final l10n = AppLocalizations.of(context);
    final chains = _availableChains;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: WalletColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
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
                      l10n.networkRow,
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
              for (var i = 0; i < chains.length; i++)
                ListTile(
                  leading: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: chains[i].dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  title: Text(
                    chains[i].network,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: WalletColors.text,
                    ),
                  ),
                  trailing: i == _selected
                      ? const Icon(
                          Icons.check,
                          size: 20,
                          color: WalletColors.accent,
                        )
                      : null,
                  onTap: () {
                    setState(() => _selected = i);
                    Navigator.of(ctx).pop();
                  },
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  /// Copying the receive address is the single most common action here, and
  /// the address text used to be inert — the only way out was the system
  /// share sheet's own "copy to clipboard".
  Future<void> _copyAddress() async {
    final l10n = AppLocalizations.of(context);
    final address = _address(context);
    if (address.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    await Clipboard.setData(ClipboardData(text: address));
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(l10n.addressCopied)));
  }

  /// Renders the receive card once, for both actions below.
  Future<Uint8List?> _renderCard() async {
    final l10n = AppLocalizations.of(context);
    final chain = _chain;
    final address = _address(context);
    if (address.isEmpty) return null;
    final network = NetworkScope.of(context).activeFor(_familyOf(chain.coin));
    final data = ReceiveCardData(
      address: address,
      assetLabel: chain.pillLabel,
      networkName: network.name,
      generatedAt: widget.clock?.call() ?? DateTime.now(),
      isTestnet: network.isTestnet,
      title: l10n.receiveCardTitle,
      networkLabel: l10n.receiveCardNetwork,
      generatedLabel: l10n.receiveCardGenerated,
      warning: chain.coin == Coin.tron
          ? l10n.receiveWarning
          : l10n.receiveWarningFor(chain.network),
      testnetLabel: l10n.testnetBadge,
    );
    return (widget.cardRenderer ?? renderReceiveCardPng)(data);
  }

  /// Writes the receive card straight into the photo library. Where the
  /// platform cannot do that without a heavyweight permission (Android below
  /// 10), it says so and points at the share action instead of silently
  /// doing something else.
  Future<void> _saveReceiveImage() async {
    final l10n = AppLocalizations.of(context);
    if (_savingImage) return;
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    setState(() => _savingImage = true);
    try {
      final png = await _renderCard();
      if (png == null) return;
      final outcome = await MediaGallery.instance.saveImage(
        png,
        name: 'kt-wallet-receive',
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (outcome) {
            SaveImageOutcome.saved => l10n.receiveImageSaved,
            SaveImageOutcome.denied => l10n.receiveImageDenied,
            SaveImageOutcome.unsupported => l10n.receiveImageUseShare,
            SaveImageOutcome.failed => l10n.receiveImageFailed,
          }),
        ),
      );
    } on Object {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.receiveImageFailed)));
    } finally {
      if (mounted) setState(() => _savingImage = false);
    }
  }

  /// Shares the receive CARD, not just the address string: the recipient gets
  /// a scannable QR that also states the network, which is what stops a
  /// wrong-chain transfer. The address still travels as the text body so it
  /// stays copy-pasteable.
  Future<void> _shareAddress() async {
    final l10n = AppLocalizations.of(context);
    final chain = _chain;
    final address = _address(context);
    if (address.isEmpty || _sharing) return;
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    setState(() => _sharing = true);
    final subject = l10n.shareAddressSubject(chain.network);
    final text = '${chain.network}\n$address';
    try {
      final png = await _renderCard();
      if (png != null) {
        try {
          final dir =
              await (widget.tempDirectory?.call() ?? getTemporaryDirectory());
          final file = File('${dir.path}/kt-wallet-receive.png');
          // Synchronous on purpose: ~150 KB is sub-millisecond, and an async
          // write cannot complete inside a widget test's fake async zone,
          // which would leave this whole path untestable.
          file.writeAsBytesSync(png, flush: true);
          await ExternalActions.instance.shareFile(
            path: file.path,
            mimeType: 'image/png',
            text: text,
            subject: subject,
          );
          return;
        } on Object {
          // Could not stage the image (no temp dir, disk full): the address
          // itself is still worth sharing, so fall through rather than
          // failing the whole action.
        }
      }
      await ExternalActions.instance.share(text: text, subject: subject);
    } on Object {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.externalActionFailed)),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final chain = _chain;
    final address = _address(context);
    // Active network for the selected family. Scope-absent (gallery/goldens)
    // falls back to the shared mainnet controller → active is never a testnet
    // → the faucet row does not render → goldens stay byte-identical.
    final activeNet = NetworkScope.of(context).activeFor(_familyOf(chain.coin));
    return KtScreen(
      navBar: KtNavBar(
        title: l10n.actionReceive,
        onBack: () => Navigator.of(context).maybePop(),
        trailing: Icons.ios_share,
        onTrailing: _shareAddress,
      ),
      children: [
        Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _pickChain,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: WalletColors.surface,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TokenIcon(
                    symbol: chain.pillLabel.split(' ').first,
                    size: 24,
                    fallbackColor: chain.tokenColor,
                    fallbackInitial: chain.glyph,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    chain.pillLabel,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: WalletColors.text,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.keyboard_arrow_down,
                    size: 16,
                    color: WalletColors.text3,
                  ),
                ],
              ),
            ),
          ),
        ),
        KtCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              if (address.isNotEmpty)
                KtQrCode(data: address, size: 220)
              else
                const SizedBox(
                  width: 220,
                  height: 220,
                  child: Center(
                    child: Icon(
                      Icons.qr_code_2,
                      size: 64,
                      color: WalletColors.text3,
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              GestureDetector(
                key: const ValueKey('receive-copy'),
                behavior: HitTestBehavior.opaque,
                onTap: address.isEmpty ? null : _copyAddress,
                child: Column(
                  children: [
                    Text(
                      address,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        fontFamily: KtFonts.mono,
                        height: 1.6,
                        color: WalletColors.text,
                      ),
                    ),
                    if (address.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.copy_rounded,
                            size: 16,
                            color: WalletColors.accent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            l10n.actionCopy,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: WalletColors.accent,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (address.isNotEmpty)
          GestureDetector(
            key: const ValueKey('receive-save-image'),
            behavior: HitTestBehavior.opaque,
            onTap: _savingImage ? null : _saveReceiveImage,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: WalletColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_savingImage)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: WalletColors.accent,
                      ),
                    )
                  else
                    const Icon(
                      Icons.image_outlined,
                      size: 18,
                      color: WalletColors.accent,
                    ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.saveReceiveImage,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: WalletColors.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        // Testnet-only: one-tap Solana airdrop, or copy-faucet-URL where the
        // network declares one. Mainnet (and testnets without either) render
        // nothing here.
        if (activeNet.isTestnet &&
            (activeNet.chain == Chain.solana || activeNet.faucetUrl != null))
          _faucetRow(l10n, activeNet),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: WalletColors.amber.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: WalletColors.amber,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  chain.coin == Coin.tron
                      ? l10n.receiveWarning
                      : l10n.receiveWarningFor(chain.network),
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: Color(0xFF9A6503),
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
