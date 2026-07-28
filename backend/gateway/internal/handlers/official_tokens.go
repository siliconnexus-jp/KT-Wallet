package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"regexp"
	"sort"
	"strings"
	"unicode"

	"ktwallet/gateway/internal/rpc"
)

var base58TokenAddressRe = regexp.MustCompile(`^[1-9A-HJ-NP-Za-km-z]+$`)

const (
	defaultTokenSearchLimit = 50
	maxTokenSearchLimit     = 100
)

// OfficialToken is one contract/mint identity trusted by the KT Wallet
// operator. Network + contract, never the display symbol alone, is the
// identity. The list can be replaced at startup through OFFICIAL_TOKENS_FILE.
type OfficialToken struct {
	Network  string `json:"network"`
	Symbol   string `json:"symbol"`
	Name     string `json:"name"`
	Contract string `json:"contract"`
	Decimals int    `json:"decimals"`
	Popular  bool   `json:"popular,omitempty"`
	Verified bool   `json:"verified"`
}

type tokenMeta struct {
	Symbol   string
	Decimals int
}

func defaultOfficialTokens() []OfficialToken {
	return []OfficialToken{
		{Network: "eth-mainnet", Symbol: "USDT", Name: "Tether USD", Contract: "0xdac17f958d2ee523a2206206994597c13d831ec7", Decimals: 6, Popular: true},
		{Network: "eth-mainnet", Symbol: "USDC", Name: "USD Coin", Contract: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", Decimals: 6, Popular: true},
		{Network: "eth-mainnet", Symbol: "BUSD", Name: "Binance USD", Contract: "0x4fabb145d64652a948d72533023f6e7a623c7c53", Decimals: 18},
		{Network: "eth-mainnet", Symbol: "DAI", Name: "Dai Stablecoin", Contract: "0x6b175474e89094c44da98b954eedeac495271d0f", Decimals: 18, Popular: true},
		{Network: "eth-mainnet", Symbol: "WETH", Name: "Wrapped Ether", Contract: "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2", Decimals: 18, Popular: true},
		{Network: "eth-mainnet", Symbol: "WBTC", Name: "Wrapped BTC", Contract: "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599", Decimals: 8, Popular: true},
		{Network: "eth-mainnet", Symbol: "LINK", Name: "Chainlink", Contract: "0x514910771af9ca656af840dff83e8264ecf986ca", Decimals: 18, Popular: true},
		{Network: "eth-mainnet", Symbol: "UNI", Name: "Uniswap", Contract: "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984", Decimals: 18, Popular: true},
		{Network: "eth-mainnet", Symbol: "SHIB", Name: "Shiba Inu", Contract: "0x95ad61b0a150d79219dcf64e1e6cc01f0b64c4ce", Decimals: 18, Popular: true},
		{Network: "eth-mainnet", Symbol: "PEPE", Name: "Pepe", Contract: "0x6982508145454ce325ddbe47a25d4ec3d2311933", Decimals: 18, Popular: true},
		{Network: "eth-mainnet", Symbol: "PYUSD", Name: "PayPal USD", Contract: "0x6c3ea9036406852006290770bedfcaba0e23a0e8", Decimals: 6, Popular: true},
		{Network: "eth-sepolia", Symbol: "USDT", Name: "Test Tether USD", Contract: "0xc4dcc311c028e341fd8602d8eb89c5de94625927", Decimals: 6},
		{Network: "polygon-mainnet", Symbol: "USDC", Name: "USD Coin", Contract: "0x3c499c542cef5e3811e1192ce70d8cc03d5c3359", Decimals: 6, Popular: true},
		{Network: "polygon-mainnet", Symbol: "USDT", Name: "Tether USD", Contract: "0xc2132d05d31c914a87c6611c10748aeb04b58e8f", Decimals: 6, Popular: true},
		{Network: "polygon-amoy", Symbol: "USDC", Name: "Test USD Coin", Contract: "0x41e94eb019c0762f9bfcf9fb1e58725bfb0e7582", Decimals: 6},
		{Network: "base-mainnet", Symbol: "USDC", Name: "USD Coin", Contract: "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913", Decimals: 6, Popular: true},
		{Network: "base-mainnet", Symbol: "USDT", Name: "Tether USD", Contract: "0xfde4c96c8593536e31f229ea8f37b2ada2699bb2", Decimals: 6, Popular: true},
		{Network: "base-sepolia", Symbol: "USDC", Name: "Test USD Coin", Contract: "0x036cbd53842c5426634e7929541ec2318f3dcf7e", Decimals: 6},
		{Network: "arbitrum-mainnet", Symbol: "USDC", Name: "USD Coin", Contract: "0xaf88d065e77c8cc2239327c5edb3a432268e5831", Decimals: 6, Popular: true},
		{Network: "arbitrum-mainnet", Symbol: "USDT", Name: "Tether USD", Contract: "0xfd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb9", Decimals: 6, Popular: true},
		{Network: "arbitrum-sepolia", Symbol: "USDC", Name: "Test USD Coin", Contract: "0x75faf114eafb1bdbe2f0316df893fd58ce46aa4d", Decimals: 6},
		{Network: "avalanche-mainnet", Symbol: "USDC", Name: "USD Coin", Contract: "0xb97ef9ef8734c71904d8002f8b6bc66dd9c48a6e", Decimals: 6, Popular: true},
		{Network: "avalanche-mainnet", Symbol: "USDT", Name: "Tether USD", Contract: "0x9702230a8ea53601f5cd2dc00fdbc13d4df4a8c7", Decimals: 6, Popular: true},
		{Network: "avalanche-fuji", Symbol: "USDC", Name: "Test USD Coin", Contract: "0x5425890298aed601595a70ab815c96711a31bc65", Decimals: 6},
		{Network: "bnb-mainnet", Symbol: "BUSD", Name: "Binance-Peg BUSD", Contract: "0xe9e7cea3dedca5984780bafc599bd69add087d56", Decimals: 18, Popular: true},
		{Network: "tron-mainnet", Symbol: "USDT", Name: "Tether USD", Contract: "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t", Decimals: 6, Popular: true},
		{Network: "tron-nile", Symbol: "USDT", Name: "Test Tether USD", Contract: "TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf", Decimals: 6},
		{Network: "sol-mainnet", Symbol: "USDC", Name: "USD Coin", Contract: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", Decimals: 6, Popular: true},
		{Network: "sol-mainnet", Symbol: "USDT", Name: "Tether USD", Contract: "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB", Decimals: 6, Popular: true},
		{Network: "sol-mainnet", Symbol: "JUP", Name: "Jupiter", Contract: "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN", Decimals: 6, Popular: true},
		{Network: "sol-mainnet", Symbol: "BONK", Name: "Bonk", Contract: "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263", Decimals: 5, Popular: true},
		{Network: "sol-mainnet", Symbol: "PYUSD", Name: "PayPal USD", Contract: "2b1kV6DkPAnxd5ixfnxCpjxmKwqjjaYmCZfHsFu24GXo", Decimals: 6, Popular: true},
		{Network: "sol-devnet", Symbol: "USDC", Name: "Test USD Coin", Contract: "4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU", Decimals: 6},
		{Network: "sol-devnet", Symbol: "PYUSD", Name: "Test PayPal USD", Contract: "CXk2AMBfi3TwaEL2468s6zP8xq9NxTXjp9gjMgzeUynM", Decimals: 6},
	}
}

// LoadOfficialTokensFile reads the operator-managed JSON array used by
// OFFICIAL_TOKENS_FILE. Invalid or duplicate entries fail the whole load so a
// typo can never silently grant a blue verification mark to the wrong token.
func LoadOfficialTokensFile(path string) ([]OfficialToken, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var tokens []OfficialToken
	if err := json.Unmarshal(raw, &tokens); err != nil {
		return nil, fmt.Errorf("decode official tokens: %w", err)
	}
	return normalizeOfficialTokens(tokens)
}

func normalizeOfficialTokens(tokens []OfficialToken) ([]OfficialToken, error) {
	if tokens == nil {
		return nil, errors.New("official token list must be a JSON array")
	}
	out := make([]OfficialToken, 0, len(tokens))
	seen := make(map[string]bool, len(tokens))
	for i, token := range tokens {
		token.Network = strings.TrimSpace(token.Network)
		token.Symbol = strings.ToUpper(strings.TrimSpace(token.Symbol))
		token.Name = strings.TrimSpace(token.Name)
		token.Contract = strings.TrimSpace(token.Contract)
		meta, ok := networks[token.Network]
		if !ok {
			return nil, fmt.Errorf("token %d: unsupported network %q", i, token.Network)
		}
		if token.Symbol == "" || len(token.Symbol) > 12 {
			return nil, fmt.Errorf("token %d: invalid symbol", i)
		}
		for _, r := range token.Symbol {
			if !(unicode.IsUpper(r) || unicode.IsDigit(r) || r == '.' || r == '-' || r == '_') {
				return nil, fmt.Errorf("token %d: invalid symbol %q", i, token.Symbol)
			}
		}
		if token.Name == "" || len(token.Name) > 80 {
			return nil, fmt.Errorf("token %d: invalid name", i)
		}
		if err := validateAddress(meta.Chain, token.Contract); err != nil {
			return nil, fmt.Errorf("token %d: invalid contract for %s", i, token.Network)
		}
		switch meta.Chain {
		case "tron":
			if len(token.Contract) != 34 ||
				!strings.HasPrefix(token.Contract, "T") ||
				!base58TokenAddressRe.MatchString(token.Contract) {
				return nil, fmt.Errorf("token %d: invalid TRON contract", i)
			}
		case "solana":
			if len(token.Contract) < 32 ||
				len(token.Contract) > 44 ||
				!base58TokenAddressRe.MatchString(token.Contract) {
				return nil, fmt.Errorf("token %d: invalid Solana mint", i)
			}
		}
		if chains[meta.Chain].EVM {
			token.Contract = strings.ToLower(token.Contract)
		}
		if token.Decimals < 0 || token.Decimals > 36 {
			return nil, fmt.Errorf("token %d: decimals must be between 0 and 36", i)
		}
		key := token.Network + "|" + token.Contract
		if seen[key] {
			return nil, fmt.Errorf("token %d: duplicate network and contract", i)
		}
		seen[key] = true
		token.Verified = true
		out = append(out, token)
	}
	return out, nil
}

func officialTokenIndex(tokens []OfficialToken) map[string]map[string]tokenMeta {
	out := make(map[string]map[string]tokenMeta)
	for _, token := range tokens {
		byContract := out[token.Network]
		if byContract == nil {
			byContract = make(map[string]tokenMeta)
			out[token.Network] = byContract
		}
		byContract[token.Contract] = tokenMeta{Symbol: token.Symbol, Decimals: token.Decimals}
	}
	return out
}

// SearchOfficialTokens implements the OKX-style single search surface:
// symbol/name substring matching, or exact contract/mint matching. Results
// are always server-verified entries; arbitrary chain tokens are not elevated.
func (g *Gateway) SearchOfficialTokens(_ context.Context, params json.RawMessage) (any, *rpc.Error) {
	var p struct {
		Query    string   `json:"query"`
		Networks []string `json:"networks"`
		Limit    *int     `json:"limit"`
	}
	if len(params) > 0 {
		if err := json.Unmarshal(params, &p); err != nil {
			return nil, rpc.Errorf(rpc.CodeInvalidParams, `invalid params: expected {"query"?, "networks"?, "limit"?}`)
		}
	}
	limit := defaultTokenSearchLimit
	if p.Limit != nil {
		if *p.Limit <= 0 || *p.Limit > maxTokenSearchLimit {
			return nil, rpc.Errorf(rpc.CodeInvalidParams, `"limit" must be between 1 and %d`, maxTokenSearchLimit)
		}
		limit = *p.Limit
	}
	networkFilter := make(map[string]bool, len(p.Networks))
	for _, network := range p.Networks {
		if _, ok := networks[network]; !ok {
			return nil, rpc.Errorf(rpc.CodeInvalidParams, `unknown "networks" value %q`, network)
		}
		networkFilter[network] = true
	}

	query := strings.ToLower(strings.TrimSpace(p.Query))
	type rankedToken struct {
		token OfficialToken
		rank  int
	}
	ranked := make([]rankedToken, 0, len(g.officialTokens))
	for _, token := range g.officialTokens {
		if len(networkFilter) > 0 && !networkFilter[token.Network] {
			continue
		}
		rank := tokenSearchRank(token, query)
		if rank < 0 {
			continue
		}
		ranked = append(ranked, rankedToken{token: token, rank: rank})
	}
	sort.SliceStable(ranked, func(i, j int) bool {
		if ranked[i].rank != ranked[j].rank {
			return ranked[i].rank < ranked[j].rank
		}
		if ranked[i].token.Popular != ranked[j].token.Popular {
			return ranked[i].token.Popular
		}
		if ranked[i].token.Symbol != ranked[j].token.Symbol {
			return ranked[i].token.Symbol < ranked[j].token.Symbol
		}
		return ranked[i].token.Network < ranked[j].token.Network
	})
	result := make([]OfficialToken, 0, min(limit, len(ranked)))
	for _, row := range ranked {
		result = append(result, row.token)
		if len(result) == limit {
			break
		}
	}
	return map[string]any{"tokens": result}, nil
}

func tokenSearchRank(token OfficialToken, query string) int {
	if query == "" {
		if token.Popular {
			return 0
		}
		return 1
	}
	symbol := strings.ToLower(token.Symbol)
	name := strings.ToLower(token.Name)
	contract := strings.ToLower(token.Contract)
	switch {
	case query == contract:
		return 0
	case query == symbol:
		return 1
	case strings.HasPrefix(symbol, query), strings.HasPrefix(name, query):
		return 2
	case strings.Contains(symbol, query), strings.Contains(name, query), strings.Contains(contract, query):
		return 3
	default:
		return -1
	}
}
