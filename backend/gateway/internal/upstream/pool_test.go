package upstream

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"ktwallet/gateway/internal/clock"
)

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
