import 'package:chains/chains.dart' show Chain;
import 'package:core_crypto/core_crypto.dart' show Coin;

import 'token_balance_service.dart' show TokenInfo;

/// Protocol family of a derivation-level [Coin]. The two enums map 1:1;
/// [Chain] is what [Network] and the explorer helpers are keyed by.
Chain chainOf(Coin coin) => switch (coin) {
  Coin.eth => Chain.ethereum,
  Coin.polygon => Chain.polygon,
  Coin.base => Chain.base,
  Coin.arbitrum => Chain.arbitrum,
  Coin.avalanche => Chain.avalanche,
  Coin.tron => Chain.tron,
  Coin.solana => Chain.solana,
};

/// Identifies the asset an asset row stands for, so the detail screen can
/// render THAT asset instead of a fixed snapshot.
///
/// Without this the detail route took no arguments at all: every row on the
/// home list and the assets tab opened the same hardcoded "3,120.00 USDT"
/// page, showing the user a balance they do not hold.
class AssetRef {
  /// A chain's native coin (ETH, POL, TRX, SOL …).
  const AssetRef.native({
    required this.coin,
    required this.name,
    required this.symbol,
  }) : tokenId = null,
       contract = null,
       network = null,
       group = const [];

  /// A registry token (USDT on TRON, USDC on Solana …).
  AssetRef.token(TokenInfo token)
    : coin = token.chain,
      name = token.symbol,
      symbol = token.symbol,
      tokenId = token.id,
      contract = token.contract,
      network = token.network,
      group = const [];

  /// One symbol deployed on several chains (USDC on Polygon, Base, Arbitrum,
  /// Avalanche, Solana …). The list used to be flattened into one row per
  /// chain, so the same coin appeared five times in a row; it is one row now,
  /// and the detail screen breaks it down per chain.
  AssetRef.tokenGroup(List<TokenInfo> tokens)
    : assert(tokens.isNotEmpty, 'a group needs at least one deployment'),
      coin = tokens.first.chain,
      name = tokens.first.symbol,
      symbol = tokens.first.symbol,
      tokenId = tokens.length == 1 ? tokens.first.id : null,
      contract = tokens.length == 1 ? tokens.first.contract : null,
      network = tokens.length == 1 ? tokens.first.network : null,
      group = tokens;

  /// The chain the asset lives on — also picks the active [Network], and with
  /// it the RPC and explorer the detail screen links to.
  final Coin coin;

  /// Display title (the chain name for native coins, the symbol for tokens).
  final String name;

  final String symbol;

  /// Registry id for a token balance lookup; null for a native coin.
  final String? tokenId;

  /// Token contract address; null for a native coin.
  final String? contract;

  /// Human network label carried by the token registry ('TRON · TRC-20').
  final String? network;

  /// Every deployment behind this row. Empty for a native coin and for a
  /// single-chain token; two or more entries mean the detail screen shows a
  /// chain picker.
  final List<TokenInfo> group;

  /// Narrows a group to the deployment at [index], keeping [group] intact.
  ///
  /// This is what Send and Receive are handed. They need to know the exact
  /// deployment — which chain, which contract, which decimals — while still
  /// being able to offer the network picker, and they must NOT be able to
  /// change the symbol: arriving from the USDT page and finding a dropdown
  /// full of other coins is how the user ended up sending the wrong asset.
  AssetRef selecting(int index) {
    if (group.isEmpty) return this;
    final token = group[index.clamp(0, group.length - 1)];
    return AssetRef._(
      coin: token.chain,
      name: name,
      symbol: symbol,
      tokenId: token.id,
      contract: token.contract,
      network: token.network,
      group: group,
    );
  }

  const AssetRef._({
    required this.coin,
    required this.name,
    required this.symbol,
    required this.tokenId,
    required this.contract,
    required this.network,
    required this.group,
  });

  /// Index of the current deployment within [group]; 0 when there is no group.
  int get chainIndex {
    if (group.isEmpty) return 0;
    final at = group.indexWhere((t) => t.id == tokenId);
    return at < 0 ? 0 : at;
  }

  bool get isToken => tokenId != null || group.isNotEmpty;

  /// True when the same symbol lives on more than one chain.
  bool get isMultiChain => group.length > 1;
}
