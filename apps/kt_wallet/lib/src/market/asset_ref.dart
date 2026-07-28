import 'package:chains/chains.dart' show Chain;
import 'package:core_crypto/core_crypto.dart' show Coin;

import 'balance_service.dart' show BalanceService;
import 'token_balance_service.dart' show TokenInfo;

/// Protocol family of a derivation-level [Coin]. The two enums map 1:1;
/// [Chain] is what [Network] and the explorer helpers are keyed by.
Chain chainOf(Coin coin) => switch (coin) {
  Coin.eth => Chain.ethereum,
  Coin.polygon => Chain.polygon,
  Coin.base => Chain.base,
  Coin.arbitrum => Chain.arbitrum,
  Coin.avalanche => Chain.avalanche,
  Coin.bnb => Chain.bnb,
  Coin.tron => Chain.tron,
  Coin.solana => Chain.solana,
};

/// One place a symbol exists: a chain, plus what it takes to read a balance
/// and build a transfer there.
///
/// Native coins and registry tokens are the same shape deliberately. ETH is a
/// native coin on Ethereum, Base and Arbitrum — three deployments of one
/// asset, exactly as USDT is on seven — and modelling only tokens as
/// multi-chain is what put "Ethereum 0 ETH", "Base 0 ETH" and "Arbitrum
/// 0 ETH" on the home list as three separate assets.
class AssetDeployment {
  const AssetDeployment({
    required this.coin,
    required this.network,
    required this.decimals,
    this.tokenId,
    this.contract,
    this.tokenProgram,
  });

  /// A chain's own coin: no contract, decimals fixed by the chain.
  AssetDeployment.native(this.coin, this.network)
    : decimals = BalanceService.decimalsFor[coin]!,
      tokenId = null,
      contract = null,
      tokenProgram = null;

  AssetDeployment.token(TokenInfo token)
    : coin = token.chain,
      network = token.network,
      decimals = token.decimals,
      tokenId = token.id,
      contract = token.contract,
      tokenProgram = token.tokenProgram;

  final Coin coin;

  /// Display label matching the network chips ('Ethereum', 'Arbitrum One').
  final String network;

  final int decimals;

  /// Registry id for a token balance lookup; null for a native coin.
  final String? tokenId;

  /// Token contract address; null for a native coin.
  final String? contract;
  final String? tokenProgram;

  bool get isToken => tokenId != null;
}

/// Identifies the asset an asset row stands for, so the detail screen can
/// render THAT asset instead of a fixed snapshot.
///
/// Without this the detail route took no arguments at all: every row on the
/// home list and the assets tab opened the same hardcoded "3,120.00 USDT"
/// page, showing the user a balance they do not hold.
class AssetRef {
  /// A chain's native coin on exactly one chain (POL, TRX, SOL, AVAX).
  AssetRef.native({
    required this.coin,
    required this.name,
    required this.symbol,
    String? network,
  }) : tokenId = null,
       contract = null,
       tokenProgram = null,
       network = network,
       group = [AssetDeployment.native(coin, network ?? name)];

  /// A registry token on one chain (USDT on TRON …).
  AssetRef.token(TokenInfo token)
    : coin = token.chain,
      name = token.symbol,
      symbol = token.symbol,
      tokenId = token.id,
      contract = token.contract,
      tokenProgram = token.tokenProgram,
      network = token.network,
      group = [AssetDeployment.token(token)];

  /// One symbol deployed on several chains (USDC on six, USDT on seven, and
  /// ETH on Ethereum plus its L2s). The list used to be flattened into one row
  /// per chain, so the same asset appeared several times in a row; it is one
  /// row now, and the detail screen breaks it down per chain.
  AssetRef.group({
    required this.name,
    required this.symbol,
    required this.group,
  }) : assert(group.isNotEmpty, 'a group needs at least one deployment'),
       coin = group.first.coin,
       tokenId = group.length == 1 ? group.first.tokenId : null,
       contract = group.length == 1 ? group.first.contract : null,
       tokenProgram = group.length == 1 ? group.first.tokenProgram : null,
       network = group.length == 1 ? group.first.network : null;

  /// Convenience for the common token case.
  AssetRef.tokenGroup(List<TokenInfo> tokens)
    : assert(tokens.isNotEmpty, 'a group needs at least one deployment'),
      coin = tokens.first.chain,
      name = tokens.first.symbol,
      symbol = tokens.first.symbol,
      tokenId = tokens.length == 1 ? tokens.first.id : null,
      contract = tokens.length == 1 ? tokens.first.contract : null,
      tokenProgram = tokens.length == 1 ? tokens.first.tokenProgram : null,
      network = tokens.length == 1 ? tokens.first.network : null,
      group = tokens.map(AssetDeployment.token).toList();

  /// The chain the asset is currently pointed at — also picks the active
  /// [Network], and with it the RPC and explorer the detail screen links to.
  final Coin coin;

  /// Display title. The SYMBOL, for natives too: a row spanning Ethereum,
  /// Base and Arbitrum cannot be titled after any one of them.
  final String name;

  final String symbol;

  /// Registry id for a token balance lookup; null for a native coin.
  final String? tokenId;

  /// Token contract address; null for a native coin.
  final String? contract;
  final String? tokenProgram;

  /// Human network label ('Arbitrum One'); null while a group is unnarrowed.
  final String? network;

  /// Every deployment behind this row. Two or more mean a chain picker.
  final List<AssetDeployment> group;

  /// Narrows a group to the deployment at [index], keeping [group] intact.
  ///
  /// This is what Send and Receive are handed. They need to know the exact
  /// deployment — which chain, which contract, which decimals — while still
  /// being able to offer the network picker, and they must NOT be able to
  /// change the symbol: arriving from the USDT page and finding a dropdown
  /// full of other coins is how the user ended up sending the wrong asset.
  AssetRef selecting(int index) {
    if (group.isEmpty) return this;
    final at = group[index.clamp(0, group.length - 1)];
    return AssetRef._(
      coin: at.coin,
      name: name,
      symbol: symbol,
      tokenId: at.tokenId,
      contract: at.contract,
      tokenProgram: at.tokenProgram,
      network: at.network,
      group: group,
    );
  }

  const AssetRef._({
    required this.coin,
    required this.name,
    required this.symbol,
    required this.tokenId,
    required this.contract,
    required this.tokenProgram,
    required this.network,
    required this.group,
  });

  /// Index of the current deployment within [group].
  int get chainIndex {
    final at = group.indexWhere((d) => d.coin == coin && d.tokenId == tokenId);
    return at < 0 ? 0 : at;
  }

  bool get isToken => tokenId != null || group.any((d) => d.isToken);

  /// True when the same symbol lives on more than one chain.
  bool get isMultiChain => group.length > 1;
}
