package handlers

import (
	"fmt"
	"sort"
	"strconv"
	"strings"

	"ktwallet/gateway/internal/cache"
	"ktwallet/gateway/internal/upstream"
)

// Metrics returns Prometheus text exposition for the JSON-RPC endpoint pools.
// It intentionally includes only canonical network ids and anonymous,
// one-based endpoint positions. URLs, provider names, request parameters,
// addresses, balances and transaction payloads are never exported.
func (g *Gateway) Metrics() string {
	networks := make([]string, 0, len(g.evm)+len(g.sol))
	health := make(map[string]upstream.PoolHealth, len(g.evm)+len(g.sol))
	for network, client := range g.evm {
		networks = append(networks, network)
		health[network] = client.Health()
	}
	for network, client := range g.sol {
		networks = append(networks, network)
		health[network] = client.Health()
	}
	sort.Strings(networks)

	var out strings.Builder
	out.WriteString("# HELP kt_gateway_upstream_endpoints Configured upstream endpoint count.\n")
	out.WriteString("# TYPE kt_gateway_upstream_endpoints gauge\n")
	out.WriteString("# HELP kt_gateway_ready Whether at least one configured JSON-RPC network can currently accept work.\n")
	out.WriteString("# TYPE kt_gateway_ready gauge\n")
	out.WriteString("# HELP kt_gateway_network_available Whether a network has at least one endpoint outside an open circuit.\n")
	out.WriteString("# TYPE kt_gateway_network_available gauge\n")
	out.WriteString("# HELP kt_gateway_upstream_open_circuits Upstream endpoints with an open circuit.\n")
	out.WriteString("# TYPE kt_gateway_upstream_open_circuits gauge\n")
	out.WriteString("# HELP kt_gateway_upstream_attempts_total Upstream attempts by anonymous endpoint and outcome.\n")
	out.WriteString("# TYPE kt_gateway_upstream_attempts_total counter\n")
	out.WriteString("# HELP kt_gateway_upstream_failures_total Upstream failures by privacy-safe reason.\n")
	out.WriteString("# TYPE kt_gateway_upstream_failures_total counter\n")
	out.WriteString("# HELP kt_gateway_upstream_latency_seconds Rolling endpoint latency percentile over at most 256 attempts.\n")
	out.WriteString("# TYPE kt_gateway_upstream_latency_seconds gauge\n")
	out.WriteString("# HELP kt_gateway_upstream_latency_samples Number of attempts retained in the rolling latency window.\n")
	out.WriteString("# TYPE kt_gateway_upstream_latency_samples gauge\n")
	out.WriteString("# HELP kt_gateway_upstream_available Whether the anonymous endpoint circuit is available for a request.\n")
	out.WriteString("# TYPE kt_gateway_upstream_available gauge\n")
	out.WriteString("# HELP kt_gateway_shared_cache_enabled Whether the cross-instance cache is configured.\n")
	out.WriteString("# TYPE kt_gateway_shared_cache_enabled gauge\n")
	out.WriteString("# HELP kt_gateway_shared_cache_operations_total Cross-instance cache operations by outcome.\n")
	out.WriteString("# TYPE kt_gateway_shared_cache_operations_total counter\n")
	out.WriteString("# HELP kt_gateway_broadcast_guard_enabled Whether the atomic cross-instance broadcast guard is configured.\n")
	out.WriteString("# TYPE kt_gateway_broadcast_guard_enabled gauge\n")
	out.WriteString("# HELP kt_gateway_broadcast_guard_operations_total Broadcast guard operations by fixed privacy-safe outcome.\n")
	out.WriteString("# TYPE kt_gateway_broadcast_guard_operations_total counter\n")
	out.WriteString("# HELP kt_gateway_token_risk_provider_enabled Whether independent token threat intelligence is configured.\n")
	out.WriteString("# TYPE kt_gateway_token_risk_provider_enabled gauge\n")
	out.WriteString("# HELP kt_gateway_token_risk_provider_operations_total External token threat-intelligence operations by privacy-safe outcome.\n")
	out.WriteString("# TYPE kt_gateway_token_risk_provider_operations_total counter\n")
	out.WriteString("# HELP kt_gateway_token_approval_provider_enabled Whether external token-approval discovery is configured.\n")
	out.WriteString("# TYPE kt_gateway_token_approval_provider_enabled gauge\n")
	out.WriteString("# HELP kt_gateway_token_approval_provider_operations_total External token-approval operations by privacy-safe outcome.\n")
	out.WriteString("# TYPE kt_gateway_token_approval_provider_operations_total counter\n")
	out.WriteString("# HELP kt_gateway_token_approval_rows_total Token-approval rows observed by fixed risk category.\n")
	out.WriteString("# TYPE kt_gateway_token_approval_rows_total counter\n")
	out.WriteString("# HELP kt_gateway_external_provider_circuit_open Whether a security-provider circuit is open and calls fail closed without contacting it.\n")
	out.WriteString("# TYPE kt_gateway_external_provider_circuit_open gauge\n")
	out.WriteString("# HELP kt_gateway_external_provider_circuit_probe_inflight Whether the only half-open recovery probe is currently in flight.\n")
	out.WriteString("# TYPE kt_gateway_external_provider_circuit_probe_inflight gauge\n")
	out.WriteString("# HELP kt_gateway_external_provider_circuit_short_circuits_total Security-provider calls rejected while a circuit was open.\n")
	out.WriteString("# TYPE kt_gateway_external_provider_circuit_short_circuits_total counter\n")
	out.WriteString("# HELP kt_gateway_app_diagnostic_uploads_total Explicitly consented aggregate-only mobile diagnostic uploads.\n")
	out.WriteString("# TYPE kt_gateway_app_diagnostic_uploads_total counter\n")
	out.WriteString("# HELP kt_gateway_app_diagnostic_samples_total Client-reported samples by fixed metric and outcome.\n")
	out.WriteString("# TYPE kt_gateway_app_diagnostic_samples_total counter\n")
	out.WriteString("# HELP kt_gateway_app_diagnostic_reports_total Reports contributing a fixed metric row.\n")
	out.WriteString("# TYPE kt_gateway_app_diagnostic_reports_total counter\n")
	out.WriteString("# HELP kt_gateway_app_diagnostic_percentile_milliseconds_sum Sum of client-computed percentiles; divide by reports for the average reported percentile.\n")
	out.WriteString("# TYPE kt_gateway_app_diagnostic_percentile_milliseconds_sum counter\n")

	ready := 0
	for _, network := range networks {
		snapshot := health[network]
		networkLabel := strconv.Quote(network)
		networkAvailable := 0
		if snapshot.Endpoints > 0 && snapshot.OpenCircuits < snapshot.Endpoints {
			networkAvailable = 1
			ready = 1
		}
		fmt.Fprintf(
			&out,
			"kt_gateway_network_available{network=%s} %d\n",
			networkLabel,
			networkAvailable,
		)
		fmt.Fprintf(
			&out,
			"kt_gateway_upstream_endpoints{network=%s} %d\n",
			networkLabel,
			snapshot.Endpoints,
		)
		fmt.Fprintf(
			&out,
			"kt_gateway_upstream_open_circuits{network=%s} %d\n",
			networkLabel,
			snapshot.OpenCircuits,
		)
		for _, endpoint := range snapshot.EndpointMetrics {
			position := strconv.Itoa(endpoint.Position)
			baseLabels := "network=" + networkLabel + ",endpoint=" + strconv.Quote(position)
			fmt.Fprintf(
				&out,
				"kt_gateway_upstream_attempts_total{%s,outcome=\"success\"} %d\n",
				baseLabels,
				endpoint.Successes,
			)
			fmt.Fprintf(
				&out,
				"kt_gateway_upstream_attempts_total{%s,outcome=\"failure\"} %d\n",
				baseLabels,
				endpoint.Failures,
			)
			writeFailureMetrics(&out, baseLabels, endpoint.FailureMetrics)
			fmt.Fprintf(
				&out,
				"kt_gateway_upstream_latency_seconds{%s,percentile=\"p50\"} %g\n",
				baseLabels,
				float64(endpoint.LatencyP50Ms)/1000,
			)
			fmt.Fprintf(
				&out,
				"kt_gateway_upstream_latency_seconds{%s,percentile=\"p95\"} %g\n",
				baseLabels,
				float64(endpoint.LatencyP95Ms)/1000,
			)
			fmt.Fprintf(
				&out,
				"kt_gateway_upstream_latency_samples{%s} %d\n",
				baseLabels,
				endpoint.Samples,
			)
			available := 1
			if endpoint.State == "open" {
				available = 0
			}
			fmt.Fprintf(
				&out,
				"kt_gateway_upstream_available{%s} %d\n",
				baseLabels,
				available,
			)
		}
	}
	fmt.Fprintf(&out, "kt_gateway_ready %d\n", ready)
	writeCacheMetrics(&out, "prices", g.priceCache.SharedEnabled(), g.priceCache.Stats())
	writeCacheMetrics(&out, "balances", g.balanceCache.SharedEnabled(), g.balanceCache.Stats())
	writeCacheMetrics(&out, "history", g.historyCache.SharedEnabled(), g.historyCache.Stats())
	writeBroadcastGuardMetrics(&out, g.broadcastGuard)
	providerEnabled := 0
	if g.goPlus != nil || g.goPlusSolana != nil {
		providerEnabled = 1
	}
	fmt.Fprintf(&out, "kt_gateway_token_risk_provider_enabled %d\n", providerEnabled)
	fmt.Fprintf(&out, "kt_gateway_token_risk_provider_operations_total{outcome=\"lookup\"} %d\n", g.tokenRiskMetrics.lookups.Load())
	fmt.Fprintf(&out, "kt_gateway_token_risk_provider_operations_total{outcome=\"unsafe\"} %d\n", g.tokenRiskMetrics.unsafe.Load())
	fmt.Fprintf(&out, "kt_gateway_token_risk_provider_operations_total{outcome=\"unknown\"} %d\n", g.tokenRiskMetrics.unknown.Load())
	fmt.Fprintf(&out, "kt_gateway_token_risk_provider_operations_total{outcome=\"error\"} %d\n", g.tokenRiskMetrics.errors.Load())
	fmt.Fprintf(&out, "kt_gateway_token_risk_provider_operations_total{outcome=\"cache_hit\"} %d\n", g.tokenRiskMetrics.cacheHits.Load())
	approvalProviderEnabled := 0
	if g.goPlusApprovals != nil {
		approvalProviderEnabled = 1
	}
	fmt.Fprintf(&out, "kt_gateway_token_approval_provider_enabled %d\n", approvalProviderEnabled)
	fmt.Fprintf(&out, "kt_gateway_token_approval_provider_operations_total{outcome=\"lookup\"} %d\n", g.tokenApprovalMetrics.lookups.Load())
	fmt.Fprintf(&out, "kt_gateway_token_approval_provider_operations_total{outcome=\"error\"} %d\n", g.tokenApprovalMetrics.errors.Load())
	fmt.Fprintf(&out, "kt_gateway_token_approval_provider_operations_total{outcome=\"cache_hit\"} %d\n", g.tokenApprovalMetrics.cacheHits.Load())
	fmt.Fprintf(&out, "kt_gateway_token_approval_rows_total{risk=\"all\"} %d\n", g.tokenApprovalMetrics.rows.Load())
	fmt.Fprintf(&out, "kt_gateway_token_approval_rows_total{risk=\"unsafe\"} %d\n", g.tokenApprovalMetrics.riskyRows.Load())
	writeProviderCircuitMetrics(&out, "token_risk_evm", g.goPlusCircuit)
	writeProviderCircuitMetrics(&out, "token_risk_solana", g.goPlusSolanaCircuit)
	writeProviderCircuitMetrics(&out, "token_approvals_evm", g.goPlusApprovalsCircuit)
	for platformIndex, platform := range appDiagnosticPlatforms {
		platformLabel := strconv.Quote(platform)
		fmt.Fprintf(&out, "kt_gateway_app_diagnostic_uploads_total{platform=%s} %d\n", platformLabel, g.appDiagnostics.uploads[platformIndex].Load())
		for _, name := range appDiagnosticMetricOrder {
			row := g.appDiagnostics.rows[platform+"\x00"+name]
			metricLabel := strconv.Quote(name)
			baseLabels := "platform=" + platformLabel + ",metric=" + metricLabel
			fmt.Fprintf(&out, "kt_gateway_app_diagnostic_samples_total{%s,outcome=\"success\"} %d\n", baseLabels, row.success.Load())
			fmt.Fprintf(&out, "kt_gateway_app_diagnostic_samples_total{%s,outcome=\"failure\"} %d\n", baseLabels, row.failure.Load())
			fmt.Fprintf(&out, "kt_gateway_app_diagnostic_reports_total{%s} %d\n", baseLabels, row.reports.Load())
			fmt.Fprintf(&out, "kt_gateway_app_diagnostic_percentile_milliseconds_sum{%s,percentile=\"p50\"} %d\n", baseLabels, row.p50MillisSum.Load())
			fmt.Fprintf(&out, "kt_gateway_app_diagnostic_percentile_milliseconds_sum{%s,percentile=\"p95\"} %d\n", baseLabels, row.p95MillisSum.Load())
		}
	}
	return out.String()
}

func writeBroadcastGuardMetrics(out *strings.Builder, guard *broadcastGuard) {
	enabled := 0
	snapshot := broadcastGuardMetricSnapshot{}
	if guard != nil {
		if guard.sharedEnabled() {
			enabled = 1
		}
		snapshot = guard.metricSnapshot()
	}
	fmt.Fprintf(out, "kt_gateway_broadcast_guard_enabled %d\n", enabled)
	values := []struct {
		outcome string
		value   uint64
	}{
		{"claim_acquired", snapshot.ClaimAcquired},
		{"replay_accepted", snapshot.ReplayAccepted},
		{"replay_rejected", snapshot.ReplayRejected},
		{"replay_unknown", snapshot.ReplayUnknown},
		{"replay_pending", snapshot.ReplayPending},
		{"unavailable", snapshot.Unavailable},
		{"corrupt_record", snapshot.CorruptRecord},
		{"persist_error", snapshot.PersistError},
	}
	for _, item := range values {
		fmt.Fprintf(
			out,
			"kt_gateway_broadcast_guard_operations_total{outcome=%s} %d\n",
			strconv.Quote(item.outcome),
			item.value,
		)
	}
}

func writeProviderCircuitMetrics(
	out *strings.Builder,
	provider string,
	circuit *providerCircuit,
) {
	snapshot := providerCircuitSnapshot{}
	if circuit != nil {
		snapshot = circuit.snapshot()
	}
	open := 0
	if snapshot.Open {
		open = 1
	}
	probe := 0
	if snapshot.ProbeInFlight {
		probe = 1
	}
	label := strconv.Quote(provider)
	fmt.Fprintf(out, "kt_gateway_external_provider_circuit_open{provider=%s} %d\n", label, open)
	fmt.Fprintf(out, "kt_gateway_external_provider_circuit_probe_inflight{provider=%s} %d\n", label, probe)
	fmt.Fprintf(out, "kt_gateway_external_provider_circuit_short_circuits_total{provider=%s} %d\n", label, snapshot.ShortCircuits)
}

func writeCacheMetrics(out *strings.Builder, name string, enabled bool, stats cache.Stats) {
	value := 0
	if enabled {
		value = 1
	}
	label := strconv.Quote(name)
	fmt.Fprintf(out, "kt_gateway_shared_cache_enabled{cache=%s} %d\n", label, value)
	fmt.Fprintf(out, "kt_gateway_shared_cache_operations_total{cache=%s,outcome=\"hit\"} %d\n", label, stats.Hits)
	fmt.Fprintf(out, "kt_gateway_shared_cache_operations_total{cache=%s,outcome=\"miss\"} %d\n", label, stats.Misses)
	fmt.Fprintf(out, "kt_gateway_shared_cache_operations_total{cache=%s,outcome=\"error\"} %d\n", label, stats.Errors)
}

func writeFailureMetrics(
	out *strings.Builder,
	baseLabels string,
	metrics upstream.FailureMetrics,
) {
	rows := []struct {
		reason string
		count  uint64
	}{
		{"rate_limited", metrics.RateLimited},
		{"timeout", metrics.Timeouts},
		{"malformed_response", metrics.MalformedResponse},
		{"transport", metrics.Transport},
		{"server_error", metrics.ServerErrors},
		{"provider_error", metrics.ProviderErrors},
		{"other", metrics.Other},
	}
	for _, row := range rows {
		fmt.Fprintf(
			out,
			"kt_gateway_upstream_failures_total{%s,reason=%s} %d\n",
			baseLabels,
			strconv.Quote(row.reason),
			row.count,
		)
	}
}
