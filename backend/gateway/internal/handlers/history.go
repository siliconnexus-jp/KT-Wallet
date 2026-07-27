package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"
	"strconv"
	"strings"

	"ktwallet/gateway/internal/rpc"
	"ktwallet/gateway/internal/upstream"
)

const (
	defaultHistoryLimit = 20
	maxHistoryLimit     = 100
)

type tokenMeta struct {
	Symbol   string
	Decimals int
}

var solanaTokensByNetwork = map[string]map[string]tokenMeta{
	"sol-mainnet": {
		"EPjFWdd5AufqSSqeM2q8puxyy5xY6Nn7C9nG4wEGGkZwyTDt1v": {Symbol: "USDC", Decimals: 6},
	},
	"sol-devnet": {
		"4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU": {Symbol: "USDC", Decimals: 6},
	},
}

var evmTokensByNetwork = map[string]map[string]tokenMeta{
	"eth-mainnet": {
		"0xdac17f958d2ee523a2206206994597c13d831ec7": {Symbol: "USDT", Decimals: 6},
	},
	"eth-sepolia": {
		"0xc4dcc311c028e341fd8602d8eb89c5de94625927": {Symbol: "USDT", Decimals: 18},
	},
	"polygon-mainnet": {
		"0x3c499c542cef5e3811e1192ce70d8cc03d5c3359": {Symbol: "USDC", Decimals: 6},
	},
	"polygon-amoy": {
		"0x41e94eb019c0762f9bfcf9fb1e58725bfb0e7582": {Symbol: "USDC", Decimals: 6},
	},
	"base-mainnet": {
		"0x833589fcd6edb6e08f4c7c32d4f71b54bda02913": {Symbol: "USDC", Decimals: 6},
	},
	"base-sepolia": {
		"0x036cbd53842c5426634e7929541ec2318f3dcf7e": {Symbol: "USDC", Decimals: 6},
	},
	"arbitrum-mainnet": {
		"0xaf88d065e77c8cc2239327c5edb3a432268e5831": {Symbol: "USDC", Decimals: 6},
	},
	"arbitrum-sepolia": {
		"0x75faf114eafb1bdbe2f0316df893fd58ce46aa4d": {Symbol: "USDC", Decimals: 6},
	},
	"avalanche-mainnet": {
		"0xb97ef9ef8734c71904d8002f8b6bc66dd9c48a6e": {Symbol: "USDC", Decimals: 6},
	},
	"avalanche-fuji": {
		"0x5425890298aed601595a70ab815c96711a31bc65": {Symbol: "USDC", Decimals: 6},
	},
}

var tronTokensByNetwork = map[string]map[string]tokenMeta{
	"tron-mainnet": {
		"TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t": {Symbol: "USDT", Decimals: 6},
	},
	"tron-nile": {
		"TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf": {Symbol: "USDT", Decimals: 6},
	},
}

const nativeSOLMint = "So11111111111111111111111111111111111111111"

type historyRecord struct {
	ID          string `json:"id"`
	Hash        string `json:"hash"`
	Direction   string `json:"direction"` // "in" | "out"
	AmountRaw   string `json:"amountRaw"`
	Decimals    int    `json:"decimals"`
	Symbol      string `json:"symbol"`
	Contract    string `json:"contract,omitempty"`
	Verified    bool   `json:"verified"`
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

// GetHistory implements kt_getHistory. TRON uses TronGrid. EVM prefers the
// configured Etherscan v2 key and otherwise falls back to keyless public
// explorers when available. Solana prefers Helius transfer history and falls
// back to the standard getSignaturesForAddress JSON-RPC method.
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
	switch {
	case p.Chain == "tron":
		res, rpcErr = g.tronHistory(ctx, network, p.Address, limit)
	case meta.EVM:
		res, rpcErr = g.evmHistory(ctx, p.Chain, network, p.Address, limit)
	default: // solana
		res, rpcErr = g.solanaHistory(ctx, network, p.Address, limit)
	}
	if rpcErr != nil {
		return nil, rpcErr
	}
	g.historyCache.Set(key, res)
	return res, nil
}

// tronHistory merges TRC-20 transfers and native TransferContract
// transactions, newest first. Token rows retain contract identity; only a
// native wrapper for the same hash is removed.
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
	tokenHashes := make(map[string]bool, len(trc20))
	for i, t := range trc20 {
		dir := "in"
		if tronAddrHex(t.From) == selfHex {
			dir = "out"
		}
		symbol, decimals, verified := historyTokenMeta(
			tronTokensByNetwork[network], t.Contract, t.Symbol, t.Decimals,
		)
		tokenHashes[t.TransactionID] = true
		records = append(records, historyRecord{
			ID:          fmt.Sprintf("%s:trc20:%s:%d", t.TransactionID, t.Contract, i),
			Hash:        t.TransactionID,
			Direction:   dir,
			AmountRaw:   t.Value,
			Decimals:    decimals,
			Symbol:      symbol,
			Contract:    t.Contract,
			Verified:    verified,
			TimestampMs: t.BlockTimestamp,
			Status:      "ok",
		})
	}
	for _, t := range native {
		if tokenHashes[t.TxID] {
			continue
		}
		dir := "in"
		if tronAddrHex(t.Owner) == selfHex {
			dir = "out"
		}
		status := "ok"
		if !t.Success {
			status = "failed"
		}
		records = append(records, historyRecord{
			ID:          t.TxID,
			Hash:        t.TxID,
			Direction:   dir,
			AmountRaw:   t.Amount,
			Decimals:    6,
			Symbol:      "TRX",
			Verified:    true,
			TimestampMs: t.BlockTimestamp,
			Status:      status,
		})
	}

	sort.SliceStable(records, func(i, j int) bool { return records[i].TimestampMs > records[j].TimestampMs })
	seen := make(map[string]bool, len(records))
	deduped := make([]historyRecord, 0, min(len(records), limit))
	for _, r := range records {
		if seen[r.ID] {
			continue
		}
		seen[r.ID] = true
		deduped = append(deduped, r)
		if len(deduped) == limit {
			break
		}
	}
	return &historyResult{Status: "ok", Records: deduped}, nil
}

func (g *Gateway) evmHistory(ctx context.Context, chain, network, address string, limit int) (*historyResult, *rpc.Error) {
	chainID := networks[network].EtherscanChainID
	var (
		txs        []upstream.EtherscanTx
		tokenTxs   []upstream.EtherscanTokenTx
		primaryErr error
	)
	// Etherscan v2 is multichain and covers every supported EVM network,
	// including Polygon Amoy, when a key is configured.
	if g.cfg.EtherscanKey != "" {
		txs, tokenTxs, primaryErr = evmHistoryLists(ctx, g.scan, chainID, address, limit)
		if primaryErr == nil {
			return evmHistoryResult(chain, network, address, limit, txs, tokenTxs), nil
		}
	}
	// Blockscout and Routescan expose the same account/txlist response shape
	// without credentials. They also keep history available when Etherscan is
	// temporarily unhealthy.
	if fallback := g.historyScan[network]; fallback != nil {
		var err error
		txs, tokenTxs, err = evmHistoryLists(ctx, fallback, chainID, address, limit)
		if err == nil {
			return evmHistoryResult(chain, network, address, limit, txs, tokenTxs), nil
		}
		if primaryErr == nil {
			primaryErr = err
		}
	}
	if primaryErr != nil {
		return nil, upstreamError("history_explorer", primaryErr)
	}
	return unsupportedHistory(), nil
}

func evmHistoryLists(
	ctx context.Context,
	source *upstream.Etherscan,
	chainID int,
	address string,
	limit int,
) ([]upstream.EtherscanTx, []upstream.EtherscanTokenTx, error) {
	txs, err := source.TxList(ctx, chainID, address, limit)
	if err != nil {
		return nil, nil, err
	}
	tokenTxs, err := source.TokenTxList(ctx, chainID, address, limit)
	if err != nil {
		return nil, nil, err
	}
	return txs, tokenTxs, nil
}

func evmHistoryResult(
	chain, network, address string,
	limit int,
	txs []upstream.EtherscanTx,
	tokenTxs []upstream.EtherscanTokenTx,
) *historyResult {
	self := strings.ToLower(address)
	symbol := chains[chain].Symbol
	records := make([]historyRecord, 0, len(txs)+len(tokenTxs))
	// Token transfers are appended first so the ERC-20 amount wins when the
	// same hash also appears as its zero-value contract-call wrapper.
	for i, t := range tokenTxs {
		decimals, err := strconv.Atoi(t.TokenDecimal)
		if err != nil || decimals < 0 || t.Hash == "" || t.ContractAddress == "" {
			continue
		}
		dir := "in"
		if strings.ToLower(t.From) == self {
			dir = "out"
		}
		status := "ok"
		if t.IsError != "" && t.IsError != "0" {
			status = "failed"
		}
		ts, err := strconv.ParseInt(t.TimeStamp, 10, 64)
		if err != nil {
			continue
		}
		contract := strings.ToLower(t.ContractAddress)
		tokenSymbol, tokenDecimals, verified := historyTokenMeta(
			evmTokensByNetwork[network], contract, t.TokenSymbol, decimals,
		)
		eventIndex := t.LogIndex
		if eventIndex == "" {
			eventIndex = strconv.Itoa(i)
		}
		records = append(records, historyRecord{
			ID:          t.Hash + ":" + eventIndex,
			Hash:        t.Hash,
			Direction:   dir,
			AmountRaw:   t.Value,
			Decimals:    tokenDecimals,
			Symbol:      tokenSymbol,
			Contract:    contract,
			Verified:    verified,
			TimestampMs: ts * 1000,
			Status:      status,
		})
	}
	for _, t := range txs {
		// The wallet history UI represents asset movements, not arbitrary
		// contract calls. A zero-value normal transaction is program activity
		// and must not be mislabeled as "received 0 ETH".
		if t.Value == "" || t.Value == "0" {
			continue
		}
		// Non-zero native value remains a separate event even when token logs
		// share the same transaction hash.
		dir := "in"
		if strings.ToLower(t.From) == self {
			dir = "out"
		}
		status := "ok"
		if t.IsError != "" && t.IsError != "0" {
			status = "failed"
		}
		ts, err := strconv.ParseInt(t.TimeStamp, 10, 64)
		if err != nil {
			continue
		}
		records = append(records, historyRecord{
			ID:          t.Hash,
			Hash:        t.Hash,
			Direction:   dir,
			AmountRaw:   t.Value,
			Decimals:    18,
			Symbol:      symbol,
			Verified:    true,
			TimestampMs: ts * 1000,
			Status:      status,
		})
	}
	sort.SliceStable(records, func(i, j int) bool { return records[i].TimestampMs > records[j].TimestampMs })
	seen := make(map[string]bool, len(records))
	deduped := make([]historyRecord, 0, min(len(records), limit))
	for _, record := range records {
		if seen[record.ID] {
			continue
		}
		seen[record.ID] = true
		deduped = append(deduped, record)
		if len(deduped) == limit {
			break
		}
	}
	return &historyResult{Status: "ok", Records: deduped}
}

func (g *Gateway) solanaHistory(ctx context.Context, network, address string, limit int) (*historyResult, *rpc.Error) {
	if g.cfg.HeliusKey != "" {
		transfers, err := g.hel[network].Transfers(ctx, address, limit)
		if err == nil {
			return heliusHistoryResult(network, address, limit, transfers), nil
		}
		// Helius is an optional enrichment layer. A key/configuration outage
		// must not hide the standard signature history available from RPC.
	}
	signatures, err := g.sol[network].GetSignaturesForAddress(ctx, address, limit)
	if err != nil {
		return nil, upstreamError("solana", err)
	}
	records := make([]historyRecord, 0, len(signatures))
	var detailErr error
	for _, sig := range signatures {
		if sig.Signature == "" {
			continue
		}
		impact, err := g.sol[network].GetTransactionAccountImpact(ctx, sig.Signature, address)
		if err != nil {
			detailErr = err
			continue
		}
		status := "ok"
		if sig.Failed() {
			status = "failed"
		}
		var timestampMs int64
		if sig.BlockTime != nil {
			timestampMs = *sig.BlockTime * 1000
		}
		if len(impact.Tokens) > 0 {
			for _, token := range impact.Tokens {
				symbol, decimals, verified := historyTokenMeta(
					solanaTokensByNetwork[network], token.Mint, "SPL", token.Decimals,
				)
				records = append(records, historyRecord{
					ID:          sig.Signature + ":spl:" + token.Mint,
					Hash:        sig.Signature,
					Direction:   token.Direction,
					AmountRaw:   token.Amount.String(),
					Decimals:    decimals,
					Symbol:      symbol,
					Contract:    token.Mint,
					Verified:    verified,
					TimestampMs: timestampMs,
					Status:      status,
				})
				if len(records) == limit {
					break
				}
			}
			if len(records) == limit {
				break
			}
			continue
		}
		// Pure program activity can have zero native and zero token movement.
		// It is not a transfer and must not be presented as "received 0 SOL".
		if impact.Amount.Sign() == 0 {
			continue
		}
		records = append(records, historyRecord{
			ID:          sig.Signature,
			Hash:        sig.Signature,
			Direction:   impact.Direction,
			AmountRaw:   impact.Amount.String(),
			Decimals:    9,
			Symbol:      "SOL",
			Verified:    true,
			TimestampMs: timestampMs,
			Status:      status,
		})
	}
	if len(signatures) > 0 && len(records) == 0 && detailErr != nil {
		return nil, upstreamError("solana", detailErr)
	}
	return &historyResult{Status: "ok", Records: records}, nil
}

func heliusHistoryResult(network, address string, limit int, transfers []upstream.HeliusTransfer) *historyResult {
	records := make([]historyRecord, 0, min(len(transfers), limit))
	for _, transfer := range transfers {
		dir := ""
		if transfer.FromUserAccount == address {
			dir = "out"
		} else if transfer.ToUserAccount == address {
			dir = "in"
		}
		if dir == "" || transfer.Signature == "" || transfer.Amount == "" {
			continue
		}
		symbol, decimals, verified := historyTokenMeta(
			solanaTokensByNetwork[network], transfer.Mint, "SPL", transfer.Decimals,
		)
		contract := transfer.Mint
		if transfer.Mint == nativeSOLMint {
			symbol, decimals, verified, contract = "SOL", 9, true, ""
		}
		inner := -1
		if transfer.InnerInstructionIdx != nil {
			inner = *transfer.InnerInstructionIdx
		}
		records = append(records, historyRecord{
			ID: fmt.Sprintf(
				"%s:%d:%d:%d",
				transfer.Signature, transfer.TransactionIndex, transfer.InstructionIndex, inner,
			),
			Hash:        transfer.Signature,
			Direction:   dir,
			AmountRaw:   transfer.Amount,
			Decimals:    decimals,
			Symbol:      symbol,
			Contract:    contract,
			Verified:    verified,
			TimestampMs: transfer.BlockTime * 1000,
			Status:      "ok",
		})
		if len(records) == limit {
			break
		}
	}
	return &historyResult{Status: "ok", Records: records}
}

func historyTokenMeta(
	registry map[string]tokenMeta,
	contract, claimedSymbol string,
	claimedDecimals int,
) (symbol string, decimals int, verified bool) {
	key := contract
	if strings.HasPrefix(strings.ToLower(contract), "0x") {
		key = strings.ToLower(contract)
	}
	if meta, ok := registry[key]; ok {
		return meta.Symbol, meta.Decimals, true
	}
	symbol = strings.ToUpper(strings.TrimSpace(claimedSymbol))
	if symbol == "" || len(symbol) > 12 {
		symbol = "TOKEN"
	}
	for _, r := range symbol {
		if !((r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '.' || r == '-' || r == '_') {
			symbol = "TOKEN"
			break
		}
	}
	if claimedDecimals < 0 || claimedDecimals > 36 {
		claimedDecimals = 0
	}
	return symbol, claimedDecimals, false
}
