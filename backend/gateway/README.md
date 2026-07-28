# KT-Wallet Chain-Query Gateway

A single-binary JSON-RPC 2.0 facade the KT-Wallet app can point at instead of
talking to chains directly. It shields clients from upstream dialects (EVM
JSON-RPC, TronGrid REST, Solana JSON-RPC, CoinGecko), from upstream rate
limits, and from API keys (Etherscan / Helius keys live here, never in the
app). The app keeps its direct mode — this gateway is a faithful superset of
it, not a new source of truth: payloads are forwarded verbatim, balances and
fees are the chain's own numbers.

Standard library only. Go 1.26.

## Running

```sh
make build && ./bin/gateway              # listens on :8080
make test                                # unit + integration tests (no network)
make race                                # tests with -race
make cover                               # coverage across internal/
make docker && make docker-run           # multi-stage distroless image
```

Smoke test:

```sh
curl -s localhost:8080/rpc -d '{"jsonrpc":"2.0","id":1,"method":"kt_health"}'
# {"jsonrpc":"2.0","id":1,"result":{"networks":["eth-mainnet","eth-sepolia",...],"ok":true,"version":"1.0.0"}}
```

## Environment

| Variable | Default | Purpose |
|---|---|---|
| `GATEWAY_ADDR` | `:8080` | Listen address |
| `ETH_RPC_URLS` | `https://eth.llamarpc.com,https://cloudflare-eth.com` | `eth-mainnet` RPC endpoints, comma-separated, tried in order |
| `POLYGON_RPC_URLS` | `https://polygon-rpc.com,https://polygon-bor-rpc.publicnode.com` | `polygon-mainnet` RPC endpoints |
| `BASE_RPC_URLS` | `https://mainnet.base.org` | `base-mainnet` RPC endpoints |
| `ARBITRUM_RPC_URLS` | `https://arb1.arbitrum.io/rpc` | `arbitrum-mainnet` RPC endpoints |
| `AVALANCHE_RPC_URLS` | `https://api.avax.network/ext/bc/C/rpc` | `avalanche-mainnet` (C-Chain) RPC endpoints |
| `BNB_RPC_URLS` | `https://bsc-dataseed.bnbchain.org` | `bnb-mainnet` RPC endpoints |
| `SOLANA_RPC_URLS` | `https://api.mainnet-beta.solana.com` | `sol-mainnet` RPC endpoints |
| `TRON_API_URL` | `https://api.trongrid.io` | `tron-mainnet` TronGrid base URL |
| `ETH_SEPOLIA_RPC_URLS` | `https://ethereum-sepolia-rpc.publicnode.com` | `eth-sepolia` RPC endpoints, comma-separated, tried in order |
| `POLYGON_AMOY_RPC_URLS` | `https://rpc-amoy.polygon.technology` | `polygon-amoy` RPC endpoints |
| `BASE_SEPOLIA_RPC_URLS` | `https://sepolia.base.org` | `base-sepolia` RPC endpoints |
| `ARBITRUM_SEPOLIA_RPC_URLS` | `https://sepolia-rollup.arbitrum.io/rpc` | `arbitrum-sepolia` RPC endpoints |
| `AVALANCHE_FUJI_RPC_URLS` | `https://api.avax-test.network/ext/bc/C/rpc` | `avalanche-fuji` RPC endpoints |
| `BNB_TESTNET_RPC_URLS` | `https://bsc-testnet-dataseed.bnbchain.org` | `bnb-testnet` RPC endpoints |
| `SOLANA_DEVNET_RPC_URLS` | `https://api.devnet.solana.com` | `sol-devnet` RPC endpoints |
| `TRON_NILE_API_URL` | `https://nile.trongrid.io` | `tron-nile` TronGrid base URL |
| `COINGECKO_API_URL` | `https://api.coingecko.com` | CoinGecko base URL (override for tests/proxies) |
| `ETHERSCAN_API_KEY` | *(unset)* | Optional EVM history enrichment/fallback for all twelve EVM networks; required only for Polygon Amoy |
| `ETHERSCAN_API_URL` | `https://api.etherscan.io/v2/api` | Etherscan-family endpoint |
| `HELIUS_API_KEY` | *(unset)* | Optional Solana parsed-history enrichment (exact native transfer); standard RPC remains available without it |
| `HELIUS_API_URL` | `https://mainnet.helius-rpc.com` | Helius RPC base URL (`sol-mainnet` transfer history) |
| `HELIUS_DEVNET_API_URL` | `https://devnet.helius-rpc.com` | Helius RPC base URL (`sol-devnet` transfer history) |
| `OFFICIAL_TOKENS_FILE` | *(built-in catalog)* | Optional absolute path to the operator-managed verified-token JSON array |
| `RATE_LIMIT_RPS` | `10` | Inbound token-bucket refill per client IP |
| `RATE_LIMIT_BURST` | `20` | Inbound token-bucket burst per client IP |

Operational behavior (fixed by contract):

- **Failover** — EVM/Solana URLs are tried in order on transport error, HTTP
  5xx or 429 (never on a valid JSON-RPC error result). After 3 consecutive
  failures an endpoint is skipped for 30 s (per-endpoint circuit breaker).
  Every network has its own pool, so circuit state never bleeds between e.g.
  `eth-mainnet` and `eth-sepolia`. Networks whose default is a single URL
  (base / arbitrum / avalanche / BNB / solana / the testnets) have no failover
  partner out of the box — add more endpoints via that network's `*_RPC_URLS`
  variable to get one.
- **Caching** — prices 30 s; balances 10 s keyed (network, address,
  tokenset-hash); chain params 5 s; history 30 s. Broadcast is never cached.
  Cache keys include the network id: a testnet answer is never served for a
  mainnet request (or vice versa).
- **Rate limiting** — inbound: token bucket per client IP → `-32001` when
  exhausted. Outbound: CoinGecko calls are serialized at 1 rps.
- **Timeouts** — 10 s per upstream attempt, 25 s request budget.
- **Logging** — one structured `slog` line per request: method, chain,
  network (empty = the client sent none, i.e. mainnet), duration, outcome.
  Addresses are truncated (first 6 + last 4 characters); payloads and full
  addresses are never logged.
- The client IP for rate limiting is taken from the TCP peer address; when
  deploying behind a reverse proxy, terminate per-IP limits there or extend
  `clientIP` to honor your proxy header.

## Protocol

JSON-RPC 2.0 over `POST /rpc` (`Content-Type: application/json`). Batch
requests are NOT supported (error `-32600`). `chain` ∈ `"eth" | "polygon" |
"base" | "arbitrum" | "avalanche" | "bnb" | "tron" | "solana"` (the app's
`Coin` enum names). A request without an `id` (or with `"id": null`) is a
notification: it executes but gets HTTP 204 and no body.

### Networks

Every chain-scoped method (`kt_getBalances`, `kt_getChainParams`,
`kt_getHistory`, `kt_broadcast`) accepts an **optional** `network` string
param selecting a specific network of the chain. The ids are exactly the
app's built-in `Network.id` values, so a client can forward
`NetworkController.activeFor(chain).id` verbatim:

| Chain | Networks | Etherscan v2 chainid (mainnet / testnet) |
|---|---|---|
| `eth` | `eth-mainnet`, `eth-sepolia` | 1 / 11155111 |
| `polygon` | `polygon-mainnet`, `polygon-amoy` | 137 / 80002 |
| `base` | `base-mainnet`, `base-sepolia` | 8453 / 84532 |
| `arbitrum` | `arbitrum-mainnet`, `arbitrum-sepolia` | 42161 / 421614 |
| `avalanche` | `avalanche-mainnet`, `avalanche-fuji` | 43114 / 43113 |
| `bnb` | `bnb-mainnet`, `bnb-testnet` | 56 / 97 |
| `tron` | `tron-mainnet`, `tron-nile` | — |
| `solana` | `sol-mainnet`, `sol-devnet` | — |

- **Omitted `network`** → the chain's mainnet — exactly the pre-network
  behavior, so existing clients are unaffected. A client that talks to
  testnets MUST send the param: an omitted `network` silently means mainnet,
  and a testnet-signed transaction broadcast to a mainnet node is rejected.
- **Unknown network id** → `-32602` naming the `network` field. The gateway
  cannot serve an arbitrary user-added ("custom") network, so clients must
  detect that case themselves — see the `networks` field of `kt_health`.
- `chain` stays required and must agree with the network's family
  (`eth-sepolia` requires `chain: "eth"`, etc.); a mismatch → `-32602`.
- **Prices are mainnet-only**: `kt_getPrices` takes no `network` param and
  always answers with mainnet fiat prices. Testnet assets have no fiat value —
  clients simply shouldn't ask for prices on testnets (the KT-Wallet app
  already suppresses fiat display there).

Supported network ids are discoverable via `kt_health`'s `networks` field.

### Official token catalog

The blue verification mark is controlled by `network + contract/mint`, never
by symbol alone. Set `OFFICIAL_TOKENS_FILE` to an operator-managed copy of
[`config/official-tokens.json`](config/official-tokens.json) and restart the
Gateway after editing it. The file replaces the built-in catalog.

Every entry requires `network`, `symbol`, `name`, `contract`, and `decimals`;
`popular` is optional. Startup fails if the JSON is malformed, a network is
unknown, an address has the wrong shape, or a network/contract identity is
duplicated. This fail-closed behavior prevents an incomplete parse from
accidentally verifying the wrong asset.

### `kt_health` ()

→ `{"ok": true, "version": "<semver>", "networks": ["eth-mainnet", "eth-sepolia", "polygon-mainnet", "polygon-amoy", "base-mainnet", "base-sepolia", "arbitrum-mainnet", "arbitrum-sepolia", "avalanche-mainnet", "avalanche-fuji", "tron-mainnet", "tron-nile", "sol-mainnet", "sol-devnet"]}`

`networks` lists every network id the chain-scoped methods accept (additive
field — older clients can ignore it). It is the discovery mechanism for
clients that need to know whether their active network can be served at all:
the KT-Wallet app probes it once per gateway URL and takes its direct path for
any network the gateway does not advertise (custom networks, or families a
newer app knows and an older gateway does not).

### `kt_getBalances` `{"chain": C, "network": N?, "address": A, "tokens": [{"contract": S, "decimals": N, "symbol": S}]?}`

→ `{"native": {"raw": "<decimal-string>", "decimals": N, "symbol": S},
    "tokens": [{"contract": S, "raw": "<decimal-string>", "decimals": N, "symbol": S, "error": S?}]}`

Per-token upstream failure sets that token's `error` (with `raw: "0"`)
instead of failing the call. Upstream mapping: EVM native `eth_getBalance`;
EVM tokens `eth_call` `0x70a08231` balanceOf; tron native + TRC-20 via
TronGrid `/v1/accounts/{addr}`; solana native `getBalance` (SPL tokens:
per-token `error: "unsupported"` for now).

### `kt_getPrices` `{"symbols": ["ETH","POL","AVAX","TRX","SOL","USDT","USDC","BUSD"]}`

→ `{"prices": {"ETH": {"usd": 1234.56, "change24h": 2.34}, ...}, "cachedAtMs": <int>}`

Unknown symbols are omitted. ETH is shared by Ethereum, Base and Arbitrum.
USDT/USDC/BUSD use CoinGecko spot quotes too, so depegs are reflected rather
than silently fixed at 1.0. `change24h` is CoinGecko's rolling 24-hour USD
percentage change; it is omitted when CoinGecko returns null or cannot
calculate a fresh value, never replaced with `0`. Price and change share the
same 30-second cache entry. `cachedAtMs` is the time the underlying data was
fetched (cache hits report the original fetch time). Prices are mainnet-only
and take no `network` param — testnet clients shouldn't ask (see
[Networks](#networks)).

### `kt_getChainParams` `{"chain": C, "network": N?, "address": A}`

→ `{"nonce": "<decimal-string>", "fees": {"slow": {"maxPriorityFeePerGas": "<dec>", "maxFeePerGas": "<dec>"}, "standard": {...}, "fast": {...}}}`

EVM chains only (`eth`, `polygon`, `base`, `arbitrum`, `avalanche`, `bnb`);
tron/solana → error `-32602`. Nonce is
`eth_getTransactionCount(pending)`. Tiers come from `eth_feeHistory`
(5 blocks, percentiles 10/50/90; priority = per-tier average, maxFee =
2×next-base-fee + priority) with an `eth_gasPrice` fallback
(priority 10/15/20 %, maxFee 100/125/150 % of gas price). Tiers are
monotonic: slow ≤ standard ≤ fast.

### `kt_getHistory` `{"chain": C, "network": N?, "address": A, "limit": N?}`

→ `{"status": "ok" | "unsupported",
    "records": [{"id": S, "hash": S, "direction": "in"|"out",
    "amountRaw": "<dec>", "decimals": N, "symbol": S, "contract": S?,
    "verified": B, "timestampMs": <int>, "status": "ok"|"failed"}]}`

- **tron** — always supported via TronGrid: TRC-20 transfers + native
  `TransferContract` transactions, merged newest-first. TRC-20 rows include
  their contract and are verified against the active network's registry.
  `tron-nile` runs the same code against the nile TronGrid base URL.
- **EVM families** — Etherscan v2 is preferred when `ETHERSCAN_API_KEY` is
  configured. Without a key (or when Etherscan is temporarily unavailable),
  Ethereum, Polygon mainnet, Base, Arbitrum, Avalanche and BNB use keyless
  Blockscout/Routescan explorers. Polygon Amoy is the sole exception: its
  official explorer requires an API key, so it reports `unsupported` when no
  Etherscan key is configured. Normal transactions and ERC-20 transfers are
  kept as event-level rows (`hash + logIndex`), so multiple transfers in one
  transaction are not lost; only its zero-value contract wrapper is removed.
  Token symbols/decimals are authoritative only for registered contracts.
- **solana** — Helius `getTransfersByAddress` is preferred when
  `HELIUS_API_KEY` is set. Without it, standard Solana RPC loads signatures
  and transaction details and derives native/SPL balance deltas. Unknown SPL
  mints remain visible as unverified `SPL` rows carrying the mint; pure
  program activity with no asset movement is omitted instead of being
  mislabeled as an incoming `0 SOL` transfer.

`id` identifies the transfer event, while `hash` remains the explorer
transaction identifier. `verified:false` means the contract/mint is not in
KT Wallet's active-network registry; clients must not render it as a canonical
asset based on symbol alone.

`limit` defaults to 20 and is capped at 100; `limit <= 0` → `-32602`.

### `kt_searchTokens` `{"query": S?, "networks": [N]?, "limit": N?}`

→ `{"tokens": [{"network": S, "symbol": S, "name": S, "contract": S,
"decimals": N, "popular": B?, "verified": true}]}`

Searches the configured official catalog by token name, symbol, contract, or
mint. Contract/mint exact matches rank first, followed by exact symbols,
prefixes, then substring matches. An empty query returns popular entries
first. `networks` optionally limits results to known network ids. `limit`
defaults to 50 and must be between 1 and 100.

### `kt_broadcast` `{"chain": C, "network": N?, "payload": S}`

→ `{"txHash": S}`

Payload is hex (0x-prefixed) for EVM, base64 for solana, and the raw TronGrid
transaction JSON string for tron — forwarded verbatim to the chain. Node
rejection → error `-32000` carrying the node's message (TronGrid hex-encoded
messages are decoded to text). Malformed payloads are rejected with `-32602`
before any upstream call. Never cached.

### Errors

| Code | Meaning |
|---|---|
| `-32700` | parse error |
| `-32600` | invalid request / batch |
| `-32601` | unknown method |
| `-32602` | invalid params (message names the offending field) |
| `-32000` | upstream_error — `data: {"upstream": S, "message": S}`; when the node itself rejected, `message` is the node's message |
| `-32001` | rate_limited |
| `-32002` | unsupported |

## Layout

```
backend/gateway/
├── cmd/gateway/          # main: env config, HTTP server, graceful shutdown
├── internal/rpc/         # JSON-RPC 2.0 server (single requests, notifications, errors)
├── internal/handlers/    # kt_* methods, validation, caching policy
├── internal/upstream/    # evm (failover pool + circuit), tron, solana, prices, history
├── internal/cache/       # TTL cache (injectable clock)
├── internal/ratelimit/   # per-IP token bucket + outbound interval limiter
└── internal/clock/       # Clock interface, Real + Fake
```
