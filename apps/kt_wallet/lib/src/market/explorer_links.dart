import 'package:chains/chains.dart' show Chain;

import '../state/networks.dart';

/// Fallback explorer base per protocol family, used when a (custom) network
/// carries no explorerUrl — the mainnet explorer is a sane default because it
/// at least resolves, and the copied link is visibly wrong rather than dead.
const _fallbackExplorerByChain = {
  Chain.ethereum: 'https://etherscan.io',
  Chain.polygon: 'https://polygonscan.com',
  Chain.base: 'https://basescan.org',
  Chain.arbitrum: 'https://arbiscan.io',
  Chain.avalanche: 'https://snowtrace.io',
  Chain.tron: 'https://tronscan.org',
  Chain.solana: 'https://explorer.solana.com',
};

/// Builds the transaction URL on [network]'s block explorer, per family URL
/// scheme:
///
/// * EVM (Etherscan-family): `{base}/tx/{hash}`
/// * TRON (Tronscan): `{base}/#/transaction/{hash}`
/// * Solana (explorer.solana.com): `{base}/tx/{hash}` — devnet's base carries
///   a `?cluster=devnet` query which must stay AFTER the path.
String explorerTxUrl(Network network, String txHash) {
  final base = network.explorerUrl ?? _fallbackExplorerByChain[network.chain]!;
  // Split a query suffix off the base (Solana devnet: '...com?cluster=devnet')
  // so the tx path is inserted before it.
  final q = base.indexOf('?');
  final root = q < 0 ? base : base.substring(0, q);
  final query = q < 0 ? '' : base.substring(q);
  return switch (network.chain) {
    Chain.tron => '$root/#/transaction/$txHash$query',
    _ => '$root/tx/$txHash$query',
  };
}
