package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"regexp"
	"sync/atomic"

	"ktwallet/gateway/internal/rpc"
)

// Client diagnostics are deliberately aggregate-only. The accepted labels
// are a closed set so an unauthenticated mobile client cannot create
// unbounded Prometheus cardinality or smuggle wallet-derived strings into an
// operator-visible system.
var appDiagnosticMetricOrder = []string{
	"app.startup",
	"app.flutterError",
	"app.platformError",
	"app.nativeFatal",
	"app.nativeAnr",
	"market.refresh",
	"history.refresh",
	"history.loadMore",
	"transaction.prepare",
	"transaction.sign",
	"transaction.broadcast",
	"transaction.finality",
}

var appDiagnosticMetricSet = func() map[string]bool {
	out := make(map[string]bool, len(appDiagnosticMetricOrder))
	for _, name := range appDiagnosticMetricOrder {
		out[name] = true
	}
	return out
}()

var appVersionRE = regexp.MustCompile(`^[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}(?:[-+][0-9A-Za-z.-]{1,32})?$`)

var appDiagnosticPlatforms = []string{"android", "ios"}

type appDiagnosticCounters struct {
	reports      atomic.Uint64
	success      atomic.Uint64
	failure      atomic.Uint64
	p50MillisSum atomic.Uint64
	p95MillisSum atomic.Uint64
}

type appDiagnosticMetrics struct {
	uploads [2]atomic.Uint64
	rows    map[string]*appDiagnosticCounters
}

func newAppDiagnosticMetrics() *appDiagnosticMetrics {
	m := &appDiagnosticMetrics{rows: make(map[string]*appDiagnosticCounters)}
	for _, platform := range appDiagnosticPlatforms {
		for _, name := range appDiagnosticMetricOrder {
			m.rows[platform+"\x00"+name] = &appDiagnosticCounters{}
		}
	}
	return m
}

type appDiagnosticRow struct {
	Name         string `json:"name"`
	Count        int    `json:"count"`
	SuccessCount int    `json:"successCount"`
	FailureCount int    `json:"failureCount"`
	P50Ms        int    `json:"p50Ms"`
	P95Ms        int    `json:"p95Ms"`
}

type appDiagnosticReport struct {
	SchemaVersion int                `json:"schemaVersion"`
	Consent       bool               `json:"consent"`
	AppVersion    string             `json:"appVersion"`
	Platform      string             `json:"platform"`
	Locale        string             `json:"locale"`
	BuildMode     string             `json:"buildMode"`
	Metrics       []appDiagnosticRow `json:"metrics"`
}

// ReportAppDiagnostics accepts a privacy-minimal, explicitly consented
// summary. It stores no request body and no event timestamp. Only fixed-label
// atomic counters are retained until process restart and scraped by the
// operator's Prometheus retention policy.
func (g *Gateway) ReportAppDiagnostics(_ context.Context, params json.RawMessage) (any, *rpc.Error) {
	var report appDiagnosticReport
	if err := decodeStrictJSON(params, &report); err != nil {
		return nil, invalidAppDiagnostics()
	}
	if report.SchemaVersion != 1 || !report.Consent || !appVersionRE.MatchString(report.AppVersion) {
		return nil, invalidAppDiagnostics()
	}
	platformIndex := -1
	for i, platform := range appDiagnosticPlatforms {
		if report.Platform == platform {
			platformIndex = i
			break
		}
	}
	if platformIndex < 0 ||
		(report.Locale != "en" && report.Locale != "zh" && report.Locale != "ja" && report.Locale != "other") ||
		(report.BuildMode != "release" && report.BuildMode != "profile" && report.BuildMode != "debug") ||
		len(report.Metrics) == 0 || len(report.Metrics) > len(appDiagnosticMetricOrder) {
		return nil, invalidAppDiagnostics()
	}

	seen := make(map[string]bool, len(report.Metrics))
	for _, row := range report.Metrics {
		if !appDiagnosticMetricSet[row.Name] || seen[row.Name] ||
			row.Count < 1 || row.Count > 100 ||
			row.SuccessCount < 0 || row.FailureCount < 0 ||
			row.SuccessCount+row.FailureCount != row.Count ||
			row.P50Ms < 0 || row.P95Ms < row.P50Ms ||
			row.P95Ms > 6*60*60*1000 {
			return nil, invalidAppDiagnostics()
		}
		seen[row.Name] = true
	}

	// Validate the complete request before mutating any counter, so a malformed
	// trailing row cannot leave a partially accepted report.
	for _, row := range report.Metrics {
		counter := g.appDiagnostics.rows[report.Platform+"\x00"+row.Name]
		counter.reports.Add(1)
		counter.success.Add(uint64(row.SuccessCount))
		counter.failure.Add(uint64(row.FailureCount))
		counter.p50MillisSum.Add(uint64(row.P50Ms))
		counter.p95MillisSum.Add(uint64(row.P95Ms))
	}
	g.appDiagnostics.uploads[platformIndex].Add(1)

	return map[string]any{
		"accepted":        true,
		"rawEventsStored": false,
	}, nil
}

func invalidAppDiagnostics() *rpc.Error {
	return rpc.Errorf(
		rpc.CodeInvalidParams,
		`invalid params: expected a consented, aggregate-only diagnostics schema`,
	)
}

func decodeStrictJSON(raw json.RawMessage, target any) error {
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return err
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return errors.New("trailing JSON value")
	}
	return nil
}
