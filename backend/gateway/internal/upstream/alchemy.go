package upstream

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
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

func decodeAlchemyTransfers(data []byte) ([]AlchemyTransfer, bool, error) {
	fields, err := decodeExactJSONObject(data, "jsonrpc", "id", "result", "error")
	if err != nil {
		return nil, false, err
	}
	var version string
	if err := json.Unmarshal(fields["jsonrpc"], &version); err != nil {
		return nil, false, err
	}
	resultRaw, hasResult := fields["result"]
	errorRaw, hasError := fields["error"]
	if version != "2.0" ||
		!bytes.Equal(bytes.TrimSpace(fields["id"]), []byte("1")) ||
		hasResult == hasError {
		return nil, false, fmt.Errorf("invalid Alchemy JSON-RPC response envelope")
	}
	if hasError {
		errorFields, err := decodeExactJSONObject(errorRaw, "code", "message", "data")
		if err != nil {
			return nil, false, err
		}
		var code *int
		var message *string
		if err := json.Unmarshal(errorFields["code"], &code); err != nil ||
			json.Unmarshal(errorFields["message"], &message) != nil ||
			code == nil || message == nil {
			return nil, false, fmt.Errorf("invalid Alchemy JSON-RPC error object")
		}
		return nil, true, nil
	}

	resultFields, err := decodeExactJSONObject(resultRaw, "transfers", "pageKey")
	if err != nil {
		return nil, false, err
	}
	if pageKeyRaw, ok := resultFields["pageKey"]; ok {
		var pageKey *string
		if err := json.Unmarshal(pageKeyRaw, &pageKey); err != nil ||
			pageKey == nil || len(*pageKey) > 512 {
			return nil, false, fmt.Errorf("invalid Alchemy page key")
		}
	}
	transfersRaw, ok := resultFields["transfers"]
	if !ok {
		return nil, false, fmt.Errorf("Alchemy result has no transfers")
	}
	var entries []json.RawMessage
	if err := json.Unmarshal(transfersRaw, &entries); err != nil || entries == nil {
		return nil, false, fmt.Errorf("Alchemy transfers is not an array")
	}
	transfers := make([]AlchemyTransfer, 0, len(entries))
	for _, entry := range entries {
		transfer, err := decodeAlchemyTransfer(entry)
		if err != nil {
			return nil, false, err
		}
		transfers = append(transfers, transfer)
	}
	return transfers, false, nil
}

func decodeAlchemyTransfer(raw json.RawMessage) (AlchemyTransfer, error) {
	fields, err := decodeExactJSONObject(
		raw,
		"blockNum",
		"uniqueId",
		"hash",
		"from",
		"to",
		"value",
		"erc721TokenId",
		"erc1155Metadata",
		"tokenId",
		"asset",
		"category",
		"rawContract",
		"metadata",
		"typeTraceAddress",
	)
	if err != nil {
		return AlchemyTransfer{}, err
	}
	for _, required := range []string{
		"blockNum", "uniqueId", "hash", "from", "to", "category", "rawContract",
	} {
		if _, ok := fields[required]; !ok {
			return AlchemyTransfer{}, fmt.Errorf("incomplete Alchemy transfer row")
		}
	}
	type transferWire struct {
		BlockNum *string `json:"blockNum"`
		UniqueID *string `json:"uniqueId"`
		Hash     *string `json:"hash"`
		From     *string `json:"from"`
		To       *string `json:"to"`
		Asset    *string `json:"asset"`
		Category *string `json:"category"`
	}
	var wire transferWire
	if err := json.Unmarshal(raw, &wire); err != nil ||
		wire.BlockNum == nil || wire.UniqueID == nil || wire.Hash == nil ||
		wire.From == nil || wire.Category == nil {
		return AlchemyTransfer{}, fmt.Errorf("incomplete Alchemy transfer row")
	}
	if !validAlchemyQuantity(*wire.BlockNum) || !validAlchemyEventID(*wire.UniqueID) ||
		!validAlchemyHash(*wire.Hash) || !validAlchemyAddress(*wire.From) {
		return AlchemyTransfer{}, fmt.Errorf("invalid Alchemy transfer identity")
	}
	if !validOptionalJSONNumber(fields["value"]) ||
		!missingOrJSONNull(fields["erc721TokenId"]) ||
		!missingOrJSONNull(fields["erc1155Metadata"]) ||
		!missingOrJSONNull(fields["tokenId"]) ||
		!validOptionalJSONString(fields["typeTraceAddress"]) {
		return AlchemyTransfer{}, fmt.Errorf("invalid Alchemy transfer field type")
	}
	to := ""
	if wire.To != nil {
		if !validAlchemyAddress(*wire.To) {
			return AlchemyTransfer{}, fmt.Errorf("invalid Alchemy recipient")
		}
		to = *wire.To
	}
	switch *wire.Category {
	case "external", "internal", "erc20":
	default:
		return AlchemyTransfer{}, fmt.Errorf("invalid Alchemy transfer category")
	}

	rawFields, err := decodeExactJSONObject(fields["rawContract"], "value", "address", "decimal")
	if err != nil {
		return AlchemyTransfer{}, err
	}
	for _, required := range []string{"value", "address", "decimal"} {
		if _, ok := rawFields[required]; !ok {
			return AlchemyTransfer{}, fmt.Errorf("incomplete Alchemy raw contract")
		}
	}
	var rawWire struct {
		Value   *string `json:"value"`
		Address *string `json:"address"`
		Decimal *string `json:"decimal"`
	}
	if err := json.Unmarshal(fields["rawContract"], &rawWire); err != nil ||
		rawWire.Value == nil || rawWire.Decimal == nil ||
		!validAlchemyQuantity(*rawWire.Value) || !validAlchemyQuantity(*rawWire.Decimal) {
		return AlchemyTransfer{}, fmt.Errorf("invalid Alchemy raw contract")
	}
	rawAmount, amountOK := new(big.Int).SetString((*rawWire.Value)[2:], 16)
	rawDecimals, decimalsOK := new(big.Int).SetString((*rawWire.Decimal)[2:], 16)
	if !amountOK || rawAmount.Sign() <= 0 || !decimalsOK ||
		!rawDecimals.IsUint64() || rawDecimals.Uint64() > 255 {
		return AlchemyTransfer{}, fmt.Errorf("invalid Alchemy raw contract semantics")
	}
	contract := ""
	if *wire.Category == "erc20" {
		if rawWire.Address == nil || !validAlchemyAddress(*rawWire.Address) {
			return AlchemyTransfer{}, fmt.Errorf("invalid Alchemy token contract")
		}
		contract = *rawWire.Address
	} else if rawWire.Address != nil {
		return AlchemyTransfer{}, fmt.Errorf("unexpected Alchemy native contract")
	}

	blockTime := ""
	if metadataRaw, ok := fields["metadata"]; ok &&
		!bytes.Equal(bytes.TrimSpace(metadataRaw), []byte("null")) {
		metadataFields, err := decodeExactJSONObject(metadataRaw, "blockTimestamp")
		if err != nil {
			return AlchemyTransfer{}, err
		}
		var timestamp *string
		if err := json.Unmarshal(metadataFields["blockTimestamp"], &timestamp); err != nil ||
			timestamp == nil {
			return AlchemyTransfer{}, fmt.Errorf("invalid Alchemy transfer metadata")
		}
		if _, err := time.Parse(time.RFC3339Nano, *timestamp); err != nil {
			return AlchemyTransfer{}, fmt.Errorf("invalid Alchemy transfer timestamp")
		}
		blockTime = *timestamp
	}
	asset := ""
	if wire.Asset != nil {
		asset = *wire.Asset
	}
	return AlchemyTransfer{
		UniqueID:  *wire.UniqueID,
		BlockNum:  *wire.BlockNum,
		Hash:      *wire.Hash,
		From:      *wire.From,
		To:        to,
		Asset:     asset,
		Category:  *wire.Category,
		Raw:       AlchemyRawContract{Value: *rawWire.Value, Address: contract, Decimal: *rawWire.Decimal},
		BlockTime: blockTime,
	}, nil
}

func validAlchemyEventID(value string) bool {
	if len(value) == 0 || len(value) > 512 {
		return false
	}
	for _, r := range value {
		if r < 0x21 || r > 0x7e {
			return false
		}
	}
	return true
}

func validAlchemyHash(value string) bool {
	return len(value) == 66 && validHexBytes(value)
}

func validAlchemyAddress(value string) bool {
	return len(value) == 42 && validHexBytes(value)
}

func validAlchemyQuantity(value string) bool {
	if len(value) < 3 || len(value) > 66 || !strings.HasPrefix(value, "0x") {
		return false
	}
	for _, digit := range value[2:] {
		if !((digit >= '0' && digit <= '9') || (digit >= 'a' && digit <= 'f') ||
			(digit >= 'A' && digit <= 'F')) {
			return false
		}
	}
	return true
}

func validOptionalJSONNumber(raw json.RawMessage) bool {
	if len(raw) == 0 || bytes.Equal(bytes.TrimSpace(raw), []byte("null")) {
		return true
	}
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.UseNumber()
	var value any
	if decoder.Decode(&value) != nil {
		return false
	}
	_, ok := value.(json.Number)
	return ok
}

func validOptionalJSONString(raw json.RawMessage) bool {
	if len(raw) == 0 || bytes.Equal(bytes.TrimSpace(raw), []byte("null")) {
		return true
	}
	var value string
	return json.Unmarshal(raw, &value) == nil
}

func missingOrJSONNull(raw json.RawMessage) bool {
	return len(raw) == 0 || bytes.Equal(bytes.TrimSpace(raw), []byte("null"))
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
		return nil, &Unavailable{Upstream: "alchemy", Message: "could not encode upstream request"}
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
		return nil, safeRequestCreationFailure("alchemy")
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := a.client.Do(req)
	if err != nil {
		return nil, safeRequestFailure("alchemy", actx, err)
	}
	defer resp.Body.Close()
	data, err := readBoundedResponse(resp.Body, 8<<20)
	if err != nil {
		return nil, safeResponseReadFailure("alchemy")
	}
	if resp.StatusCode != http.StatusOK {
		return nil, &Unavailable{
			Upstream: "alchemy",
			Message:  fmt.Sprintf("Alchemy returned HTTP %d", resp.StatusCode),
		}
	}
	transfers, rejected, err := decodeAlchemyTransfers(data)
	if err != nil {
		return nil, &Unavailable{Upstream: "alchemy", Message: "malformed Alchemy response"}
	}
	if rejected {
		return nil, &Unavailable{
			Upstream: "alchemy",
			Message:  "Alchemy rejected history request",
		}
	}
	return transfers, nil
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
		return nil, &Unavailable{Upstream: "alchemy", Message: "could not encode upstream request"}
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
		return nil, safeRequestCreationFailure("alchemy")
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := a.client.Do(req)
	if err != nil {
		return nil, safeRequestFailure("alchemy", actx, err)
	}
	defer resp.Body.Close()
	data, err := readBoundedResponse(resp.Body, 8<<20)
	if err != nil {
		return nil, safeResponseReadFailure("alchemy")
	}
	if resp.StatusCode != http.StatusOK {
		return nil, &Unavailable{
			Upstream: "alchemy",
			Message:  fmt.Sprintf("Alchemy returned HTTP %d", resp.StatusCode),
		}
	}
	timestamps, rejected, err := decodeAlchemyBlockTimestamps(data, blocks)
	if err != nil {
		return nil, &Unavailable{
			Upstream: "alchemy",
			Message:  "malformed Alchemy batch response",
		}
	}
	if rejected {
		return nil, &Unavailable{
			Upstream: "alchemy",
			Message:  "Alchemy rejected block request",
		}
	}
	return timestamps, nil
}

func decodeAlchemyBlockTimestamps(
	data []byte,
	blocks []string,
) (map[string]string, bool, error) {
	var entries []json.RawMessage
	if err := json.Unmarshal(data, &entries); err != nil || entries == nil ||
		len(entries) != len(blocks) {
		return nil, false, fmt.Errorf("invalid Alchemy batch response")
	}

	timestamps := make(map[string]string, len(entries))
	seenIDs := make(map[int]struct{}, len(entries))
	for _, entry := range entries {
		fields, err := decodeExactJSONObject(entry, "jsonrpc", "id", "result", "error")
		if err != nil {
			return nil, false, err
		}
		var version string
		var id *int
		if err := json.Unmarshal(fields["jsonrpc"], &version); err != nil ||
			json.Unmarshal(fields["id"], &id) != nil || id == nil ||
			version != "2.0" || *id <= 0 || *id > len(blocks) {
			return nil, false, fmt.Errorf("invalid Alchemy batch envelope")
		}
		if _, duplicate := seenIDs[*id]; duplicate {
			return nil, false, fmt.Errorf("duplicate Alchemy batch id")
		}
		seenIDs[*id] = struct{}{}

		resultRaw, hasResult := fields["result"]
		errorRaw, hasError := fields["error"]
		if hasResult == hasError {
			return nil, false, fmt.Errorf("invalid Alchemy batch result")
		}
		if hasError {
			errorFields, err := decodeExactJSONObject(errorRaw, "code", "message", "data")
			if err != nil {
				return nil, false, err
			}
			var code *int
			var message *string
			if err := json.Unmarshal(errorFields["code"], &code); err != nil ||
				json.Unmarshal(errorFields["message"], &message) != nil ||
				code == nil || message == nil {
				return nil, false, fmt.Errorf("invalid Alchemy batch error")
			}
			return nil, true, nil
		}

		blockFields, err := decodeUniqueJSONObject(resultRaw)
		if err != nil {
			return nil, false, err
		}
		for key := range blockFields {
			if strings.EqualFold(key, "timestamp") && key != "timestamp" {
				return nil, false, fmt.Errorf("ambiguous Alchemy block timestamp")
			}
		}
		timestampRaw, ok := blockFields["timestamp"]
		if !ok {
			return nil, false, fmt.Errorf("Alchemy block timestamp is missing")
		}
		var timestamp *string
		if err := json.Unmarshal(timestampRaw, &timestamp); err != nil ||
			timestamp == nil || !validAlchemyQuantity(*timestamp) {
			return nil, false, fmt.Errorf("invalid Alchemy block timestamp")
		}
		seconds, ok := new(big.Int).SetString((*timestamp)[2:], 16)
		if !ok || !seconds.IsInt64() || seconds.Sign() < 0 {
			return nil, false, fmt.Errorf("invalid Alchemy block timestamp")
		}
		timestamps[blocks[*id-1]] = time.Unix(
			seconds.Int64(),
			0,
		).UTC().Format(time.RFC3339Nano)
	}
	if len(timestamps) != len(blocks) {
		return nil, false, fmt.Errorf("incomplete Alchemy batch response")
	}
	return timestamps, false, nil
}
