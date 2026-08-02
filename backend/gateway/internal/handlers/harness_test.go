package handlers_test

import (
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"

	"ktwallet/gateway/internal/clock"
	"ktwallet/gateway/internal/handlers"
	"ktwallet/gateway/internal/ratelimit"
	"ktwallet/gateway/internal/rpc"
)

// unreachable is a URL that refuses connections immediately. Every upstream
// defaults to it so a test that should not hit the network fails fast (and
// visibly) if it does.
const unreachable = "http://127.0.0.1:1"

// Verified TRON base58check <-> hex pairs (see validate_test.go).
const (
	tronSelfB58  = "TS6pWDWcKRYfZFzDMgUp7vzjVhyHfq4c4C"
	tronSelfHex  = "41b0f28f797f0e57e56c1729783b7a5e5d4bacd0f4"
	tronOtherB58 = "TUQQ9bYZNGPhzFTSKvqxYkAvgQQD2Ha9uT"
	tronOtherHex = "41ca35f7e6b1f67bf1eedee6d25b3b0f4a52d4b1cc"
	tronUSDT     = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"
	evmSelf      = "0x1111111111111111111111111111111111111111"
	evmTokenA    = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	evmTokenB    = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
	solSelf      = "9xQeWvG816bUx9EPjHmaT23yvVM2ZWbrrpZb9PusVFin"
	solOther     = "4Nd1mYtBS4yPPsSycFSCA1WzX7yBW2cVDpn9WzWtLDwT"
)

// --- generic JSON-RPC fake (EVM and Solana nodes) --------------------------

type rpcFake struct {
	t   *testing.T
	srv *httptest.Server

	mu       sync.Mutex
	calls    map[string]int
	lastReq  map[string][]json.RawMessage
	handlers map[string]func(params []json.RawMessage) (result any, rpcError map[string]any)
}

func newRPCFake(t *testing.T) *rpcFake {
	t.Helper()
	f := &rpcFake{
		t:        t,
		calls:    map[string]int{},
		lastReq:  map[string][]json.RawMessage{},
		handlers: map[string]func([]json.RawMessage) (any, map[string]any){},
	}
	f.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Method string            `json:"method"`
			Params []json.RawMessage `json:"params"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, "bad request body", 400)
			return
		}
		f.mu.Lock()
		f.calls[req.Method]++
		f.lastReq[req.Method] = req.Params
		h := f.handlers[req.Method]
		f.mu.Unlock()

		w.Header().Set("Content-Type", "application/json")
		if h == nil {
			_ = json.NewEncoder(w).Encode(map[string]any{
				"jsonrpc": "2.0", "id": 1,
				"error": map[string]any{"code": -32601, "message": "unexpected method in test: " + req.Method},
			})
			return
		}
		result, rpcError := h(req.Params)
		resp := map[string]any{"jsonrpc": "2.0", "id": 1}
		if rpcError != nil {
			resp["error"] = rpcError
		} else {
			resp["result"] = result
		}
		_ = json.NewEncoder(w).Encode(resp)
	}))
	t.Cleanup(f.srv.Close)
	return f
}

func (f *rpcFake) handle(method string, h func([]json.RawMessage) (any, map[string]any)) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.handlers[method] = h
}

func (f *rpcFake) result(method string, result any) {
	f.handle(method, func([]json.RawMessage) (any, map[string]any) { return result, nil })
}

func (f *rpcFake) nodeError(method string, code int, msg string) {
	f.handle(method, func([]json.RawMessage) (any, map[string]any) {
		return nil, map[string]any{"code": code, "message": msg}
	})
}

func (f *rpcFake) count(method string) int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.calls[method]
}

func (f *rpcFake) totalCalls() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	n := 0
	for _, c := range f.calls {
		n += c
	}
	return n
}

func (f *rpcFake) params(method string) []json.RawMessage {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.lastReq[method]
}

// --- generic REST fake (TronGrid, CoinGecko, Etherscan, Helius) ------------

type restHit struct {
	Path string // path?query
	Body string
	At   time.Time
}

type restFake struct {
	srv *httptest.Server

	mu     sync.Mutex
	hits   []restHit
	routes map[string]http.HandlerFunc // matched by longest path prefix
}

func newRESTFake(t *testing.T) *restFake {
	t.Helper()
	f := &restFake{routes: map[string]http.HandlerFunc{}}
	f.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		r.Body = io.NopCloser(strings.NewReader(string(body)))
		f.mu.Lock()
		f.hits = append(f.hits, restHit{Path: r.URL.RequestURI(), Body: string(body), At: time.Now()})
		var best string
		for prefix := range f.routes {
			if strings.HasPrefix(r.URL.Path, prefix) && len(prefix) > len(best) {
				best = prefix
			}
		}
		h := f.routes[best]
		f.mu.Unlock()
		if h == nil {
			http.Error(w, "no test route for "+r.URL.Path, 404)
			return
		}
		h(w, r)
	}))
	t.Cleanup(f.srv.Close)
	return f
}

func (f *restFake) route(prefix string, h http.HandlerFunc) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.routes[prefix] = h
}

func (f *restFake) routeJSON(prefix string, body string) {
	f.route(prefix, func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(body))
	})
}

func (f *restFake) hitsFor(prefix string) []restHit {
	f.mu.Lock()
	defer f.mu.Unlock()
	var out []restHit
	for _, h := range f.hits {
		if strings.HasPrefix(h.Path, prefix) {
			out = append(out, h)
		}
	}
	return out
}

func (f *restFake) hitCount(prefix string) int { return len(f.hitsFor(prefix)) }

// --- gateway test environment ----------------------------------------------

type env struct {
	t   *testing.T
	clk *clock.Fake
	srv *rpc.Server
	gw  *handlers.Gateway
}

func discardLog() *slog.Logger { return slog.New(slog.NewTextHandler(io.Discard, nil)) }

// newEnv builds a gateway whose upstreams all point at an unreachable
// address; tests override just the upstreams they script.
func newEnv(t *testing.T, mutate func(cfg *handlers.Config)) *env {
	t.Helper()
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	cfg := handlers.Config{
		Version:                  "9.9.9-test",
		Log:                      discardLog(),
		Clock:                    clk,
		AttemptTimeout:           2 * time.Second,
		EthURLs:                  []string{unreachable},
		PolygonURLs:              []string{unreachable},
		BaseURLs:                 []string{unreachable},
		ArbitrumURLs:             []string{unreachable},
		AvalancheURLs:            []string{unreachable},
		BNBURLs:                  []string{unreachable},
		SolanaURLs:               []string{unreachable},
		TronURL:                  unreachable,
		EthSepoliaURLs:           []string{unreachable},
		PolygonAmoyURLs:          []string{unreachable},
		BaseSepoliaURLs:          []string{unreachable},
		ArbitrumSepoliaURLs:      []string{unreachable},
		AvalancheFujiURLs:        []string{unreachable},
		BNBTestnetURLs:           []string{unreachable},
		SolanaDevnetURLs:         []string{unreachable},
		TronNileURL:              unreachable,
		CoinGeckoURL:             unreachable,
		CoinGeckoInterval:        time.Millisecond,
		EtherscanURL:             unreachable,
		HeliusURL:                unreachable,
		HeliusDevnetURL:          unreachable,
		DisableExternalTokenRisk: true,
		DisableExternalApprovals: true,
		EVMHistoryFallbackURLs:   map[string]string{},
	}
	if mutate != nil {
		mutate(&cfg)
	}
	g := handlers.New(cfg)
	// Generous inbound limiter so ordinary tests never trip it.
	srv := rpc.NewServer(cfg.Log, ratelimit.New(clk, 100000, 100000), 25*time.Second)
	g.Register(srv)
	return &env{t: t, clk: clk, srv: srv, gw: g}
}

// do posts a raw body to the JSON-RPC endpoint.
func (e *env) do(body, remoteAddr string) (int, map[string]any) {
	e.t.Helper()
	req := httptest.NewRequest("POST", "/rpc", strings.NewReader(body))
	if remoteAddr != "" {
		req.RemoteAddr = remoteAddr
	}
	rec := httptest.NewRecorder()
	e.srv.ServeHTTP(rec, req)
	if rec.Body.Len() == 0 {
		return rec.Code, nil
	}
	var out map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		e.t.Fatalf("non-JSON response: %v\n%s", err, rec.Body.String())
	}
	return rec.Code, out
}

// rpc calls a method with params (any JSON-marshalable value or raw string).
func (e *env) rpc(method string, params any) map[string]any {
	e.t.Helper()
	var paramsJSON string
	switch p := params.(type) {
	case nil:
		paramsJSON = "{}"
	case string:
		paramsJSON = p
	default:
		b, err := json.Marshal(p)
		if err != nil {
			e.t.Fatal(err)
		}
		paramsJSON = string(b)
	}
	_, resp := e.do(fmt.Sprintf(`{"jsonrpc":"2.0","id":1,"method":%q,"params":%s}`, method, paramsJSON), "")
	return resp
}

// result extracts a successful result or fails the test.
func result(t *testing.T, resp map[string]any) map[string]any {
	t.Helper()
	if resp["error"] != nil {
		t.Fatalf("unexpected error: %v", resp["error"])
	}
	r, ok := resp["result"].(map[string]any)
	if !ok {
		t.Fatalf("missing/invalid result: %v", resp)
	}
	return r
}

// rpcError extracts the error object or fails the test.
func rpcError(t *testing.T, resp map[string]any) map[string]any {
	t.Helper()
	e, ok := resp["error"].(map[string]any)
	if !ok {
		t.Fatalf("expected an error, got: %v", resp)
	}
	return e
}

func assertErrCode(t *testing.T, resp map[string]any, code int) map[string]any {
	t.Helper()
	e := rpcError(t, resp)
	if int(e["code"].(float64)) != code {
		t.Fatalf("error code = %v, want %d (error: %v)", e["code"], code, e)
	}
	return e
}

// assertJSONEq compares got (already-decoded JSON) with a golden JSON string.
func assertJSONEq(t *testing.T, wantJSON string, got any) {
	t.Helper()
	var want any
	if err := json.Unmarshal([]byte(wantJSON), &want); err != nil {
		t.Fatalf("bad golden JSON: %v", err)
	}
	// Normalize got through a JSON round-trip.
	b, err := json.Marshal(got)
	if err != nil {
		t.Fatal(err)
	}
	var norm any
	_ = json.Unmarshal(b, &norm)
	if !reflect.DeepEqual(want, norm) {
		t.Fatalf("JSON mismatch:\n got: %s\nwant: %s", b, wantJSON)
	}
}

func errData(t *testing.T, e map[string]any) map[string]any {
	t.Helper()
	d, ok := e["data"].(map[string]any)
	if !ok {
		t.Fatalf("error is missing data: %v", e)
	}
	return d
}
