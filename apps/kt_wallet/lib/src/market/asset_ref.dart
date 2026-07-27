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
       network = null;

  /// A registry token (USDT on TRON, USDC on Solana …).
  AssetRef.token(TokenInfo token)
    : coin = token.chain,
      name = token.symbol,
      symbol = token.symbol,
      tokenId = token.id,
      contract = token.contract,
      network = token.network;

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

  bool get isToken => tokenId != null;
}
