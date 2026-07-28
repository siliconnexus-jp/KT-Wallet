package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"ktwallet/gateway/internal/rpc"
)

type tokenRef struct {
	Contract string `json:"contract"`
	Decimals int    `json:"decimals"`
	Symbol   string `json:"symbol"`
}

type balanceEntry struct {
	Raw      string `json:"raw"`
	Decimals int    `json:"decimals"`
	Symbol   string `json:"symbol"`
}

type tokenBalanceEntry struct {
	Contract string `json:"contract"`
	Raw      string `json:"raw"`
	Decimals int    `json:"decimals"`
	Symbol   string `json:"symbol"`
	Error    string `json:"error,omitempty"`
}

type balancesResult struct {
	Native balanceEntry        `json:"native"`
	Tokens []tokenBalanceEntry `json:"tokens"`
}

// GetBalances implements kt_getBalances. Native balance failure fails the
// call; a per-token upstream failure only annotates that token with "error".
func (g *Gateway) GetBalances(ctx context.Context, params json.RawMessage) (any, *rpc.Error) {
	var p struct {
		Chain   string     `json:"chain"`
		Network string     `json:"network"`
		Address string     `json:"address"`
		Tokens  []tokenRef `json:"tokens"`
	}
	if err := json.Unmarshal(params, &p); err != nil || len(params) == 0 {
		return nil, rpc.Errorf(rpc.CodeInvalidParams, `invalid params: expected {"chain", "network"?, "address", "tokens"?}`)
	}
	meta, rpcErr := validateChain(p.Chain)
	if rpcErr != nil {
		return nil, rpcErr
	}
	network, rpcErr := resolveNetwork(p.Chain, p.Network)
	if rpcErr != nil {
		return nil, rpcErr
	}
	if rpcErr := validateAddress(p.Chain, p.Address); rpcErr != nil {
		return nil, rpcErr
	}
	for i, t := range p.Tokens {
		if strings.TrimSpace(t.Contract) == "" {
			return nil, rpc.Errorf(rpc.CodeInvalidParams, `invalid params: "tokens[%d].contract" must not be blank`, i)
		}
		if t.Decimals < 0 || t.Decimals > 77 {
			return nil, rpc.Errorf(rpc.CodeInvalidParams, `invalid params: "tokens[%d].decimals" out of range`, i)
		}
	}

	// Keyed by network (not chain): a testnet answer must never be served
	// for a mainnet request or vice versa.
	key := network + "|" + p.Address + "|" + tokenSetHash(p.Tokens)
	if v, ok := g.balanceCache.Get(key); ok {
		return v, nil
	}

	var res *balancesResult
	var err *rpc.Error
	switch {
	case meta.EVM:
		res, err = g.evmBalances(ctx, p.Chain, network, meta, p.Address, p.Tokens)
	case p.Chain == "tron":
		res, err = g.tronBalances(ctx, network, meta, p.Address, p.Tokens)
	default: // solana
		res, err = g.solanaBalances(ctx, network, meta, p.Address, p.Tokens)
	}
	if err != nil {
		return nil, err
	}
	g.balanceCache.Set(key, res)
	return res, nil
}

func (g *Gateway) evmBalances(ctx context.Context, chain, network string, meta chainMeta, address string, tokens []tokenRef) (*balancesResult, *rpc.Error) {
	evm := g.evm[network]
	native, err := evm.GetBalance(ctx, address)
	if err != nil {
		return nil, upstreamError(chain, err)
	}
	res := &balancesResult{
		Native: balanceEntry{Raw: native.String(), Decimals: meta.Decimals, Symbol: meta.Symbol},
		Tokens: make([]tokenBalanceEntry, 0, len(tokens)),
	}
	for _, t := range tokens {
		entry := tokenBalanceEntry{Contract: t.Contract, Raw: "0", Decimals: t.Decimals, Symbol: t.Symbol}
		if !evmAddressRe.MatchString(t.Contract) {
			entry.Error = "invalid contract address"
		} else if bal, err := evm.TokenBalance(ctx, t.Contract, address); err != nil {
			entry.Error = err.Error()
		} else {
			entry.Raw = bal.String()
		}
		res.Tokens = append(res.Tokens, entry)
	}
	return res, nil
}

func (g *Gateway) tronBalances(ctx context.Context, network string, meta chainMeta, address string, tokens []tokenRef) (*balancesResult, *rpc.Error) {
	acct, err := g.tron[network].GetAccount(ctx, address)
	if err != nil {
		return nil, upstreamError("trongrid", err)
	}
	res := &balancesResult{
		Native: balanceEntry{Raw: acct.Balance.String(), Decimals: meta.Decimals, Symbol: meta.Symbol},
		Tokens: make([]tokenBalanceEntry, 0, len(tokens)),
	}
	for _, t := range tokens {
		entry := tokenBalanceEntry{Contract: t.Contract, Raw: "0", Decimals: t.Decimals, Symbol: t.Symbol}
		if raw, ok := acct.TRC20[t.Contract]; ok {
			if _, valid := newDecimal(raw); valid {
				entry.Raw = raw
			} else {
				entry.Error = fmt.Sprintf("TronGrid returned a non-numeric balance: %q", raw)
			}
		}
		res.Tokens = append(res.Tokens, entry)
	}
	return res, nil
}

func (g *Gateway) solanaBalances(ctx context.Context, network string, meta chainMeta, address string, tokens []tokenRef) (*balancesResult, *rpc.Error) {
	native, err := g.sol[network].GetBalance(ctx, address)
	if err != nil {
		return nil, upstreamError("solana", err)
	}
	res := &balancesResult{
		Native: balanceEntry{Raw: native.String(), Decimals: meta.Decimals, Symbol: meta.Symbol},
		Tokens: make([]tokenBalanceEntry, 0, len(tokens)),
	}
	for _, t := range tokens {
		entry := tokenBalanceEntry{Contract: t.Contract, Raw: "0", Decimals: t.Decimals, Symbol: t.Symbol}
		if bal, err := g.sol[network].GetTokenBalance(ctx, address, t.Contract); err != nil {
			entry.Error = err.Error()
		} else {
			entry.Raw = bal.String()
		}
		res.Tokens = append(res.Tokens, entry)
	}
	return res, nil
}
