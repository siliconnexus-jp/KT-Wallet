// Package handlers implements the kt_* JSON-RPC methods on top of the
// upstream clients, with per-method TTL caching. The gateway is a faithful
// superset of the app's direct mode: it forwards chain semantics untouched
// and never becomes a source of truth of its own.
package handlers

import (
	"errors"
	"log/slog"
	"net/http"
	"time"

	"ktwallet/gateway/internal/cache"
	"ktwallet/gateway/internal/clock"
	"ktwallet/gateway/internal/ratelimit"
	"ktwallet/gateway/internal/rpc"
	"ktwallet/gateway/internal/upstream"
)

// Cache TTLs fixed by the service contract.
const (
	pricesTTL   = 30 * time.Second
	balancesTTL = 10 * time.Second
	// History must converge quickly after a broadcast. A 30-second empty-page
	// cache made a recipient balance update while its record remained absent.
	historyTTL = 5 * time.Second
	// External threat intelligence is public contract metadata, but the free
	// provider is rate limited. Five minutes keeps checks fresh without making
	// every confirmation tap consume another provider request.
	tokenRiskTTL = 5 * time.Minute
	// Approval lists are wallet-specific and change after a revoke. Keep this
	// local-only cache short; it must never enter the shared Redis cache.
	tokenApprovalsTTL = 30 * time.Second
)

// Config wires the gateway. Zero values fall back to production defaults.
type Config struct {
	Version string
	Log     *slog.Logger
	Clock   clock.Clock
	// HTTPClient is used for every upstream call.
	HTTPClient *http.Client
	// AttemptTimeout bounds a single upstream attempt (default 10s).
	AttemptTimeout time.Duration
	// SharedCache enables local-first cross-instance caching. Values remain
	// bounded by the method TTLs; cache keys are hashed before reaching Store.
	// Transaction preflight, spendable balances and status are never cached.
	// Broadcast outcome coordination uses the separate AtomicStore contract.
	SharedCache cache.Store
	// BroadcastStore is the fail-closed, cross-instance idempotency store for
	// signed transaction submission. Production wires the same Redis client as
	// SharedCache, but the stronger AtomicStore contract is intentionally kept
	// separate from best-effort read caching.
	BroadcastStore cache.AtomicStore

	EthURLs       []string
	PolygonURLs   []string
	BaseURLs      []string
	ArbitrumURLs  []string
	AvalancheURLs []string
	BNBURLs       []string
	SolanaURLs    []string
	TronURL       string

	// Testnet upstreams (one per supported non-mainnet network).
	EthSepoliaURLs      []string
	PolygonAmoyURLs     []string
	BaseSepoliaURLs     []string
	ArbitrumSepoliaURLs []string
	AvalancheFujiURLs   []string
	BNBTestnetURLs      []string
	SolanaDevnetURLs    []string
	TronNileURL         string

	CoinGeckoURL string
	// CoinGeckoInterval spaces outbound CoinGecko calls (default 1s).
	CoinGeckoInterval time.Duration

	EtherscanURL string
	EtherscanKey string
	// AlchemyKeys enable the Transfers API as the primary EVM history indexer.
	// AlchemyURLs maps KT network ids to JSON-RPC endpoint pools; nil uses the
	// production endpoints generated from AlchemyKeys. AlchemyRPCCount marks
	// how many leading EVM URLs should be round-robin balanced before the
	// remaining public fallbacks.
	AlchemyKeys     []string
	AlchemyURLs     map[string][]string
	AlchemyRPCCount int
	HeliusURL       string
	// HeliusDevnetURL is the Helius endpoint serving sol-devnet history; it
	// shares HeliusKey with the mainnet endpoint.
	HeliusDevnetURL string
	HeliusKey       string

	// GoPlusURL enables independent token threat intelligence. The provider
	// receives only a public chain id and token contract, never a wallet
	// address or transaction. DisableExternalTokenRisk is intended for fully
	// offline/private deployments and deterministic tests.
	GoPlusURL                string
	GoPlusSolanaURL          string
	GoPlusApprovalURL        string
	GoPlusAccessToken        string
	DisableExternalTokenRisk bool
	DisableExternalApprovals bool

	// EVMHistoryFallbackURLs maps network ids to keyless Etherscan-compatible
	// explorer endpoints. A nil map uses the production defaults; an empty
	// non-nil map disables the public fallback (useful for tests/private
	// deployments). Polygon Amoy intentionally has no default because its
	// official explorer requires an API key.
	EVMHistoryFallbackURLs map[string]string

	// OfficialTokens is the operator-controlled verified token catalog. Nil
	// uses the built-in production list; an explicit empty slice disables all
	// verification marks. Production may replace it via OFFICIAL_TOKENS_FILE.
	OfficialTokens []OfficialToken

	// TokenRisks is the operator-controlled denylist for malicious, phishing,
	// spam, impersonating, honeypot or otherwise suspicious contracts/mints.
	// It is deliberately independent from display symbols. An explicit risk
	// entry always wins over an OfficialTokens entry for the same identity.
	TokenRisks []TokenRisk
}

// Defaults returns the production upstream configuration.
func Defaults() Config {
	return Config{
		Version:        "1.16.8",
		Clock:          clock.Real{},
		AttemptTimeout: 10 * time.Second,
		EthURLs:        []string{"https://eth.llamarpc.com", "https://cloudflare-eth.com"},
		PolygonURLs:    []string{"https://polygon-rpc.com", "https://polygon-bor-rpc.publicnode.com"},
		// The newer EVM families default to the same public endpoints the app
		// uses in direct mode (see builtinNetworks in the app's networks.dart),
		// so gateway mode and direct mode read the same chains out of the box.
		BaseURLs:       []string{"https://mainnet.base.org"},
		ArbitrumURLs:   []string{"https://arb1.arbitrum.io/rpc"},
		AvalancheURLs:  []string{"https://api.avax.network/ext/bc/C/rpc"},
		BNBURLs:        []string{"https://bsc-dataseed.bnbchain.org"},
		SolanaURLs:     []string{"https://api.mainnet-beta.solana.com"},
		TronURL:        "https://api.trongrid.io",
		EthSepoliaURLs: []string{"https://ethereum-sepolia-rpc.publicnode.com"},
		// Polygon retired the legacy rpc-amoy.polygon.technology hostname.
		// Keep multiple independently operated endpoints so gateway mode
		// remains usable when one provider is blocked or unhealthy.
		PolygonAmoyURLs: []string{
			"https://polygon-amoy-bor-rpc.publicnode.com",
			"https://polygon-amoy.drpc.org",
		},
		BaseSepoliaURLs:     []string{"https://sepolia.base.org"},
		ArbitrumSepoliaURLs: []string{"https://sepolia-rollup.arbitrum.io/rpc"},
		AvalancheFujiURLs:   []string{"https://api.avax-test.network/ext/bc/C/rpc"},
		BNBTestnetURLs: []string{
			"https://bsc-testnet-dataseed.bnbchain.org",
			"https://bsc-testnet.bnbchain.org",
			"https://bsc-testnet-rpc.publicnode.com",
		},
		SolanaDevnetURLs:  []string{"https://api.devnet.solana.com"},
		TronNileURL:       "https://nile.trongrid.io",
		CoinGeckoURL:      "https://api.coingecko.com",
		CoinGeckoInterval: time.Second,
		EtherscanURL:      "https://api.etherscan.io/v2/api",
		HeliusURL:         "https://mainnet.helius-rpc.com",
		HeliusDevnetURL:   "https://devnet.helius-rpc.com",
		GoPlusURL:         "https://api.gopluslabs.io/api/v1/token_security",
		GoPlusSolanaURL:   "https://api.gopluslabs.io/api/v1/solana/token_security",
		GoPlusApprovalURL: "https://api.gopluslabs.io/api/v2/token_approval_security",
		OfficialTokens:    defaultOfficialTokens(),
		TokenRisks:        []TokenRisk{},
		EVMHistoryFallbackURLs: map[string]string{
			"eth-mainnet":       "https://eth.blockscout.com/api",
			"eth-sepolia":       "https://eth-sepolia.blockscout.com/api",
			"polygon-mainnet":   "https://polygon.blockscout.com/api",
			"base-mainnet":      "https://base.blockscout.com/api",
			"base-sepolia":      "https://base-sepolia.blockscout.com/api",
			"arbitrum-mainnet":  "https://arbitrum.blockscout.com/api",
			"arbitrum-sepolia":  "https://arbitrum-sepolia.blockscout.com/api",
			"avalanche-mainnet": "https://api.routescan.io/v2/network/mainnet/evm/43114/etherscan/api",
			"avalanche-fuji":    "https://api.routescan.io/v2/network/testnet/evm/43113/etherscan/api",
			// Routescan removed BNB Smart Chain 56/97 from its indexed
			// networks. Omitting those fallbacks is deliberate: returning
			// "unsupported" is safer than misreporting a real wallet as
			// having no transactions. Operators can configure Etherscan v2
			// (or another compatible indexer) for BNB history.
		},
	}
}

// Gateway holds the upstream clients and caches behind the kt_* methods.
// Chain-scoped clients are keyed by network id ("eth-mainnet", "tron-nile",
// ...) so every network gets its own pool/circuit state.
type Gateway struct {
	cfg  Config
	clk  clock.Clock
	evm  map[string]*upstream.EVM    // one per EVM network id (eth/polygon/base/arbitrum/avalanche × mainnet/testnet)
	tron map[string]*upstream.Tron   // tron-mainnet, tron-nile
	sol  map[string]*upstream.Solana // sol-mainnet, sol-devnet
	cg   *upstream.CoinGecko
	scan *upstream.Etherscan
	// alchemy is the preferred indexed EVM history source when configured.
	alchemy map[string]*upstream.Alchemy
	// historyScan contains keyless public explorer clients keyed by network.
	// The configured Etherscan v2 client above remains preferred when a key is
	// available because it also covers Polygon Amoy.
	historyScan            map[string]*upstream.Etherscan
	hel                    map[string]*upstream.Helius // sol-mainnet, sol-devnet
	goPlus                 *upstream.GoPlus
	goPlusSolana           *upstream.GoPlusSolana
	goPlusApprovals        *upstream.GoPlusApprovals
	goPlusCircuit          *providerCircuit
	goPlusSolanaCircuit    *providerCircuit
	goPlusApprovalsCircuit *providerCircuit

	priceCache          *cache.Cache
	balanceCache        *cache.Cache
	historyCache        *cache.Cache
	tokenRiskCache      *cache.Cache
	tokenApprovalsCache *cache.Cache

	officialTokens       []OfficialToken
	officialByNetwork    map[string]map[string]tokenMeta
	tokenRisks           map[string]TokenRisk
	tokenRiskMetrics     tokenRiskProviderMetrics
	tokenApprovalMetrics tokenApprovalProviderMetrics
	appDiagnostics       *appDiagnosticMetrics
	broadcastGuard       *broadcastGuard
}

// New builds a Gateway from cfg, filling unset fields from Defaults.
func New(cfg Config) *Gateway {
	def := Defaults()
	if cfg.Version == "" {
		cfg.Version = def.Version
	}
	if cfg.Log == nil {
		cfg.Log = slog.Default()
	}
	if cfg.Clock == nil {
		cfg.Clock = def.Clock
	}
	if cfg.AttemptTimeout <= 0 {
		cfg.AttemptTimeout = def.AttemptTimeout
	}
	if len(cfg.EthURLs) == 0 {
		cfg.EthURLs = def.EthURLs
	}
	if len(cfg.PolygonURLs) == 0 {
		cfg.PolygonURLs = def.PolygonURLs
	}
	if len(cfg.BaseURLs) == 0 {
		cfg.BaseURLs = def.BaseURLs
	}
	if len(cfg.ArbitrumURLs) == 0 {
		cfg.ArbitrumURLs = def.ArbitrumURLs
	}
	if len(cfg.AvalancheURLs) == 0 {
		cfg.AvalancheURLs = def.AvalancheURLs
	}
	if len(cfg.BNBURLs) == 0 {
		cfg.BNBURLs = def.BNBURLs
	}
	if len(cfg.SolanaURLs) == 0 {
		cfg.SolanaURLs = def.SolanaURLs
	}
	if cfg.TronURL == "" {
		cfg.TronURL = def.TronURL
	}
	if len(cfg.EthSepoliaURLs) == 0 {
		cfg.EthSepoliaURLs = def.EthSepoliaURLs
	}
	if len(cfg.PolygonAmoyURLs) == 0 {
		cfg.PolygonAmoyURLs = def.PolygonAmoyURLs
	}
	if len(cfg.BaseSepoliaURLs) == 0 {
		cfg.BaseSepoliaURLs = def.BaseSepoliaURLs
	}
	if len(cfg.ArbitrumSepoliaURLs) == 0 {
		cfg.ArbitrumSepoliaURLs = def.ArbitrumSepoliaURLs
	}
	if len(cfg.AvalancheFujiURLs) == 0 {
		cfg.AvalancheFujiURLs = def.AvalancheFujiURLs
	}
	if len(cfg.BNBTestnetURLs) == 0 {
		cfg.BNBTestnetURLs = def.BNBTestnetURLs
	}
	if len(cfg.SolanaDevnetURLs) == 0 {
		cfg.SolanaDevnetURLs = def.SolanaDevnetURLs
	}
	if cfg.TronNileURL == "" {
		cfg.TronNileURL = def.TronNileURL
	}
	if cfg.CoinGeckoURL == "" {
		cfg.CoinGeckoURL = def.CoinGeckoURL
	}
	if cfg.CoinGeckoInterval <= 0 {
		cfg.CoinGeckoInterval = def.CoinGeckoInterval
	}
	if cfg.EtherscanURL == "" {
		cfg.EtherscanURL = def.EtherscanURL
	}
	if cfg.HeliusURL == "" {
		cfg.HeliusURL = def.HeliusURL
	}
	if cfg.HeliusDevnetURL == "" {
		cfg.HeliusDevnetURL = def.HeliusDevnetURL
	}
	if cfg.GoPlusURL == "" {
		cfg.GoPlusURL = def.GoPlusURL
	}
	if cfg.GoPlusSolanaURL == "" {
		cfg.GoPlusSolanaURL = def.GoPlusSolanaURL
	}
	if cfg.GoPlusApprovalURL == "" {
		cfg.GoPlusApprovalURL = def.GoPlusApprovalURL
	}
	if cfg.EVMHistoryFallbackURLs == nil {
		cfg.EVMHistoryFallbackURLs = def.EVMHistoryFallbackURLs
	}
	if cfg.OfficialTokens == nil {
		cfg.OfficialTokens = def.OfficialTokens
	}
	if cfg.TokenRisks == nil {
		cfg.TokenRisks = def.TokenRisks
	}
	if cfg.AlchemyURLs == nil && len(cfg.AlchemyKeys) > 0 {
		cfg.AlchemyURLs = AlchemyNetworkURLs(cfg.AlchemyKeys)
	}
	officialTokens, err := normalizeOfficialTokens(cfg.OfficialTokens)
	if err != nil {
		// Fail closed: invalid programmatic configuration yields no blue
		// verification marks. The command validates external files before New.
		cfg.Log.Error("invalid official token catalog", "err", err)
		officialTokens = []OfficialToken{}
	}
	tokenRisks, err := normalizeTokenRisks(cfg.TokenRisks)
	if err != nil {
		// Same fail-closed policy as the official catalog: invalid in-process
		// configuration can never accidentally mark an address safe. The
		// command validates external files before constructing the Gateway.
		cfg.Log.Error("invalid token risk registry", "err", err)
		tokenRisks = map[string]TokenRisk{}
	}

	clk := cfg.Clock
	hc := cfg.HTTPClient
	at := cfg.AttemptTimeout
	historyScan := make(map[string]*upstream.Etherscan, len(cfg.EVMHistoryFallbackURLs))
	for network, baseURL := range cfg.EVMHistoryFallbackURLs {
		if baseURL != "" {
			historyScan[network] = upstream.NewEtherscan(baseURL, "", hc, at)
		}
	}
	alchemy := make(map[string]*upstream.Alchemy, len(cfg.AlchemyURLs))
	for network, endpoints := range cfg.AlchemyURLs {
		if len(endpoints) > 0 {
			alchemy[network] = upstream.NewAlchemy(endpoints, hc, at)
		}
	}
	newEVM := func(name string, urls []string) *upstream.EVM {
		return upstream.NewEVMRoundRobin(
			name,
			urls,
			cfg.AlchemyRPCCount,
			clk,
			hc,
			at,
		)
	}
	g := &Gateway{
		cfg: cfg,
		clk: clk,
		evm: map[string]*upstream.EVM{
			"eth-mainnet":       newEVM("eth-mainnet", cfg.EthURLs),
			"eth-sepolia":       newEVM("eth-sepolia", cfg.EthSepoliaURLs),
			"polygon-mainnet":   newEVM("polygon-mainnet", cfg.PolygonURLs),
			"polygon-amoy":      newEVM("polygon-amoy", cfg.PolygonAmoyURLs),
			"base-mainnet":      newEVM("base-mainnet", cfg.BaseURLs),
			"base-sepolia":      newEVM("base-sepolia", cfg.BaseSepoliaURLs),
			"arbitrum-mainnet":  newEVM("arbitrum-mainnet", cfg.ArbitrumURLs),
			"arbitrum-sepolia":  newEVM("arbitrum-sepolia", cfg.ArbitrumSepoliaURLs),
			"avalanche-mainnet": newEVM("avalanche-mainnet", cfg.AvalancheURLs),
			"avalanche-fuji":    newEVM("avalanche-fuji", cfg.AvalancheFujiURLs),
			"bnb-mainnet":       newEVM("bnb-mainnet", cfg.BNBURLs),
			"bnb-testnet":       newEVM("bnb-testnet", cfg.BNBTestnetURLs),
		},
		tron: map[string]*upstream.Tron{
			"tron-mainnet": upstream.NewTron(cfg.TronURL, hc, at),
			"tron-nile":    upstream.NewTron(cfg.TronNileURL, hc, at),
		},
		sol: map[string]*upstream.Solana{
			"sol-mainnet": upstream.NewSolana(cfg.SolanaURLs, clk, hc, at),
			"sol-devnet":  upstream.NewSolana(cfg.SolanaDevnetURLs, clk, hc, at),
		},
		cg:          upstream.NewCoinGecko(cfg.CoinGeckoURL, hc, ratelimit.NewInterval(cfg.CoinGeckoInterval), at),
		scan:        upstream.NewEtherscan(cfg.EtherscanURL, cfg.EtherscanKey, hc, at),
		alchemy:     alchemy,
		historyScan: historyScan,
		hel: map[string]*upstream.Helius{
			"sol-mainnet": upstream.NewHelius(cfg.HeliusURL, cfg.HeliusKey, hc, at),
			"sol-devnet":  upstream.NewHelius(cfg.HeliusDevnetURL, cfg.HeliusKey, hc, at),
		},
		priceCache: cache.NewShared(
			clk,
			pricesTTL,
			cfg.SharedCache,
			"prices",
			cache.JSONPointerCodec[cachedPrices](),
		),
		balanceCache: cache.NewShared(
			clk,
			balancesTTL,
			cfg.SharedCache,
			"balances",
			cache.JSONPointerCodec[balancesResult](),
		),
		historyCache: cache.NewShared(
			clk,
			historyTTL,
			cfg.SharedCache,
			"history",
			cache.JSONPointerCodec[historyResult](),
		),
		tokenRiskCache:      cache.New(clk, tokenRiskTTL),
		tokenApprovalsCache: cache.New(clk, tokenApprovalsTTL),
		officialTokens:      officialTokens,
		officialByNetwork:   officialTokenIndex(officialTokens),
		tokenRisks:          tokenRisks,
		appDiagnostics:      newAppDiagnosticMetrics(),
		broadcastGuard:      newBroadcastGuard(clk, cfg.BroadcastStore),
	}
	if !cfg.DisableExternalTokenRisk {
		g.goPlus = upstream.NewGoPlus(
			cfg.GoPlusURL,
			cfg.GoPlusAccessToken,
			hc,
			at,
		)
		g.goPlusSolana = upstream.NewGoPlusSolana(
			cfg.GoPlusSolanaURL,
			cfg.GoPlusAccessToken,
			hc,
			at,
		)
		g.goPlusCircuit = newProviderCircuit(clk)
		g.goPlusSolanaCircuit = newProviderCircuit(clk)
	}
	if !cfg.DisableExternalApprovals {
		g.goPlusApprovals = upstream.NewGoPlusApprovals(
			cfg.GoPlusApprovalURL,
			cfg.GoPlusAccessToken,
			hc,
			at,
		)
		g.goPlusApprovalsCircuit = newProviderCircuit(clk)
	}
	return g
}

// AlchemyNetworkURLs returns the official JSON-RPC endpoint for each EVM
// network supported by KT Wallet. The returned values contain API keys
// and must never be logged or returned to clients.
func AlchemyNetworkURLs(keys []string) map[string][]string {
	const suffix = ".g.alchemy.com/v2/"
	slugs := map[string]string{
		"eth-mainnet":       "eth-mainnet",
		"eth-sepolia":       "eth-sepolia",
		"polygon-mainnet":   "polygon-mainnet",
		"polygon-amoy":      "polygon-amoy",
		"base-mainnet":      "base-mainnet",
		"base-sepolia":      "base-sepolia",
		"arbitrum-mainnet":  "arb-mainnet",
		"arbitrum-sepolia":  "arb-sepolia",
		"avalanche-mainnet": "avax-mainnet",
		"avalanche-fuji":    "avax-fuji",
		"bnb-mainnet":       "bnb-mainnet",
		"bnb-testnet":       "bnb-testnet",
	}
	urls := make(map[string][]string, len(slugs))
	for network, slug := range slugs {
		for _, key := range keys {
			if key != "" {
				urls[network] = append(urls[network], "https://"+slug+suffix+key)
			}
		}
	}
	return urls
}

// Register binds every kt_* method onto the JSON-RPC server.
func (g *Gateway) Register(s *rpc.Server) {
	s.Register("kt_health", g.Health)
	s.Register("kt_getBalances", g.GetBalances)
	s.Register("kt_getPortfolio", g.GetPortfolio)
	s.Register("kt_getPrices", g.GetPrices)
	s.Register("kt_getChainParams", g.GetChainParams)
	s.Register("kt_simulateEvmTransfer", g.SimulateEVMTransfer)
	s.Register("kt_estimateEvmGas", g.EstimateEVMGas)
	s.Register("kt_getEvmSpendableBalances", g.GetEVMSpendableBalances)
	s.Register("kt_getHistory", g.GetHistory)
	s.Register("kt_getTransactionStatus", g.GetTransactionStatus)
	s.Register("kt_searchTokens", g.SearchOfficialTokens)
	s.Register("kt_checkTokenRisk", g.CheckTokenRisk)
	s.Register("kt_getEvmTokenApprovals", g.GetEVMTokenApprovals)
	s.Register("kt_reportDiagnostics", g.ReportAppDiagnostics)
	s.Register("kt_broadcast", g.Broadcast)
}

// upstreamError maps upstream failures onto the public contract. Client text
// is normalized because net/http errors may contain credential-bearing URLs
// and node messages are untrusted provider input.
func upstreamError(defaultUpstream string, err error) *rpc.Error {
	var ne *upstream.NodeError
	if errors.As(err, &ne) {
		message := upstream.PublicNodeErrorMessage(ne.Message)
		return &rpc.Error{
			Code:    rpc.CodeUpstream,
			Message: message,
			Data:    map[string]string{"upstream": defaultUpstream, "message": message},
		}
	}
	var ua *upstream.Unavailable
	if errors.As(err, &ua) {
		return &rpc.Error{
			Code:    rpc.CodeUpstream,
			Message: "upstream_error",
			Data:    map[string]string{"upstream": defaultUpstream, "message": "upstream temporarily unavailable"},
		}
	}
	return &rpc.Error{
		Code:    rpc.CodeUpstream,
		Message: "upstream_error",
		Data:    map[string]string{"upstream": defaultUpstream, "message": "upstream request failed"},
	}
}
