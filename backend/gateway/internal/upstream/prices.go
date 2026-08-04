package upstream

import (
	"context"
	"fmt"
	"math"
	"net/http"
	"net/url"
	"regexp"
	"sort"
	"strconv"
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
	USD          float64   `json:"usd"`
	CNY          float64   `json:"cny"`
	JPY          float64   `json:"jpy"`
	USD24hChange *float64  `json:"usd_24h_change"`
	LastUpdated  time.Time `json:"-"`
}

const (
	maxCoinGeckoIDs             = 50
	maxCoinGeckoIDLength        = 80
	maxCoinGeckoQuoteAge        = 15 * time.Minute
	maxCoinGeckoFutureClockSkew = 5 * time.Minute
	maxCoinGecko24hChange       = 1_000_000_000.0
	maxCoinGeckoFXDeviation     = 0.005
	minCoinGeckoCNYPerUSD       = 0.1
	maxCoinGeckoCNYPerUSD       = 100.0
	minCoinGeckoJPYPerUSD       = 1.0
	maxCoinGeckoJPYPerUSD       = 10_000.0
)

var coinGeckoIDPattern = regexp.MustCompile(`^[a-z0-9]+(?:-[a-z0-9]+)*$`)

// SimplePrice returns one fresh, complete quote for every requested coin id.
// The response is an all-or-nothing trust boundary: partial, additional,
// ambiguous or stale provider data is rejected rather than cached as a real
// portfolio valuation.
func (c *CoinGecko) SimplePrice(ctx context.Context, ids []string) (map[string]MarketQuote, error) {
	requestIDs, expectedIDs, err := validateCoinGeckoIDs(ids)
	if err != nil {
		return nil, &Unavailable{Upstream: "coingecko", Message: "invalid CoinGecko request"}
	}
	if c.limiter != nil {
		if err := c.limiter.Wait(ctx); err != nil {
			return nil, &Unavailable{Upstream: "coingecko", Message: "request canceled while waiting for upstream rate limit"}
		}
	}
	q := url.Values{}
	q.Set("ids", strings.Join(requestIDs, ","))
	q.Set("vs_currencies", "usd,cny,jpy")
	q.Set("include_24hr_change", "true")
	q.Set("include_last_updated_at", "true")
	q.Set("precision", "full")
	u := c.base + "/api/v3/simple/price?" + q.Encode()

	actx, cancel := context.WithTimeout(ctx, c.timeout)
	defer cancel()
	req, err := http.NewRequestWithContext(actx, http.MethodGet, u, nil)
	if err != nil {
		return nil, safeRequestCreationFailure("coingecko")
	}
	resp, err := c.client.Do(req)
	if err != nil {
		return nil, safeRequestFailure("coingecko", actx, err)
	}
	defer resp.Body.Close()
	data, err := readBoundedResponse(resp.Body, 1<<20)
	if err != nil {
		return nil, safeResponseReadFailure("coingecko")
	}
	if resp.StatusCode != http.StatusOK {
		return nil, &Unavailable{Upstream: "coingecko", Message: fmt.Sprintf("CoinGecko returned HTTP %d", resp.StatusCode)}
	}
	out, err := decodeCoinGeckoQuotes(data, expectedIDs, time.Now())
	if err != nil {
		return nil, &Unavailable{Upstream: "coingecko", Message: "malformed CoinGecko response"}
	}
	return out, nil
}

func validateCoinGeckoIDs(ids []string) ([]string, map[string]struct{}, error) {
	if len(ids) == 0 || len(ids) > maxCoinGeckoIDs {
		return nil, nil, fmt.Errorf("invalid CoinGecko id count")
	}
	requestIDs := make([]string, len(ids))
	expected := make(map[string]struct{}, len(ids))
	for i, id := range ids {
		if len(id) == 0 || len(id) > maxCoinGeckoIDLength || !coinGeckoIDPattern.MatchString(id) {
			return nil, nil, fmt.Errorf("invalid CoinGecko id")
		}
		if _, duplicate := expected[id]; duplicate {
			return nil, nil, fmt.Errorf("duplicate CoinGecko id")
		}
		expected[id] = struct{}{}
		requestIDs[i] = id
	}
	sort.Strings(requestIDs)
	return requestIDs, expected, nil
}

func decodeCoinGeckoQuotes(data []byte, expectedIDs map[string]struct{}, now time.Time) (map[string]MarketQuote, error) {
	objects, err := decodeUniqueJSONObject(data)
	if err != nil || len(objects) != len(expectedIDs) {
		return nil, fmt.Errorf("invalid CoinGecko response object")
	}

	out := make(map[string]MarketQuote, len(objects))
	for id, raw := range objects {
		if _, requested := expectedIDs[id]; !requested {
			return nil, fmt.Errorf("unrequested CoinGecko id")
		}
		quote, err := decodeCoinGeckoQuote(raw, now)
		if err != nil {
			return nil, err
		}
		out[id] = quote
	}
	for id := range expectedIDs {
		if _, present := out[id]; !present {
			return nil, fmt.Errorf("missing CoinGecko id")
		}
	}
	if err := validateCoinGeckoFXConsistency(out); err != nil {
		return nil, err
	}
	return out, nil
}

func validateCoinGeckoFXConsistency(quotes map[string]MarketQuote) error {
	cnyRates := make([]float64, 0, len(quotes))
	jpyRates := make([]float64, 0, len(quotes))
	for _, quote := range quotes {
		cnyRate := quote.CNY / quote.USD
		jpyRate := quote.JPY / quote.USD
		if !finiteInRange(cnyRate, minCoinGeckoCNYPerUSD, maxCoinGeckoCNYPerUSD) ||
			!finiteInRange(jpyRate, minCoinGeckoJPYPerUSD, maxCoinGeckoJPYPerUSD) {
			return fmt.Errorf("invalid CoinGecko fiat conversion")
		}
		cnyRates = append(cnyRates, cnyRate)
		jpyRates = append(jpyRates, jpyRate)
	}
	if !ratesAgree(cnyRates) || !ratesAgree(jpyRates) {
		return fmt.Errorf("inconsistent CoinGecko fiat conversion")
	}
	return nil
}

func finiteInRange(value, minimum, maximum float64) bool {
	return !math.IsNaN(value) && !math.IsInf(value, 0) && value >= minimum && value <= maximum
}

func ratesAgree(rates []float64) bool {
	if len(rates) < 2 {
		return true
	}
	sorted := append([]float64(nil), rates...)
	sort.Float64s(sorted)
	median := sorted[len(sorted)/2]
	if len(sorted)%2 == 0 {
		median = (sorted[len(sorted)/2-1] + median) / 2
	}
	for _, rate := range sorted {
		if math.Abs(rate/median-1) > maxCoinGeckoFXDeviation {
			return false
		}
	}
	return true
}

func decodeCoinGeckoQuote(raw []byte, now time.Time) (MarketQuote, error) {
	fields, err := decodeExactJSONObject(
		raw,
		"usd", "usd_24h_change",
		"cny", "cny_24h_change",
		"jpy", "jpy_24h_change",
		"last_updated_at",
	)
	if err != nil {
		return MarketQuote{}, err
	}
	for _, required := range []string{
		"usd", "usd_24h_change",
		"cny", "cny_24h_change",
		"jpy", "jpy_24h_change",
		"last_updated_at",
	} {
		if _, present := fields[required]; !present {
			return MarketQuote{}, fmt.Errorf("missing CoinGecko quote member")
		}
	}

	usd, err := parsePositiveFiniteJSONNumber(fields["usd"])
	if err != nil {
		return MarketQuote{}, err
	}
	cny, err := parsePositiveFiniteJSONNumber(fields["cny"])
	if err != nil {
		return MarketQuote{}, err
	}
	jpy, err := parsePositiveFiniteJSONNumber(fields["jpy"])
	if err != nil {
		return MarketQuote{}, err
	}
	usdChange, err := parseNullableCoinGeckoChange(fields["usd_24h_change"])
	if err != nil {
		return MarketQuote{}, err
	}
	if _, err := parseNullableCoinGeckoChange(fields["cny_24h_change"]); err != nil {
		return MarketQuote{}, err
	}
	if _, err := parseNullableCoinGeckoChange(fields["jpy_24h_change"]); err != nil {
		return MarketQuote{}, err
	}
	updatedAt, err := parseCoinGeckoTimestamp(fields["last_updated_at"], now)
	if err != nil {
		return MarketQuote{}, err
	}

	return MarketQuote{
		USD:          usd,
		CNY:          cny,
		JPY:          jpy,
		USD24hChange: usdChange,
		LastUpdated:  updatedAt,
	}, nil
}

func parsePositiveFiniteJSONNumber(raw []byte) (float64, error) {
	value, err := strconv.ParseFloat(strings.TrimSpace(string(raw)), 64)
	if err != nil || value <= 0 || math.IsNaN(value) || math.IsInf(value, 0) {
		return 0, fmt.Errorf("invalid CoinGecko price")
	}
	return value, nil
}

func parseNullableCoinGeckoChange(raw []byte) (*float64, error) {
	text := strings.TrimSpace(string(raw))
	if text == "null" {
		return nil, nil
	}
	value, err := strconv.ParseFloat(text, 64)
	if err != nil || math.IsNaN(value) || math.IsInf(value, 0) ||
		value < -100 || value > maxCoinGecko24hChange {
		return nil, fmt.Errorf("invalid CoinGecko 24 hour change")
	}
	return &value, nil
}

func parseCoinGeckoTimestamp(raw []byte, now time.Time) (time.Time, error) {
	text := strings.TrimSpace(string(raw))
	if text == "" || strings.IndexFunc(text, func(r rune) bool { return r < '0' || r > '9' }) >= 0 {
		return time.Time{}, fmt.Errorf("invalid CoinGecko source timestamp")
	}
	seconds, err := strconv.ParseInt(text, 10, 64)
	if err != nil || seconds <= 0 {
		return time.Time{}, fmt.Errorf("invalid CoinGecko source timestamp")
	}
	updatedAt := time.Unix(seconds, 0)
	if updatedAt.Before(now.Add(-maxCoinGeckoQuoteAge)) || updatedAt.After(now.Add(maxCoinGeckoFutureClockSkew)) {
		return time.Time{}, fmt.Errorf("stale CoinGecko source timestamp")
	}
	return updatedAt, nil
}
