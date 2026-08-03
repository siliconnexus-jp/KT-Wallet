package handlers_test

import (
	"strings"
	"testing"
)

func validAppDiagnostics() map[string]any {
	return map[string]any{
		"schemaVersion": 1,
		"consent":       true,
		"appVersion":    "1.0.0+1",
		"platform":      "ios",
		"locale":        "zh",
		"buildMode":     "release",
		"metrics": []map[string]any{
			{
				"name": "app.startup", "count": 2,
				"successCount": 2, "failureCount": 0,
				"p50Ms": 340, "p95Ms": 710,
			},
			{
				"name": "transaction.broadcast", "count": 3,
				"successCount": 2, "failureCount": 1,
				"p50Ms": 900, "p95Ms": 2200,
			},
		},
	}
}

func TestReportAppDiagnosticsAcceptsOnlyAggregateConsentAndExportsFixedMetrics(t *testing.T) {
	e := newEnv(t, nil)
	got := result(t, e.rpc("kt_reportDiagnostics", validAppDiagnostics()))
	if got["accepted"] != true || got["rawEventsStored"] != false {
		t.Fatalf("unexpected result: %v", got)
	}

	metrics := e.gw.Metrics()
	for _, want := range []string{
		`kt_gateway_app_diagnostic_uploads_total{platform="ios"} 1`,
		`kt_gateway_app_diagnostic_samples_total{platform="ios",metric="app.startup",outcome="success"} 2`,
		`kt_gateway_app_diagnostic_samples_total{platform="ios",metric="transaction.broadcast",outcome="failure"} 1`,
		`kt_gateway_app_diagnostic_reports_total{platform="ios",metric="app.startup"} 1`,
		`kt_gateway_app_diagnostic_percentile_milliseconds_sum{platform="ios",metric="app.startup",percentile="p95"} 710`,
	} {
		if !strings.Contains(metrics, want) {
			t.Fatalf("metrics missing %q:\n%s", want, metrics)
		}
	}
}

func TestReportAppDiagnosticsFailsClosedWithoutPartialMutation(t *testing.T) {
	cases := map[string]func(map[string]any){
		"no consent":       func(p map[string]any) { p["consent"] = false },
		"unknown platform": func(p map[string]any) { p["platform"] = "web" },
		"arbitrary locale": func(p map[string]any) { p["locale"] = "wallet-address" },
		"unknown metric": func(p map[string]any) {
			p["metrics"] = []map[string]any{{
				"name": "wallet.0xsecret", "count": 1,
				"successCount": 1, "failureCount": 0, "p50Ms": 1, "p95Ms": 1,
			}}
		},
		"inconsistent counts": func(p map[string]any) {
			rows := p["metrics"].([]map[string]any)
			rows[1]["failureCount"] = 2
		},
		"descending percentile": func(p map[string]any) {
			rows := p["metrics"].([]map[string]any)
			rows[0]["p50Ms"] = 800
		},
		"oversized duration": func(p map[string]any) {
			rows := p["metrics"].([]map[string]any)
			rows[0]["p95Ms"] = 6*60*60*1000 + 1
		},
		"duplicate metric": func(p map[string]any) {
			rows := p["metrics"].([]map[string]any)
			p["metrics"] = append(rows, rows[0])
		},
		"arbitrary app version": func(p map[string]any) { p["appVersion"] = "../../secret" },
		"unknown root field":    func(p map[string]any) { p["walletAddress"] = evmSelf },
	}

	for name, mutate := range cases {
		t.Run(name, func(t *testing.T) {
			e := newEnv(t, nil)
			params := validAppDiagnostics()
			mutate(params)
			assertErrCode(t, e.rpc("kt_reportDiagnostics", params), -32602)
			metrics := e.gw.Metrics()
			if !strings.Contains(metrics, `kt_gateway_app_diagnostic_uploads_total{platform="ios"} 0`) {
				t.Fatalf("invalid report mutated counters:\n%s", metrics)
			}
		})
	}
}

func TestReportAppDiagnosticsRejectsDuplicateJSONKeys(t *testing.T) {
	e := newEnv(t, nil)
	const params = `{
		"schemaVersion":1,
		"consent":true,
		"consent":false,
		"appVersion":"1.0.0+1",
		"platform":"ios",
		"locale":"zh",
		"buildMode":"release",
		"metrics":[]
	}`
	assertErrCode(t, e.rpc("kt_reportDiagnostics", params), -32602)
	if metrics := e.gw.Metrics(); !strings.Contains(
		metrics,
		`kt_gateway_app_diagnostic_uploads_total{platform="ios"} 0`,
	) {
		t.Fatalf("duplicate-key report mutated counters:\n%s", metrics)
	}
}
