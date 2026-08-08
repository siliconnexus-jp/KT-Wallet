package handlers

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"math/big"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"ktwallet/gateway/internal/rpc"
	"ktwallet/gateway/internal/upstream"
)

const (
	defaultHistoryLimit = 20
	maxHistoryLimit     = 100
)

const nativeSOLMint = "So11111111111111111111111111111111111111111"

type historyRecord struct {
	ID          string `json:"id"`
	Hash        string `json:"hash"`
	Direction   string `json:"direction"` // "in" | "out"
	From        string `json:"from,omitempty"`
	To          string `json:"to,omitempty"`
	AmountRaw   string `json:"amountRaw"`
	Decimals    int    `json:"decimals"`
	Symbol      string `json:"symbol"`
	Contract    string `json:"contract,omitempty"`
	Verified    bool   `json:"verified"`
	TimestampMs int64  `json:"timestampMs"`
	Status      string `json:"status"` // "ok" | "failed" | "pending" | "unknown"
}

type historyResult struct {
	Chain   string          `json:"chain"`
	Network string          `json:"network"`
	Address string          `json:"address"`
	Status  string          `json:"status"` // "ok" | "unsupported"
	Records []historyRecord `json:"records"`
}

func unsupportedHistory() *historyResult {
	return &historyResult{Status: "unsupported", Records: []historyRecord{}}
}

func historyExecutionStatus(status upstream.ExecutionStatus) string {
	switch status {
	case upstream.ExecutionConfirmed:
		return "ok"
	case upstream.ExecutionFailed:
		return "failed"
	default:
		return "unknown"
	}
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
	if err := decodeStrictJSON(params, &p); err != nil || len(params) == 0 {
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
	if v, ok := g.historyCache.GetContext(ctx, key); ok {
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
	// Bind every successful response (including unsupported) to the exact
	// request identity. The mobile client rejects a page that cannot prove
	// which chain, network, and owner it belongs to.
	res.Chain = p.Chain
	res.Network = network
	res.Address = p.Address
	g.historyCache.SetContext(ctx, key, res)
	return res, nil
}

// tronHistory merges TRC-20 transfers and protocol/internal value movements,
// newest first. Every event is independently validated as touching the
// requested wallet; a shared transaction hash never suppresses a distinct
// asset movement.
func (g *Gateway) tronHistory(ctx context.Context, network, address string, limit int) (*historyResult, *rpc.Error) {
	selfHex := tronAddrHex(address)

	tron := g.tron[network]
	var (
		trc20       []upstream.TRC20Transfer
		native      []upstream.NativeTransfer
		internal    []upstream.InternalTransfer
		trc20Err    error
		nativeErr   error
		internalErr error
	)
	var wg sync.WaitGroup
	wg.Add(3)
	go func() {
		defer wg.Done()
		trc20, trc20Err = tron.TRC20Transfers(ctx, address, limit)
	}()
	go func() {
		defer wg.Done()
		native, nativeErr = tron.NativeTransactions(ctx, address, limit)
	}()
	go func() {
		defer wg.Done()
		internal, internalErr = tron.InternalTransactions(ctx, address, limit)
	}()
	wg.Wait()
	firstErr := trc20Err
	if firstErr == nil {
		firstErr = nativeErr
	}
	if firstErr == nil {
		firstErr = internalErr
	}
	if trc20Err != nil && nativeErr != nil && internalErr != nil {
		return nil, upstreamError("trongrid", firstErr)
	}

	records := make([]historyRecord, 0, len(trc20)+len(native)+len(internal))
	for _, t := range trc20 {
		from := tronAddrHex(t.From)
		to := tronAddrHex(t.To)
		if from != selfHex && to != selfHex {
			continue
		}
		dir := "in"
		if from == selfHex {
			dir = "out"
		}
		symbol, decimals, verified := historyTokenMeta(
			g.officialByNetwork[network], t.Contract, t.Symbol, t.Decimals,
		)
		records = append(records, historyRecord{
			ID:          tronTRC20EventID(t),
			Hash:        t.TransactionID,
			Direction:   dir,
			From:        t.From,
			To:          t.To,
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
		from := tronAddrHex(t.Owner)
		to := tronAddrHex(t.To)
		if from != selfHex && to != selfHex {
			continue
		}
		dir := "in"
		if from == selfHex {
			dir = "out"
		}
		status := historyExecutionStatus(t.Status)
		id := t.TxID
		if t.ContractIndex > 0 {
			id += fmt.Sprintf(":contract:%d", t.ContractIndex)
		}
		decimals := 6
		symbol := "TRX"
		contract := ""
		verified := true
		if t.TokenID != "" {
			id += ":trc10:" + t.TokenID
			decimals = 0
			symbol = "TRC10"
			contract = t.TokenID
			verified = false
		}
		records = append(records, historyRecord{
			ID:          id,
			Hash:        t.TxID,
			Direction:   dir,
			From:        tronAddrDisplay(t.Owner),
			To:          tronAddrDisplay(t.To),
			AmountRaw:   t.Amount,
			Decimals:    decimals,
			Symbol:      symbol,
			Contract:    contract,
			Verified:    verified,
			TimestampMs: t.BlockTimestamp,
			Status:      status,
		})
	}
	for _, t := range internal {
		from := tronAddrHex(t.From)
		to := tronAddrHex(t.To)
		if from != selfHex && to != selfHex {
			continue
		}
		dir := "in"
		if from == selfHex {
			dir = "out"
		}
		status := historyExecutionStatus(t.Status)
		decimals := 6
		symbol := "TRX"
		contract := ""
		verified := true
		if t.TokenID != "" {
			decimals = 0
			symbol = "TRC10"
			contract = t.TokenID
			verified = false
		}
		id := t.TxID + ":internal:" + t.InternalTxID
		if t.AssetIndex > 0 || t.TokenID != "" {
			id += ":trc10:" + t.TokenID
		}
		records = append(records, historyRecord{
			ID:          id,
			Hash:        t.TxID,
			Direction:   dir,
			From:        tronAddrDisplay(t.From),
			To:          tronAddrDisplay(t.To),
			AmountRaw:   t.Amount,
			Decimals:    decimals,
			Symbol:      symbol,
			Contract:    contract,
			Verified:    verified,
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
	// Preserve independently validated records when one TronGrid resource is
	// unavailable. A partial set with no usable records is not proof that the
	// wallet has no history, so do not cache it as an authoritative empty page.
	if firstErr != nil && len(deduped) == 0 {
		return nil, upstreamError("trongrid", firstErr)
	}
	return &historyResult{Status: "ok", Records: deduped}, nil
}

func tronTRC20EventID(t upstream.TRC20Transfer) string {
	semantic := strings.Join([]string{
		strings.ToLower(t.TransactionID),
		t.Contract,
		t.From,
		t.To,
		t.Value,
	}, "\x00")
	digest := sha256.Sum256([]byte(semantic))
	return fmt.Sprintf("%s:trc20:%s:%x", t.TransactionID, t.Contract, digest[:8])
}

func (g *Gateway) evmHistory(ctx context.Context, chain, network, address string, limit int) (*historyResult, *rpc.Error) {
	chainID := networks[network].EtherscanChainID
	var (
		txs         []upstream.EtherscanTx
		tokenTxs    []upstream.EtherscanTokenTx
		internalTxs []upstream.EtherscanInternalTx
		primaryErr  error
	)
	// Alchemy's indexed Transfers API is primary because it covers every EVM
	// network used by KT Wallet, including BNB 56/97 and Polygon Amoy.
	if source := g.alchemy[network]; source != nil {
		transfers, err := source.Transfers(ctx, address, limit)
		if err == nil {
			return alchemyHistoryResult(
				chain,
				address,
				limit,
				transfers,
				g.officialByNetwork[network],
			), nil
		}
		primaryErr = err
	}
	// Etherscan v2 is multichain and covers every supported EVM network,
	// including Polygon Amoy, when a key is configured. Each account stream
	// falls back independently so one broken token/internal endpoint cannot
	// discard valid native history (and vice versa).
	explorers := make([]*upstream.Etherscan, 0, 2)
	if g.cfg.EtherscanKey != "" {
		explorers = append(explorers, g.scan)
	}
	// Blockscout and Routescan expose the same account/txlist response shape
	// without credentials. They also keep history available when Etherscan is
	// temporarily unhealthy.
	if fallback := g.historyScan[network]; fallback != nil {
		explorers = append(explorers, fallback)
	}
	if len(explorers) > 0 {
		var explorerErr error
		txs, tokenTxs, internalTxs, explorerErr = evmHistoryLists(
			ctx, explorers, chainID, address, limit, true,
		)
		result := evmHistoryResult(
			chain,
			address,
			limit,
			txs,
			tokenTxs,
			internalTxs,
			g.officialByNetwork[network],
		)
		if explorerErr == nil || len(result.Records) > 0 {
			return result, nil
		}
		if primaryErr == nil {
			primaryErr = explorerErr
		}
	}
	if primaryErr != nil {
		return nil, upstreamError("history_explorer", primaryErr)
	}
	return unsupportedHistory(), nil
}

func alchemyHistoryResult(
	chain, address string,
	limit int,
	transfers []upstream.AlchemyTransfer,
	registry map[string]tokenMeta,
) *historyResult {
	self := strings.ToLower(address)
	nativeSymbol := chains[chain].Symbol
	nativeDecimals := chains[chain].Decimals
	records := make([]historyRecord, 0, len(transfers))
	for i, transfer := range transfers {
		from := strings.ToLower(transfer.From)
		to := strings.ToLower(transfer.To)
		if from != self && to != self {
			continue
		}
		raw, ok := parseAlchemyHexInteger(transfer.Raw.Value)
		if !ok || raw.Sign() == 0 || transfer.Hash == "" {
			continue
		}
		decimals, ok := parseAlchemyHexInt(transfer.Raw.Decimal)
		if !ok || decimals < 0 {
			continue
		}
		timestamp, err := time.Parse(time.RFC3339Nano, transfer.BlockTime)
		if err != nil {
			continue
		}

		direction := "in"
		if from == self {
			direction = "out"
		}
		id := transfer.UniqueID
		if id == "" {
			id = fmt.Sprintf("%s:%s:%d", transfer.Hash, transfer.Category, i)
		}
		symbol := nativeSymbol
		contract := ""
		verified := true
		if transfer.Category == "erc20" {
			contract = strings.ToLower(transfer.Raw.Address)
			if contract == "" {
				continue
			}
			symbol, decimals, verified = historyTokenMeta(
				registry, contract, transfer.Asset, decimals,
			)
		} else {
			// A native transfer is denominated by the chain, not by whatever
			// scale the indexer reports for it. This is the same table the
			// sibling `symbol` above comes from; taking one from the registry
			// and the other from upstream is what let a 1 BNB transfer be
			// emitted as a verified row reading 1,000,000,000 BNB.
			decimals = nativeDecimals
		}
		records = append(records, historyRecord{
			ID:          id,
			Hash:        transfer.Hash,
			Direction:   direction,
			From:        transfer.From,
			To:          transfer.To,
			AmountRaw:   raw.String(),
			Decimals:    decimals,
			Symbol:      symbol,
			Contract:    contract,
			Verified:    verified,
			TimestampMs: timestamp.UnixMilli(),
			Status:      "ok",
		})
	}
	sort.SliceStable(records, func(i, j int) bool {
		return records[i].TimestampMs > records[j].TimestampMs
	})
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

func parseAlchemyHexInteger(value string) (*big.Int, bool) {
	if len(value) < 3 || !strings.HasPrefix(value, "0x") {
		return nil, false
	}
	n, ok := new(big.Int).SetString(value[2:], 16)
	return n, ok
}

func parseAlchemyHexInt(value string) (int, bool) {
	n, ok := parseAlchemyHexInteger(value)
	if !ok || !n.IsInt64() {
		return 0, false
	}
	v := n.Int64()
	if v > int64(^uint(0)>>1) {
		return 0, false
	}
	return int(v), true
}

func evmHistoryLists(
	ctx context.Context,
	sources []*upstream.Etherscan,
	chainID int,
	address string,
	limit int,
	includeInternal bool,
) ([]upstream.EtherscanTx, []upstream.EtherscanTokenTx, []upstream.EtherscanInternalTx, error) {
	var (
		txs         []upstream.EtherscanTx
		tokenTxs    []upstream.EtherscanTokenTx
		internalTxs []upstream.EtherscanInternalTx
		txErr       error
		tokenErr    error
	)
	var wg sync.WaitGroup
	wg.Add(2)
	go func() {
		defer wg.Done()
		txs, txErr = firstExplorerTxList(ctx, sources, chainID, address, limit)
	}()
	go func() {
		defer wg.Done()
		tokenTxs, tokenErr = firstExplorerTokenTxList(ctx, sources, chainID, address, limit)
	}()
	if includeInternal {
		// Internal traces are an enrichment layer. Some otherwise compatible
		// explorers do not expose txlistinternal; that must not hide normal and
		// token history which was already fetched successfully.
		wg.Add(1)
		go func() {
			defer wg.Done()
			internalTxs, _ = firstExplorerInternalTxList(ctx, sources, chainID, address, limit)
		}()
	}
	wg.Wait()
	if txErr != nil || tokenErr != nil {
		if txErr != nil {
			return txs, tokenTxs, internalTxs, txErr
		}
		return txs, tokenTxs, internalTxs, tokenErr
	}
	return txs, tokenTxs, internalTxs, nil
}

func firstExplorerTxList(
	ctx context.Context,
	sources []*upstream.Etherscan,
	chainID int,
	address string,
	limit int,
) ([]upstream.EtherscanTx, error) {
	var lastErr error
	for _, source := range sources {
		rows, err := source.TxList(ctx, chainID, address, limit)
		if err == nil {
			return rows, nil
		}
		lastErr = err
		if ctx.Err() != nil {
			break
		}
	}
	return nil, lastErr
}

func firstExplorerTokenTxList(
	ctx context.Context,
	sources []*upstream.Etherscan,
	chainID int,
	address string,
	limit int,
) ([]upstream.EtherscanTokenTx, error) {
	var lastErr error
	for _, source := range sources {
		rows, err := source.TokenTxList(ctx, chainID, address, limit)
		if err == nil {
			return rows, nil
		}
		lastErr = err
		if ctx.Err() != nil {
			break
		}
	}
	return nil, lastErr
}

func firstExplorerInternalTxList(
	ctx context.Context,
	sources []*upstream.Etherscan,
	chainID int,
	address string,
	limit int,
) ([]upstream.EtherscanInternalTx, error) {
	var lastErr error
	for _, source := range sources {
		rows, err := source.InternalTxList(ctx, chainID, address, limit)
		if err == nil {
			return rows, nil
		}
		lastErr = err
		if ctx.Err() != nil {
			break
		}
	}
	return nil, lastErr
}

func evmHistoryResult(
	chain, address string,
	limit int,
	txs []upstream.EtherscanTx,
	tokenTxs []upstream.EtherscanTokenTx,
	internalTxs []upstream.EtherscanInternalTx,
	registry map[string]tokenMeta,
) *historyResult {
	self := strings.ToLower(address)
	symbol := chains[chain].Symbol
	records := make([]historyRecord, 0, len(txs)+len(tokenTxs)+len(internalTxs))
	normalMovements := make(map[string]bool, len(txs))
	for _, t := range txs {
		from := strings.ToLower(t.From)
		to := strings.ToLower(t.To)
		if from != self && to != self {
			continue
		}
		normalMovements[evmMovementKey(t.Hash, t.From, t.To, t.Value, t.TimeStamp)] = true
	}
	// Token transfers are appended first so the ERC-20 amount wins when the
	// same hash also appears as its zero-value contract-call wrapper.
	for i, t := range tokenTxs {
		decimals, err := strconv.Atoi(t.TokenDecimal)
		if err != nil || decimals < 0 || t.Hash == "" || t.ContractAddress == "" {
			continue
		}
		from := strings.ToLower(t.From)
		to := strings.ToLower(t.To)
		if from != self && to != self {
			continue
		}
		dir := "in"
		if from == self {
			dir = "out"
		}
		status := historyExecutionStatus(upstream.EtherscanTokenExecutionStatus(t))
		ts, err := strconv.ParseInt(t.TimeStamp, 10, 64)
		if err != nil {
			continue
		}
		contract := strings.ToLower(t.ContractAddress)
		tokenSymbol, tokenDecimals, verified := historyTokenMeta(
			registry, contract, t.TokenSymbol, decimals,
		)
		eventIndex := t.LogIndex
		if eventIndex == "" {
			eventIndex = strconv.Itoa(i)
		}
		records = append(records, historyRecord{
			ID:          t.Hash + ":" + eventIndex,
			Hash:        t.Hash,
			Direction:   dir,
			From:        t.From,
			To:          t.To,
			AmountRaw:   t.Value,
			Decimals:    tokenDecimals,
			Symbol:      tokenSymbol,
			Contract:    contract,
			Verified:    verified,
			TimestampMs: ts * 1000,
			Status:      status,
		})
	}
	for i, t := range internalTxs {
		hash := t.CanonicalHash()
		if hash == "" || t.Value == "" || t.Value == "0" {
			continue
		}
		// Some nominally Etherscan-compatible explorers return the normal
		// txlist body for txlistinternal. Suppress that false duplicate.
		if normalMovements[evmMovementKey(hash, t.From, t.To, t.Value, t.TimeStamp)] {
			continue
		}
		from := strings.ToLower(t.From)
		to := strings.ToLower(t.To)
		if from != self && to != self {
			continue
		}
		dir := "in"
		if from == self {
			dir = "out"
		}
		status := historyExecutionStatus(
			upstream.EtherscanExecutionStatus(t.IsError, t.ReceiptStatus),
		)
		ts, err := strconv.ParseInt(t.TimeStamp, 10, 64)
		if err != nil {
			continue
		}
		traceID := t.CanonicalTraceID()
		if traceID == "" {
			traceID = strconv.Itoa(i)
		}
		records = append(records, historyRecord{
			ID:          hash + ":internal:" + traceID,
			Hash:        hash,
			Direction:   dir,
			From:        t.From,
			To:          t.To,
			AmountRaw:   t.Value,
			Decimals:    18,
			Symbol:      symbol,
			Verified:    true,
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
		from := strings.ToLower(t.From)
		to := strings.ToLower(t.To)
		if from != self && to != self {
			continue
		}
		// Non-zero native value remains a separate event even when token logs
		// share the same transaction hash.
		dir := "in"
		if from == self {
			dir = "out"
		}
		status := historyExecutionStatus(
			upstream.EtherscanExecutionStatus(t.IsError, t.ReceiptStatus),
		)
		ts, err := strconv.ParseInt(t.TimeStamp, 10, 64)
		if err != nil {
			continue
		}
		records = append(records, historyRecord{
			ID:          t.Hash,
			Hash:        t.Hash,
			Direction:   dir,
			From:        t.From,
			To:          t.To,
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

func evmMovementKey(hash, from, to, value, timestamp string) string {
	return strings.Join(
		[]string{hash, strings.ToLower(from), strings.ToLower(to), value, timestamp},
		"|",
	)
}

func (g *Gateway) solanaHistory(ctx context.Context, network, address string, limit int) (*historyResult, *rpc.Error) {
	if g.cfg.HeliusKey != "" {
		transfers, err := g.hel[network].Transfers(ctx, address, limit)
		if err == nil {
			return heliusHistoryResult(
				address,
				limit,
				transfers,
				g.officialByNetwork[network],
			), nil
		}
		// Helius is an optional enrichment layer. A key/configuration outage
		// must not hide the standard signature history available from RPC.
	}
	signatures, err := g.solanaHistorySignatures(ctx, network, address, limit)
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
		status := historyExecutionStatus(sig.ExecutionStatus())
		var timestampMs int64
		if sig.BlockTime != nil {
			timestampMs = *sig.BlockTime * 1000
		}
		if len(impact.Tokens) > 0 {
			for _, token := range impact.Tokens {
				from, to := token.From, token.To
				if token.Direction == "out" && from == "" {
					from = address
				}
				if token.Direction == "in" && to == "" {
					to = address
				}
				symbol, decimals, verified := historyTokenMeta(
					g.officialByNetwork[network],
					token.Mint,
					"SPL",
					token.Decimals,
				)
				records = append(records, historyRecord{
					ID:          sig.Signature + ":spl:" + token.Mint,
					Hash:        sig.Signature,
					Direction:   token.Direction,
					From:        from,
					To:          to,
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
		from, to := impact.From, impact.To
		if impact.Direction == "out" && from == "" {
			from = address
		}
		if impact.Direction == "in" && to == "" {
			to = address
		}
		records = append(records, historyRecord{
			ID:          sig.Signature,
			Hash:        sig.Signature,
			Direction:   impact.Direction,
			From:        from,
			To:          to,
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

func (g *Gateway) solanaHistorySignatures(
	ctx context.Context,
	network, owner string,
	limit int,
) ([]upstream.SolanaSignature, error) {
	node := g.sol[network]
	ownerSignatures, err := node.GetSignaturesForAddress(ctx, owner, limit)
	if err != nil {
		return nil, err
	}
	bySignature := make(map[string]upstream.SolanaSignature)
	for _, signature := range ownerSignatures {
		if signature.Signature != "" {
			bySignature[signature.Signature] = signature
		}
	}
	tokenAccounts, err := node.GetOwnedTokenAccounts(ctx, owner)
	if err == nil {
		// Bound fan-out for wallets that have accumulated hundreds of spam
		// token accounts. Registered/common assets are normally far below it.
		if len(tokenAccounts) > 32 {
			tokenAccounts = tokenAccounts[:32]
		}
		var mu sync.Mutex
		var wg sync.WaitGroup
		sem := make(chan struct{}, 6)
		for _, tokenAccount := range tokenAccounts {
			wg.Add(1)
			go func(account string) {
				defer wg.Done()
				select {
				case sem <- struct{}{}:
					defer func() { <-sem }()
				case <-ctx.Done():
					return
				}
				rows, rowErr := node.GetSignaturesForAddress(ctx, account, limit)
				if rowErr != nil {
					return
				}
				mu.Lock()
				defer mu.Unlock()
				for _, signature := range rows {
					if signature.Signature != "" {
						bySignature[signature.Signature] = signature
					}
				}
			}(tokenAccount)
		}
		wg.Wait()
	}
	signatures := make([]upstream.SolanaSignature, 0, len(bySignature))
	for _, signature := range bySignature {
		signatures = append(signatures, signature)
	}
	sort.SliceStable(signatures, func(i, j int) bool {
		left, right := signatures[i].BlockTime, signatures[j].BlockTime
		if left == nil {
			return false
		}
		if right == nil {
			return true
		}
		return *left > *right
	})
	maxCandidates := limit * 4
	if len(signatures) > maxCandidates {
		signatures = signatures[:maxCandidates]
	}
	return signatures, nil
}

func heliusHistoryResult(
	address string,
	limit int,
	transfers []upstream.HeliusTransfer,
	registry map[string]tokenMeta,
) *historyResult {
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
			registry, transfer.Mint, "SPL", transfer.Decimals,
		)
		contract := transfer.Mint
		if transfer.Mint == nativeSOLMint {
			symbol, decimals, verified, contract = "SOL", 9, true, ""
		}
		inner := -1
		if transfer.InnerInstructionIdx != nil {
			inner = *transfer.InnerInstructionIdx
		}
		status := "unknown"
		switch transfer.ConfirmationStatus {
		case "confirmed", "finalized":
			status = "ok"
		case "processed":
			status = "pending"
		}
		records = append(records, historyRecord{
			ID: fmt.Sprintf(
				"%s:%d:%d:%d",
				transfer.Signature, transfer.TransactionIndex, transfer.InstructionIndex, inner,
			),
			Hash:        transfer.Signature,
			Direction:   dir,
			From:        transfer.FromUserAccount,
			To:          transfer.ToUserAccount,
			AmountRaw:   transfer.Amount,
			Decimals:    decimals,
			Symbol:      symbol,
			Contract:    contract,
			Verified:    verified,
			TimestampMs: transfer.BlockTime * 1000,
			Status:      status,
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
