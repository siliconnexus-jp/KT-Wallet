package upstream

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"
)

func coinGeckoQuote(updatedAt int64) string {
	return fmt.Sprintf(`{"usd":2000.25,"usd_24h_change":3.25,`+
		`"cny":14001.75,"cny_24h_change":3.2,`+
		`"jpy":300037.5,"jpy_24h_change":3.1,"last_updated_at":%d}`, updatedAt)
}

func newCoinGeckoResponseClient(t *testing.T, payload string, inspect func(*http.Request)) *CoinGecko {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if inspect != nil {
			inspect(r)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = fmt.Fprint(w, payload)
	}))
	t.Cleanup(server.Close)
	return NewCoinGecko(server.URL, server.Client(), nil, time.Second)
}

func TestCoinGeckoRejectsAmbiguousOrUnboundResponses(t *testing.T) {
	t.Parallel()

	now := time.Now().Unix()
	quote := coinGeckoQuote(now)
	tests := []struct {
		name    string
		payload string
	}{
		{"unexpected response id", `{"ethereum":` + quote + `,"solana":` + quote + `}`},
		{"response id alias collision", `{"Ethereum":` + quote + `,"ethereum":` + quote + `}`},
		{"duplicate response id ending valid", `{"ethereum":{"usd":1},"ethereum":` + quote + `}`},
		{"unknown quote member", `{"ethereum":` + strings.Replace(quote, `"last_updated_at":`, `"unexpected":1,"last_updated_at":`, 1) + `}`},
		{"quote member alias collision", `{"ethereum":` + strings.Replace(quote, `"usd":2000.25`, `"USD":1,"usd":2000.25`, 1) + `}`},
		{"duplicate usd ending valid", `{"ethereum":` + strings.Replace(quote, `"usd":2000.25`, `"usd":1,"usd":2000.25`, 1) + `}`},
		{"missing requested response id", `{}`},
		{"missing usd", `{"ethereum":` + strings.Replace(quote, `"usd":2000.25,`, ``, 1) + `}`},
		{"missing cny", `{"ethereum":` + strings.Replace(quote, `"cny":14001.75,`, ``, 1) + `}`},
		{"missing jpy", `{"ethereum":` + strings.Replace(quote, `"jpy":300037.5,`, ``, 1) + `}`},
		{"missing usd change", `{"ethereum":` + strings.Replace(quote, `"usd_24h_change":3.25,`, ``, 1) + `}`},
		{"missing cny change", `{"ethereum":` + strings.Replace(quote, `"cny_24h_change":3.2,`, ``, 1) + `}`},
		{"missing jpy change", `{"ethereum":` + strings.Replace(quote, `"jpy_24h_change":3.1,`, ``, 1) + `}`},
		{"missing source timestamp", `{"ethereum":` + strings.Replace(quote, fmt.Sprintf(`,"last_updated_at":%d`, now), ``, 1) + `}`},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			client := newCoinGeckoResponseClient(t, tc.payload, nil)
			if _, err := client.SimplePrice(context.Background(), []string{"ethereum"}); err == nil {
				t.Fatal("ambiguous or request-unbound CoinGecko response must fail closed")
			}
		})
	}
}

func TestCoinGeckoRejectsInvalidFinancialValuesAndFreshness(t *testing.T) {
	t.Parallel()

	now := time.Now().Unix()
	quote := coinGeckoQuote(now)
	tests := []struct {
		name    string
		payload string
	}{
		{"zero usd", `{"ethereum":` + strings.Replace(quote, `"usd":2000.25`, `"usd":0`, 1) + `}`},
		{"negative usd", `{"ethereum":` + strings.Replace(quote, `"usd":2000.25`, `"usd":-1`, 1) + `}`},
		{"zero cny", `{"ethereum":` + strings.Replace(quote, `"cny":14001.75`, `"cny":0`, 1) + `}`},
		{"negative jpy", `{"ethereum":` + strings.Replace(quote, `"jpy":300037.5`, `"jpy":-1`, 1) + `}`},
		{"implausible cny per usd", `{"ethereum":` + strings.Replace(quote, `"cny":14001.75`, `"cny":2000250`, 1) + `}`},
		{"implausible jpy per usd", `{"ethereum":` + strings.Replace(quote, `"jpy":300037.5`, `"jpy":200025000`, 1) + `}`},
		{"change below minus one hundred percent", `{"ethereum":` + strings.Replace(quote, `"usd_24h_change":3.25`, `"usd_24h_change":-100.0001`, 1) + `}`},
		{"implausibly large positive change", `{"ethereum":` + strings.Replace(quote, `"usd_24h_change":3.25`, `"usd_24h_change":1000000001`, 1) + `}`},
		{"fractional source timestamp", `{"ethereum":` + strings.Replace(quote, fmt.Sprintf(`"last_updated_at":%d`, now), `"last_updated_at":1.5`, 1) + `}`},
		{"stale source timestamp", `{"ethereum":` + strings.Replace(quote, fmt.Sprintf(`"last_updated_at":%d`, now), fmt.Sprintf(`"last_updated_at":%d`, now-int64((16*time.Minute)/time.Second)), 1) + `}`},
		{"future source timestamp", `{"ethereum":` + strings.Replace(quote, fmt.Sprintf(`"last_updated_at":%d`, now), fmt.Sprintf(`"last_updated_at":%d`, now+int64((6*time.Minute)/time.Second)), 1) + `}`},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			client := newCoinGeckoResponseClient(t, tc.payload, nil)
			if _, err := client.SimplePrice(context.Background(), []string{"ethereum"}); err == nil {
				t.Fatal("invalid CoinGecko financial value or freshness metadata must fail closed")
			}
		})
	}
}

func TestCoinGeckoRejectsInconsistentCrossCurrencyRates(t *testing.T) {
	t.Parallel()

	now := time.Now().Unix()
	ethereum := coinGeckoQuote(now)
	solana := strings.NewReplacer(
		`"usd":2000.25`, `"usd":100`,
		`"cny":14001.75`, `"cny":7000`,
		`"jpy":300037.5`, `"jpy":15000`,
	).Replace(coinGeckoQuote(now))
	client := newCoinGeckoResponseClient(
		t,
		`{"ethereum":`+ethereum+`,"solana":`+solana+`}`,
		nil,
	)
	if _, err := client.SimplePrice(context.Background(), []string{"ethereum", "solana"}); err == nil {
		t.Fatal("materially inconsistent CoinGecko fiat conversion rates must fail closed")
	}
}

func TestCoinGeckoBindsFullPrecisionRequestAndAcceptsNullableChange(t *testing.T) {
	t.Parallel()

	now := time.Now().Unix()
	quote := strings.Replace(coinGeckoQuote(now), `"usd_24h_change":3.25`, `"usd_24h_change":null`, 1)
	client := newCoinGeckoResponseClient(t, `{"ethereum":`+quote+`}`, func(r *http.Request) {
		if r.URL.Path != "/api/v3/simple/price" {
			t.Errorf("unexpected path %q", r.URL.Path)
		}
		q := r.URL.Query()
		if q.Get("ids") != "ethereum" {
			t.Errorf("ids = %q, want ethereum", q.Get("ids"))
		}
		if q.Get("vs_currencies") != "usd,cny,jpy" {
			t.Errorf("vs_currencies = %q", q.Get("vs_currencies"))
		}
		if q.Get("include_24hr_change") != "true" {
			t.Errorf("include_24hr_change = %q", q.Get("include_24hr_change"))
		}
		if q.Get("include_last_updated_at") != "true" {
			t.Errorf("include_last_updated_at = %q", q.Get("include_last_updated_at"))
		}
		if q.Get("precision") != "full" {
			t.Errorf("precision = %q", q.Get("precision"))
		}
	})

	got, err := client.SimplePrice(context.Background(), []string{"ethereum"})
	if err != nil {
		t.Fatalf("valid CoinGecko response rejected: %v", err)
	}
	if got["ethereum"].USD24hChange != nil {
		t.Fatalf("nullable change must remain unknown, got %v", *got["ethereum"].USD24hChange)
	}
}

func TestCoinGeckoRejectsInvalidOrDuplicateRequestIDsBeforeNetwork(t *testing.T) {
	t.Parallel()

	var calls int
	client := newCoinGeckoResponseClient(t, `{}`, func(*http.Request) { calls++ })
	for _, ids := range [][]string{
		nil,
		{},
		{"ethereum", "ethereum"},
		{"Ethereum"},
		{"ethereum,solana"},
		{strings.Repeat("a", 81)},
	} {
		if _, err := client.SimplePrice(context.Background(), ids); err == nil {
			t.Fatalf("invalid CoinGecko ids %q must fail closed", ids)
		}
	}
	if calls != 0 {
		t.Fatalf("invalid CoinGecko request must not reach network, calls=%d", calls)
	}
}

func TestCoinGeckoLiveResponse(t *testing.T) {
	if os.Getenv("KT_LIVE_COINGECKO") != "1" {
		t.Skip("set KT_LIVE_COINGECKO=1 for the read-only provider contract smoke test")
	}
	client := NewCoinGecko("https://api.coingecko.com", http.DefaultClient, nil, 15*time.Second)
	quotes, err := client.SimplePrice(
		context.Background(),
		[]string{"ethereum", "solana", "usd-coin"},
	)
	if err != nil {
		t.Fatalf("live CoinGecko response rejected by reviewed schema: %v", err)
	}
	if len(quotes) != 3 {
		t.Fatalf("live CoinGecko response count=%d, want 3", len(quotes))
	}
	for _, id := range []string{"ethereum", "solana", "usd-coin"} {
		if quotes[id].USD <= 0 || quotes[id].LastUpdated.IsZero() {
			t.Fatalf("live CoinGecko quote %q is incomplete: %+v", id, quotes[id])
		}
	}
}
