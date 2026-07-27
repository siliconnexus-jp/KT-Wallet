package upstream

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"ktwallet/gateway/internal/ratelimit"
)

// CoinGecko fetches USD spot prices from the CoinGecko simple-price API.
// Outbound calls are throttled through an Interval limiter (1 rps by default)
// so multiple client requests never stampede the shared public API.
type CoinGecko struct {
	base    string
	client  *http.Client
	limiter *ratelimit.Interval
	timeout time.Duration
}

// NewCoinGecko builds a client for base (e.g. https://api.coingecko.com).
func NewCoinGecko(base string, client *http.Client, limiter *ratelimit.Interval, attemptTimeout time.Duration) *CoinGecko {
	if client == nil {
		client = http.DefaultClient
	}
	if attemptTimeout <= 0 {
		attemptTimeout = 10 * time.Second
	}
	return &CoinGecko{base: strings.TrimRight(base, "/"), client: client, limiter: limiter, timeout: attemptTimeout}
}

// MarketQuote is the subset of CoinGecko's simple-price response consumed by
// the wallet. USD24hChange is nullable because CoinGecko reports null when it
// cannot calculate a fresh change; callers must not turn that into 0%.
type MarketQuote struct {
	USD          float64  `json:"usd"`
	USD24hChange *float64 `json:"usd_24h_change"`
}

// SimplePrice returns coin-id -> USD market quote for ids. Missing ids are
// simply absent from the map.
func (c *CoinGecko) SimplePrice(ctx context.Context, ids []string) (map[string]MarketQuote, error) {
	if c.limiter != nil {
		if err := c.limiter.Wait(ctx); err != nil {
			return nil, &Unavailable{Upstream: "coingecko", Message: "request canceled while waiting for upstream rate limit"}
		}
	}
	q := url.Values{}
	q.Set("ids", strings.Join(ids, ","))
	q.Set("vs_currencies", "usd")
	q.Set("include_24hr_change", "true")
	u := c.base + "/api/v3/simple/price?" + q.Encode()

	actx, cancel := context.WithTimeout(ctx, c.timeout)
	defer cancel()
	req, err := http.NewRequestWithContext(actx, http.MethodGet, u, nil)
	if err != nil {
		return nil, &Unavailable{Upstream: "coingecko", Message: err.Error()}
	}
	resp, err := c.client.Do(req)
	if err != nil {
		return nil, &Unavailable{Upstream: "coingecko", Message: err.Error()}
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return nil, &Unavailable{Upstream: "coingecko", Message: err.Error()}
	}
	if resp.StatusCode != http.StatusOK {
		return nil, &Unavailable{Upstream: "coingecko", Message: fmt.Sprintf("CoinGecko returned HTTP %d", resp.StatusCode)}
	}
	var out map[string]MarketQuote
	if err := json.Unmarshal(data, &out); err != nil {
		return nil, &Unavailable{Upstream: "coingecko", Message: "malformed CoinGecko response"}
	}
	return out, nil
}
