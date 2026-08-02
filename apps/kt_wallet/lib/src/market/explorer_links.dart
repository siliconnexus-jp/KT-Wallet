import 'package:chains/chains.dart' show Chain;

import '../state/networks.dart';

/// Builds the transaction URL on [network]'s block explorer, per family URL
/// scheme:
///
/// * EVM (Etherscan-family): `{base}/tx/{hash}`
/// * TRON (Tronscan): `{base}/#/transaction/{hash}`
/// * Solana (explorer.solana.com): `{base}/tx/{hash}` — devnet's base carries
///   a `?cluster=devnet` query which must stay AFTER the path.
String? explorerTxUrl(Network network, String txHash) => _explorerUrl(network, {
  Chain.tron: '#/transaction',
  _anyOtherChain: 'tx',
}, txHash);

/// Builds the account URL on [network]'s block explorer.
///
/// * EVM: `{base}/address/{address}`
/// * TRON: `{base}/#/address/{address}`
/// * Solana: `{base}/address/{address}`
String? explorerAddressUrl(Network network, String address) => _explorerUrl(
  network,
  {Chain.tron: '#/address', _anyOtherChain: 'address'},
  address,
);

/// Builds the token/contract URL on [network]'s block explorer.
///
/// * EVM: `{base}/token/{contract}`
/// * TRON: `{base}/#/token20/{contract}`
/// * Solana: `{base}/address/{mint}` — SPL mints are plain accounts there.
String? explorerTokenUrl(Network network, String contract) => _explorerUrl(
  network,
  {Chain.tron: '#/token20', Chain.solana: 'address', _anyOtherChain: 'token'},
  contract,
);

/// Sentinel key for "every family not named explicitly" in the path maps.
const _anyOtherChain = Chain.ethereum;

String? _explorerUrl(Network network, Map<Chain, String> paths, String id) {
  // A custom testnet/private chain without a configured explorer has no
  // truthful explorer link. Falling back to the protocol family's mainnet
  // would present a valid-looking URL for the wrong chain.
  final base = network.explorerUrl;
  if (base == null || base.trim().isEmpty) return null;
  // Split a query suffix off the base (Solana devnet: '...com?cluster=devnet')
  // so the path is inserted before it.
  final q = base.indexOf('?');
  final root = q < 0 ? base : base.substring(0, q);
  final query = q < 0 ? '' : base.substring(q);
  final path = paths[network.chain] ?? paths[_anyOtherChain]!;
  // Hashes and addresses are untrusted indexer/RPC data. Keep them inside one
  // path segment so `?`, `#` or `/` cannot rewrite the explorer destination.
  return '$root/$path/${Uri.encodeComponent(id)}$query';
}
