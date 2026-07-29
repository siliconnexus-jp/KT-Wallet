package upstream

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"strconv"
	"strings"
	"sync/atomic"
	"time"
)

// Alchemy is a JSON-RPC client for alchemy_getAssetTransfers. The endpoint
// includes the API key and is kept exclusively in the gateway process.
type Alchemy struct {
	endpoints []string
	client    *http.Client
	timeout   time.Duration
	next      atomic.Uint64
}

func NewAlchemy(endpoints []string, client *http.Client, attemptTimeout time.Duration) *Alchemy {
	if client == nil {
		client = http.DefaultClient
	}
	if attemptTimeout <= 0 {
		attemptTimeout = 10 * time.Second
	}
	return &Alchemy{endpoints: append([]string(nil), endpoints...), client: client, timeout: attemptTimeout}
}

type AlchemyRawContract struct {
	Value   string `json:"value"`
	Address string `json:"address"`
	Decimal string `json:"decimal"`
}

type AlchemyTransfer struct {
	UniqueID  string             `json:"uniqueId"`
	BlockNum  string             `json:"blockNum"`
	Hash      string             `json:"hash"`
	From      string             `json:"from"`
	To        string             `json:"to"`
	Asset     string             `json:"asset"`
	Category  string             `json:"category"`
	Raw       AlchemyRawContract `json:"rawContract"`
	BlockTime string             `json:"-"`
}

// UnmarshalJSON accepts the optional metadata.blockTimestamp field without
// exposing Alchemy's floating-point display amount as a source of truth.
func (t *AlchemyTransfer) UnmarshalJSON(data []byte) error {
	type alias AlchemyTransfer
	var wire struct {
		alias
		Metadata struct {
			BlockTimestamp string `json:"blockTimestamp"`
		} `json:"metadata"`
	}
	if err := json.Unmarshal(data, &wire); err != nil {
		return err
	}
	*t = AlchemyTransfer(wire.alias)
	t.BlockTime = wire.Metadata.BlockTimestamp
	return nil
}

// Transfers returns confirmed native and ERC-20 movements involving address.
// Incoming and outgoing feeds are requested concurrently. Internal transfers
// are requested where supported; if a network rejects that category, the
// client retries with external + erc20 so base history remains available.
func (a *Alchemy) Transfers(ctx context.Context, address string, limit int) ([]AlchemyTransfer, error) {
	type result struct {
		items []AlchemyTransfer
		err   error
	}
	results := make(chan result, 2)
	for _, direction := range []string{"fromAddress", "toAddress"} {
		direction := direction
		go func() {
			items, err := a.transfersFor(ctx, address, limit, direction, true)
			if err != nil {
				items, err = a.transfersFor(ctx, address, limit, direction, false)
			}
			results <- result{items: items, err: err}
		}()
	}

	var (
		all      []AlchemyTransfer
		firstErr error
	)
	for range 2 {
		r := <-results
		if r.err != nil && firstErr == nil {
			firstErr = r.err
		}
		all = append(all, r.items...)
	}
	if firstErr != nil {
		return nil, firstErr
	}
	if err := a.fillMissingBlockTimes(ctx, all); err != nil {
		return nil, err
	}
	return all, nil
}

func (a *Alchemy) transfersFor(
	ctx context.Context,
	address string,
	limit int,
	direction string,
	includeInternal bool,
) ([]AlchemyTransfer, error) {
	categories := []string{"external", "erc20"}
	if includeInternal {
		categories = append(categories, "internal")
	}
	params := map[string]any{
		"fromBlock":        "0x0",
		"toBlock":          "latest",
		"excludeZeroValue": true,
		"withMetadata":     true,
		"order":            "desc",
		"maxCount":         "0x" + strconv.FormatInt(int64(limit), 16),
		"category":         categories,
		direction:          address,
	}
	payload, err := json.Marshal(map[string]any{
		"jsonrpc": "2.0",
		"id":      1,
		"method":  "alchemy_getAssetTransfers",
		"params":  []any{params},
	})
	if err != nil {
		return nil, &Unavailable{Upstream: "alchemy", Message: err.Error()}
	}

	if len(a.endpoints) == 0 {
		return nil, &Unavailable{Upstream: "alchemy", Message: "no Alchemy endpoints configured"}
	}
	start := int(a.next.Add(1)-1) % len(a.endpoints)
	var lastErr error
	for offset := range len(a.endpoints) {
		endpoint := a.endpoints[(start+offset)%len(a.endpoints)]
		transfers, err := a.requestEndpoint(ctx, endpoint, payload)
		if err == nil {
			return transfers, nil
		}
		lastErr = err
		if ctx.Err() != nil {
			break
		}
	}
	return nil, lastErr
}

func (a *Alchemy) requestEndpoint(
	ctx context.Context,
	endpoint string,
	payload []byte,
) ([]AlchemyTransfer, error) {
	actx, cancel := context.WithTimeout(ctx, a.timeout)
	defer cancel()
	req, err := http.NewRequestWithContext(actx, http.MethodPost, endpoint, bytes.NewReader(payload))
	if err != nil {
		return nil, &Unavailable{Upstream: "alchemy", Message: err.Error()}
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := a.client.Do(req)
	if err != nil {
		return nil, &Unavailable{Upstream: "alchemy", Message: err.Error()}
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	if err != nil {
		return nil, &Unavailable{Upstream: "alchemy", Message: err.Error()}
	}
	if resp.StatusCode != http.StatusOK {
		return nil, &Unavailable{
			Upstream: "alchemy",
			Message:  fmt.Sprintf("Alchemy returned HTTP %d", resp.StatusCode),
		}
	}
	var out struct {
		Result struct {
			Transfers []AlchemyTransfer `json:"transfers"`
		} `json:"result"`
		Error *struct {
			Code    int    `json:"code"`
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.Unmarshal(data, &out); err != nil {
		return nil, &Unavailable{Upstream: "alchemy", Message: "malformed Alchemy response"}
	}
	if out.Error != nil {
		return nil, &Unavailable{
			Upstream: "alchemy",
			Message:  fmt.Sprintf("Alchemy error %d: %s", out.Error.Code, out.Error.Message),
		}
	}
	if out.Result.Transfers == nil {
		return nil, &Unavailable{Upstream: "alchemy", Message: "Alchemy response has no transfers"}
	}
	return out.Result.Transfers, nil
}

func (a *Alchemy) fillMissingBlockTimes(
	ctx context.Context,
	transfers []AlchemyTransfer,
) error {
	missing := make(map[string][]int)
	for i := range transfers {
		if transfers[i].BlockTime == "" && transfers[i].BlockNum != "" {
			missing[transfers[i].BlockNum] = append(missing[transfers[i].BlockNum], i)
		}
	}
	if len(missing) == 0 {
		return nil
	}
	blocks := make([]string, 0, len(missing))
	for block := range missing {
		blocks = append(blocks, block)
	}
	timestamps, err := a.blockTimestamps(ctx, blocks)
	if err != nil {
		return err
	}
	for block, indexes := range missing {
		timestamp, ok := timestamps[block]
		if !ok {
			return &Unavailable{
				Upstream: "alchemy",
				Message:  "Alchemy block timestamp response is incomplete",
			}
		}
		for _, index := range indexes {
			transfers[index].BlockTime = timestamp
		}
	}
	return nil
}

func (a *Alchemy) blockTimestamps(
	ctx context.Context,
	blocks []string,
) (map[string]string, error) {
	batch := make([]map[string]any, 0, len(blocks))
	for i, block := range blocks {
		batch = append(batch, map[string]any{
			"jsonrpc": "2.0",
			"id":      i + 1,
			"method":  "eth_getBlockByNumber",
			"params":  []any{block, false},
		})
	}
	payload, err := json.Marshal(batch)
	if err != nil {
		return nil, &Unavailable{Upstream: "alchemy", Message: err.Error()}
	}
	if len(a.endpoints) == 0 {
		return nil, &Unavailable{Upstream: "alchemy", Message: "no Alchemy endpoints configured"}
	}
	start := int(a.next.Add(1)-1) % len(a.endpoints)
	var lastErr error
	for offset := range len(a.endpoints) {
		endpoint := a.endpoints[(start+offset)%len(a.endpoints)]
		timestamps, err := a.requestBlockTimestamps(ctx, endpoint, payload, blocks)
		if err == nil {
			return timestamps, nil
		}
		lastErr = err
		if ctx.Err() != nil {
			break
		}
	}
	return nil, lastErr
}

func (a *Alchemy) requestBlockTimestamps(
	ctx context.Context,
	endpoint string,
	payload []byte,
	blocks []string,
) (map[string]string, error) {
	actx, cancel := context.WithTimeout(ctx, a.timeout)
	defer cancel()
	req, err := http.NewRequestWithContext(actx, http.MethodPost, endpoint, bytes.NewReader(payload))
	if err != nil {
		return nil, &Unavailable{Upstream: "alchemy", Message: err.Error()}
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := a.client.Do(req)
	if err != nil {
		return nil, &Unavailable{Upstream: "alchemy", Message: err.Error()}
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	if err != nil {
		return nil, &Unavailable{Upstream: "alchemy", Message: err.Error()}
	}
	if resp.StatusCode != http.StatusOK {
		return nil, &Unavailable{
			Upstream: "alchemy",
			Message:  fmt.Sprintf("Alchemy returned HTTP %d", resp.StatusCode),
		}
	}
	var out []struct {
		ID     int `json:"id"`
		Result *struct {
			Timestamp string `json:"timestamp"`
		} `json:"result"`
		Error *struct {
			Code    int    `json:"code"`
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.Unmarshal(data, &out); err != nil {
		return nil, &Unavailable{
			Upstream: "alchemy",
			Message:  "malformed Alchemy batch response",
		}
	}
	timestamps := make(map[string]string, len(out))
	for _, item := range out {
		if item.Error != nil {
			return nil, &Unavailable{
				Upstream: "alchemy",
				Message:  fmt.Sprintf("Alchemy error %d: %s", item.Error.Code, item.Error.Message),
			}
		}
		if item.ID <= 0 || item.ID > len(blocks) ||
			item.Result == nil || item.Result.Timestamp == "" {
			return nil, &Unavailable{
				Upstream: "alchemy",
				Message:  "Alchemy block response is incomplete",
			}
		}
		seconds, ok := new(big.Int).SetString(
			strings.TrimPrefix(item.Result.Timestamp, "0x"),
			16,
		)
		if !ok || !seconds.IsInt64() {
			return nil, &Unavailable{
				Upstream: "alchemy",
				Message:  "Alchemy returned an invalid block timestamp",
			}
		}
		timestamps[blocks[item.ID-1]] = time.Unix(
			seconds.Int64(),
			0,
		).UTC().Format(time.RFC3339Nano)
	}
	return timestamps, nil
}
