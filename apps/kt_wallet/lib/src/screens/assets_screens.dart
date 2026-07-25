import 'package:chains/chains.dart' show Chain;
import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:ui_kit/ui_kit.dart';

import '../../l10n/app_localizations.dart';
import '../market/airdrop_service.dart';
import '../market/balance_service.dart';
import '../market/market_controller.dart';
import '../market/market_scope.dart';
import '../platform/external_actions.dart';
import 'home_screen.dart' show tokenRowMeta;
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
  // (color, symbol glyph, name, holdings, value, change, change color, network)
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
    ),
  ];
  static const _networks = ['Ethereum', 'Polygon', 'TRON', 'Solana'];

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
  List<(Color, String, String, String, String, String, Color, String)>
  _liveRows(MarketController market) {
    return [
      for (final (coin, name, symbol, color, glyph, network) in const [
        (Coin.eth, 'Ethereum', 'ETH', Color(0xFF627EEA), 'Ξ', 'Ethereum'),
        (Coin.polygon, 'POL', 'POL', Color(0xFF8247E5), '⬡', 'Polygon'),
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
          );
        }(),
      for (final token in market.tokens)
        () {
          final result = market.tokenBalanceFor(token.id);
          final amount = result.amount;
          final ok = result.status == BalanceStatus.ok && amount != null;
          final fiat = market.tokenFiatValueUsd(token);
          final (color, glyph) =
              tokenRowMeta[token.symbol] ??
              (WalletColors.accent, token.symbol.substring(0, 1));
          return (
            color,
            glyph,
            token.symbol,
            '${ok ? amount.format(maxFraction: 6) : '--'} ${token.symbol} · ${token.network}',
            fiat == null ? '--' : formatUsd(fiat),
            '',
            WalletColors.text3,
            token.network,
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
    final rows = live ? _liveRows(market) : _assets;
    final q = _query.trim().toLowerCase();
    final results = [
      for (final a in rows)
        if ((_net == 0 || a.$8 == _networks[_net - 1]) &&
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
          options: [l10n.viewAll, ..._networks],
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
                    onTap: () => context.push('/token'),
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
  final (Color, String, String, String, String, String, Color, String) a;
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

/// W3 Token 详情 — hero balance + info card + recent tx.
class TokenDetailScreen extends StatelessWidget {
  const TokenDetailScreen({super.key});

  /// Demo USDT TRC-20 contract address shown on the info card.
  static const _contract = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KtScreen(
      navBar: KtNavBar(
        title: 'USDT',
        onBack: () => Navigator.of(context).maybePop(),
        trailing: Icons.open_in_new,
        onTrailing: () async {
          final opened = await ExternalActions.instance.open(
            Uri.parse('https://tronscan.org/#/token20/$_contract'),
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
  const ReceiveScreen({super.key, this.airdropClient});

  /// Injectable http client for the devnet airdrop faucet (tests); null in
  /// production (the [AirdropService] creates and closes its own).
  final http.Client? airdropClient;

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

  // Default TRON, matching the design.
  int _selected = 2;

  /// True while a devnet airdrop request is in flight (guards double-taps).
  bool _airdropping = false;

  _ReceiveChain get _chain => _chains[_selected];

  /// Protocol family of the selected coin (Coin is the derivation-level enum,
  /// Chain the network-level one; they map 1:1).
  static Chain _familyOf(Coin coin) => switch (coin) {
    Coin.eth => Chain.ethereum,
    Coin.polygon => Chain.polygon,
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
        messenger
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(content: Text(l10n.airdropFailed(e.message))),
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
            for (var i = 0; i < _chains.length; i++)
              ListTile(
                leading: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _chains[i].dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(
                  _chains[i].network,
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
    );
  }

  Future<void> _shareAddress() async {
    final l10n = AppLocalizations.of(context);
    final address = _address(context);
    if (address.isEmpty) return;
    try {
      await ExternalActions.instance.share(
        text: '${_chain.network}\n$address',
        subject: l10n.shareAddressSubject(_chain.network),
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l10n.externalActionFailed)));
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
            ],
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
