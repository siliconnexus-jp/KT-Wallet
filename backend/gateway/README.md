# KT-Wallet Chain-Query Gateway

A single-binary JSON-RPC 2.0 facade the KT-Wallet app can point at instead of
talking to chains directly. It shields clients from upstream dialects (EVM
JSON-RPC, TronGrid REST, Solana JSON-RPC, CoinGecko), from upstream rate
limits, and from API keys (Etherscan / Helius keys live here, never in the
app). The app keeps its direct mode — this gateway is a faithful superset of
it, not a new source of truth: payloads are forwarded verbatim, balances and
fees are the chain's own numbers.

Go 1.26.5 or newer is required. The patch floor is intentional: Go 1.26.1
contains standard-library vulnerabilities reachable from the Gateway's TLS,
HTTP and certificate-validation paths. Redis is optional; without `REDIS_URL`
the binary keeps the existing process-local cache behavior.

## Running

```sh
make build && ./bin/gateway              # listens on :8080
make test                                # unit + integration tests (no network)
make race                                # tests with -race
make cover                               # coverage across internal/
make vuln                                # reachable Go/stdlib vulnerability scan
make audit                               # vet + tests + vulnerability scan
make docker && make docker-run           # multi-stage distroless image
make docker-audit                        # build and OSV-scan the final image
```

The Docker build and runtime bases are digest-pinned. `go.mod` requires
Go 1.26.5, so the Go toolchain auto-selection also applies to local and Linux
release builds instead of depending on whichever patch version happens to be
installed globally. `make docker` defaults to `linux/amd64`, matching the
current production host; set `PLATFORM=linux/arm64` explicitly for an ARM
deployment rather than accidentally publishing a host-native image.

Smoke test:

```sh
curl -s localhost:8080/rpc -d '{"jsonrpc":"2.0","id":1,"method":"kt_health"}'
curl -s localhost:8080/healthz
curl -s localhost:8080/readyz
curl -s -H "Authorization: Bearer $METRICS_BEARER_TOKEN" localhost:8080/metrics
# {"jsonrpc":"2.0","id":1,"result":{"networks":["eth-mainnet","eth-sepolia",...],"ok":true,"version":"1.16.15"}}
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
| `POLYGON_AMOY_RPC_URLS` | `https://polygon-amoy-bor-rpc.publicnode.com,https://polygon-amoy.drpc.org` | `polygon-amoy` RPC endpoints |
| `BASE_SEPOLIA_RPC_URLS` | `https://sepolia.base.org` | `base-sepolia` RPC endpoints |
| `ARBITRUM_SEPOLIA_RPC_URLS` | `https://sepolia-rollup.arbitrum.io/rpc` | `arbitrum-sepolia` RPC endpoints |
| `AVALANCHE_FUJI_RPC_URLS` | `https://api.avax-test.network/ext/bc/C/rpc` | `avalanche-fuji` RPC endpoints |
| `BNB_TESTNET_RPC_URLS` | `https://bsc-testnet-dataseed.bnbchain.org` | `bnb-testnet` RPC endpoints |
| `SOLANA_DEVNET_RPC_URLS` | `https://api.devnet.solana.com` | `sol-devnet` RPC endpoints |
| `TRON_NILE_API_URL` | `https://nile.trongrid.io` | `tron-nile` TronGrid base URL |
| `COINGECKO_API_URL` | `https://api.coingecko.com` | CoinGecko base URL (override for tests/proxies) |
| `ETHERSCAN_API_KEY` | *(unset)* | Optional EVM history enrichment/fallback for all twelve EVM networks; required only for Polygon Amoy |
| `ETHERSCAN_API_URL` | `https://api.etherscan.io/v2/api` | Etherscan-family endpoint |
| `ALCHEMY_API_KEYS` | *(unset)* | Comma-separated Alchemy keys; round-robin EVM reads and indexed history across all keys, with automatic read failover; broadcasts select one eligible key and never fail over after submission starts |
| `ALCHEMY_API_KEY` | *(unset)* | Backward-compatible single-key fallback, used only when `ALCHEMY_API_KEYS` is empty |
| `HELIUS_API_KEY` | *(unset)* | Optional Solana parsed-history enrichment (exact native transfer); standard RPC remains available without it |
| `HELIUS_API_URL` | `https://mainnet.helius-rpc.com` | Helius RPC base URL (`sol-mainnet` transfer history) |
| `HELIUS_DEVNET_API_URL` | `https://devnet.helius-rpc.com` | Helius RPC base URL (`sol-devnet` transfer history) |
| `GOPLUS_API_URL` | `https://api.gopluslabs.io/api/v1/token_security` | Independent token threat-intelligence endpoint; receives only chain id + public token contract; public URLs require HTTPS (HTTP is loopback-only) |
| `GOPLUS_SOLANA_API_URL` | `https://api.gopluslabs.io/api/v1/solana/token_security` | Solana Token Security endpoint; receives only the public mint and blocks only explicit malicious privileged-authority evidence |
| `GOPLUS_APPROVAL_API_URL` | `https://api.gopluslabs.io/api/v2/token_approval_security` | Opt-in EVM token-approval endpoint; receives chain id + public wallet address only after the App records explicit user consent |
| `GOPLUS_ACCESS_TOKEN` | *(unset)* | Optional GoPlus bearer token for a higher provider quota; never returned or logged |
| `DISABLE_EXTERNAL_TOKEN_RISK` | `false` | Explicitly disable external token checks for offline/private deployments; unknown tokens remain `unknown` |
| `DISABLE_EXTERNAL_APPROVAL_LOOKUP` | `false` | Disable wallet-specific external approval scans; calls return unsupported rather than an empty/clean list |
| `OFFICIAL_TOKENS_FILE` | *(built-in catalog)* | Optional absolute path to the operator-managed verified-token JSON array |
| `TOKEN_RISKS_FILE` | *(empty registry)* | Optional absolute path to the operator-managed malicious/spam contract registry |
| `REDIS_URL` | *(unset)* | Shared read cache plus atomic cross-instance broadcast guard; required for a multi-instance production deployment. Remote hosts require `rediss://`, while plaintext `redis://` is accepted only on loopback; startup fails when explicitly configured but unavailable |
| `RATE_LIMIT_RPS` | `10` | Inbound token-bucket refill per client IP |
| `RATE_LIMIT_BURST` | `20` | Inbound token-bucket burst per client IP |
| `TRUSTED_PROXY_CIDRS` | *(unset)* | Comma-separated reverse-proxy CIDRs allowed to supply `X-Forwarded-For` / `X-Real-IP`; for same-host Nginx use `127.0.0.1/32,::1/128` |
| `METRICS_BEARER_TOKEN` | *(unset; endpoint disabled)* | At least 32-byte bearer token required by `GET /metrics`; keep it in the service secret store and monitoring client only |

Operational behavior (fixed by contract):

- **Failover** — EVM/Solana **read** requests are tried in order on transport
  error, HTTP 5xx or 429 (never on a valid JSON-RPC error result). A broadcast
  selects exactly one endpoint whose circuit is not already open; after that
  request starts, timeout, disconnect, HTTP failure, malformed response or
  provider-routing error returns `submission_unknown` and never contacts a
  second endpoint. After 3 consecutive
  failures an endpoint is skipped for 30 s (per-endpoint circuit breaker).
  Every network has its own pool, so circuit state never bleeds between e.g.
  `eth-mainnet` and `eth-sepolia`. Networks whose default is a single URL
  (base / arbitrum / avalanche / BNB / solana / the testnets) have no failover
  partner out of the box — add more endpoints via that network's `*_RPC_URLS`
  variable to get one.
- **Reverse proxy** — the maintained production template is
  `ops/haproxy/haproxy.cfg`. It keeps active `/healthz` routing across the two
  Gateway processes but sets `retries 0` and forbids redispatch/retry-on,
  because `/rpc` also carries irreversible `kt_broadcast` writes. `make audit`
  runs `ops/verify-haproxy.sh` so a replay-capable proxy configuration fails
  the release gate.
- **Broadcast idempotency** — a canonical SHA-256 fingerprint of
  `(chain, network, signed payload)` is claimed before contacting a node. The
  exact transaction bytes are never stored. Replays within 24 hours return the
  first accepted/rejected/unknown outcome, while a concurrent or crash-left
  `pending` claim returns `submission_unknown` and never submits again. With
  `REDIS_URL` the claim is atomic across Gateway processes; inability to claim
  Redis fails closed before the upstream write. Stored records are also
  schema-checked: accepted requires a non-empty transaction hash and error
  states require their matching RPC code. Corrupt records fail closed instead
  of returning an empty success. This is the final defense against a client,
  CDN or outer proxy replaying the same POST.
- **Caching** — prices 30 s; display balances 10 s keyed (network, address,
  tokenset-hash); history 5 s. Chain params (including pending nonce),
  spendable balances, simulation and direct transaction-status checks are
  never read-cached. Broadcast keeps only the hashed idempotency claim and its
  outcome; it never stores the signed payload.
  Cache keys include the network id: a testnet answer is never served for a
  mainnet request (or vice versa). With `REDIS_URL`, each instance remains
  local-first and shares the same TTL-bounded entries through Redis. Redis
  keys contain only a namespace and SHA-256 fingerprint — never a readable
  wallet address or token set. Values still contain wallet-derived balance or
  history data, so production Redis must be private, authenticated, encrypted
  in transit (`rediss://`) and configured without persistent backups unless a
  separate privacy review approves them. A runtime Redis error falls back to
  a local miss and is counted in Prometheus. Redis command retries are disabled,
  I/O is capped at 750 ms, and one failure opens a 5-second circuit with a
  single half-open recovery probe, so an optional cache outage cannot add
  repeated multi-second stalls to wallet reads. A stale success from an
  operation that began before a concurrent failure cannot close the circuit.
  An invalid/unreachable
  explicitly configured Redis still fails startup instead of silently creating
  inconsistent instances.
- **Rate limiting** — inbound: token bucket per client IP → `-32001` when
  exhausted. Behind a reverse proxy, forwarding headers are ignored unless the
  TCP peer matches `TRUSTED_PROXY_CIDRS`; trusted chains are walked from right
  to left so a client-supplied leftmost value cannot choose a fresh bucket.
  Comma-separated and repeated XFF field lines are flattened in wire order so
  HAProxy's `option forwardfor` append behavior remains compatible. Malformed,
  empty or overlong chains and duplicate X-Real-IP fields fall back to the peer
  address. Once any XFF field is present but invalid, X-Real-IP is not consulted
  as a second identity source. The limiter keeps a
  hard 65,536-bucket cap and sends excess high-cardinality clients through a
  conservative shared overflow bucket, preventing unbounded memory growth.
  Outbound: CoinGecko calls are serialized at 1 rps. GoPlus
  results are cached locally for 5 minutes so repeated confirmation taps do
  not consume its public quota. EVM Token Security, Solana Token Security and
  opt-in EVM approval discovery each have an independent circuit: 3 consecutive
  failures open it for 30 seconds, then exactly one half-open probe is allowed.
  Open circuits fail closed immediately (risk remains unavailable; approvals
  never become an empty list), and their fixed-name state/counters are exported
  to Prometheus without addresses or provider URLs.
- **Timeouts** — 10 s per upstream attempt, 25 s request budget.
- **Body limits** — inbound JSON-RPC is capped at 4 MiB; CoinGecko at 1 MiB,
  GoPlus at 2 MiB, and chain/indexer responses at 8 MiB. Every boundary reads
  one byte past the limit and rejects the whole body before parsing, so a valid
  JSON prefix followed by oversized whitespace/padding cannot be accepted as
  a complete request or provider response.
- **Logging** — one structured `slog` line per request: method, chain,
  network (empty = the client sent none, i.e. mainnet), duration and outcome.
  Method is emitted only when it exactly matches a server-registered method;
  chain and network are emitted only when they exactly match the built-in
  fixed vocabulary. Unknown client strings collapse to `unknown` / `invalid`,
  so an attacker cannot smuggle an address, recovery phrase or credential into
  logs through routing fields. Wallet addresses, truncated address fragments,
  payloads, balances, hashes and provider credentials are never logged.
- **Error privacy** — transport failures never retain `net/http` error text,
  because Go commonly embeds the complete provider URL and its path/query API
  key. Provider routing, REST/RPC error bodies and malformed values are mapped
  to a fixed public vocabulary. The JSON-RPC boundary independently replaces
  every unavailable or unknown error with a canonical message and canonical
  upstream name; common transaction rejections (insufficient funds, nonce,
  fee, blockhash and signature failures) remain actionable without reflecting
  arbitrary provider text.
- **Token threat intelligence** — the exact operator denylist always wins.
  Supported EVM/TRON mainnets are then checked against GoPlus using only chain
  id + public contract; `sol-mainnet` uses the provider's separate Solana beta
  endpoint with only the exact public mint. Explicit external malicious evidence
  overrides an official identity entry. EVM/TRON promote only honeypot,
  fake-token, malicious-address or gas-abuse evidence. Solana promotes only an
  explicit `malicious_address` attached to the creator, transfer hook, or a
  privileged authority; mintable, freezable and mutable-metadata capabilities
  alone do not block legitimate tokens such as USDC. No evidence remains
  `unknown`; an official catalog match becomes `safe` only after that check
  finds no explicit malicious evidence. Timeout/429/malformed responses become
  an upstream error so the App displays “unable to check” instead of a green
  state. Testnets retain local registry/catalog behavior and never inherit
  mainnet provider evidence.
- **Eight-mainnet risk smoke** — operators can run
  `sh ops/verify-token-risk-matrix.sh https://gateway.example` to select one
  popular official identity for Ethereum, Polygon, Base, Arbitrum, Avalanche,
  BNB, TRON and Solana from the checked-in catalog. Every response must be
  `safe` with `official_catalog+goplus`; transport errors, RPC errors,
  `unknown`, `unsafe`, malformed/oversized responses, an incomplete catalog,
  redirects, credential-bearing URLs and public HTTP endpoints fail closed.
  The output records only network, status and source, never the queried
  contract or any provider credential. `make token-risk-matrix-test` runs the
  deterministic positive and negative guard suite without contacting a live
  provider.
- **Token approval privacy and freshness** — approval scans are opt-in and
  require `privacyConsent: true` on every request because the external
  provider receives a public wallet address. The sanitized result is cached
  for 30 seconds under `SHA-256(network|lowercase-address)`; the address is
  not retained in the key or value. Provider failure is an error, never an
  empty approval list. Testnets, Avalanche and non-EVM networks return
  unsupported. A revoke changes wallet state, so clients refresh after
  confirmation and never interpret a stale row as a second transfer.
- The client IP for rate limiting is taken from the TCP peer unless that peer
  is explicitly trusted. Never set `TRUSTED_PROXY_CIDRS` to `0.0.0.0/0` or
  `::/0`; Nginx should overwrite or append the real remote address.

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

### Token risk registry

Set `TOKEN_RISKS_FILE` to an operator-managed copy of
[`config/token-risks.json`](config/token-risks.json). Each row contains the
exact `network`, `contract`/mint and one category: `malicious`, `phishing`,
`spam`, `impersonation`, `honeypot`, or `suspicious`.

Startup rejects the whole file on malformed JSON, invalid addresses,
unsupported categories or duplicate identities. A risk entry always overrides
the official-token catalog so an operator can revoke a previously verified
identity. The checked-in file is intentionally empty: it is a configuration
surface, not a claim that KT Wallet currently subscribes to a continuously
maintained threat-intelligence provider.

### `kt_getEvmTokenApprovals`

`{"chain":"eth","network":"eth-mainnet","address":"0x...","privacyConsent":true}`

Returns the complete provider-reported outstanding ERC-20 allowance rows for
one public EOA:

```json
{
  "status": "ok",
  "source": "goplus",
  "network": "eth-mainnet",
  "approvals": [{
    "tokenAddress": "0x...",
    "tokenName": "Example Token",
    "tokenSymbol": "TKN",
    "decimals": 18,
    "balance": "1000000000000000000",
    "spender": "0x...",
    "spenderName": "Example Protocol",
    "spenderTag": "",
    "spenderTrusted": false,
    "amount": "Unlimited",
    "unlimited": true,
    "approvedAt": 1735689600,
    "transaction": "0x...",
    "risk": "unknown"
  }]
}
```

Supported networks are `eth-mainnet`, `polygon-mainnet`, `base-mainnet`,
`arbitrum-mainnet` and `bnb-mainnet`. Missing consent or an invalid address is
`-32602`; unsupported networks are `-32002`; provider timeout, rate limit,
malformed response or incomplete data is an upstream error. Only a complete
successful provider response may produce an empty array. The Gateway never
signs or broadcasts revocations: the App constructs the exact token-contract
call `approve(spender, 0)`, authenticates/signs it locally or through KT Cold
Signer, verifies the signed bytes and broadcasts via the normal transaction
path.

### `kt_health` ()

→ `{"ok": true, "version": "<semver>", "networks": ["eth-mainnet", "eth-sepolia", "polygon-mainnet", "polygon-amoy", "base-mainnet", "base-sepolia", "arbitrum-mainnet", "arbitrum-sepolia", "avalanche-mainnet", "avalanche-fuji", "bnb-mainnet", "bnb-testnet", "tron-mainnet", "tron-nile", "sol-mainnet", "sol-devnet"], "upstreams": {"eth-mainnet": {"endpoints": 2, "openCircuits": 0, "successes": 12, "failures": 1, "latencyP50Ms": 84, "latencyP95Ms": 230, "failureMetrics": {"rateLimited": 1, "timeouts": 0, "malformedResponses": 0, "transport": 0, "serverErrors": 0, "providerErrors": 0, "other": 0}, "endpointMetrics": [...]}}}`

`networks` lists every network id the chain-scoped methods accept (additive
field — older clients can ignore it). It is the discovery mechanism for
clients that need to know whether their active network can be served at all:
the KT-Wallet app probes it once per gateway URL and takes its direct path for
any network the gateway does not advertise (custom networks, or families a
newer app knows and an older gateway does not).

`upstreams` is an additive, privacy-safe operational snapshot. It keeps a
rolling window of at most 256 timings per endpoint and exports P50/P95,
success/failure totals, open circuits and separate `rateLimited`, `timeouts`,
`malformedResponses`, `transport`, `serverErrors`, `providerErrors` and
`other` buckets. Individual endpoints are identified only by one-based config
position. Provider URLs, API keys, wallet addresses, balances and RPC payloads
are never retained or returned.

### Operational HTTP endpoints

- `GET /healthz` is process liveness and does not contact upstreams.
- `GET /readyz` reports every degraded network in `unavailableNetworks` but
  returns `503` only when no configured JSON-RPC network has an endpoint
  outside an open circuit. One chain outage therefore cannot remove a useful
  multi-chain instance from load-balancer rotation.
- `GET /metrics` exposes the same anonymous endpoint statistics in Prometheus
  text format, plus shared-cache and atomic broadcast-guard counters. The
  broadcast metrics expose only fixed outcomes (`claim_acquired`, replay
  states, `unavailable`, `corrupt_record`, `persist_error`); they never contain
  a key, hash, address or transaction. Metric labels contain only canonical
  network IDs, anonymous endpoint positions, fixed cache names, outcomes,
  failure reasons and rolling latency percentiles. The
  endpoint returns `404` unless `METRICS_BEARER_TOKEN` is configured and the
  request supplies the exact `Authorization: Bearer <token>` header.

The metrics endpoint contains no wallet data or provider credentials, but
operators should still restrict it to their monitoring network at the reverse
proxy. Counters and rolling windows are process-local and reset on restart;
multi-instance aggregation belongs in Prometheus or the chosen telemetry
backend.

Production-ready example files live under `ops/prometheus/`:

- `prometheus-scrape.example.yml` scrapes the HTTPS metrics endpoint every
  30 seconds.
- `kt-wallet-gateway-alerts.yml` defines target-down, all-network outage,
  single-network degradation, upstream failure ratio/P95 latency, shared-cache,
  token-risk/approval provider errors, security-provider circuit state and
  anonymous client trend alerts. Three additional rules make missing
  Alertmanager discovery, delivery errors and queue saturation visible by
  scraping Prometheus's own loopback metrics. The rule file currently contains
  17 rules and has deterministic `promtool test rules` coverage for the three
  delivery-pipeline conditions.
- `../alertmanager/alertmanager.yml` is a destination-free routing baseline for
  severity grouping, inhibition, silences and a separate untrusted-client
  route. `../alertmanager/README.md` documents its loopback-only deployment and
  the operator-owned external receiver overlay.

The security-provider failure, rollback and recovery procedure is documented
in [`ops/RISK_PROVIDER_RUNBOOK.md`](ops/RISK_PROVIDER_RUNBOOK.md). It preserves
the fail-closed UI contract while allowing operators to disable a failing
external provider or override one exact malicious identity without changing
the mobile signing rules.

Run `make monitoring-container-audit` to validate Alertmanager 0.32.1 with the
official `amtool`, validate all Prometheus rules, and execute their unit tests.
The receiver-neutral configuration is also checked by `make audit` so a
credential or destination cannot be committed accidentally.

The current production host runs Alertmanager 0.32.1 on `127.0.0.1:9098` with
UTF-8 strict matchers, five-day retention and bounded silences. Prometheus
3.12.0 scrapes itself plus both Gateway instances, discovers the local
Alertmanager and has delivered a temporary critical canary through the real
notification queue. The canary rule was removed immediately afterward and the
formal rule file was restored byte-for-byte. No external paging destination is
configured yet, so this proves ingestion, grouping and silencing—not that a
human receives an email, message or page.

### Optional mobile diagnostics

`kt_reportDiagnostics` accepts a report only after the App has shown a fresh
user disclosure and the user explicitly selects **Agree and send**. The App
does not upload in the background and does not automatically retry an
ambiguous request. The accepted schema is deliberately closed: app version,
platform, broad locale, build mode, and count/success/failure/P50/P95 for the
twelve fixed operation names. Unknown fields, labels, duplicate metrics,
inconsistent counts and out-of-range values are rejected before any counter is
changed.

The Gateway converts a valid report directly into fixed-label in-memory
counters. It does not store request bodies, raw events, exact timestamps,
device/session identifiers, wallet data, transaction data, errors or stacks.
The production Prometheus currently enforces `7d` and `512MB` retention limits.
Because the endpoint is anonymous and unauthenticated, client-report alerts are
marked `trust="untrusted-client-report"`; they are investigation hints, not a
population crash-rate denominator or paging signal.

### `kt_reportDiagnostics`

```json
{
  "schemaVersion": 1,
  "consent": true,
  "appVersion": "1.0.0",
  "platform": "ios",
  "locale": "en",
  "buildMode": "release",
  "metrics": [
    {
      "name": "transaction.broadcast",
      "count": 3,
      "successCount": 2,
      "failureCount": 1,
      "p50Ms": 900,
      "p95Ms": 2200
    }
  ]
}
```

→ `{"accepted": true, "rawEventsStored": false}`

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

### `kt_simulateEvmTransfer` `{"chain": C, "network": N?, "from": A, "to": A, "value": S, "data": S, "blockTag": "pending"|"latest"?}`

→ `{"gasLimit":"<decimal-string>"}`

EVM only. It executes the exact call with `eth_estimateGas`; `blockTag`
defaults to `pending`. Ordinary transfers use pending state and fail closed
when a node cannot provide it. A same-nonce replacement may explicitly use
`latest` only after the client has proved that its target nonce equals the
confirmed nonce. This exception supports nodes such as Avalanche C-Chain that
reject pending-state queries without silently ignoring an unknown queued
transaction.

### `kt_estimateEvmGas` `{"chain": C, "network": N?, "from": A, "to": A, "value": S, "data": S}`

→ `{"gasLimit":"<decimal-string>"}`

Compatibility alias for EVM gas estimation. New clients should prefer
`kt_simulateEvmTransfer`, whose request records the state tag explicitly.

### `kt_getEvmSpendableBalances` `{"chain": C, "network": N?, "address": A, "tokenContract": A?}`

→ `{"native":"<decimal-string>", "nativePending":"<decimal-string>", "nativeLatest":"<decimal-string>", "pendingAvailable":true|false, "token":"<decimal-string>"?}`

EVM only. `nativeLatest` and `nativePending` are read from the same upstream
selection; `native` is a rolling-upgrade alias of `nativePending`. When a
`tokenContract` is supplied, `token` is read at the same usable state view.
When the node explicitly reports that pending state is unsupported, the
Gateway returns the latest native value in both explicit fields and sets
`pendingAvailable:false`; other errors fail the call. Clients must not treat a
false marker as proof that no pending outgoing transaction exists.

### `kt_getHistory` `{"chain": C, "network": N?, "address": A, "limit": N?}`

→ `{"status": "ok" | "unsupported",
    "records": [{"id": S, "hash": S, "direction": "in"|"out",
    "amountRaw": "<dec>", "decimals": N, "symbol": S, "contract": S?,
    "verified": B, "timestampMs": <int>, "status": "ok"|"failed"}]}`

- **tron** — always supported via TronGrid: TRC-20 transfers + native
  `TransferContract` transactions, merged newest-first. TRC-20 rows include
  their contract and are verified against the active network's registry.
  `tron-nile` runs the same code against the nile TronGrid base URL.
- **EVM families** — Alchemy Transfers API is preferred when
  `ALCHEMY_API_KEY` is configured and covers native/internal/ERC-20 movements
  on all twelve EVM networks, including BNB 56/97 and Polygon Amoy. The same
  key also prepends Alchemy to every EVM JSON-RPC pool for balances, fee
  estimation and status checks. Reads may fail over; a broadcast chooses one
  currently eligible endpoint and is never re-posted after the attempt starts. If Alchemy is unavailable,
  Etherscan v2 (`ETHERSCAN_API_KEY`) and then keyless Blockscout/Routescan
  explorers remain fallbacks. Transfer rows keep their event-level
  `uniqueId`, so multiple transfers in one transaction are not lost. Token
  symbols/decimals are authoritative only for registered contracts.
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

### `kt_checkTokenRisk` `{"chain": C, "network": N?, "contract": S}`

→ `{"status":"safe"|"unsafe"|"unknown", "category":S?, "source":S, "network":N, "contract":S}`

Every successful result echoes the resolved network and normalized contract or
mint identity. Clients must bind both fields to the request before displaying
an official identity or acting on an unsafe/unknown result; EVM addresses are
case-insensitive, while TRON and Solana identities are case-sensitive.

- `unsafe` means the exact network + contract/mint is in the operator risk
  registry; `category` describes the configured reason.
- `safe` means the exact identity is in the verified-token catalog and is not
  overridden by the risk registry. It confirms identity only, not investment
  safety or future contract behavior.
- `unknown` means neither registry can establish the identity. Clients must
  not render this as safe. A transport/service failure is distinct from this
  successful `unknown` response and must be shown as “unable to check”.

### `kt_broadcast` `{"chain": C, "network": N?, "payload": S}`

→ `{"txHash": S}`

Payload is hex (0x-prefixed) for EVM, base64 for solana, and the raw TronGrid
transaction JSON string for tron — forwarded verbatim to the chain. Node
rejection → error `-32000` carrying the node's message (TronGrid hex-encoded
messages are decoded to text). If submission started but the authoritative
answer was lost, the Gateway returns `-32003 submission_unknown`; clients must
reconcile with the locally derived transaction hash and must not submit again.
EVM/Solana broadcasts never fail over to another RPC after the first write
attempt. Malformed payloads are rejected with `-32602` before any upstream
call. The Gateway atomically deduplicates the canonical signed payload for 24
hours: accepted/rejected/unknown results are replayed without a second upstream
write, and a concurrent/crash-left pending claim returns
`-32003 submission_unknown`. Production multi-instance deployments must set
`REDIS_URL`; only a SHA-256 fingerprint and result metadata enter Redis, never
the signed transaction bytes.

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
| `-32003` | submission_unknown — a broadcast was attempted but no authoritative node answer survived; never retry automatically |

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
