package handlers_test

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	"ktwallet/gateway/internal/handlers"
	"ktwallet/gateway/internal/rpc"
)

// newCoinGeckoFake serves /api/v3/simple/price from a fixed id->usd table,
// echoing only the requested ids (like the real API).
func newCoinGeckoFake(t *testing.T, table map[string]float64) *restFake {
	f := newRESTFake(t)
	f.route("/api/v3/simple/price", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("include_24hr_change") != "true" {
			t.Errorf("include_24hr_change must be true, got %q", r.URL.Query().Get("include_24hr_change"))
		}
		if r.URL.Query().Get("include_last_updated_at") != "true" {
			t.Errorf("include_last_updated_at must be true, got %q", r.URL.Query().Get("include_last_updated_at"))
		}
		if r.URL.Query().Get("precision") != "full" {
			t.Errorf("precision must be full, got %q", r.URL.Query().Get("precision"))
		}
		out := map[string]map[string]any{}
		for _, id := range strings.Split(r.URL.Query().Get("ids"), ",") {
			if usd, ok := table[id]; ok {
				out[id] = map[string]any{
					"usd":             usd,
					"usd_24h_change":  nil,
					"cny":             usd * 7,
					"cny_24h_change":  nil,
					"jpy":             usd * 150,
					"jpy_24h_change":  nil,
					"last_updated_at": time.Now().Unix(),
				}
			}
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(out)
	})
	return f
}

func TestPricesInclude24HourChangeAndPreserveUnknown(t *testing.T) {
	f := newRESTFake(t)
	f.route("/api/v3/simple/price", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("include_24hr_change") != "true" {
			t.Errorf("include_24hr_change must be true, got %q", r.URL.Query().Get("include_24hr_change"))
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = fmt.Fprintf(w, `{
			"ethereum":{"usd":2000,"cny":14000,"jpy":300000,"usd_24h_change":3.25,"cny_24h_change":3.2,"jpy_24h_change":3.1,"last_updated_at":%d},
			"tether":{"usd":0.999,"cny":6.993,"jpy":149.85,"usd_24h_change":-0.08,"cny_24h_change":-0.07,"jpy_24h_change":-0.06,"last_updated_at":%d},
			"usd-coin":{"usd":1.001,"cny":7.007,"jpy":150.15,"usd_24h_change":null,"cny_24h_change":null,"jpy_24h_change":null,"last_updated_at":%d}
		}`, time.Now().Unix(), time.Now().Unix(), time.Now().Unix())
	})
	e := newEnv(t, func(cfg *handlers.Config) { cfg.CoinGeckoURL = f.srv.URL })

	res := result(t, e.rpc("kt_getPrices", `{"symbols":["ETH","USDT","USDC"]}`))
	assertJSONEq(t, `{
		"ETH":{"usd":2000,"change24h":3.25},
		"USDT":{"usd":0.999,"change24h":-0.08},
		"USDC":{"usd":1.001}
	}`, res["prices"])
	assertJSONEq(t, `{"USD":1,"CNY":7,"JPY":150}`, res["fiatPerUsd"])
}

func TestPricesStablecoinsUseMarketQuotes(t *testing.T) {
	cg := newCoinGeckoFake(t, map[string]float64{
		"tether":   0.999,
		"usd-coin": 1.001,
	})
	e := newEnv(t, func(cfg *handlers.Config) { cfg.CoinGeckoURL = cg.srv.URL })

	resp := e.rpc("kt_getPrices", `{"symbols":["USDT","USDC"]}`)
	res := result(t, resp)
	assertJSONEq(t, `{"USDT":{"usd":0.999},"USDC":{"usd":1.001}}`, res["prices"])
	if _, ok := res["cachedAtMs"].(float64); !ok {
		t.Fatalf("cachedAtMs missing: %v", res)
	}
	if got := cg.hitCount("/api/v3/simple/price"); got != 1 {
		t.Fatalf("stablecoins must use the live market feed: CoinGecko saw %d calls", got)
	}
}

func TestPricesMixedFetch(t *testing.T) {
	cg := newCoinGeckoFake(t, map[string]float64{
		"ethereum": 2345.67, "solana": 98.5, "avalanche-2": 22.25,
		"tether": 0.998, "binance-usd": 0.997,
	})
	e := newEnv(t, func(cfg *handlers.Config) { cfg.CoinGeckoURL = cg.srv.URL })

	resp := e.rpc("kt_getPrices", `{"symbols":["ETH","USDT","BUSD","SOL","AVAX"]}`)
	res := result(t, resp)
	assertJSONEq(t, `{
		"ETH":{"usd":2345.67},"SOL":{"usd":98.5},"AVAX":{"usd":22.25},
		"USDT":{"usd":0.998},"BUSD":{"usd":0.997}
	}`, res["prices"])

	hits := cg.hitsFor("/api/v3/simple/price")
	if len(hits) != 1 {
		t.Fatalf("expected exactly one CoinGecko call, got %d", len(hits))
	}
	// Stablecoins must be queried too so depegs are visible.
	u, _ := url.Parse(hits[0].Path)
	ids := u.Query().Get("ids")
	if !strings.Contains(ids, "tether") || !strings.Contains(ids, "binance-usd") {
		t.Fatalf("stablecoin ids must be fetched, got ids=%q", ids)
	}
	if !strings.Contains(ids, "ethereum") || !strings.Contains(ids, "solana") ||
		!strings.Contains(ids, "avalanche-2") {
		t.Fatalf("expected ethereum+solana+avalanche in ids, got %q", ids)
	}
	if u.Query().Get("vs_currencies") != "usd,cny,jpy" {
		t.Fatalf("vs_currencies must be usd,cny,jpy, got %q", u.Query().Get("vs_currencies"))
	}
	if u.Query().Get("include_24hr_change") != "true" {
		t.Fatalf("include_24hr_change must be true, got %q", u.Query().Get("include_24hr_change"))
	}
}

func TestPricesUsesDeterministicMedianFiatRate(t *testing.T) {
	f := newRESTFake(t)
	f.route("/api/v3/simple/price", func(w http.ResponseWriter, _ *http.Request) {
		now := time.Now().Unix()
		quote := func(usd, cnyRate, jpyRate float64) string {
			return fmt.Sprintf(`{"usd":%g,"usd_24h_change":null,`+
				`"cny":%g,"cny_24h_change":null,`+
				`"jpy":%g,"jpy_24h_change":null,"last_updated_at":%d}`,
				usd, usd*cnyRate, usd*jpyRate, now)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = fmt.Fprintf(w, `{"avalanche-2":%s,"ethereum":%s,"solana":%s}`,
			quote(20, 6.99, 149.9),
			quote(2000, 7.00, 150.0),
			quote(100, 7.01, 150.1),
		)
	})
	e := newEnv(t, func(cfg *handlers.Config) { cfg.CoinGeckoURL = f.srv.URL })

	res := result(t, e.rpc("kt_getPrices", `{"symbols":["AVAX","ETH","SOL"]}`))
	assertJSONEq(t, `{"USD":1,"CNY":7,"JPY":150}`, res["fiatPerUsd"])
}

func TestPricesUnknownSymbolOmitted(t *testing.T) {
	cg := newCoinGeckoFake(t, map[string]float64{"ethereum": 2000})
	e := newEnv(t, func(cfg *handlers.Config) { cfg.CoinGeckoURL = cg.srv.URL })

	resp := e.rpc("kt_getPrices", `{"symbols":["ETH","DOGE","WAT"]}`)
	res := result(t, resp)
	assertJSONEq(t, `{"ETH":{"usd":2000}}`, res["prices"])
}

func TestPricesCacheHitWithinTTL(t *testing.T) {
	cg := newCoinGeckoFake(t, map[string]float64{"ethereum": 2000})
	e := newEnv(t, func(cfg *handlers.Config) { cfg.CoinGeckoURL = cg.srv.URL })

	res1 := result(t, e.rpc("kt_getPrices", `{"symbols":["ETH"]}`))
	e.clk.Advance(29 * time.Second)
	res2 := result(t, e.rpc("kt_getPrices", `{"symbols":["ETH"]}`))

	if got := cg.hitCount("/api/v3/simple/price"); got != 1 {
		t.Fatalf("second request within TTL must be served from cache, upstream calls = %d", got)
	}
	if res1["cachedAtMs"] != res2["cachedAtMs"] {
		t.Fatalf("cached response must report the original cachedAtMs (%v vs %v)", res1["cachedAtMs"], res2["cachedAtMs"])
	}
}

func TestPricesCacheExpiry(t *testing.T) {
	cg := newCoinGeckoFake(t, map[string]float64{"ethereum": 2000})
	e := newEnv(t, func(cfg *handlers.Config) { cfg.CoinGeckoURL = cg.srv.URL })

	res1 := result(t, e.rpc("kt_getPrices", `{"symbols":["ETH"]}`))
	e.clk.Advance(31 * time.Second)
	res2 := result(t, e.rpc("kt_getPrices", `{"symbols":["ETH"]}`))

	if got := cg.hitCount("/api/v3/simple/price"); got != 2 {
		t.Fatalf("expired cache must refetch, upstream calls = %d", got)
	}
	if res1["cachedAtMs"] == res2["cachedAtMs"] {
		t.Fatal("cachedAtMs should move forward after a refetch")
	}
}

func TestPricesSymbolOrderSharesCacheKey(t *testing.T) {
	cg := newCoinGeckoFake(t, map[string]float64{"ethereum": 2000, "solana": 100})
	e := newEnv(t, func(cfg *handlers.Config) { cfg.CoinGeckoURL = cg.srv.URL })

	result(t, e.rpc("kt_getPrices", `{"symbols":["ETH","SOL"]}`))
	result(t, e.rpc("kt_getPrices", `{"symbols":["SOL","ETH"]}`))
	if got := cg.hitCount("/api/v3/simple/price"); got != 1 {
		t.Fatalf("symbol order must not defeat the cache, upstream calls = %d", got)
	}
}

func TestPricesUpstreamLimiterSpacesCalls(t *testing.T) {
	cg := newCoinGeckoFake(t, map[string]float64{"ethereum": 2000, "tron": 0.1})
	const spacing = 150 * time.Millisecond
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.CoinGeckoURL = cg.srv.URL
		cfg.CoinGeckoInterval = spacing
	})

	// Different symbol sets -> different cache keys -> two upstream calls.
	result(t, e.rpc("kt_getPrices", `{"symbols":["ETH"]}`))
	result(t, e.rpc("kt_getPrices", `{"symbols":["TRX"]}`))

	hits := cg.hitsFor("/api/v3/simple/price")
	if len(hits) != 2 {
		t.Fatalf("expected 2 upstream calls, got %d", len(hits))
	}
	if gap := hits[1].At.Sub(hits[0].At); gap < spacing-30*time.Millisecond {
		t.Fatalf("outbound limiter must space CoinGecko calls: gap was %v, want >= ~%v", gap, spacing)
	}
}

func TestPricesInvalidParams(t *testing.T) {
	e := newEnv(t, nil) // CoinGecko unreachable: any upstream call would error
	for _, params := range []string{`{}`, `{"symbols":[]}`, `{"symbols":"ETH"}`, `null`} {
		resp := e.rpc("kt_getPrices", params)
		assertErrCode(t, resp, rpc.CodeInvalidParams)
	}
}

func TestPricesUpstreamFailure(t *testing.T) {
	f := newRESTFake(t)
	f.route("/api/v3/simple/price", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(500)
	})
	e := newEnv(t, func(cfg *handlers.Config) { cfg.CoinGeckoURL = f.srv.URL })

	resp := e.rpc("kt_getPrices", `{"symbols":["ETH"]}`)
	errObj := assertErrCode(t, resp, rpc.CodeUpstream)
	d := errData(t, errObj)
	if d["upstream"] != "coingecko" {
		t.Fatalf("expected coingecko upstream in error data, got %v", d)
	}
}

func TestPricesMalformedResponseDoesNotPoisonCache(t *testing.T) {
	f := newRESTFake(t)
	var calls int
	f.route("/api/v3/simple/price", func(w http.ResponseWriter, _ *http.Request) {
		calls++
		w.Header().Set("Content-Type", "application/json")
		if calls == 1 {
			_, _ = w.Write([]byte(`{"ethereum":{"usd":2000,"cny":14000,"jpy":300000}}`))
			return
		}
		_, _ = fmt.Fprintf(w, `{"ethereum":{`+
			`"usd":2000,"usd_24h_change":null,`+
			`"cny":14000,"cny_24h_change":null,`+
			`"jpy":300000,"jpy_24h_change":null,`+
			`"last_updated_at":%d}}`, time.Now().Unix())
	})
	e := newEnv(t, func(cfg *handlers.Config) { cfg.CoinGeckoURL = f.srv.URL })

	assertErrCode(t, e.rpc("kt_getPrices", `{"symbols":["ETH"]}`), rpc.CodeUpstream)
	res := result(t, e.rpc("kt_getPrices", `{"symbols":["ETH"]}`))
	assertJSONEq(t, `{"ETH":{"usd":2000}}`, res["prices"])
	if calls != 2 {
		t.Fatalf("malformed response must not populate cache, calls=%d", calls)
	}
}

func TestPricesLiveSupportedCatalog(t *testing.T) {
	if os.Getenv("KT_LIVE_COINGECKO") != "1" {
		t.Skip("set KT_LIVE_COINGECKO=1 for the read-only supported catalog smoke test")
	}
	symbols := []string{
		"ETH", "POL", "AVAX", "BNB", "TRX", "SOL", "USDT", "USDC", "BUSD",
		"DAI", "WETH", "WBTC", "LINK", "UNI", "SHIB", "PEPE", "JUP", "BONK", "PYUSD",
	}
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.CoinGeckoURL = "https://api.coingecko.com"
		cfg.AttemptTimeout = 15 * time.Second
	})

	res := result(t, e.rpc("kt_getPrices", map[string]any{"symbols": symbols}))
	prices, ok := res["prices"].(map[string]any)
	if !ok || len(prices) != len(symbols) {
		t.Fatalf("live supported price count=%d, want %d: %v", len(prices), len(symbols), res["prices"])
	}
	for _, symbol := range symbols {
		if _, present := prices[symbol]; !present {
			t.Fatalf("live supported price is missing %s", symbol)
		}
	}
}
