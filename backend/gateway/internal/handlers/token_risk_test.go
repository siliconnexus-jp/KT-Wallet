package handlers_test

import (
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"ktwallet/gateway/internal/handlers"
	"ktwallet/gateway/internal/rpc"
)

func TestCheckTokenRiskReturnsUnsafeSafeAndUnknown(t *testing.T) {
	const risky = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.TokenRisks = []handlers.TokenRisk{{
			Network: "eth-mainnet", Contract: risky, Category: "phishing",
		}}
	})

	unsafe := result(t, e.rpc("kt_checkTokenRisk", map[string]any{
		"chain": "eth", "network": "eth-mainnet", "contract": risky,
	}))
	if unsafe["status"] != "unsafe" || unsafe["category"] != "phishing" {
		t.Fatalf("unsafe result = %v", unsafe)
	}

	const usdt = "0xdac17f958d2ee523a2206206994597c13d831ec7"
	safe := result(t, e.rpc("kt_checkTokenRisk", map[string]any{
		"chain": "eth", "network": "eth-mainnet", "contract": usdt,
	}))
	if safe["status"] != "safe" || safe["source"] != "official_catalog" {
		t.Fatalf("safe result = %v", safe)
	}

	unknown := result(t, e.rpc("kt_checkTokenRisk", map[string]any{
		"chain": "eth", "network": "eth-mainnet",
		"contract": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
	}))
	if unknown["status"] != "unknown" {
		t.Fatalf("unknown result = %v", unknown)
	}
}

func TestCheckTokenRiskBindsEveryResultToTheRequestedIdentity(t *testing.T) {
	const contract = "0xdac17f958d2ee523a2206206994597c13d831ec7"
	e := newEnv(t, nil)
	got := result(t, e.rpc("kt_checkTokenRisk", map[string]any{
		"chain": "eth", "network": "eth-mainnet", "contract": contract,
	}))
	if got["network"] != "eth-mainnet" || got["contract"] != contract {
		t.Fatalf("risk identity = %v, want exact eth-mainnet + contract", got)
	}
}

func TestCheckTokenRiskUsesIndependentProviderAndCachesExplicitThreat(t *testing.T) {
	const risky = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	provider := newRESTFake(t)
	provider.route("/1", func(w http.ResponseWriter, r *http.Request) {
		if got := r.URL.Query().Get("contract_addresses"); got != risky {
			t.Fatalf("provider contract = %q", got)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"code":1,"result":{"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa":{"is_honeypot":"1"}}}`))
	})
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.DisableExternalTokenRisk = false
		cfg.GoPlusURL = provider.srv.URL
	})

	for range 2 {
		got := result(t, e.rpc("kt_checkTokenRisk", map[string]any{
			"chain": "eth", "network": "eth-mainnet", "contract": risky,
		}))
		if got["status"] != "unsafe" || got["category"] != "honeypot" || got["source"] != "goplus" {
			t.Fatalf("provider result = %v", got)
		}
	}
	if hits := provider.hitCount("/1"); hits != 1 {
		t.Fatalf("provider hits = %d, want one cached lookup", hits)
	}
	metrics := e.gw.Metrics()
	for _, want := range []string{
		"kt_gateway_token_risk_provider_enabled 1",
		`kt_gateway_token_risk_provider_operations_total{outcome="lookup"} 1`,
		`kt_gateway_token_risk_provider_operations_total{outcome="unsafe"} 1`,
		`kt_gateway_token_risk_provider_operations_total{outcome="cache_hit"} 1`,
	} {
		if !strings.Contains(metrics, want) {
			t.Fatalf("metrics missing %q:\n%s", want, metrics)
		}
	}
}

func TestCheckTokenRiskProviderNoEvidenceStaysUnknown(t *testing.T) {
	provider := newRESTFake(t)
	provider.routeJSON("/56", `{"code":1,"result":{"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb":{"is_honeypot":"0","is_mintable":"1","is_blacklisted":"1"}}}`)
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.DisableExternalTokenRisk = false
		cfg.GoPlusURL = provider.srv.URL
	})
	got := result(t, e.rpc("kt_checkTokenRisk", map[string]any{
		"chain": "bnb", "network": "bnb-mainnet",
		"contract": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
	}))
	if got["status"] != "unknown" || got["source"] != "goplus" {
		t.Fatalf("provider no-evidence result = %v", got)
	}
}

func TestCheckTokenRiskUsesSolanaProviderWithoutMisclassifyingLegitimateAuthorities(t *testing.T) {
	const usdc = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
	const bonk = "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"
	provider := newRESTFake(t)
	provider.route("/", func(w http.ResponseWriter, r *http.Request) {
		mint := r.URL.Query().Get("contract_addresses")
		switch mint {
		case usdc:
			_, _ = w.Write([]byte(`{"code":1,"result":{"` + usdc + `":{
              "mintable":{"status":"1","authority":[{"malicious_address":0}]},
              "freezable":{"status":"1","authority":[{"malicious_address":"0"}]}
            }}}`))
		case bonk:
			_, _ = w.Write([]byte(`{"code":1,"result":{"` + bonk + `":{
              "metadata_mutable":{"metadata_upgrade_authority":[{"malicious_address":"1"}]}
            }}}`))
		default:
			t.Fatalf("unexpected Solana mint %q", mint)
		}
	})
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.DisableExternalTokenRisk = false
		cfg.GoPlusSolanaURL = provider.srv.URL
	})

	for range 2 {
		got := result(t, e.rpc("kt_checkTokenRisk", map[string]any{
			"chain": "solana", "network": "sol-mainnet", "contract": usdc,
		}))
		if got["status"] != "safe" || got["source"] != "official_catalog+goplus" {
			t.Fatalf("legitimate Solana authority result = %v", got)
		}
	}
	got := result(t, e.rpc("kt_checkTokenRisk", map[string]any{
		"chain": "solana", "network": "sol-mainnet", "contract": bonk,
	}))
	if got["status"] != "unsafe" || got["category"] != "malicious" || got["source"] != "goplus" {
		t.Fatalf("explicit Solana authority threat = %v", got)
	}
	if hits := provider.hitCount("/"); hits != 2 {
		t.Fatalf("Solana provider hits = %d, want two identities with USDC cached", hits)
	}
}

func TestCheckTokenRiskProviderFailureIsUnavailableNotUnknownOrSafe(t *testing.T) {
	provider := newRESTFake(t)
	provider.route("/1", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusTooManyRequests)
		_, _ = w.Write([]byte("private provider detail"))
	})
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.DisableExternalTokenRisk = false
		cfg.GoPlusURL = provider.srv.URL
	})
	err := assertErrCode(t, e.rpc("kt_checkTokenRisk", map[string]any{
		"chain": "eth", "network": "eth-mainnet",
		"contract": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
	}), rpc.CodeUpstream)
	data := errData(t, err)
	if data["upstream"] != "goplus" || strings.Contains(data["message"].(string), "private provider detail") {
		t.Fatalf("unsafe provider error data = %v", data)
	}
}

func TestCheckTokenRiskProviderCircuitFailsClosedAndRecovers(t *testing.T) {
	const contract = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
	provider := newRESTFake(t)
	provider.route("/1", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusTooManyRequests)
	})
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.DisableExternalTokenRisk = false
		cfg.GoPlusURL = provider.srv.URL
	})

	for range 4 {
		assertErrCode(t, e.rpc("kt_checkTokenRisk", map[string]any{
			"chain": "eth", "network": "eth-mainnet", "contract": contract,
		}), rpc.CodeUpstream)
	}
	if hits := provider.hitCount("/1"); hits != 3 {
		t.Fatalf("open circuit must short-circuit the fourth request, hits = %d", hits)
	}
	metrics := e.gw.Metrics()
	for _, want := range []string{
		`kt_gateway_external_provider_circuit_open{provider="token_risk_evm"} 1`,
		`kt_gateway_external_provider_circuit_short_circuits_total{provider="token_risk_evm"} 1`,
		`kt_gateway_token_risk_provider_operations_total{outcome="lookup"} 3`,
		`kt_gateway_token_risk_provider_operations_total{outcome="error"} 3`,
	} {
		if !strings.Contains(metrics, want) {
			t.Fatalf("metrics missing %q:\n%s", want, metrics)
		}
	}

	provider.routeJSON("/1", `{"code":1,"result":{"`+contract+`":{"is_honeypot":"0"}}}`)
	e.clk.Advance(31 * time.Second)
	got := result(t, e.rpc("kt_checkTokenRisk", map[string]any{
		"chain": "eth", "network": "eth-mainnet", "contract": contract,
	}))
	if got["status"] != "unknown" {
		t.Fatalf("recovery result = %v", got)
	}
	if hits := provider.hitCount("/1"); hits != 4 {
		t.Fatalf("half-open recovery probe hits = %d, want 4", hits)
	}
	if metrics := e.gw.Metrics(); !strings.Contains(
		metrics,
		`kt_gateway_external_provider_circuit_open{provider="token_risk_evm"} 0`,
	) {
		t.Fatalf("successful probe did not close circuit:\n%s", metrics)
	}
}

func TestCheckSolanaTokenRiskProviderFailureIsUnavailableNotUnknownOrSafe(t *testing.T) {
	provider := newRESTFake(t)
	provider.route("/", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusTooManyRequests)
		_, _ = w.Write([]byte("private Solana provider detail"))
	})
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.DisableExternalTokenRisk = false
		cfg.GoPlusSolanaURL = provider.srv.URL
	})
	err := assertErrCode(t, e.rpc("kt_checkTokenRisk", map[string]any{
		"chain": "solana", "network": "sol-mainnet",
		"contract": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
	}), rpc.CodeUpstream)
	data := errData(t, err)
	if data["upstream"] != "goplus-solana" ||
		strings.Contains(data["message"].(string), "private Solana provider detail") {
		t.Fatalf("unsafe Solana provider error data = %v", data)
	}
}

func TestSolanaProviderIsMainnetOnlyAndOperatorRiskStillPrecedesIt(t *testing.T) {
	const usdc = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
	const risky = "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"
	provider := newRESTFake(t)
	provider.routeJSON("/", `{"code":1,"result":{}}`)
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.DisableExternalTokenRisk = false
		cfg.GoPlusSolanaURL = provider.srv.URL
		cfg.TokenRisks = []handlers.TokenRisk{{
			Network: "sol-mainnet", Contract: risky, Category: "spam",
		}}
	})

	devnet := result(t, e.rpc("kt_checkTokenRisk", map[string]any{
		"chain": "solana", "network": "sol-devnet", "contract": usdc,
	}))
	if devnet["status"] == "unsafe" {
		t.Fatalf("devnet must not inherit mainnet provider evidence: %v", devnet)
	}
	blocked := result(t, e.rpc("kt_checkTokenRisk", map[string]any{
		"chain": "solana", "network": "sol-mainnet", "contract": risky,
	}))
	if blocked["status"] != "unsafe" || blocked["source"] != "operator_registry" {
		t.Fatalf("operator Solana risk = %v", blocked)
	}
	if hits := provider.hitCount("/"); hits != 0 {
		t.Fatalf("devnet and operator risk must not call mainnet provider, hits = %d", hits)
	}
}

func TestOperatorRiskPrecedesExternalProvider(t *testing.T) {
	provider := newRESTFake(t)
	provider.routeJSON("/", `{"code":1,"result":{}}`)
	const risky = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.DisableExternalTokenRisk = false
		cfg.GoPlusURL = provider.srv.URL
		cfg.TokenRisks = []handlers.TokenRisk{{
			Network: "eth-mainnet", Contract: risky, Category: "phishing",
		}}
	})
	_ = result(t, e.rpc("kt_checkTokenRisk", map[string]any{
		"chain": "eth", "network": "eth-mainnet", "contract": risky,
	}))
	if hits := provider.hitCount("/"); hits != 0 {
		t.Fatalf("provider must not override the operator emergency registry, hits = %d", hits)
	}
}

func TestExternalExplicitThreatOverridesOfficialIdentity(t *testing.T) {
	const usdt = "0xdac17f958d2ee523a2206206994597c13d831ec7"
	provider := newRESTFake(t)
	provider.routeJSON("/1", `{"code":1,"result":{"0xdac17f958d2ee523a2206206994597c13d831ec7":{"fake_token":"1"}}}`)
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.DisableExternalTokenRisk = false
		cfg.GoPlusURL = provider.srv.URL
	})
	got := result(t, e.rpc("kt_checkTokenRisk", map[string]any{
		"chain": "eth", "network": "eth-mainnet", "contract": usdt,
	}))
	if got["status"] != "unsafe" || got["category"] != "impersonation" || got["source"] != "goplus" {
		t.Fatalf("external threat must override official identity: %v", got)
	}
}

func TestOfficialIdentityIsSafeOnlyAfterExternalCheckFindsNoExplicitThreat(t *testing.T) {
	const usdt = "0xdac17f958d2ee523a2206206994597c13d831ec7"
	provider := newRESTFake(t)
	provider.routeJSON("/1", `{"code":1,"result":{"0xdac17f958d2ee523a2206206994597c13d831ec7":{"is_honeypot":"0","is_mintable":"1"}}}`)
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.DisableExternalTokenRisk = false
		cfg.GoPlusURL = provider.srv.URL
	})
	got := result(t, e.rpc("kt_checkTokenRisk", map[string]any{
		"chain": "eth", "network": "eth-mainnet", "contract": usdt,
	}))
	if got["status"] != "safe" || got["source"] != "official_catalog+goplus" {
		t.Fatalf("official externally checked result = %v", got)
	}
}

func TestTokenRiskOverridesOfficialCatalog(t *testing.T) {
	const usdt = "0xdac17f958d2ee523a2206206994597c13d831ec7"
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.TokenRisks = []handlers.TokenRisk{{
			Network: "eth-mainnet", Contract: usdt, Category: "suspicious",
		}}
	})
	got := result(t, e.rpc("kt_checkTokenRisk", map[string]any{
		"chain": "eth", "network": "eth-mainnet", "contract": usdt,
	}))
	if got["status"] != "unsafe" || got["category"] != "suspicious" {
		t.Fatalf("risk registry must override official catalog: %v", got)
	}
}

func TestCheckTokenRiskValidatesNetworkAndContract(t *testing.T) {
	e := newEnv(t, nil)
	assertErrCode(t, e.rpc("kt_checkTokenRisk", map[string]any{
		"chain": "eth", "network": "sol-mainnet",
		"contract": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
	}), rpc.CodeInvalidParams)
	assertErrCode(t, e.rpc("kt_checkTokenRisk", map[string]any{
		"chain": "eth", "network": "eth-mainnet", "contract": "not-an-address",
	}), rpc.CodeInvalidParams)
}

func TestLoadTokenRisksFileRejectsPartialOrAmbiguousRegistry(t *testing.T) {
	dir := t.TempDir()
	validPath := filepath.Join(dir, "valid.json")
	if err := os.WriteFile(validPath, []byte(`[
  {"network":"eth-mainnet","contract":"0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","category":"PHISHING"}
]`), 0o600); err != nil {
		t.Fatal(err)
	}
	entries, err := handlers.LoadTokenRisksFile(validPath)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 || entries[0].Contract != "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" || entries[0].Category != "phishing" {
		t.Fatalf("normalized entries = %#v", entries)
	}

	for name, body := range map[string]string{
		"not-array":    `{}`,
		"bad-category": `[{"network":"eth-mainnet","contract":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","category":"safe"}]`,
		"duplicate": `[
 {"network":"eth-mainnet","contract":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","category":"spam"},
 {"network":"eth-mainnet","contract":"0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","category":"phishing"}
]`,
	} {
		path := filepath.Join(dir, name+".json")
		if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
			t.Fatal(err)
		}
		if _, err := handlers.LoadTokenRisksFile(path); err == nil {
			t.Errorf("%s must reject the full registry", name)
		}
	}
}

func TestCheckedInTokenRiskRegistryLoads(t *testing.T) {
	entries, err := handlers.LoadTokenRisksFile(
		filepath.Join("..", "..", "config", "token-risks.json"),
	)
	if err != nil {
		t.Fatal(err)
	}
	if entries == nil {
		t.Fatal("checked-in registry must be an explicit JSON array")
	}
}
