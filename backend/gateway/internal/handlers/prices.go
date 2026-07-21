package handlers

import (
	"context"
	"encoding/json"
	"sort"
	"strings"
	"time"

	"ktwallet/gateway/internal/rpc"
)

// pegged stablecoins are answered from the built-in 1.0 USD peg without any
// upstream call.
var pegged = map[string]bool{"USDT": true, "USDC": true}

// geckoIDs maps ticker symbols the wallet uses to CoinGecko coin ids.
var geckoIDs = map[string]string{
	"ETH": "ethereum",
	"POL": "polygon-ecosystem-token",
	"TRX": "tron",
	"SOL": "solana",
}

type usdPrice struct {
	USD float64 `json:"usd"`
}

type cachedPrices struct {
	prices map[string]usdPrice // symbol -> price, upstream symbols only
	at     time.Time
}

// GetPrices implements kt_getPrices. Unknown symbols are omitted; stablecoins
// short-circuit to the peg; everything else is fetched from CoinGecko behind
// a 30s cache and a 1 rps outbound limiter.
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
	seen := make(map[string]bool)
	var fetch []string
	for _, s := range p.Symbols {
		sym := strings.ToUpper(strings.TrimSpace(s))
		if sym == "" || seen[sym] {
			continue
		}
		seen[sym] = true
		switch {
		case pegged[sym]:
			out[sym] = usdPrice{USD: 1.0}
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
		if v, ok := g.priceCache.Get(key); ok {
			c := v.(*cachedPrices)
			for sym, pr := range c.prices {
				out[sym] = pr
			}
			cachedAt = c.at
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
				if usd, ok := res[geckoIDs[sym]]; ok {
					fetched[sym] = usdPrice{USD: usd}
					out[sym] = usdPrice{USD: usd}
				}
			}
			cachedAt = g.clk.Now()
			g.priceCache.Set(key, &cachedPrices{prices: fetched, at: cachedAt})
		}
	}

	return map[string]any{
		"prices":     out,
		"cachedAtMs": cachedAt.UnixMilli(),
	}, nil
}
