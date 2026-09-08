import 'package:chains/chains.dart';

/// Build-time display metadata, never a signing whitelist or a price feed.
/// Only the parsed transaction identity is accepted; QR summaries cannot add
/// entries or override scales. Update this file only after reviewing sources.
class OfflineToken {
  const OfflineToken(
    this.chain,
    this.chainId,
    this.contract,
    this.symbol,
    this.decimals,
  );

  final Chain chain;
  final int? chainId;
  final String contract;
  final String symbol;
  final int decimals;
}

/// Reviewed mainnet deployments, 2026-09-07. Sources and limitations:
/// docs/OFFLINE_TOKEN_CATALOG.md. No network or mutable registry dependency.
const offlineTokens = <OfflineToken>[
  OfflineToken(
    Chain.ethereum,
    1,
    '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48',
    'USDC',
    6,
  ),
  OfflineToken(
    Chain.polygon,
    137,
    '0x3c499c542cef5e3811e1192ce70d8cc03d5c3359',
    'USDC',
    6,
  ),
  OfflineToken(
    Chain.base,
    8453,
    '0x833589fcd6edb6e08f4c7c32d4f71b54bda02913',
    'USDC',
    6,
  ),
  OfflineToken(
    Chain.arbitrum,
    42161,
    '0xaf88d065e77c8cc2239327c5edb3a432268e5831',
    'USDC',
    6,
  ),
  OfflineToken(
    Chain.avalanche,
    43114,
    '0xb97ef9ef8734c71904d8002f8b6bc66dd9c48a6e',
    'USDC',
    6,
  ),
  OfflineToken(
    Chain.solana,
    null,
    'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v',
    'USDC',
    6,
  ),
  OfflineToken(
    Chain.ethereum,
    1,
    '0xdac17f958d2ee523a2206206994597c13d831ec7',
    'USDT',
    6,
  ),
  OfflineToken(
    Chain.arbitrum,
    42161,
    '0xfd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb9',
    'USDT0',
    6,
  ),
  OfflineToken(
    Chain.avalanche,
    43114,
    '0x9702230a8ea53601f5cd2dc00fdbc13d4df4a8c7',
    'USDT',
    6,
  ),
  OfflineToken(
    Chain.tron,
    null,
    'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
    'USDT',
    6,
  ),
  OfflineToken(
    Chain.solana,
    null,
    'Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB',
    'USDT',
    6,
  ),
  OfflineToken(
    Chain.ethereum,
    1,
    '0x6b175474e89094c44da98b954eedeac495271d0f',
    'DAI',
    18,
  ),
  OfflineToken(
    Chain.ethereum,
    1,
    '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2',
    'WETH',
    18,
  ),
  OfflineToken(
    Chain.ethereum,
    1,
    '0x2260fac5e5542a773aa44fbcfedf7c193bc2c599',
    'WBTC',
    8,
  ),
];

OfflineToken? offlineTokenFor(ParsedUnsignedTransfer parsed) {
  final contract = parsed.tokenContract;
  if (contract == null || parsed.operation == TxOperation.nativeTransfer) {
    return null;
  }
  for (final token in offlineTokens) {
    if (token.chain != parsed.chain) continue;
    // An EVM contract address alone cannot identify its chain or testnet.
    if (token.chainId != null &&
        parsed.networkId != BigInt.from(token.chainId!)) {
      continue;
    }
    if (token.chainId == null && parsed.networkId != null) continue;
    // Base58 is case-sensitive; only hex EVM identities may ignore case.
    final matches = token.chainId == null
        ? contract == token.contract
        : contract.toLowerCase() == token.contract;
    if (matches) return token;
  }
  return null;
}

/// One local scale for both transaction review and authentication screens.
(int, String)? offlineAssetFor(ParsedUnsignedTransfer parsed) {
  if (parsed.operation == TxOperation.nativeTransfer) {
    return switch (parsed.chain) {
      Chain.ethereum || Chain.base || Chain.arbitrum => (18, 'ETH'),
      Chain.polygon => (18, 'POL'),
      Chain.avalanche => (18, 'AVAX'),
      Chain.bnb => (18, 'BNB'),
      Chain.tron => (6, 'TRX'),
      Chain.solana => (9, 'SOL'),
    };
  }
  final token = offlineTokenFor(parsed);
  return token == null ? null : (token.decimals, token.symbol);
}
