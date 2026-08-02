package handlers_test

import (
	"encoding/json"
	"net/http"
	"net/url"
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
		out := map[string]map[string]float64{}
		for _, id := range strings.Split(r.URL.Query().Get("ids"), ",") {
			if usd, ok := table[id]; ok {
				out[id] = map[string]float64{
					"usd": usd,
					"cny": usd * 7,
					"jpy": usd * 150,
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
		_, _ = w.Write([]byte(`{
			"ethereum":{"usd":2000,"cny":14000,"jpy":300000,"usd_24h_change":3.25},
			"tether":{"usd":0.999,"cny":6.993,"jpy":149.85,"usd_24h_change":-0.08},
			"usd-coin":{"usd":1.001,"cny":7.007,"jpy":150.15,"usd_24h_change":null}
		}`))
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
