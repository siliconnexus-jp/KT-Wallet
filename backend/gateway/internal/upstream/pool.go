// Package upstream contains the chain/API clients the gateway proxies to:
// EVM JSON-RPC (with URL failover + circuit breaking), TronGrid REST, Solana
// JSON-RPC, CoinGecko prices, and the Etherscan/Helius history APIs.
package upstream

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"slices"
	"strings"
	"sync"
	"time"

	"ktwallet/gateway/internal/clock"
)

// FailThreshold is the number of consecutive failures after which an endpoint
// circuit opens; OpenDuration is how long it then stays skipped.
const (
	FailThreshold = 3
	OpenDuration  = 30 * time.Second

	// latencyWindowSize bounds the in-memory observability cost per endpoint.
	// A rolling window is sufficient for operational percentiles while avoiding
	// unbounded retention of request timing data.
	latencyWindowSize = 256
)

// NodeError is a valid JSON-RPC error returned by an upstream node. It does
// NOT trigger failover — the node answered, it just said no.
type NodeError struct {
	Code    int
	Message string
}

func (e *NodeError) Error() string {
	return fmt.Sprintf("node error %d: %s", e.Code, PublicNodeErrorMessage(e.Message))
}

// Unavailable means the upstream(s) could not produce an answer: transport
// error, 5xx/429, garbage response, or every circuit open.
type Unavailable struct {
	Upstream string
	Message  string
}

// Error is intentionally generic. Callers that need structured diagnostics
// can inspect the typed fields inside this package, but generic logging must
// never accidentally serialize a provider hostname, URL-derived identifier,
// or future unreviewed message.
func (e *Unavailable) Error() string { return "upstream temporarily unavailable" }

type failureKind string

const (
	failureRateLimited failureKind = "rate_limited"
	failureTimeout     failureKind = "timeout"
	failureMalformed   failureKind = "malformed_response"
	failureTransport   failureKind = "transport"
	failureServer      failureKind = "server_error"
	failureProvider    failureKind = "provider_error"
	failureOther       failureKind = "other"
)

type attemptFailure struct {
	kind failureKind
	err  error
}

func (e *attemptFailure) Error() string { return e.err.Error() }
func (e *attemptFailure) Unwrap() error { return e.err }

type failureCounts struct {
	rateLimited uint64
	timeouts    uint64
	malformed   uint64
	transport   uint64
	server      uint64
	provider    uint64
	other       uint64
}

// FailureMetrics classifies failures without retaining request payloads,
// addresses, transaction data, endpoint URLs, or provider credentials.
type FailureMetrics struct {
	RateLimited       uint64 `json:"rateLimited"`
	Timeouts          uint64 `json:"timeouts"`
	MalformedResponse uint64 `json:"malformedResponses"`
	Transport         uint64 `json:"transport"`
	ServerErrors      uint64 `json:"serverErrors"`
	ProviderErrors    uint64 `json:"providerErrors"`
	Other             uint64 `json:"other"`
}

type endpoint struct {
	url                string
	fails              int
	openUntil          time.Time
	successes          uint64
	failures           uint64
	lastLatencyMs      int64
	failureCounts      failureCounts
	latencySamples     [latencyWindowSize]int64
	latencySampleCount int
	latencySampleNext  int
}

// EndpointHealth identifies an endpoint only by its one-based configuration
// position. Provider URLs are deliberately excluded because they can contain
// API keys. Operators can correlate the position with their private config.
type EndpointHealth struct {
	Position       int            `json:"position"`
	State          string         `json:"state"`
	Successes      uint64         `json:"successes"`
	Failures       uint64         `json:"failures"`
	FailureMetrics FailureMetrics `json:"failureMetrics"`
	LastLatencyMs  int64          `json:"lastLatencyMs"`
	LatencyP50Ms   int64          `json:"latencyP50Ms"`
	LatencyP95Ms   int64          `json:"latencyP95Ms"`
	Samples        int            `json:"samples"`
}

// PoolHealth is a key-safe operational summary. It deliberately exposes no
// endpoint URL because provider URLs can contain API keys.
type PoolHealth struct {
	Endpoints       int              `json:"endpoints"`
	OpenCircuits    int              `json:"openCircuits"`
	Successes       uint64           `json:"successes"`
	Failures        uint64           `json:"failures"`
	FailureMetrics  FailureMetrics   `json:"failureMetrics"`
	LastLatencyMs   int64            `json:"lastLatencyMs"`
	LatencyP50Ms    int64            `json:"latencyP50Ms"`
	LatencyP95Ms    int64            `json:"latencyP95Ms"`
	Samples         int              `json:"samples"`
	EndpointMetrics []EndpointHealth `json:"endpointMetrics"`
}

// Pool is an ordered list of JSON-RPC endpoints with failover and a
// per-endpoint circuit breaker. Failover triggers on transport errors,
// HTTP 5xx and HTTP 429 — never on a well-formed JSON-RPC error result.
type Pool struct {
	name    string
	clk     clock.Clock
	client  *http.Client
	timeout time.Duration // per-attempt budget

	mu  sync.Mutex
	eps []*endpoint

	roundRobinPrefix int
	nextPrimary      int
}

// NewPool builds a Pool over urls, tried in order.
func NewPool(name string, urls []string, clk clock.Clock, client *http.Client, attemptTimeout time.Duration) *Pool {
	return newPool(name, urls, 0, clk, client, attemptTimeout)
}

// NewPoolRoundRobinPrefix balances across the first prefixCount endpoints and
// preserves the remaining endpoints as ordered failover targets.
func NewPoolRoundRobinPrefix(
	name string,
	urls []string,
	prefixCount int,
	clk clock.Clock,
	client *http.Client,
	attemptTimeout time.Duration,
) *Pool {
	return newPool(name, urls, prefixCount, clk, client, attemptTimeout)
}

func newPool(
	name string,
	urls []string,
	prefixCount int,
	clk clock.Clock,
	client *http.Client,
	attemptTimeout time.Duration,
) *Pool {
	eps := make([]*endpoint, 0, len(urls))
	for _, u := range urls {
		if u != "" {
			eps = append(eps, &endpoint{url: u})
		}
	}
	if client == nil {
		client = http.DefaultClient
	}
	if attemptTimeout <= 0 {
		attemptTimeout = 10 * time.Second
	}
	prefixCount = min(max(prefixCount, 0), len(eps))
	return &Pool{
		name:             name,
		clk:              clk,
		client:           client,
		timeout:          attemptTimeout,
		eps:              eps,
		roundRobinPrefix: prefixCount,
	}
}

// Call performs one JSON-RPC call, failing over between endpoints. The
// returned error is either *NodeError or *Unavailable.
func (p *Pool) Call(ctx context.Context, method string, params any) (json.RawMessage, error) {
	body, err := rpcRequestBody(method, params)
	if err != nil {
		return nil, &Unavailable{Upstream: p.name, Message: "could not encode upstream request"}
	}

	var lastErr *Unavailable
	attempted := false
	for _, ep := range p.endpointsForCall() {
		if p.circuitOpen(ep) {
			continue
		}
		attempted = true
		started := time.Now()
		result, nodeErr, failure := p.attempt(ctx, ep.url, body)
		latency := time.Since(started)
		if failure != nil {
			kind := failureKindOf(failure)
			p.recordFailure(ep, latency, kind)
			lastErr = &Unavailable{Upstream: hostOf(ep.url), Message: publicFailureMessage(kind)}
			// If the overall context is done there is no point trying more URLs.
			if ctx.Err() != nil {
				return nil, lastErr
			}
			continue
		}
		if nodeErr != nil {
			// Provider-account routing errors mean the request never reached
			// the chain. They are safe to fail over for read-only calls and
			// commonly occur when one key in a multi-key pool has not enabled
			// a particular network yet.
			if providerRoutingError(nodeErr) {
				p.recordFailure(ep, latency, failureProvider)
				lastErr = &Unavailable{
					Upstream: hostOf(ep.url),
					Message:  "provider rejected network routing",
				}
				continue
			}
			p.recordSuccess(ep, latency)
			return nil, nodeErr
		}
		p.recordSuccess(ep, latency)
		return result, nil
	}
	if !attempted {
		return nil, &Unavailable{Upstream: p.name, Message: "all upstreams temporarily unavailable (circuit open)"}
	}
	return nil, lastErr
}

// CallOnce performs one JSON-RPC write against exactly one currently eligible
// endpoint. Endpoints whose circuit was already open are skipped before any
// request is sent, but a transport error, timeout, HTTP failure, malformed
// response, or provider-routing error after the attempt starts is returned
// immediately. This is the irreversible-write boundary used by transaction
// broadcasts: a lost response can hide an accepted transaction, so trying a
// second endpoint would violate at-most-one submission semantics.
func (p *Pool) CallOnce(ctx context.Context, method string, params any) (json.RawMessage, error) {
	body, err := rpcRequestBody(method, params)
	if err != nil {
		return nil, &Unavailable{Upstream: p.name, Message: "could not encode upstream request"}
	}

	for _, ep := range p.endpointsForCall() {
		if p.circuitOpen(ep) {
			continue
		}
		started := time.Now()
		result, nodeErr, failure := p.attempt(ctx, ep.url, body)
		latency := time.Since(started)
		if failure != nil {
			kind := failureKindOf(failure)
			p.recordFailure(ep, latency, kind)
			return nil, &Unavailable{
				Upstream: hostOf(ep.url),
				Message:  publicFailureMessage(kind),
			}
		}
		if nodeErr != nil {
			if providerRoutingError(nodeErr) {
				p.recordFailure(ep, latency, failureProvider)
				return nil, &Unavailable{
					Upstream: hostOf(ep.url),
					Message:  "provider rejected network routing",
				}
			}
			p.recordSuccess(ep, latency)
			return nil, nodeErr
		}
		p.recordSuccess(ep, latency)
		return result, nil
	}
	return nil, &Unavailable{
		Upstream: p.name,
		Message:  "all upstreams temporarily unavailable (circuit open)",
	}
}

func rpcRequestBody(method string, params any) ([]byte, error) {
	if params == nil {
		params = []any{}
	}
	return json.Marshal(map[string]any{
		"jsonrpc": "2.0",
		"id":      1,
		"method":  method,
		"params":  params,
	})
}

func providerRoutingError(err *NodeError) bool {
	message := strings.ToLower(err.Message)
	return strings.Contains(message, "not enabled for this app") ||
		strings.Contains(message, "api key is not valid") ||
		strings.Contains(message, "invalid api key") ||
		strings.Contains(message, "authentication failed")
}

func publicFailureMessage(kind failureKind) string {
	switch kind {
	case failureRateLimited:
		return "upstream rate limit reached"
	case failureTimeout:
		return "upstream request timed out"
	case failureMalformed:
		return "malformed upstream response"
	case failureTransport:
		return "upstream request failed"
	case failureServer:
		return "upstream server unavailable"
	case failureProvider:
		return "provider rejected network routing"
	default:
		return "upstream temporarily unavailable"
	}
}

func (p *Pool) endpointsForCall() []*endpoint {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.roundRobinPrefix <= 1 {
		return append([]*endpoint(nil), p.eps...)
	}
	start := p.nextPrimary % p.roundRobinPrefix
	p.nextPrimary = (p.nextPrimary + 1) % p.roundRobinPrefix
	ordered := make([]*endpoint, 0, len(p.eps))
	for offset := range p.roundRobinPrefix {
		ordered = append(ordered, p.eps[(start+offset)%p.roundRobinPrefix])
	}
	ordered = append(ordered, p.eps[p.roundRobinPrefix:]...)
	return ordered
}

// attempt runs a single HTTP exchange. failure != nil marks a failover-worthy
// problem; nodeErr is a valid JSON-RPC error answer.
func (p *Pool) attempt(ctx context.Context, u string, body []byte) (result json.RawMessage, nodeErr *NodeError, failure error) {
	actx, cancel := context.WithTimeout(ctx, p.timeout)
	defer cancel()
	req, err := http.NewRequestWithContext(actx, http.MethodPost, u, bytes.NewReader(body))
	if err != nil {
		return nil, nil, &attemptFailure{
			kind: failureOther,
			err:  errors.New("could not create upstream request"),
		}
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := p.client.Do(req)
	if err != nil {
		kind := failureTransport
		if errors.Is(err, context.DeadlineExceeded) ||
			errors.Is(actx.Err(), context.DeadlineExceeded) {
			kind = failureTimeout
		}
		return nil, nil, &attemptFailure{kind: kind, err: errors.New(publicFailureMessage(kind))}
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusTooManyRequests {
		_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 4096))
		return nil, nil, &attemptFailure{
			kind: failureRateLimited,
			err:  fmt.Errorf("upstream returned HTTP %d", resp.StatusCode),
		}
	}
	if resp.StatusCode >= 500 {
		_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 4096))
		return nil, nil, &attemptFailure{
			kind: failureServer,
			err:  fmt.Errorf("upstream returned HTTP %d", resp.StatusCode),
		}
	}
	data, err := readBoundedResponse(resp.Body, 8<<20)
	if err != nil {
		return nil, nil, &attemptFailure{
			kind: failureTransport,
			err:  errors.New(publicFailureMessage(failureTransport)),
		}
	}
	fields, err := decodeExactJSONObject(data, "jsonrpc", "id", "result", "error")
	if err != nil {
		return nil, nil, &attemptFailure{
			kind: failureMalformed,
			err:  fmt.Errorf("invalid JSON-RPC response (HTTP %d)", resp.StatusCode),
		}
	}
	var jsonRPCVersion string
	if err := json.Unmarshal(fields["jsonrpc"], &jsonRPCVersion); err != nil {
		return nil, nil, &attemptFailure{
			kind: failureMalformed,
			err:  fmt.Errorf("invalid JSON-RPC response envelope (HTTP %d)", resp.StatusCode),
		}
	}
	result, hasResult := fields["result"]
	rpcErrorRaw, hasError := fields["error"]
	if jsonRPCVersion != "2.0" ||
		!bytes.Equal(bytes.TrimSpace(fields["id"]), []byte("1")) ||
		hasResult == hasError {
		return nil, nil, &attemptFailure{
			kind: failureMalformed,
			err:  fmt.Errorf("invalid JSON-RPC response envelope (HTTP %d)", resp.StatusCode),
		}
	}
	if hasError {
		errorFields, err := decodeExactJSONObject(rpcErrorRaw, "code", "message", "data")
		if err != nil {
			return nil, nil, &attemptFailure{
				kind: failureMalformed,
				err:  fmt.Errorf("invalid JSON-RPC error envelope (HTTP %d)", resp.StatusCode),
			}
		}
		var code *int
		var message *string
		if err := json.Unmarshal(errorFields["code"], &code); err != nil ||
			json.Unmarshal(errorFields["message"], &message) != nil ||
			code == nil || message == nil {
			return nil, nil, &attemptFailure{
				kind: failureMalformed,
				err:  fmt.Errorf("invalid JSON-RPC error envelope (HTTP %d)", resp.StatusCode),
			}
		}
		return nil, &NodeError{Code: *code, Message: *message}, nil
	}
	return result, nil, nil
}

func (p *Pool) circuitOpen(ep *endpoint) bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return ep.openUntil.After(p.clk.Now())
}

func (p *Pool) recordFailure(ep *endpoint, latency time.Duration, kind failureKind) {
	p.mu.Lock()
	defer p.mu.Unlock()
	ep.fails++
	ep.failures++
	ep.lastLatencyMs = latency.Milliseconds()
	ep.recordLatency(latency.Milliseconds())
	ep.failureCounts.increment(kind)
	if ep.fails >= FailThreshold {
		ep.openUntil = p.clk.Now().Add(OpenDuration)
	}
}

func (p *Pool) recordSuccess(ep *endpoint, latency time.Duration) {
	p.mu.Lock()
	defer p.mu.Unlock()
	ep.fails = 0
	ep.openUntil = time.Time{}
	ep.successes++
	ep.lastLatencyMs = latency.Milliseconds()
	ep.recordLatency(latency.Milliseconds())
}

// Health returns an aggregate snapshot suitable for health endpoints and
// metrics. It never performs network I/O.
func (p *Pool) Health() PoolHealth {
	p.mu.Lock()
	defer p.mu.Unlock()
	out := PoolHealth{
		Endpoints:       len(p.eps),
		EndpointMetrics: make([]EndpointHealth, 0, len(p.eps)),
	}
	allLatencies := make([]int64, 0, len(p.eps)*latencyWindowSize)
	for index, ep := range p.eps {
		open := ep.openUntil.After(p.clk.Now())
		if open {
			out.OpenCircuits++
		}
		out.Successes += ep.successes
		out.Failures += ep.failures
		out.FailureMetrics.add(ep.failureCounts.snapshot())
		if ep.lastLatencyMs > out.LastLatencyMs {
			out.LastLatencyMs = ep.lastLatencyMs
		}
		latencies := ep.latencies()
		allLatencies = append(allLatencies, latencies...)
		p50, p95 := latencyPercentiles(latencies)
		out.EndpointMetrics = append(out.EndpointMetrics, EndpointHealth{
			Position:       index + 1,
			State:          endpointState(ep, open),
			Successes:      ep.successes,
			Failures:       ep.failures,
			FailureMetrics: ep.failureCounts.snapshot(),
			LastLatencyMs:  ep.lastLatencyMs,
			LatencyP50Ms:   p50,
			LatencyP95Ms:   p95,
			Samples:        len(latencies),
		})
	}
	out.LatencyP50Ms, out.LatencyP95Ms = latencyPercentiles(allLatencies)
	out.Samples = len(allLatencies)
	return out
}

func failureKindOf(err error) failureKind {
	var failure *attemptFailure
	if errors.As(err, &failure) {
		return failure.kind
	}
	return failureOther
}

func (c *failureCounts) increment(kind failureKind) {
	switch kind {
	case failureRateLimited:
		c.rateLimited++
	case failureTimeout:
		c.timeouts++
	case failureMalformed:
		c.malformed++
	case failureTransport:
		c.transport++
	case failureServer:
		c.server++
	case failureProvider:
		c.provider++
	default:
		c.other++
	}
}

func (c failureCounts) snapshot() FailureMetrics {
	return FailureMetrics{
		RateLimited:       c.rateLimited,
		Timeouts:          c.timeouts,
		MalformedResponse: c.malformed,
		Transport:         c.transport,
		ServerErrors:      c.server,
		ProviderErrors:    c.provider,
		Other:             c.other,
	}
}

func (m *FailureMetrics) add(other FailureMetrics) {
	m.RateLimited += other.RateLimited
	m.Timeouts += other.Timeouts
	m.MalformedResponse += other.MalformedResponse
	m.Transport += other.Transport
	m.ServerErrors += other.ServerErrors
	m.ProviderErrors += other.ProviderErrors
	m.Other += other.Other
}

func (e *endpoint) recordLatency(latencyMs int64) {
	e.latencySamples[e.latencySampleNext] = max(latencyMs, 0)
	e.latencySampleNext = (e.latencySampleNext + 1) % latencyWindowSize
	if e.latencySampleCount < latencyWindowSize {
		e.latencySampleCount++
	}
}

func (e *endpoint) latencies() []int64 {
	out := make([]int64, e.latencySampleCount)
	if e.latencySampleCount == 0 {
		return out
	}
	start := 0
	if e.latencySampleCount == latencyWindowSize {
		start = e.latencySampleNext
	}
	for i := range e.latencySampleCount {
		out[i] = e.latencySamples[(start+i)%latencyWindowSize]
	}
	return out
}

func latencyPercentiles(samples []int64) (p50, p95 int64) {
	if len(samples) == 0 {
		return 0, 0
	}
	ordered := append([]int64(nil), samples...)
	slices.Sort(ordered)
	nearestRank := func(percent int) int64 {
		// Integer ceil(percent * n / 100), converted to a zero-based index.
		rank := (percent*len(ordered) + 99) / 100
		return ordered[max(rank-1, 0)]
	}
	return nearestRank(50), nearestRank(95)
}

func endpointState(ep *endpoint, open bool) string {
	if open {
		return "open"
	}
	if ep.successes == 0 && ep.failures == 0 {
		return "unknown"
	}
	if ep.fails > 0 || (ep.failures > 0 && ep.failures*10 > ep.successes+ep.failures) {
		return "degraded"
	}
	return "healthy"
}

func hostOf(raw string) string {
	if u, err := url.Parse(raw); err == nil && u.Hostname() != "" {
		return u.Hostname()
	}
	return "upstream"
}
