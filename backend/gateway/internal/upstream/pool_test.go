package upstream

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"ktwallet/gateway/internal/clock"
)

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(req *http.Request) (*http.Response, error) {
	return f(req)
}

// fakeNode is a scriptable JSON-RPC endpoint that counts hits.
type fakeNode struct {
	srv  *httptest.Server
	hits atomic.Int64
	mu   sync.Mutex
	// respond decides the answer; nil means `{"result":"ok"}`.
	respond func(w http.ResponseWriter, r *http.Request)
}

func (n *fakeNode) setRespond(f func(http.ResponseWriter, *http.Request)) {
	n.mu.Lock()
	defer n.mu.Unlock()
	n.respond = f
}

func newFakeNode(t *testing.T, respond func(w http.ResponseWriter, r *http.Request)) *fakeNode {
	t.Helper()
	n := &fakeNode{respond: respond}
	n.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		n.hits.Add(1)
		n.mu.Lock()
		respond := n.respond
		n.mu.Unlock()
		if respond != nil {
			respond(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"jsonrpc":"2.0","id":1,"result":"ok"}`))
	}))
	t.Cleanup(n.srv.Close)
	return n
}

func respondStatus(code int) func(http.ResponseWriter, *http.Request) {
	return func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(code) }
}

func TestFailoverOn500(t *testing.T) {
	dead := newFakeNode(t, respondStatus(500))
	alive := newFakeNode(t, nil)
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	p := NewPool("eth", []string{dead.srv.URL, alive.srv.URL}, clk, nil, time.Second)

	res, err := p.Call(context.Background(), "eth_gasPrice", nil)
	if err != nil {
		t.Fatalf("expected failover success, got %v", err)
	}
	if string(res) != `"ok"` {
		t.Fatalf("unexpected result %s", res)
	}
	if dead.hits.Load() != 1 || alive.hits.Load() != 1 {
		t.Fatalf("both URLs should be hit exactly once, got %d/%d", dead.hits.Load(), alive.hits.Load())
	}
}

func TestCallOnceDoesNotFailOverAfterWriteAttempt(t *testing.T) {
	dead := newFakeNode(t, respondStatus(503))
	alive := newFakeNode(t, nil)
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	p := NewPool("eth", []string{dead.srv.URL, alive.srv.URL}, clk, nil, time.Second)

	_, err := p.CallOnce(context.Background(), "eth_sendRawTransaction", []any{"0x00"})
	var unavailable *Unavailable
	if !errors.As(err, &unavailable) {
		t.Fatalf("expected result-unknown Unavailable, got %v", err)
	}
	if dead.hits.Load() != 1 || alive.hits.Load() != 0 {
		t.Fatalf("write must hit one endpoint only, got %d/%d", dead.hits.Load(), alive.hits.Load())
	}
}

func TestTransportFailureDoesNotExposeCredentialBearingURL(t *testing.T) {
	secret := strings.Join([]string{"mN4pQ8vZ2sK7", "cR5xT9wY3dF6", "hJ8uL1aB0eG7"}, "")
	client := &http.Client{Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
		return nil, errors.New(`Post "` + req.URL.String() + `": connection refused`)
	})}
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	p := NewPool(
		"eth",
		[]string{"https://eth-mainnet.example.invalid/v2/" + secret},
		clk,
		client,
		time.Second,
	)

	_, err := p.CallOnce(context.Background(), "eth_sendRawTransaction", []any{"0x00"})
	var unavailable *Unavailable
	if !errors.As(err, &unavailable) {
		t.Fatalf("expected Unavailable, got %v", err)
	}
	if strings.Contains(err.Error(), secret) || strings.Contains(unavailable.Message, secret) {
		t.Fatalf("transport failure exposed provider credential: %v", err)
	}
}

func TestCallOnceProviderRoutingErrorIsUnknownWithoutFailover(t *testing.T) {
	disabled := newFakeNode(t, func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"jsonrpc":"2.0","id":1,"error":{
			"code":-32000,"message":"network is not enabled for this app"
		}}`))
	})
	enabled := newFakeNode(t, nil)
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	p := NewPool("eth", []string{disabled.srv.URL, enabled.srv.URL}, clk, nil, time.Second)

	_, err := p.CallOnce(context.Background(), "eth_sendRawTransaction", []any{"0x00"})
	var unavailable *Unavailable
	if !errors.As(err, &unavailable) {
		t.Fatalf("provider routing failure must remain result-unknown, got %v", err)
	}
	if disabled.hits.Load() != 1 || enabled.hits.Load() != 0 {
		t.Fatalf("write must not fail over after provider response, got %d/%d", disabled.hits.Load(), enabled.hits.Load())
	}
}

func TestCallOncePreservesExplicitNodeRejection(t *testing.T) {
	rejecting := newFakeNode(t, func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"jsonrpc":"2.0","id":1,"error":{"code":-32000,"message":"nonce too low"}}`))
	})
	second := newFakeNode(t, nil)
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	p := NewPool("eth", []string{rejecting.srv.URL, second.srv.URL}, clk, nil, time.Second)

	_, err := p.CallOnce(context.Background(), "eth_sendRawTransaction", []any{"0x00"})
	var nodeErr *NodeError
	if !errors.As(err, &nodeErr) || nodeErr.Message != "nonce too low" {
		t.Fatalf("expected explicit node rejection, got %v", err)
	}
	if rejecting.hits.Load() != 1 || second.hits.Load() != 0 {
		t.Fatalf("node rejection must not fail over, got %d/%d", rejecting.hits.Load(), second.hits.Load())
	}
}

func TestCallOnceMaySelectNextEndpointOnlyWhenEarlierCircuitWasAlreadyOpen(t *testing.T) {
	dead := newFakeNode(t, respondStatus(503))
	alive := newFakeNode(t, nil)
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	p := NewPool("eth", []string{dead.srv.URL, alive.srv.URL}, clk, nil, time.Second)

	for range FailThreshold {
		if _, err := p.Call(context.Background(), "eth_blockNumber", nil); err != nil {
			t.Fatal(err)
		}
	}
	if dead.hits.Load() != FailThreshold || alive.hits.Load() != FailThreshold {
		t.Fatalf("read setup must open the first circuit, got %d/%d", dead.hits.Load(), alive.hits.Load())
	}

	result, err := p.CallOnce(context.Background(), "eth_sendRawTransaction", []any{"0x00"})
	if err != nil || string(result) != `"ok"` {
		t.Fatalf("eligible endpoint should accept the single write: result=%s err=%v", result, err)
	}
	if dead.hits.Load() != FailThreshold || alive.hits.Load() != FailThreshold+1 {
		t.Fatalf("open endpoint must be skipped before submission, got %d/%d", dead.hits.Load(), alive.hits.Load())
	}
}

func TestFailoverOn429(t *testing.T) {
	limited := newFakeNode(t, respondStatus(429))
	alive := newFakeNode(t, nil)
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	p := NewPool("eth", []string{limited.srv.URL, alive.srv.URL}, clk, nil, time.Second)

	if _, err := p.Call(context.Background(), "eth_gasPrice", nil); err != nil {
		t.Fatalf("429 should fail over: %v", err)
	}
	if limited.hits.Load() != 1 || alive.hits.Load() != 1 {
		t.Fatalf("want 1/1 hits, got %d/%d", limited.hits.Load(), alive.hits.Load())
	}
	health := p.Health()
	if health.FailureMetrics.RateLimited != 1 ||
		health.FailureMetrics.ServerErrors != 0 {
		t.Fatalf("429 must have its own failure bucket: %+v", health.FailureMetrics)
	}
}

func TestRoundRobinPrefixBalancesPrimariesBeforeFallback(t *testing.T) {
	primaryA := newFakeNode(t, nil)
	primaryB := newFakeNode(t, nil)
	fallback := newFakeNode(t, nil)
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	p := NewPoolRoundRobinPrefix(
		"eth",
		[]string{primaryA.srv.URL, primaryB.srv.URL, fallback.srv.URL},
		2,
		clk,
		nil,
		time.Second,
	)

	for range 6 {
		if _, err := p.Call(context.Background(), "eth_blockNumber", nil); err != nil {
			t.Fatal(err)
		}
	}
	if primaryA.hits.Load() != 3 || primaryB.hits.Load() != 3 {
		t.Fatalf(
			"primaries must be balanced evenly, hits = %d/%d",
			primaryA.hits.Load(),
			primaryB.hits.Load(),
		)
	}
	if fallback.hits.Load() != 0 {
		t.Fatalf("healthy primaries must not touch fallback, hits = %d", fallback.hits.Load())
	}
}

func TestNoFailoverOnNodeError(t *testing.T) {
	erroring := newFakeNode(t, func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"jsonrpc":"2.0","id":1,"error":{"code":-32000,"message":"nonce too low"}}`))
	})
	second := newFakeNode(t, nil)
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	p := NewPool("eth", []string{erroring.srv.URL, second.srv.URL}, clk, nil, time.Second)

	_, err := p.Call(context.Background(), "eth_sendRawTransaction", []any{"0x00"})
	var ne *NodeError
	if !errors.As(err, &ne) {
		t.Fatalf("expected NodeError, got %v", err)
	}
	if ne.Message != "nonce too low" {
		t.Fatalf("node message lost: %q", ne.Message)
	}
	if second.hits.Load() != 0 {
		t.Fatal("a valid JSON-RPC error result must NOT trigger failover")
	}
	// And the endpoint's circuit must not accumulate failures.
	if _, err := p.Call(context.Background(), "eth_sendRawTransaction", []any{"0x00"}); err == nil {
		t.Fatal("expected node error again")
	}
	if erroring.hits.Load() != 2 {
		t.Fatalf("node-error endpoint should stay first in rotation, hits=%d", erroring.hits.Load())
	}
}

func TestFailoverWhenProviderKeyHasNotEnabledNetwork(t *testing.T) {
	disabled := newFakeNode(t, func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"jsonrpc":"2.0","id":1,"error":{
			"code":-32000,
			"message":"BNB_TESTNET is not enabled for this app. Visit the dashboard to enable the network"
		}}`))
	})
	enabled := newFakeNode(t, nil)
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	p := NewPoolRoundRobinPrefix(
		"bnb-testnet",
		[]string{disabled.srv.URL, enabled.srv.URL},
		2,
		clk,
		nil,
		time.Second,
	)

	if _, err := p.Call(context.Background(), "eth_blockNumber", nil); err != nil {
		t.Fatalf("disabled provider app must fail over to another key: %v", err)
	}
	if disabled.hits.Load() != 1 || enabled.hits.Load() != 1 {
		t.Fatalf("want disabled/enabled hits 1/1, got %d/%d", disabled.hits.Load(), enabled.hits.Load())
	}
	if got := p.Health().FailureMetrics.ProviderErrors; got != 1 {
		t.Fatalf("provider routing failure count = %d, want 1", got)
	}
}

func TestCircuitOpensAfterThreeFailuresAndRecloses(t *testing.T) {
	dead := newFakeNode(t, respondStatus(503))
	alive := newFakeNode(t, nil)
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	p := NewPool("eth", []string{dead.srv.URL, alive.srv.URL}, clk, nil, time.Second)

	for i := 0; i < 3; i++ {
		if _, err := p.Call(context.Background(), "eth_gasPrice", nil); err != nil {
			t.Fatalf("call %d should succeed via failover: %v", i, err)
		}
	}
	if dead.hits.Load() != 3 {
		t.Fatalf("dead endpoint should have been tried 3 times, got %d", dead.hits.Load())
	}

	// 4th call: circuit is open, the dead endpoint must not be touched.
	if _, err := p.Call(context.Background(), "eth_gasPrice", nil); err != nil {
		t.Fatal(err)
	}
	if dead.hits.Load() != 3 {
		t.Fatalf("dead endpoint hit while its circuit was open (hits=%d)", dead.hits.Load())
	}
	health := p.Health()
	if health.Endpoints != 2 || health.OpenCircuits != 1 ||
		health.Failures != 3 || health.Successes != 4 {
		t.Fatalf("unexpected health snapshot while circuit is open: %+v", health)
	}

	// Just before the window closes it stays skipped...
	clk.Advance(29 * time.Second)
	if _, err := p.Call(context.Background(), "eth_gasPrice", nil); err != nil {
		t.Fatal(err)
	}
	if dead.hits.Load() != 3 {
		t.Fatalf("dead endpoint hit at 29s (hits=%d)", dead.hits.Load())
	}

	// ...and after 30s the endpoint is probed again.
	clk.Advance(2 * time.Second)
	if _, err := p.Call(context.Background(), "eth_gasPrice", nil); err != nil {
		t.Fatal(err)
	}
	if dead.hits.Load() != 4 {
		t.Fatalf("circuit should re-close (allow a probe) after 30s, hits=%d", dead.hits.Load())
	}
}

func TestCircuitResetOnSuccess(t *testing.T) {
	flaky := newFakeNode(t, respondStatus(500))
	alive := newFakeNode(t, nil)
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	p := NewPool("eth", []string{flaky.srv.URL, alive.srv.URL}, clk, nil, time.Second)

	// Two failures, then recovery: the counter must reset.
	_, _ = p.Call(context.Background(), "m", nil)
	_, _ = p.Call(context.Background(), "m", nil)
	flaky.setRespond(nil) // healthy again
	for i := 0; i < 5; i++ {
		if _, err := p.Call(context.Background(), "m", nil); err != nil {
			t.Fatal(err)
		}
	}
	// 2 failures + 6 successes; if the counter had not reset the circuit
	// would have opened on the third call.
	if flaky.hits.Load() != 7 {
		t.Fatalf("expected first endpoint to serve all later calls, hits=%d", flaky.hits.Load())
	}
}

func TestAllUpstreamsFailing(t *testing.T) {
	d1 := newFakeNode(t, respondStatus(502))
	d2 := newFakeNode(t, respondStatus(502))
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	p := NewPool("eth", []string{d1.srv.URL, d2.srv.URL}, clk, nil, time.Second)

	_, err := p.Call(context.Background(), "eth_gasPrice", nil)
	var ua *Unavailable
	if !errors.As(err, &ua) {
		t.Fatalf("expected Unavailable, got %v", err)
	}
	if ua.Message == "" || ua.Upstream == "" {
		t.Fatalf("Unavailable must carry upstream and message: %+v", ua)
	}
}

func TestGarbageResponseFailsOver(t *testing.T) {
	garbage := newFakeNode(t, func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte("<html>not json</html>"))
	})
	alive := newFakeNode(t, nil)
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	p := NewPool("eth", []string{garbage.srv.URL, alive.srv.URL}, clk, nil, time.Second)
	if _, err := p.Call(context.Background(), "eth_gasPrice", nil); err != nil {
		t.Fatalf("garbage body should fail over: %v", err)
	}
	if alive.hits.Load() != 1 {
		t.Fatal("second endpoint should have answered")
	}
	if got := p.Health().FailureMetrics.MalformedResponse; got != 1 {
		t.Fatalf("malformed response count = %d, want 1", got)
	}
}

func TestMissingJSONRPCResultFailsOverAsMalformed(t *testing.T) {
	missing := newFakeNode(t, func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"jsonrpc":"2.0","id":1}`))
	})
	alive := newFakeNode(t, nil)
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	p := NewPool("eth", []string{missing.srv.URL, alive.srv.URL}, clk, nil, time.Second)
	if _, err := p.Call(context.Background(), "eth_gasPrice", nil); err != nil {
		t.Fatalf("missing result must fail over: %v", err)
	}
	if got := p.Health().FailureMetrics.MalformedResponse; got != 1 {
		t.Fatalf("malformed response count = %d, want 1", got)
	}
}

func TestTimeoutHasDedicatedFailureBucket(t *testing.T) {
	slow := newFakeNode(t, func(w http.ResponseWriter, _ *http.Request) {
		time.Sleep(25 * time.Millisecond)
		_, _ = w.Write([]byte(`{"jsonrpc":"2.0","id":1,"result":"late"}`))
	})
	alive := newFakeNode(t, nil)
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	p := NewPool("eth", []string{slow.srv.URL, alive.srv.URL}, clk, nil, 5*time.Millisecond)
	if _, err := p.Call(context.Background(), "eth_gasPrice", nil); err != nil {
		t.Fatalf("timeout must fail over: %v", err)
	}
	health := p.Health()
	if health.FailureMetrics.Timeouts != 1 ||
		health.FailureMetrics.Transport != 0 {
		t.Fatalf("timeout must not be grouped as transport: %+v", health.FailureMetrics)
	}
}

func TestHealthPublishesBoundedLatencyPercentilesAndAnonymousEndpoints(t *testing.T) {
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	p := NewPool(
		"eth",
		[]string{"https://secret-key@example.invalid/v2/private"},
		clk,
		nil,
		time.Second,
	)
	ep := p.eps[0]
	for _, latency := range []time.Duration{
		10 * time.Millisecond,
		20 * time.Millisecond,
		30 * time.Millisecond,
		40 * time.Millisecond,
		100 * time.Millisecond,
	} {
		p.recordSuccess(ep, latency)
	}

	health := p.Health()
	if health.LatencyP50Ms != 30 || health.LatencyP95Ms != 100 ||
		health.Samples != 5 {
		t.Fatalf("unexpected aggregate latency metrics: %+v", health)
	}
	if len(health.EndpointMetrics) != 1 {
		t.Fatalf("endpoint metrics = %d, want 1", len(health.EndpointMetrics))
	}
	endpoint := health.EndpointMetrics[0]
	if endpoint.Position != 1 || endpoint.State != "healthy" ||
		endpoint.LatencyP50Ms != 30 || endpoint.LatencyP95Ms != 100 {
		t.Fatalf("unexpected anonymous endpoint metrics: %+v", endpoint)
	}
	encoded, err := json.Marshal(health)
	if err != nil {
		t.Fatal(err)
	}
	for _, secret := range []string{"secret-key", "example.invalid", "/v2/private"} {
		if string(encoded) == secret || bytes.Contains(encoded, []byte(secret)) {
			t.Fatalf("health metrics leaked endpoint material %q: %s", secret, encoded)
		}
	}
}

func TestLatencyWindowIsBoundedToMostRecentSamples(t *testing.T) {
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	p := NewPool("eth", []string{"https://example.invalid"}, clk, nil, time.Second)
	ep := p.eps[0]
	for i := range latencyWindowSize + 20 {
		p.recordSuccess(ep, time.Duration(i)*time.Millisecond)
	}

	health := p.Health()
	if health.Samples != latencyWindowSize {
		t.Fatalf("samples = %d, want bounded window %d", health.Samples, latencyWindowSize)
	}
	// The first 20 samples were evicted, so the rolling window spans 20..275.
	if health.LatencyP50Ms != 147 || health.LatencyP95Ms != 263 {
		t.Fatalf("unexpected rolling percentiles: p50=%d p95=%d", health.LatencyP50Ms, health.LatencyP95Ms)
	}
}

func TestRequestShape(t *testing.T) {
	var got map[string]any
	node := newFakeNode(t, nil)
	node.setRespond(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewDecoder(r.Body).Decode(&got)
		_, _ = w.Write([]byte(`{"jsonrpc":"2.0","id":1,"result":"0x0"}`))
	})
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	p := NewPool("eth", []string{node.srv.URL}, clk, nil, time.Second)
	if _, err := p.Call(context.Background(), "eth_getBalance", []any{"0xabc", "latest"}); err != nil {
		t.Fatal(err)
	}
	if got["jsonrpc"] != "2.0" || got["method"] != "eth_getBalance" {
		t.Fatalf("malformed outbound request: %v", got)
	}
	params := got["params"].([]any)
	if params[0] != "0xabc" || params[1] != "latest" {
		t.Fatalf("params not forwarded verbatim: %v", params)
	}
}
