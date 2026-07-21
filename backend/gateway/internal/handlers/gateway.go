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
	pricesTTL      = 30 * time.Second
	balancesTTL    = 10 * time.Second
	chainParamsTTL = 5 * time.Second
	historyTTL     = 30 * time.Second
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

	EthURLs     []string
	PolygonURLs []string
	SolanaURLs  []string
	TronURL     string

	CoinGeckoURL string
	// CoinGeckoInterval spaces outbound CoinGecko calls (default 1s).
	CoinGeckoInterval time.Duration

	EtherscanURL string
	EtherscanKey string
	HeliusURL    string
	HeliusKey    string
}

// Defaults returns the production upstream configuration.
func Defaults() Config {
	return Config{
		Version:           "1.0.0",
		Clock:             clock.Real{},
		AttemptTimeout:    10 * time.Second,
		EthURLs:           []string{"https://eth.llamarpc.com", "https://cloudflare-eth.com"},
		PolygonURLs:       []string{"https://polygon-rpc.com", "https://polygon-bor-rpc.publicnode.com"},
		SolanaURLs:        []string{"https://api.mainnet-beta.solana.com"},
		TronURL:           "https://api.trongrid.io",
		CoinGeckoURL:      "https://api.coingecko.com",
		CoinGeckoInterval: time.Second,
		EtherscanURL:      "https://api.etherscan.io/v2/api",
		HeliusURL:         "https://api.helius.xyz",
	}
}

// Gateway holds the upstream clients and caches behind the kt_* methods.
type Gateway struct {
	cfg  Config
	clk  clock.Clock
	evm  map[string]*upstream.EVM // keyed "eth" / "polygon"
	tron *upstream.Tron
	sol  *upstream.Solana
	cg   *upstream.CoinGecko
	scan *upstream.Etherscan
	hel  *upstream.Helius

	priceCache   *cache.Cache
	balanceCache *cache.Cache
	paramsCache  *cache.Cache
	historyCache *cache.Cache
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
	if len(cfg.SolanaURLs) == 0 {
		cfg.SolanaURLs = def.SolanaURLs
	}
	if cfg.TronURL == "" {
		cfg.TronURL = def.TronURL
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

	clk := cfg.Clock
	hc := cfg.HTTPClient
	at := cfg.AttemptTimeout
	g := &Gateway{
		cfg: cfg,
		clk: clk,
		evm: map[string]*upstream.EVM{
			"eth":     upstream.NewEVM("eth", cfg.EthURLs, clk, hc, at),
			"polygon": upstream.NewEVM("polygon", cfg.PolygonURLs, clk, hc, at),
		},
		tron:         upstream.NewTron(cfg.TronURL, hc, at),
		sol:          upstream.NewSolana(cfg.SolanaURLs, clk, hc, at),
		cg:           upstream.NewCoinGecko(cfg.CoinGeckoURL, hc, ratelimit.NewInterval(cfg.CoinGeckoInterval), at),
		scan:         upstream.NewEtherscan(cfg.EtherscanURL, cfg.EtherscanKey, hc, at),
		hel:          upstream.NewHelius(cfg.HeliusURL, cfg.HeliusKey, hc, at),
		priceCache:   cache.New(clk, pricesTTL),
		balanceCache: cache.New(clk, balancesTTL),
		paramsCache:  cache.New(clk, chainParamsTTL),
		historyCache: cache.New(clk, historyTTL),
	}
	return g
}

// Register binds every kt_* method onto the JSON-RPC server.
func (g *Gateway) Register(s *rpc.Server) {
	s.Register("kt_health", g.Health)
	s.Register("kt_getBalances", g.GetBalances)
	s.Register("kt_getPrices", g.GetPrices)
	s.Register("kt_getChainParams", g.GetChainParams)
	s.Register("kt_getHistory", g.GetHistory)
	s.Register("kt_broadcast", g.Broadcast)
}

// upstreamError maps upstream client failures onto the contract's -32000
// error: message carries the node's own words when the node answered, and
// data always holds {"upstream", "message"}.
func upstreamError(defaultUpstream string, err error) *rpc.Error {
	var ne *upstream.NodeError
	if errors.As(err, &ne) {
		return &rpc.Error{
			Code:    rpc.CodeUpstream,
			Message: ne.Message,
			Data:    map[string]string{"upstream": defaultUpstream, "message": ne.Message},
		}
	}
	var ua *upstream.Unavailable
	if errors.As(err, &ua) {
		return &rpc.Error{
			Code:    rpc.CodeUpstream,
			Message: "upstream_error",
			Data:    map[string]string{"upstream": ua.Upstream, "message": ua.Message},
		}
	}
	return &rpc.Error{
		Code:    rpc.CodeUpstream,
		Message: "upstream_error",
		Data:    map[string]string{"upstream": defaultUpstream, "message": err.Error()},
	}
}
