package handlers_test

import (
	"net/http"
	"strings"
	"testing"
	"time"

	"ktwallet/gateway/internal/handlers"
	"ktwallet/gateway/internal/rpc"
)

const approvalOwner = "0x85f6be9460291e86e0fb49b07d0a83cc5f7206cd"

func TestTokenApprovalsRequireExplicitConsentBeforeProviderRequest(t *testing.T) {
	provider := newRESTFake(t)
	provider.routeJSON("/1", `{"code":1,"result":[]}`)
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.DisableExternalApprovals = false
		cfg.GoPlusApprovalURL = provider.srv.URL
	})
	assertErrCode(t, e.rpc("kt_getEvmTokenApprovals", map[string]any{
		"chain": "eth", "network": "eth-mainnet", "address": approvalOwner,
	}), rpc.CodeInvalidParams)
	if hits := provider.hitCount("/1"); hits != 0 {
		t.Fatalf("provider contacted without consent: %d", hits)
	}
}

func TestTokenApprovalsReturnSanitizedRiskRowsAndUseLocalCache(t *testing.T) {
	provider := newRESTFake(t)
	provider.route("/1", func(w http.ResponseWriter, r *http.Request) {
		if got := r.URL.Query().Get("addresses"); got != approvalOwner {
			t.Fatalf("addresses = %q", got)
		}
		if len(r.URL.Query()) != 1 {
			t.Fatalf("unexpected query = %v", r.URL.Query())
		}
		_, _ = w.Write([]byte(`{"code":1,"result":[{
	          "token_address":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
	          "chain_id":"1","token_name":"Token","token_symbol":"TOK","decimals":18,"balance":"5",
	          "is_open_source":1,
	          "malicious_address":0,"malicious_behavior":[],"approved_list":[{
	            "approved_contract":"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
	            "approved_amount":"Unlimited","approved_time":1700000000,
	            "initial_approval_time":1699999999,
	            "initial_approval_hash":"0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
	            "hash":"0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
	            "address_info":{"contract_name":"Router","tag":"Example",
	              "creator_address":"0xdddddddddddddddddddddddddddddddddddddddd","is_contract":1,
	              "doubt_list":1,"malicious_behavior":["phishing"],"deployed_time":1600000000,
	              "trust_list":0,"is_open_source":1}}]}]}`))
	})
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.DisableExternalApprovals = false
		cfg.GoPlusApprovalURL = provider.srv.URL
	})

	for range 2 {
		got := result(t, e.rpc("kt_getEvmTokenApprovals", map[string]any{
			"chain": "eth", "network": "eth-mainnet", "address": approvalOwner,
			"privacyConsent": true,
		}))
		if got["status"] != "ok" || got["source"] != "goplus" || got["network"] != "eth-mainnet" {
			t.Fatalf("result metadata = %v", got)
		}
		rows, ok := got["approvals"].([]any)
		if !ok || len(rows) != 1 {
			t.Fatalf("rows = %#v", got["approvals"])
		}
		row := rows[0].(map[string]any)
		if row["risk"] != "unsafe" || row["unlimited"] != true || row["spender"] != "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" {
			t.Fatalf("row = %v", row)
		}
	}
	if hits := provider.hitCount("/1"); hits != 1 {
		t.Fatalf("provider hits = %d, want local-cache hit", hits)
	}
	metrics := e.gw.Metrics()
	for _, want := range []string{
		"kt_gateway_token_approval_provider_enabled 1",
		`kt_gateway_token_approval_provider_operations_total{outcome="lookup"} 1`,
		`kt_gateway_token_approval_provider_operations_total{outcome="cache_hit"} 1`,
		`kt_gateway_token_approval_rows_total{risk="all"} 1`,
		`kt_gateway_token_approval_rows_total{risk="unsafe"} 1`,
	} {
		if !strings.Contains(metrics, want) {
			t.Fatalf("metrics missing %q:\n%s", want, metrics)
		}
	}
}

func TestTokenApprovalsProviderFailureIsUnavailableNotEmpty(t *testing.T) {
	provider := newRESTFake(t)
	provider.route("/56", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusTooManyRequests)
		_, _ = w.Write([]byte("private provider response"))
	})
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.DisableExternalApprovals = false
		cfg.GoPlusApprovalURL = provider.srv.URL
	})
	err := assertErrCode(t, e.rpc("kt_getEvmTokenApprovals", map[string]any{
		"chain": "bnb", "network": "bnb-mainnet", "address": approvalOwner,
		"privacyConsent": true,
	}), rpc.CodeUpstream)
	data := errData(t, err)
	if data["upstream"] != "goplus-approvals" || strings.Contains(data["message"].(string), "private provider response") {
		t.Fatalf("unsafe provider error = %v", data)
	}
}

func TestTokenApprovalsProviderCircuitFailsClosedAndRecovers(t *testing.T) {
	provider := newRESTFake(t)
	provider.route("/1", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusServiceUnavailable)
	})
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.DisableExternalApprovals = false
		cfg.GoPlusApprovalURL = provider.srv.URL
	})
	params := map[string]any{
		"chain": "eth", "network": "eth-mainnet", "address": approvalOwner,
		"privacyConsent": true,
	}
	for range 4 {
		assertErrCode(t, e.rpc("kt_getEvmTokenApprovals", params), rpc.CodeUpstream)
	}
	if hits := provider.hitCount("/1"); hits != 3 {
		t.Fatalf("open approval circuit must skip fourth provider call, hits = %d", hits)
	}
	metrics := e.gw.Metrics()
	for _, want := range []string{
		`kt_gateway_external_provider_circuit_open{provider="token_approvals_evm"} 1`,
		`kt_gateway_external_provider_circuit_short_circuits_total{provider="token_approvals_evm"} 1`,
	} {
		if !strings.Contains(metrics, want) {
			t.Fatalf("metrics missing %q:\n%s", want, metrics)
		}
	}

	provider.routeJSON("/1", `{"code":1,"result":[]}`)
	e.clk.Advance(31 * time.Second)
	got := result(t, e.rpc("kt_getEvmTokenApprovals", params))
	if got["status"] != "ok" {
		t.Fatalf("approval recovery result = %v", got)
	}
	if hits := provider.hitCount("/1"); hits != 4 {
		t.Fatalf("approval recovery probe hits = %d, want 4", hits)
	}
}

func TestTokenApprovalsRejectUnsupportedNetworkAndInvalidIdentity(t *testing.T) {
	e := newEnv(t, nil)
	assertErrCode(t, e.rpc("kt_getEvmTokenApprovals", map[string]any{
		"chain": "eth", "network": "eth-sepolia", "address": approvalOwner,
		"privacyConsent": true,
	}), rpc.CodeUnsupported)
	assertErrCode(t, e.rpc("kt_getEvmTokenApprovals", map[string]any{
		"chain": "avalanche", "network": "avalanche-mainnet", "address": approvalOwner,
		"privacyConsent": true,
	}), rpc.CodeUnsupported)
	assertErrCode(t, e.rpc("kt_getEvmTokenApprovals", map[string]any{
		"chain": "eth", "network": "eth-mainnet", "address": "0x1234",
		"privacyConsent": true,
	}), rpc.CodeInvalidParams)
	assertErrCode(t, e.rpc("kt_getEvmTokenApprovals", map[string]any{
		"chain": "solana", "network": "sol-mainnet", "address": approvalOwner,
		"privacyConsent": true,
	}), rpc.CodeInvalidParams)
}
