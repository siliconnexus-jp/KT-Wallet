/// The native denomination of each supported chain.
///
/// This is a protocol constant, not display metadata: how many base units make
/// one coin is fixed by the chain itself, and no remote source is allowed to
/// redefine it. Two layers need it and neither may own it — [GatewayClient]
/// checks an incoming balance against it at the transport boundary, while
/// `BalanceService` interprets raw amounts with it one layer up. Keeping a
/// second copy in either place is what lets them drift: the checker would then
/// reject a correct gateway response for a chain the consumer reads correctly,
/// silently disabling gateway mode for that chain.
///
/// `gateway_client.dart` sits BELOW `balance_service.dart` in the import graph,
/// so the table cannot live in the service. It lives here, imported by both.
library;

import 'package:core_crypto/core_crypto.dart' show Coin;

/// Base units per whole coin, as a decimal exponent (wei / SUN / lamports).
const nativeDecimalsFor = <Coin, int>{
  Coin.eth: 18,
  Coin.polygon: 18,
  Coin.base: 18,
  Coin.arbitrum: 18,
  Coin.avalanche: 18,
  Coin.bnb: 18,
  Coin.tron: 6,
  Coin.solana: 9,
};

/// Native-coin display symbol per chain. Base and Arbitrum settle in ETH.
const nativeSymbolFor = <Coin, String>{
  Coin.eth: 'ETH',
  Coin.polygon: 'POL',
  Coin.base: 'ETH',
  Coin.arbitrum: 'ETH',
  Coin.avalanche: 'AVAX',
  Coin.bnb: 'BNB',
  Coin.tron: 'TRX',
  Coin.solana: 'SOL',
};
