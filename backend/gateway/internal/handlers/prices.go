package handlers

import (
	"context"
	"encoding/json"
	"sort"
	"strings"
	"time"

	"ktwallet/gateway/internal/rpc"
)

// geckoIDs maps ticker symbols the wallet uses to CoinGecko coin ids.
var geckoIDs = map[string]string{
	"ETH":   "ethereum",
	"POL":   "polygon-ecosystem-token",
	"AVAX":  "avalanche-2",
	"BNB":   "binancecoin",
	"TRX":   "tron",
	"SOL":   "solana",
	"USDT":  "tether",
	"USDC":  "usd-coin",
	"BUSD":  "binance-usd",
	"DAI":   "dai",
	"WETH":  "weth",
	"WBTC":  "wrapped-bitcoin",
	"LINK":  "chainlink",
	"UNI":   "uniswap",
	"SHIB":  "shiba-inu",
	"PEPE":  "pepe",
	"JUP":   "jupiter-exchange-solana",
	"BONK":  "bonk",
	"PYUSD": "paypal-usd",
}

type usdPrice struct {
	USD       float64  `json:"usd"`
	Change24h *float64 `json:"change24h,omitempty"`
}

type cachedPrices struct {
	Prices     map[string]usdPrice `json:"prices"` // symbol -> price, upstream symbols only
	FiatPerUSD map[string]float64  `json:"fiatPerUsd"`
	At         time.Time           `json:"at"`
}

// GetPrices implements kt_getPrices. Unknown symbols are omitted; every quote,
// including stablecoins, is fetched from CoinGecko so a depeg is reflected
// instead of being silently fixed at 1.0 USD.
func (g *Gateway) GetPrices(ctx context.Context, params json.RawMessage) (any, *rpc.Error) {
	var p struct {
		Symbols []string `json:"symbols"`
	}
	if err := json.Unmarshal(params, &p); err != nil || len(params) == 0 {
		return nil, rpc.Errorf(rpc.CodeInvalidParams, `invalid params: expected {"symbols": [...]}`)
	}
	if len(p.Symbols) == 0 {
		return nil, rpc.Errorf(rpc.CodeInvalidParams, `invalid params: "symbols" must be a non-empty array`)
	}

	out := make(map[string]usdPrice)
	fiatPerUSD := map[string]float64{"USD": 1}
	seen := make(map[string]bool)
	var fetch []string
	for _, s := range p.Symbols {
		sym := strings.ToUpper(strings.TrimSpace(s))
		if sym == "" || seen[sym] {
			continue
		}
		seen[sym] = true
		switch {
		case geckoIDs[sym] != "":
			fetch = append(fetch, sym)
		default:
			// unknown symbol: omitted from the response
		}
	}

	cachedAt := g.clk.Now()
	if len(fetch) > 0 {
		sort.Strings(fetch)
		key := strings.Join(fetch, ",")
		if v, ok := g.priceCache.GetContext(ctx, key); ok {
			c := v.(*cachedPrices)
			for sym, pr := range c.Prices {
				out[sym] = pr
			}
			for currency, rate := range c.FiatPerUSD {
				fiatPerUSD[currency] = rate
			}
			cachedAt = c.At
		} else {
			ids := make([]string, len(fetch))
			for i, sym := range fetch {
				ids[i] = geckoIDs[sym]
			}
			res, err := g.cg.SimplePrice(ctx, ids)
			if err != nil {
				return nil, upstreamError("coingecko", err)
			}
			fetched := make(map[string]usdPrice)
			for _, sym := range fetch {
				if quote, ok := res[geckoIDs[sym]]; ok {
					price := usdPrice{
						USD:       quote.USD,
						Change24h: quote.USD24hChange,
					}
					fetched[sym] = price
					out[sym] = price
					if quote.USD > 0 {
						if _, exists := fiatPerUSD["CNY"]; !exists && quote.CNY > 0 {
							fiatPerUSD["CNY"] = quote.CNY / quote.USD
						}
						if _, exists := fiatPerUSD["JPY"]; !exists && quote.JPY > 0 {
							fiatPerUSD["JPY"] = quote.JPY / quote.USD
						}
					}
				}
			}
			cachedAt = g.clk.Now()
			g.priceCache.SetContext(ctx, key, &cachedPrices{
				Prices:     fetched,
				FiatPerUSD: fiatPerUSD,
				At:         cachedAt,
			})
		}
	}

	return map[string]any{
		"prices":     out,
		"fiatPerUsd": fiatPerUSD,
		"cachedAtMs": cachedAt.UnixMilli(),
	}, nil
}
