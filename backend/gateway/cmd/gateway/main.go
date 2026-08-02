// Command gateway runs the KT-Wallet chain-query gateway: a JSON-RPC 2.0
// facade over EVM JSON-RPC, TronGrid, Solana JSON-RPC and CoinGecko, with
// caching, failover, rate limiting and API-key shielding.
package main

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"ktwallet/gateway/internal/cache"
	"ktwallet/gateway/internal/clock"
	"ktwallet/gateway/internal/handlers"
	"ktwallet/gateway/internal/ratelimit"
	"ktwallet/gateway/internal/rpc"
	"ktwallet/gateway/internal/upstream"
)

const requestBudget = 25 * time.Second

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	slog.SetDefault(log)

	cfg := handlers.Defaults()
	cfg.Log = log
	cfg.HTTPClient = &http.Client{Timeout: 15 * time.Second}
	var sharedCache *cache.RedisStore
	if rawURL := strings.TrimSpace(os.Getenv("REDIS_URL")); rawURL != "" {
		var err error
		sharedCache, err = cache.NewRedisStore(rawURL)
		if err != nil {
			log.Error("invalid shared cache configuration", "err", err)
			os.Exit(1)
		}
		pingCtx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		err = sharedCache.Ping(pingCtx)
		cancel()
		if err != nil {
			log.Error("shared cache unavailable", "err", err)
			os.Exit(1)
		}
		cfg.SharedCache = sharedCache
		cfg.BroadcastStore = sharedCache
		defer func() { _ = sharedCache.Close() }()
		log.Info("shared cache enabled")
	}
	if v := envList("ETH_RPC_URLS"); len(v) > 0 {
		cfg.EthURLs = v
	}
	if v := envList("POLYGON_RPC_URLS"); len(v) > 0 {
		cfg.PolygonURLs = v
	}
	if v := envList("BASE_RPC_URLS"); len(v) > 0 {
		cfg.BaseURLs = v
	}
	if v := envList("ARBITRUM_RPC_URLS"); len(v) > 0 {
		cfg.ArbitrumURLs = v
	}
	if v := envList("AVALANCHE_RPC_URLS"); len(v) > 0 {
		cfg.AvalancheURLs = v
	}
	if v := envList("BNB_RPC_URLS"); len(v) > 0 {
		cfg.BNBURLs = v
	}
	if v := envList("SOLANA_RPC_URLS"); len(v) > 0 {
		cfg.SolanaURLs = v
	}
	if v := os.Getenv("TRON_API_URL"); v != "" {
		cfg.TronURL = v
	}
	if v := envList("ETH_SEPOLIA_RPC_URLS"); len(v) > 0 {
		cfg.EthSepoliaURLs = v
	}
	if v := envList("POLYGON_AMOY_RPC_URLS"); len(v) > 0 {
		cfg.PolygonAmoyURLs = v
	}
	if v := envList("BASE_SEPOLIA_RPC_URLS"); len(v) > 0 {
		cfg.BaseSepoliaURLs = v
	}
	if v := envList("ARBITRUM_SEPOLIA_RPC_URLS"); len(v) > 0 {
		cfg.ArbitrumSepoliaURLs = v
	}
	if v := envList("AVALANCHE_FUJI_RPC_URLS"); len(v) > 0 {
		cfg.AvalancheFujiURLs = v
	}
	if v := envList("BNB_TESTNET_RPC_URLS"); len(v) > 0 {
		cfg.BNBTestnetURLs = v
	}
	if v := envList("SOLANA_DEVNET_RPC_URLS"); len(v) > 0 {
		cfg.SolanaDevnetURLs = v
	}
	if v := os.Getenv("TRON_NILE_API_URL"); v != "" {
		cfg.TronNileURL = v
	}
	if v := os.Getenv("COINGECKO_API_URL"); v != "" {
		cfg.CoinGeckoURL = v
	}
	if v := os.Getenv("ETHERSCAN_API_URL"); v != "" {
		cfg.EtherscanURL = v
	}
	cfg.EtherscanKey = os.Getenv("ETHERSCAN_API_KEY")
	cfg.AlchemyKeys = envList("ALCHEMY_API_KEYS")
	if len(cfg.AlchemyKeys) == 0 {
		if legacy := strings.TrimSpace(os.Getenv("ALCHEMY_API_KEY")); legacy != "" {
			cfg.AlchemyKeys = []string{legacy}
		}
	}
	if len(cfg.AlchemyKeys) > 0 {
		alchemy := handlers.AlchemyNetworkURLs(cfg.AlchemyKeys)
		cfg.AlchemyRPCCount = len(cfg.AlchemyKeys)
		cfg.EthURLs = prependURLs(alchemy["eth-mainnet"], cfg.EthURLs)
		cfg.EthSepoliaURLs = prependURLs(alchemy["eth-sepolia"], cfg.EthSepoliaURLs)
		cfg.PolygonURLs = prependURLs(alchemy["polygon-mainnet"], cfg.PolygonURLs)
		cfg.PolygonAmoyURLs = prependURLs(alchemy["polygon-amoy"], cfg.PolygonAmoyURLs)
		cfg.BaseURLs = prependURLs(alchemy["base-mainnet"], cfg.BaseURLs)
		cfg.BaseSepoliaURLs = prependURLs(alchemy["base-sepolia"], cfg.BaseSepoliaURLs)
		cfg.ArbitrumURLs = prependURLs(alchemy["arbitrum-mainnet"], cfg.ArbitrumURLs)
		cfg.ArbitrumSepoliaURLs = prependURLs(alchemy["arbitrum-sepolia"], cfg.ArbitrumSepoliaURLs)
		cfg.AvalancheURLs = prependURLs(alchemy["avalanche-mainnet"], cfg.AvalancheURLs)
		cfg.AvalancheFujiURLs = prependURLs(alchemy["avalanche-fuji"], cfg.AvalancheFujiURLs)
		cfg.BNBURLs = prependURLs(alchemy["bnb-mainnet"], cfg.BNBURLs)
		cfg.BNBTestnetURLs = prependURLs(alchemy["bnb-testnet"], cfg.BNBTestnetURLs)
	}
	if v := os.Getenv("HELIUS_API_URL"); v != "" {
		cfg.HeliusURL = v
	}
	if v := os.Getenv("HELIUS_DEVNET_API_URL"); v != "" {
		cfg.HeliusDevnetURL = v
	}
	cfg.HeliusKey = os.Getenv("HELIUS_API_KEY")
	if v := strings.TrimSpace(os.Getenv("GOPLUS_API_URL")); v != "" {
		cfg.GoPlusURL = v
	}
	if v := strings.TrimSpace(os.Getenv("GOPLUS_SOLANA_API_URL")); v != "" {
		cfg.GoPlusSolanaURL = v
	}
	if v := strings.TrimSpace(os.Getenv("GOPLUS_APPROVAL_API_URL")); v != "" {
		cfg.GoPlusApprovalURL = v
	}
	cfg.GoPlusAccessToken = strings.TrimSpace(os.Getenv("GOPLUS_ACCESS_TOKEN"))
	if v := strings.TrimSpace(os.Getenv("DISABLE_EXTERNAL_TOKEN_RISK")); v != "" {
		disabled, err := strconv.ParseBool(v)
		if err != nil {
			log.Error("invalid external token risk configuration")
			os.Exit(1)
		}
		cfg.DisableExternalTokenRisk = disabled
	}
	if v := strings.TrimSpace(os.Getenv("DISABLE_EXTERNAL_APPROVAL_LOOKUP")); v != "" {
		disabled, err := strconv.ParseBool(v)
		if err != nil {
			log.Error("invalid external approval lookup configuration")
			os.Exit(1)
		}
		cfg.DisableExternalApprovals = disabled
	}
	if !cfg.DisableExternalTokenRisk {
		if err := upstream.ValidateGoPlusURL(cfg.GoPlusURL); err != nil {
			log.Error("invalid external token risk configuration", "err", err)
			os.Exit(1)
		}
	}
	if !cfg.DisableExternalApprovals {
		if err := upstream.ValidateGoPlusURL(cfg.GoPlusApprovalURL); err != nil {
			log.Error("invalid external approval lookup configuration", "err", err)
			os.Exit(1)
		}
	}
	if path := strings.TrimSpace(os.Getenv("OFFICIAL_TOKENS_FILE")); path != "" {
		tokens, err := handlers.LoadOfficialTokensFile(path)
		if err != nil {
			log.Error(
				"failed to load official token catalog",
				"path",
				path,
				"err",
				err,
			)
			os.Exit(1)
		}
		cfg.OfficialTokens = tokens
	}
	if path := strings.TrimSpace(os.Getenv("TOKEN_RISKS_FILE")); path != "" {
		risks, err := handlers.LoadTokenRisksFile(path)
		if err != nil {
			log.Error(
				"failed to load token risk registry",
				"path",
				path,
				"err",
				err,
			)
			os.Exit(1)
		}
		cfg.TokenRisks = risks
	}

	rate := envFloat("RATE_LIMIT_RPS", 10)
	burst := envFloat("RATE_LIMIT_BURST", 20)
	limiter := ratelimit.New(clock.Real{}, rate, burst)

	gw := handlers.New(cfg)
	server := rpc.NewServer(log, limiter, requestBudget)
	trustedProxyCIDRs := strings.TrimSpace(os.Getenv("TRUSTED_PROXY_CIDRS"))
	if err := server.SetTrustedProxyCIDRs(trustedProxyCIDRs); err != nil {
		log.Error("invalid trusted proxy configuration", "err", err)
		os.Exit(1)
	}
	gw.Register(server)
	metricsToken, err := validateMetricsBearerToken(
		os.Getenv("METRICS_BEARER_TOKEN"),
	)
	if err != nil {
		log.Error("invalid metrics authentication configuration", "err", err)
		os.Exit(1)
	}

	mux := http.NewServeMux()
	mux.Handle("POST /rpc", server)
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"ok":true}`))
	})
	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		ready, unavailable := gw.Readiness()
		if !ready {
			w.WriteHeader(http.StatusServiceUnavailable)
		}
		_ = json.NewEncoder(w).Encode(map[string]any{
			"ok":                  ready,
			"ready":               ready,
			"unavailableNetworks": unavailable,
		})
	})
	mux.HandleFunc("GET /metrics", metricsHandler(gw.Metrics, metricsToken))

	addr := os.Getenv("GATEWAY_ADDR")
	if addr == "" {
		addr = ":8080"
	}
	httpServer := &http.Server{
		Addr:              addr,
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      requestBudget + 5*time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	errCh := make(chan error, 1)
	go func() { errCh <- httpServer.ListenAndServe() }()
	log.Info("gateway listening", "addr", addr, "version", cfg.Version)

	select {
	case <-ctx.Done():
		log.Info("shutting down")
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = httpServer.Shutdown(shutdownCtx)
	case err := <-errCh:
		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Error("server failed", "err", err)
			os.Exit(1)
		}
	}
}

func envList(key string) []string {
	raw := os.Getenv(key)
	if raw == "" {
		return nil
	}
	parts := strings.Split(raw, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		if s := strings.TrimSpace(p); s != "" {
			out = append(out, s)
		}
	}
	return out
}

func envFloat(key string, def float64) float64 {
	raw := os.Getenv(key)
	if raw == "" {
		return def
	}
	v, err := strconv.ParseFloat(raw, 64)
	if err != nil || v <= 0 {
		slog.Warn("ignoring invalid env value", "key", key, "value", raw)
		return def
	}
	return v
}

func validateMetricsBearerToken(raw string) (string, error) {
	token := strings.TrimSpace(raw)
	if token == "" {
		return "", nil
	}
	if len(token) < 32 {
		return "", fmt.Errorf("METRICS_BEARER_TOKEN must contain at least 32 bytes")
	}
	return token, nil
}

func hasValidMetricsBearer(r *http.Request, token string) bool {
	if token == "" {
		return false
	}
	provided := r.Header.Get("Authorization")
	expected := "Bearer " + token
	if len(provided) != len(expected) {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(provided), []byte(expected)) == 1
}

func metricsHandler(metrics func() string, token string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !hasValidMetricsBearer(r, token) {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
		_, _ = w.Write([]byte(metrics()))
	}
}

func prependURLs(primaries, fallbacks []string) []string {
	if len(primaries) == 0 {
		return fallbacks
	}
	out := make([]string, 0, len(fallbacks)+len(primaries))
	out = append(out, primaries...)
	for _, fallback := range fallbacks {
		duplicate := false
		for _, primary := range primaries {
			if fallback == primary {
				duplicate = true
				break
			}
		}
		if !duplicate {
			out = append(out, fallback)
		}
	}
	return out
}
