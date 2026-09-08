import 'address.dart';

/// Reviewed mainnet/testnet signing domains. Custom networks are never trusted
/// merely because an online QR labels them as a known network.
const evmSigningNetworks = <int, Chain>{
  1: Chain.ethereum,
  11155111: Chain.ethereum,
  137: Chain.polygon,
  80002: Chain.polygon,
  8453: Chain.base,
  84532: Chain.base,
  42161: Chain.arbitrum,
  421614: Chain.arbitrum,
  43114: Chain.avalanche,
  43113: Chain.avalanche,
  56: Chain.bnb,
  97: Chain.bnb,
};

void validateEvmNetworkIdentity(
  Chain chain,
  BigInt chainId, {
  bool allowUnknown = false,
}) {
  Chain? expected;
  for (final entry in evmSigningNetworks.entries) {
    if (chainId == BigInt.from(entry.key)) expected = entry.value;
  }
  if (chainId <= BigInt.zero ||
      (expected == null ? !allowUnknown : expected != chain)) {
    throw const FormatException('untrusted or mismatched EVM signing network');
  }
}
