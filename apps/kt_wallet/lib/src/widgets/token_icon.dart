import 'package:chains/chains.dart' show Chain;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

/// Circular token/brand icon. Renders the bundled logo PNG for known
/// symbols/networks (assets/tokens/, MIT-licensed cryptocurrency-icons set)
/// and falls back to the classic letter [KtAvatar] for anything unknown
/// (e.g. user-added custom tokens).
class TokenIcon extends StatelessWidget {
  const TokenIcon({
    super.key,
    required this.symbol,
    this.size = 40,
    this.fallbackColor,
    this.fallbackInitial,
  });

  /// Token symbol or network name; matching is case-insensitive and accepts
  /// common aliases ('Ethereum' → eth, 'Polygon'/'POL' → matic, 'TRON' → trx).
  final String symbol;
  final double size;
  final Color? fallbackColor;
  final String? fallbackInitial;

  static const _assetBySymbol = {
    'usdt': 'usdt',
    'usdc': 'usdc',
    'busd': 'busd',
    'uni': 'uni',
    'eth': 'eth',
    'ethereum': 'eth',
    'sol': 'sol',
    'solana': 'sol',
    'trx': 'trx',
    'tron': 'trx',
    'pol': 'matic',
    'matic': 'matic',
    'polygon': 'matic',
  };

  @override
  Widget build(BuildContext context) {
    final asset = _assetBySymbol[symbol.toLowerCase()];
    if (asset == null) {
      return KtAvatar(
        color: fallbackColor ?? WalletColors.accent,
        initial: fallbackInitial ?? (symbol.isEmpty ? '?' : symbol[0]),
        size: size,
      );
    }
    return ClipOval(
      child: Image.asset(
        'assets/tokens/$asset.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

/// Circular network logo, for anywhere the user picks a chain.
///
/// Chains the bundled icon set covers (Ethereum, Polygon, TRON, Solana) get
/// their real logo; the L2s it does not (Base, Arbitrum, Avalanche) fall back
/// to a brand-coloured initial — the same treatment the home asset rows
/// already give them, so a chain looks identical everywhere it appears.
class ChainIcon extends StatelessWidget {
  const ChainIcon({super.key, required this.chain, this.size = 28});

  final Chain chain;
  final double size;

  static const _name = {
    Chain.ethereum: 'Ethereum',
    Chain.polygon: 'Polygon',
    Chain.base: 'Base',
    Chain.arbitrum: 'Arbitrum',
    Chain.avalanche: 'Avalanche',
    Chain.tron: 'TRON',
    Chain.solana: 'Solana',
  };

  static const _color = {
    Chain.ethereum: ChainColors.ethereum,
    Chain.polygon: ChainColors.polygon,
    Chain.base: ChainColors.base,
    Chain.arbitrum: ChainColors.arbitrum,
    Chain.avalanche: ChainColors.avalanche,
    Chain.tron: ChainColors.tron,
    Chain.solana: ChainColors.solana,
  };

  @override
  Widget build(BuildContext context) {
    final name = _name[chain]!;
    return TokenIcon(
      symbol: name,
      size: size,
      fallbackColor: _color[chain]!,
      fallbackInitial: name[0],
    );
  }
}
