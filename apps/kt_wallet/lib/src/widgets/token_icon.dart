import 'package:chains/chains.dart' show Chain;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

/// Circular token/brand icon. Renders the bundled logo PNG for known
/// symbols/networks (assets/tokens/ — the MIT cryptocurrency-icons set, plus
/// current chain/token artwork from the MIT trustwallet/assets set) and falls
/// back to the classic letter [KtAvatar] for anything unknown.
///
/// [official] is a security boundary, not decoration. A custom contract may
/// call itself USDT (or any other protected symbol), so callers that have not
/// verified its network + contract identity must set [official] to false. In
/// that case the official brand artwork is never rendered.
class TokenIcon extends StatelessWidget {
  const TokenIcon({
    super.key,
    required this.symbol,
    this.size = 40,
    this.fallbackColor,
    this.fallbackInitial,
    this.official = true,
  });

  /// Token symbol or network name; matching is case-insensitive and accepts
  /// common aliases ('Ethereum' → eth, 'Polygon'/'POL' → matic, 'TRON' → trx).
  final String symbol;
  final double size;
  final Color? fallbackColor;
  final String? fallbackInitial;
  final bool official;

  static const _assetBySymbol = {
    'usdt': 'usdt',
    'usdc': 'usdc',
    'busd': 'busd',
    'dai': 'dai',
    'weth': 'weth',
    'wbtc': 'wbtc',
    'link': 'link',
    'uni': 'uni',
    'shib': 'shib',
    'pepe': 'pepe',
    'pyusd': 'pyusd',
    'jup': 'jup',
    'bonk': 'bonk',
    'eth': 'eth',
    'ethereum': 'eth',
    'bnb': 'bnb',
    'bnb smart chain': 'bnb',
    'binance smart chain': 'bnb',
    'sol': 'sol',
    'solana': 'sol',
    'trx': 'trx',
    'tron': 'trx',
    'pol': 'matic',
    'matic': 'matic',
    'polygon': 'matic',
    'base': 'base',
    'arb': 'arb',
    'arbitrum': 'arb',
    'arbitrum one': 'arb',
    'avax': 'avax',
    'avalanche': 'avax',
    'avalanche c-chain': 'avax',
  };

  /// Bundled artwork file for [symbol], or null when only the letter fallback
  /// applies. Public so surfaces that draw outside the widget tree — the
  /// shared receive card, rendered straight onto a canvas — pick exactly the
  /// same image the on-screen icon shows.
  static String? assetFor(String symbol, {bool official = true}) =>
      official ? _assetBySymbol[symbol.toLowerCase()] : null;

  @override
  Widget build(BuildContext context) {
    final asset = assetFor(symbol, official: official);
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
    Chain.bnb: 'BNB Smart Chain',
    Chain.tron: 'TRON',
    Chain.solana: 'Solana',
  };

  static const _color = {
    Chain.ethereum: ChainColors.ethereum,
    Chain.polygon: ChainColors.polygon,
    Chain.base: ChainColors.base,
    Chain.arbitrum: ChainColors.arbitrum,
    Chain.avalanche: ChainColors.avalanche,
    Chain.bnb: Color(0xFFF3BA2F),
    Chain.tron: ChainColors.tron,
    Chain.solana: ChainColors.solana,
  };

  /// Bundled artwork for [chain]; see [TokenIcon.assetFor].
  static String? assetFor(Chain chain) => TokenIcon.assetFor(_name[chain]!);

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
