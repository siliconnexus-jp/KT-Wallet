package handlers_test

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"

	"ktwallet/gateway/internal/handlers"
)

// deadServer always answers with the given status and counts hits.
type deadServer struct {
	srv  *httptest.Server
	hits atomic.Int64
}

func newDeadServer(t *testing.T, status int) *deadServer {
	d := &deadServer{}
	d.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		d.hits.Add(1)
		w.WriteHeader(status)
	}))
	t.Cleanup(d.srv.Close)
	return d
}

func TestGatewayEVMFailover(t *testing.T) {
	dead := newDeadServer(t, 500)
	alive := newRPCFake(t)
	alive.result("eth_getBalance", "0x64")
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EthURLs = []string{dead.srv.URL, alive.srv.URL}
	})

	res := result(t, e.rpc("kt_getBalances", balancesParams("eth", evmSelf, "")))
	if res["native"].(map[string]any)["raw"] != "100" {
		t.Fatalf("failover result wrong: %v", res)
	}
	if dead.hits.Load() != 1 || alive.count("eth_getBalance") != 1 {
		t.Fatalf("both URLs should be tried once, got %d/%d", dead.hits.Load(), alive.count("eth_getBalance"))
	}
}

func TestGatewayCircuitBreaker(t *testing.T) {
	dead := newDeadServer(t, 503)
	alive := newRPCFake(t)
	alive.result("eth_getBalance", "0x1")
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EthURLs = []string{dead.srv.URL, alive.srv.URL}
	})

	// Distinct addresses defeat the balance cache so each request goes
	// upstream; the dead endpoint accumulates 3 consecutive failures.
	addr := func(i int) string { return fmt.Sprintf("0x%040d", i) }
	for i := 1; i <= 3; i++ {
		result(t, e.rpc("kt_getBalances", balancesParams("eth", addr(i), "")))
	}
	if dead.hits.Load() != 3 {
		t.Fatalf("dead endpoint should have been probed 3 times, got %d", dead.hits.Load())
	}

	// Circuit open: request 4 must not touch the dead endpoint.
	result(t, e.rpc("kt_getBalances", balancesParams("eth", addr(4), "")))
	if dead.hits.Load() != 3 {
		t.Fatalf("dead endpoint hit while circuit open (hits=%d)", dead.hits.Load())
	}

	// After the 30s window the endpoint is probed again.
	e.clk.Advance(31 * time.Second)
	result(t, e.rpc("kt_getBalances", balancesParams("eth", addr(5), "")))
	if dead.hits.Load() != 4 {
		t.Fatalf("circuit must re-close after 30s (hits=%d)", dead.hits.Load())
	}
}
