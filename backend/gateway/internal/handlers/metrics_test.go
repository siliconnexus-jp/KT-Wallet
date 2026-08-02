package handlers_test

import (
	"strings"
	"testing"

	"ktwallet/gateway/internal/handlers"
)

func TestMetricsExposeAnonymousEndpointStatsWithoutSecrets(t *testing.T) {
	const secretEndpoint = "https://user:super-secret@provider.invalid/v2/private-key"
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EthURLs = []string{secretEndpoint}
	})

	metrics := e.gw.Metrics()
	for _, want := range []string{
		"# TYPE kt_gateway_upstream_attempts_total counter",
		`kt_gateway_ready 1`,
		`kt_gateway_network_available{network="eth-mainnet"} 1`,
		`kt_gateway_upstream_endpoints{network="eth-mainnet"} 1`,
		`kt_gateway_upstream_attempts_total{network="eth-mainnet",endpoint="1",outcome="success"} 0`,
		`kt_gateway_upstream_failures_total{network="eth-mainnet",endpoint="1",reason="timeout"} 0`,
		`kt_gateway_upstream_latency_seconds{network="eth-mainnet",endpoint="1",percentile="p95"} 0`,
		`kt_gateway_upstream_available{network="eth-mainnet",endpoint="1"} 1`,
		`kt_gateway_shared_cache_enabled{cache="balances"} 0`,
		`kt_gateway_shared_cache_operations_total{cache="balances",outcome="error"} 0`,
		`kt_gateway_broadcast_guard_enabled 0`,
		`kt_gateway_broadcast_guard_operations_total{outcome="claim_acquired"} 0`,
		`kt_gateway_broadcast_guard_operations_total{outcome="corrupt_record"} 0`,
		`kt_gateway_broadcast_guard_operations_total{outcome="persist_error"} 0`,
		`kt_gateway_token_risk_provider_enabled 0`,
		`kt_gateway_token_risk_provider_operations_total{outcome="error"} 0`,
		`kt_gateway_token_approval_provider_enabled 0`,
		`kt_gateway_token_approval_provider_operations_total{outcome="error"} 0`,
		`# TYPE kt_gateway_external_provider_circuit_open gauge`,
		`kt_gateway_external_provider_circuit_open{provider="token_risk_evm"} 0`,
		`kt_gateway_external_provider_circuit_probe_inflight{provider="token_risk_solana"} 0`,
		`kt_gateway_external_provider_circuit_short_circuits_total{provider="token_approvals_evm"} 0`,
		`# TYPE kt_gateway_app_diagnostic_uploads_total counter`,
		`kt_gateway_app_diagnostic_uploads_total{platform="android"} 0`,
		`kt_gateway_app_diagnostic_samples_total{platform="ios",metric="app.nativeFatal",outcome="failure"} 0`,
	} {
		if !strings.Contains(metrics, want) {
			t.Fatalf("metrics missing %q:\n%s", want, metrics)
		}
	}
	for _, secret := range []string{
		"super-secret",
		"provider.invalid",
		"/v2/private-key",
		"user:",
	} {
		if strings.Contains(metrics, secret) {
			t.Fatalf("metrics leaked endpoint material %q:\n%s", secret, metrics)
		}
	}
}

func TestMetricsReflectOpenCircuitAndFailureReason(t *testing.T) {
	e := newEnv(t, nil)
	for range 3 {
		e.rpc("kt_getBalances", balancesParams("eth", evmSelf, ""))
	}

	metrics := e.gw.Metrics()
	for _, want := range []string{
		`kt_gateway_upstream_open_circuits{network="eth-mainnet"} 1`,
		`kt_gateway_network_available{network="eth-mainnet"} 0`,
		`kt_gateway_ready 1`,
		`kt_gateway_upstream_attempts_total{network="eth-mainnet",endpoint="1",outcome="failure"} 3`,
		`kt_gateway_upstream_failures_total{network="eth-mainnet",endpoint="1",reason="transport"} 3`,
		`kt_gateway_upstream_available{network="eth-mainnet",endpoint="1"} 0`,
	} {
		if !strings.Contains(metrics, want) {
			t.Fatalf("metrics missing %q:\n%s", want, metrics)
		}
	}
}
