package handlers_test

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestHealthGolden(t *testing.T) {
	e := newEnv(t, nil)
	resp := e.rpc("kt_health", nil)
	res := result(t, resp)
	if res["ok"] != true || res["version"] != "9.9.9-test" {
		t.Fatalf("unexpected health identity: %v", res)
	}
	assertJSONEq(t, `[
			"eth-mainnet","eth-sepolia","polygon-mainnet","polygon-amoy",
			"base-mainnet","base-sepolia","arbitrum-mainnet","arbitrum-sepolia",
			"avalanche-mainnet","avalanche-fuji",
			"bnb-mainnet","bnb-testnet",
			"tron-mainnet","tron-nile","sol-mainnet","sol-devnet"]`,
		res["networks"])
	upstreams, ok := res["upstreams"].(map[string]any)
	if !ok || len(upstreams) != 14 {
		t.Fatalf("expected 12 EVM + 2 Solana pool summaries, got %T %v", res["upstreams"], res["upstreams"])
	}
	for _, network := range []string{"eth-mainnet", "polygon-amoy", "bnb-testnet", "sol-devnet"} {
		row, ok := upstreams[network].(map[string]any)
		if !ok || row["endpoints"].(float64) < 1 || row["openCircuits"].(float64) != 0 {
			t.Fatalf("bad upstream summary for %s: %v", network, upstreams[network])
		}
		if row["latencyP50Ms"] == nil || row["latencyP95Ms"] == nil ||
			row["failureMetrics"] == nil || row["endpointMetrics"] == nil {
			t.Fatalf("missing observability fields for %s: %v", network, row)
		}
	}
	encoded, err := json.Marshal(res)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(encoded), "127.0.0.1") ||
		strings.Contains(string(encoded), "http://") {
		t.Fatalf("health response leaked endpoint URL: %s", encoded)
	}
}

func TestHealthIgnoresParams(t *testing.T) {
	e := newEnv(t, nil)
	resp := e.rpc("kt_health", `{"anything":"goes"}`)
	if result(t, resp)["ok"] != true {
		t.Fatal("kt_health must succeed regardless of params")
	}
}

func TestReadinessStartsReadyWithoutPerformingProbeIO(t *testing.T) {
	e := newEnv(t, nil)
	ready, unavailable := e.gw.Readiness()
	if !ready || len(unavailable) != 0 {
		t.Fatalf("fresh configured pools should be ready: ready=%v unavailable=%v", ready, unavailable)
	}
}

func TestReadinessReportsSingleNetworkDegradationWithoutCascadingOutage(t *testing.T) {
	e := newEnv(t, nil)
	for range 3 {
		e.rpc("kt_getBalances", balancesParams("eth", evmSelf, ""))
	}

	ready, unavailable := e.gw.Readiness()
	if !ready || len(unavailable) != 1 || unavailable[0] != "eth-mainnet" {
		t.Fatalf("single-chain outage must remain partially ready: ready=%v unavailable=%v", ready, unavailable)
	}
}

func TestReadinessFailsOnlyWhenEveryJSONRPCNetworkIsUnavailable(t *testing.T) {
	e := newEnv(t, nil)
	networks := []struct {
		chain   string
		network string
		address string
	}{
		{"eth", "eth-mainnet", evmSelf},
		{"eth", "eth-sepolia", evmSelf},
		{"polygon", "polygon-mainnet", evmSelf},
		{"polygon", "polygon-amoy", evmSelf},
		{"base", "base-mainnet", evmSelf},
		{"base", "base-sepolia", evmSelf},
		{"arbitrum", "arbitrum-mainnet", evmSelf},
		{"arbitrum", "arbitrum-sepolia", evmSelf},
		{"avalanche", "avalanche-mainnet", evmSelf},
		{"avalanche", "avalanche-fuji", evmSelf},
		{"bnb", "bnb-mainnet", evmSelf},
		{"bnb", "bnb-testnet", evmSelf},
		{"solana", "sol-mainnet", solSelf},
		{"solana", "sol-devnet", solSelf},
	}
	for _, target := range networks {
		params := map[string]any{
			"chain":   target.chain,
			"network": target.network,
			"address": target.address,
		}
		for range 3 {
			e.rpc("kt_getBalances", params)
		}
	}

	ready, unavailable := e.gw.Readiness()
	if ready || len(unavailable) != len(networks) {
		t.Fatalf("all-network outage must fail readiness: ready=%v unavailable=%v", ready, unavailable)
	}
}
