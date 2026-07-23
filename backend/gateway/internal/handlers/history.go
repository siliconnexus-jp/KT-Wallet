package handlers

import (
	"context"
	"encoding/json"
	"sort"
	"strconv"
	"strings"

	"ktwallet/gateway/internal/rpc"
)

const (
	defaultHistoryLimit = 20
	maxHistoryLimit     = 100
)

type historyRecord struct {
	Hash        string `json:"hash"`
	Direction   string `json:"direction"` // "in" | "out"
	AmountRaw   string `json:"amountRaw"`
	Decimals    int    `json:"decimals"`
	Symbol      string `json:"symbol"`
	TimestampMs int64  `json:"timestampMs"`
	Status      string `json:"status"` // "ok" | "failed"
}

type historyResult struct {
	Status  string          `json:"status"` // "ok" | "unsupported"
	Records []historyRecord `json:"records"`
}

func unsupportedHistory() *historyResult {
	return &historyResult{Status: "unsupported", Records: []historyRecord{}}
}

// GetHistory implements kt_getHistory. TRON networks are always supported
// through TronGrid (mainnet or nile base URL); eth/polygon networks need an
// Etherscan-family key (Etherscan v2 covers testnets via chainid); solana
// networks need a Helius key (sol-devnet uses the Helius devnet endpoint);
// anything else reports {"status":"unsupported"}.
func (g *Gateway) GetHistory(ctx context.Context, params json.RawMessage) (any, *rpc.Error) {
	var p struct {
		Chain   string `json:"chain"`
		Network string `json:"network"`
		Address string `json:"address"`
		Limit   *int   `json:"limit"`
	}
	if err := json.Unmarshal(params, &p); err != nil || len(params) == 0 {
		return nil, rpc.Errorf(rpc.CodeInvalidParams, `invalid params: expected {"chain", "network"?, "address", "limit"?}`)
	}
	if _, rpcErr := validateChain(p.Chain); rpcErr != nil {
		return nil, rpcErr
	}
	network, rpcErr := resolveNetwork(p.Chain, p.Network)
	if rpcErr != nil {
		return nil, rpcErr
	}
	if rpcErr := validateAddress(p.Chain, p.Address); rpcErr != nil {
		return nil, rpcErr
	}
	limit := defaultHistoryLimit
	if p.Limit != nil {
		if *p.Limit <= 0 {
			return nil, rpc.Errorf(rpc.CodeInvalidParams, `invalid params: "limit" must be a positive integer`)
		}
		limit = min(*p.Limit, maxHistoryLimit)
	}

	key := network + "|" + p.Address + "|" + strconv.Itoa(limit)
	if v, ok := g.historyCache.Get(key); ok {
		return v, nil
	}

	var res *historyResult
	switch p.Chain {
	case "tron":
		res, rpcErr = g.tronHistory(ctx, network, p.Address, limit)
	case "eth", "polygon":
		if g.cfg.EtherscanKey == "" {
			res = unsupportedHistory()
		} else {
			res, rpcErr = g.evmHistory(ctx, p.Chain, network, p.Address, limit)
		}
	case "solana":
		if g.cfg.HeliusKey == "" {
			res = unsupportedHistory()
		} else {
			res, rpcErr = g.solanaHistory(ctx, network, p.Address, limit)
		}
	}
	if rpcErr != nil {
		return nil, rpcErr
	}
	g.historyCache.Set(key, res)
	return res, nil
}

// tronHistory merges TRC-20 transfers and native TransferContract
// transactions, newest first, deduplicated by transaction hash.
func (g *Gateway) tronHistory(ctx context.Context, network, address string, limit int) (*historyResult, *rpc.Error) {
	selfHex := tronAddrHex(address)

	tron := g.tron[network]
	trc20, err := tron.TRC20Transfers(ctx, address, limit)
	if err != nil {
		return nil, upstreamError("trongrid", err)
	}
	native, err := tron.NativeTransactions(ctx, address, limit)
	if err != nil {
		return nil, upstreamError("trongrid", err)
	}

	records := make([]historyRecord, 0, len(trc20)+len(native))
	for _, t := range trc20 {
		dir := "in"
		if tronAddrHex(t.From) == selfHex {
			dir = "out"
		}
		records = append(records, historyRecord{
			Hash:        t.TransactionID,
			Direction:   dir,
			AmountRaw:   t.Value,
			Decimals:    t.Decimals,
			Symbol:      t.Symbol,
			TimestampMs: t.BlockTimestamp,
			Status:      "ok",
		})
	}
	for _, t := range native {
		dir := "in"
		if tronAddrHex(t.Owner) == selfHex {
			dir = "out"
		}
		status := "ok"
		if !t.Success {
			status = "failed"
		}
		records = append(records, historyRecord{
			Hash:        t.TxID,
			Direction:   dir,
			AmountRaw:   t.Amount,
			Decimals:    6,
			Symbol:      "TRX",
			TimestampMs: t.BlockTimestamp,
			Status:      status,
		})
	}

	sort.SliceStable(records, func(i, j int) bool { return records[i].TimestampMs > records[j].TimestampMs })
	seen := make(map[string]bool, len(records))
	deduped := make([]historyRecord, 0, len(records))
	for _, r := range records {
		if seen[r.Hash] {
			continue
		}
		seen[r.Hash] = true
		deduped = append(deduped, r)
		if len(deduped) == limit {
			break
		}
	}
	return &historyResult{Status: "ok", Records: deduped}, nil
}

func (g *Gateway) evmHistory(ctx context.Context, chain, network, address string, limit int) (*historyResult, *rpc.Error) {
	// Etherscan v2 is multichain: the network picks the chainid
	// (1 / 11155111 / 137 / 80002) against the same endpoint and key.
	chainID := networks[network].EtherscanChainID
	txs, err := g.scan.TxList(ctx, chainID, address, limit)
	if err != nil {
		return nil, upstreamError("etherscan", err)
	}
	self := strings.ToLower(address)
	symbol := chains[chain].Symbol
	records := make([]historyRecord, 0, len(txs))
	for _, t := range txs {
		dir := "in"
		if strings.ToLower(t.From) == self {
			dir = "out"
		}
		status := "ok"
		if t.IsError != "" && t.IsError != "0" {
			status = "failed"
		}
		ts, _ := strconv.ParseInt(t.TimeStamp, 10, 64)
		records = append(records, historyRecord{
			Hash:        t.Hash,
			Direction:   dir,
			AmountRaw:   t.Value,
			Decimals:    18,
			Symbol:      symbol,
			TimestampMs: ts * 1000,
			Status:      status,
		})
		if len(records) == limit {
			break
		}
	}
	return &historyResult{Status: "ok", Records: records}, nil
}

func (g *Gateway) solanaHistory(ctx context.Context, network, address string, limit int) (*historyResult, *rpc.Error) {
	txs, err := g.hel[network].Transactions(ctx, address, limit)
	if err != nil {
		return nil, upstreamError("helius", err)
	}
	records := make([]historyRecord, 0, len(txs))
	for _, t := range txs {
		// Pick the first native transfer that touches the queried address;
		// transactions without one (pure program interactions) are skipped.
		var amount string
		dir := ""
		for _, nt := range t.NativeTransfers {
			if nt.FromUserAccount == address {
				dir, amount = "out", nt.Amount.String()
				break
			}
			if nt.ToUserAccount == address {
				dir, amount = "in", nt.Amount.String()
				break
			}
		}
		if dir == "" {
			continue
		}
		status := "ok"
		if t.TransactionError != nil {
			status = "failed"
		}
		records = append(records, historyRecord{
			Hash:        t.Signature,
			Direction:   dir,
			AmountRaw:   amount,
			Decimals:    9,
			Symbol:      "SOL",
			TimestampMs: t.Timestamp * 1000,
			Status:      status,
		})
		if len(records) == limit {
			break
		}
	}
	return &historyResult{Status: "ok", Records: records}, nil
}
