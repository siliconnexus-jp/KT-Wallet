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
# {"jsonrpc":"2.0","id":1,"result":{"ok":true,"version":"1.0.0"}}
```

## Environment

| Variable | Default | Purpose |
|---|---|---|
| `GATEWAY_ADDR` | `:8080` | Listen address |
| `ETH_RPC_URLS` | `https://eth.llamarpc.com,https://cloudflare-eth.com` | Ethereum RPC endpoints, comma-separated, tried in order |
| `POLYGON_RPC_URLS` | `https://polygon-rpc.com,https://polygon-bor-rpc.publicnode.com` | Polygon RPC endpoints |
| `SOLANA_RPC_URLS` | `https://api.mainnet-beta.solana.com` | Solana RPC endpoints |
| `TRON_API_URL` | `https://api.trongrid.io` | TronGrid base URL |
| `COINGECKO_API_URL` | `https://api.coingecko.com` | CoinGecko base URL (override for tests/proxies) |
| `ETHERSCAN_API_KEY` | *(unset)* | Enables eth/polygon history via the Etherscan v2 multichain API |
| `ETHERSCAN_API_URL` | `https://api.etherscan.io/v2/api` | Etherscan-family endpoint |
| `HELIUS_API_KEY` | *(unset)* | Enables solana history via Helius |
| `HELIUS_API_URL` | `https://api.helius.xyz` | Helius base URL |
| `RATE_LIMIT_RPS` | `10` | Inbound token-bucket refill per client IP |
| `RATE_LIMIT_BURST` | `20` | Inbound token-bucket burst per client IP |

Operational behavior (fixed by contract):

- **Failover** — EVM/Solana URLs are tried in order on transport error, HTTP
  5xx or 429 (never on a valid JSON-RPC error result). After 3 consecutive
  failures an endpoint is skipped for 30 s (per-endpoint circuit breaker).
- **Caching** — prices 30 s; balances 10 s keyed (chain, address,
  tokenset-hash); chain params 5 s; history 30 s. Broadcast is never cached.
- **Rate limiting** — inbound: token bucket per client IP → `-32001` when
  exhausted. Outbound: CoinGecko calls are serialized at 1 rps.
- **Timeouts** — 10 s per upstream attempt, 25 s request budget.
- **Logging** — one structured `slog` line per request: method, chain,
  duration, outcome. Addresses are truncated (first 6 + last 4 characters);
  payloads and full addresses are never logged.
- The client IP for rate limiting is taken from the TCP peer address; when
  deploying behind a reverse proxy, terminate per-IP limits there or extend
  `clientIP` to honor your proxy header.

## Protocol

JSON-RPC 2.0 over `POST /rpc` (`Content-Type: application/json`). Batch
requests are NOT supported (error `-32600`). `chain` ∈ `"eth" | "polygon" |
"tron" | "solana"`. A request without an `id` (or with `"id": null`) is a
notification: it executes but gets HTTP 204 and no body.

### `kt_health` ()

→ `{"ok": true, "version": "<semver>"}`

### `kt_getBalances` `{"chain": C, "address": A, "tokens": [{"contract": S, "decimals": N, "symbol": S}]?}`

→ `{"native": {"raw": "<decimal-string>", "decimals": N, "symbol": S},
    "tokens": [{"contract": S, "raw": "<decimal-string>", "decimals": N, "symbol": S, "error": S?}]}`

Per-token upstream failure sets that token's `error` (with `raw: "0"`)
instead of failing the call. Upstream mapping: EVM native `eth_getBalance`;
EVM tokens `eth_call` `0x70a08231` balanceOf; tron native + TRC-20 via
TronGrid `/v1/accounts/{addr}`; solana native `getBalance` (SPL tokens:
per-token `error: "unsupported"` for now).

### `kt_getPrices` `{"symbols": ["ETH","POL","TRX","SOL","USDT","USDC"]}`

→ `{"prices": {"ETH": {"usd": 1234.56}, ...}, "cachedAtMs": <int>}`

Unknown symbols are omitted. USDT/USDC are answered from the built-in 1.0 peg
without an upstream call. `cachedAtMs` is the time the underlying upstream
data was fetched (cache hits report the original fetch time).

### `kt_getChainParams` `{"chain": C, "address": A}`

→ `{"nonce": "<decimal-string>", "fees": {"slow": {"maxPriorityFeePerGas": "<dec>", "maxFeePerGas": "<dec>"}, "standard": {...}, "fast": {...}}}`

EVM chains only; tron/solana → error `-32602`. Nonce is
`eth_getTransactionCount(pending)`. Tiers come from `eth_feeHistory`
(5 blocks, percentiles 10/50/90; priority = per-tier average, maxFee =
2×next-base-fee + priority) with an `eth_gasPrice` fallback
(priority 10/15/20 %, maxFee 100/125/150 % of gas price). Tiers are
monotonic: slow ≤ standard ≤ fast.

### `kt_getHistory` `{"chain": C, "address": A, "limit": N?}`

→ `{"status": "ok" | "unsupported",
    "records": [{"hash": S, "direction": "in"|"out", "amountRaw": "<dec>", "decimals": N, "symbol": S, "timestampMs": <int>, "status": "ok"|"failed"}]}`

- **tron** — always supported via TronGrid: TRC-20 transfers + native
  `TransferContract` transactions, merged newest-first, deduplicated by hash.
- **eth/polygon** — supported only when `ETHERSCAN_API_KEY` is configured
  (Etherscan v2, `chainid` 1 / 137); otherwise `{"status":"unsupported","records":[]}`.
- **solana** — supported only when `HELIUS_API_KEY` is set (Helius parsed
  history, native transfers); otherwise unsupported.

`limit` defaults to 20 and is capped at 100; `limit <= 0` → `-32602`.

### `kt_broadcast` `{"chain": C, "payload": S}`

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
