# Offline signing display catalog

The cold signer bundles 14 common mainnet token deployments in
`apps/cold_signer/lib/src/signing/offline_token_catalog.dart`. Native assets
already use local protocol scales. This catalog is display metadata, not an
asset-risk endorsement, price feed, network attestation or signing whitelist.

Reviewed 2026-09-07 against the existing online catalog and these primary sources:

- USDC (Ethereum, Polygon, Base, Arbitrum, Avalanche, Solana):
  https://developers.circle.com/stablecoins/usdc-contract-addresses
- USDT (Ethereum, Avalanche, TRON, Solana):
  https://tether.to/en/supported-protocols/
- Arbitrum USDT0 (same contract historically displayed as USDT):
  https://usdt0.to/ecosystem/arbitrum
- Ethereum DAI and WETH:
  https://developers.uniswap.org/docs/protocols/v3/guides/swapping/multi-hop-swapping
- Ethereum WBTC:
  https://wbtc.network/transparency

Matching uses parsed transaction chain and contract/mint; EVM additionally
requires the raw transaction's exact chain ID. EVM hex is case-insensitive;
TRON/Solana Base58 is case-sensitive. QR summary symbols/decimals are never read
for a successfully parsed transaction. All amounts retain exact integer math,
with the raw amount and full contract still visible for review.

Unknown contracts and EVM testnets keep the raw-unit warning. Catalog updates
require an app release; cold devices never download token metadata. Adding an
entry does not permit new transaction types, nonzero approvals or blind signing.

AIRGAP-V1 TRON/Solana messages do not carry an independently verified cluster
identity in the parsed transaction. Their catalog match identifies a known
mainnet contract/mint only; it must not be presented as proof of network or
current contract state. Matching decimals is not a guarantee of asset safety.

Regression tests cover every entry, wrong chains and network IDs, Base58 case,
unknown contracts, malicious QR hints, exact Arbitrum USDC formatting, and
live-review layout in Chinese, English and Japanese at 320/390/430 pixels and
100%/200% text scale.
