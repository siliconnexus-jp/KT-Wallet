// Command gateway runs the KT-Wallet chain-query gateway: a JSON-RPC 2.0
// facade over EVM JSON-RPC, TronGrid, Solana JSON-RPC and CoinGecko, with
// caching, failover, rate limiting and API-key shielding.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"ktwallet/gateway/internal/clock"
	"ktwallet/gateway/internal/handlers"
	"ktwallet/gateway/internal/ratelimit"
	"ktwallet/gateway/internal/rpc"
)

const requestBudget = 25 * time.Second

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	slog.SetDefault(log)

	cfg := handlers.Defaults()
	cfg.Log = log
	cfg.HTTPClient = &http.Client{Timeout: 15 * time.Second}
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
	if v := os.Getenv("HELIUS_API_URL"); v != "" {
		cfg.HeliusURL = v
	}
	if v := os.Getenv("HELIUS_DEVNET_API_URL"); v != "" {
		cfg.HeliusDevnetURL = v
	}
	cfg.HeliusKey = os.Getenv("HELIUS_API_KEY")
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

	rate := envFloat("RATE_LIMIT_RPS", 10)
	burst := envFloat("RATE_LIMIT_BURST", 20)
	limiter := ratelimit.New(clock.Real{}, rate, burst)

	gw := handlers.New(cfg)
	server := rpc.NewServer(log, limiter, requestBudget)
	gw.Register(server)

	mux := http.NewServeMux()
	mux.Handle("POST /rpc", server)
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"ok":true}`))
	})

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
