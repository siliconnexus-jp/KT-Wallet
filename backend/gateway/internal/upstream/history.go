package upstream

import (
	"bytes"
	"context"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// ExecutionStatus preserves the difference between an explicit terminal
// answer and a provider field that was absent or contradictory.
type ExecutionStatus uint8

const (
	ExecutionUnknown ExecutionStatus = iota
	ExecutionConfirmed
	ExecutionFailed
)

// EtherscanExecutionStatus combines the two status fields used across
// Etherscan-compatible providers. Missing or contradictory evidence remains
// unknown instead of inheriting Go's zero values as success.
func EtherscanExecutionStatus(isError, receiptStatus string) ExecutionStatus {
	confirmed, failed := false, false
	switch strings.TrimSpace(isError) {
	case "0":
		confirmed = true
	case "1":
		failed = true
	}
	switch strings.TrimSpace(receiptStatus) {
	case "1":
		confirmed = true
	case "0":
		failed = true
	}
	if confirmed == failed {
		return ExecutionUnknown
	}
	if confirmed {
		return ExecutionConfirmed
	}
	return ExecutionFailed
}

// Etherscan is a client for the Etherscan v2 multichain account API,
// used for eth/polygon transaction history when an API key is configured.
type Etherscan struct {
	base    string
	key     string
	client  *http.Client
	timeout time.Duration
}

// NewEtherscan builds a client; base defaults elsewhere to
// https://api.etherscan.io/v2/api.
func NewEtherscan(base, key string, client *http.Client, attemptTimeout time.Duration) *Etherscan {
	if client == nil {
		client = http.DefaultClient
	}
	if attemptTimeout <= 0 {
		attemptTimeout = 10 * time.Second
	}
	return &Etherscan{base: strings.TrimRight(base, "/"), key: key, client: client, timeout: attemptTimeout}
}

// EtherscanTx is one row of module=account&action=txlist.
type EtherscanTx struct {
	Hash          string `json:"hash"`
	From          string `json:"from"`
	To            string `json:"to"`
	Value         string `json:"value"`
	TimeStamp     string `json:"timeStamp"`
	IsError       string `json:"isError"`
	ReceiptStatus string `json:"txreceipt_status"`
}

// EtherscanTokenTx is one ERC-20 transfer row from
// module=account&action=tokentx.
type EtherscanTokenTx struct {
	Hash             string `json:"hash"`
	LogIndex         string `json:"logIndex"`
	From             string `json:"from"`
	To               string `json:"to"`
	Value            string `json:"value"`
	TimeStamp        string `json:"timeStamp"`
	TokenDecimal     string `json:"tokenDecimal"`
	TokenSymbol      string `json:"tokenSymbol"`
	ContractAddress  string `json:"contractAddress"`
	IsError          string `json:"isError"`
	ReceiptStatus    string `json:"txreceipt_status"`
	BlockNumber      string `json:"blockNumber"`
	BlockHash        string `json:"blockHash"`
	TransactionIndex string `json:"transactionIndex"`
	Confirmations    string `json:"confirmations"`
}

// EtherscanTokenExecutionStatus recognizes the canonical indexed-event shape
// documented by Etherscan/Blockscout. ERC-20 transfer rows are receipt logs, so
// a valid block location is positive success evidence even though tokentx does
// not expose the normal-transaction execution fields. Explicit provider fields
// take precedence and malformed or contradictory values remain unknown.
func EtherscanTokenExecutionStatus(t EtherscanTokenTx) ExecutionStatus {
	if strings.TrimSpace(t.IsError) != "" || strings.TrimSpace(t.ReceiptStatus) != "" {
		return EtherscanExecutionStatus(t.IsError, t.ReceiptStatus)
	}
	block, blockErr := strconv.ParseUint(strings.TrimSpace(t.BlockNumber), 10, 64)
	_, indexErr := strconv.ParseUint(strings.TrimSpace(t.TransactionIndex), 10, 64)
	_, confirmationsErr := strconv.ParseUint(strings.TrimSpace(t.Confirmations), 10, 64)
	hash := strings.TrimSpace(t.BlockHash)
	decoded, hashErr := hex.DecodeString(strings.TrimPrefix(hash, "0x"))
	if blockErr != nil || block == 0 || indexErr != nil || confirmationsErr != nil ||
		len(hash) != 66 || !strings.HasPrefix(hash, "0x") || hashErr != nil || len(decoded) != 32 {
		return ExecutionUnknown
	}
	return ExecutionConfirmed
}

// EtherscanInternalTx is one native-value movement emitted from an EVM call
// trace (`module=account&action=txlistinternal`). Contract-based faucets,
// multisigs, bridges, and airdrops can credit a wallet this way without
// producing a normal transaction whose `to` is the wallet.
type EtherscanInternalTx struct {
	Hash            string `json:"hash"`
	TraceID         string `json:"traceId"`
	From            string `json:"from"`
	To              string `json:"to"`
	Value           string `json:"value"`
	TimeStamp       string `json:"timeStamp"`
	IsError         string `json:"isError"`
	ReceiptStatus   string `json:"txreceipt_status"`
	TransactionHash string `json:"transactionHash"`
	Index           string `json:"index"`
}

// CanonicalHash and CanonicalTraceID normalize Etherscan's hash/traceId and
// Blockscout's transactionHash/index spellings.
func (t EtherscanInternalTx) CanonicalHash() string {
	if strings.TrimSpace(t.Hash) != "" {
		return t.Hash
	}
	return t.TransactionHash
}

func (t EtherscanInternalTx) CanonicalTraceID() string {
	if strings.TrimSpace(t.TraceID) != "" {
		return t.TraceID
	}
	return t.Index
}

// TxList fetches the newest `limit` normal transactions for address on the
// given chain id.
func (e *Etherscan) TxList(ctx context.Context, chainID int, address string, limit int) ([]EtherscanTx, error) {
	var txs []EtherscanTx
	if err := e.accountList(ctx, chainID, address, limit, "txlist", &txs); err != nil {
		return nil, err
	}
	return txs, nil
}

// TokenTxList fetches the newest ERC-20 transfers involving address.
func (e *Etherscan) TokenTxList(ctx context.Context, chainID int, address string, limit int) ([]EtherscanTokenTx, error) {
	var txs []EtherscanTokenTx
	if err := e.accountList(ctx, chainID, address, limit, "tokentx", &txs); err != nil {
		return nil, err
	}
	return txs, nil
}

// InternalTxList fetches native-value call-trace transfers involving address.
func (e *Etherscan) InternalTxList(ctx context.Context, chainID int, address string, limit int) ([]EtherscanInternalTx, error) {
	var txs []EtherscanInternalTx
	if err := e.accountList(ctx, chainID, address, limit, "txlistinternal", &txs); err != nil {
		return nil, err
	}
	return txs, nil
}

func (e *Etherscan) accountList(ctx context.Context, chainID int, address string, limit int, action string, dest any) error {
	q := url.Values{}
	q.Set("chainid", fmt.Sprintf("%d", chainID))
	q.Set("module", "account")
	q.Set("action", action)
	q.Set("address", address)
	q.Set("page", "1")
	q.Set("offset", fmt.Sprintf("%d", limit))
	q.Set("sort", "desc")
	q.Set("apikey", e.key)
	u := e.base + "?" + q.Encode()

	actx, cancel := context.WithTimeout(ctx, e.timeout)
	defer cancel()
	req, err := http.NewRequestWithContext(actx, http.MethodGet, u, nil)
	if err != nil {
		return safeRequestCreationFailure("etherscan")
	}
	resp, err := e.client.Do(req)
	if err != nil {
		return safeRequestFailure("etherscan", actx, err)
	}
	defer resp.Body.Close()
	data, err := readBoundedResponse(resp.Body, 8<<20)
	if err != nil {
		return safeResponseReadFailure("etherscan")
	}
	if resp.StatusCode != http.StatusOK {
		return &Unavailable{Upstream: "etherscan", Message: fmt.Sprintf("Etherscan returned HTTP %d", resp.StatusCode)}
	}
	var out struct {
		Status  string          `json:"status"`
		Message string          `json:"message"`
		Result  json.RawMessage `json:"result"`
	}
	if err := json.Unmarshal(data, &out); err != nil {
		return &Unavailable{Upstream: "etherscan", Message: "malformed Etherscan response"}
	}
	trimmedResult := bytes.TrimSpace(out.Result)
	if len(trimmedResult) == 0 || bytes.Equal(trimmedResult, []byte("null")) {
		return &Unavailable{Upstream: "etherscan", Message: "explorer returned no result"}
	}
	if err := json.Unmarshal(out.Result, dest); err != nil {
		// status "0" + non-array result carries an error string
		// ("Max rate limit reached", "Invalid API Key", ...). "No transactions
		// found" still returns an empty array, which parses above.
		return &Unavailable{Upstream: "etherscan", Message: "explorer rejected request"}
	}
	return nil
}

// Helius is a client for the Helius transfer-history RPC, used for Solana
// wallet transfer history when HELIUS_API_KEY is configured.
type Helius struct {
	base    string
	key     string
	client  *http.Client
	timeout time.Duration
}

// NewHelius builds a client; base defaults elsewhere to https://api.helius.xyz.
func NewHelius(base, key string, client *http.Client, attemptTimeout time.Duration) *Helius {
	if client == nil {
		client = http.DefaultClient
	}
	if attemptTimeout <= 0 {
		attemptTimeout = 10 * time.Second
	}
	return &Helius{base: strings.TrimRight(base, "/"), key: key, client: client, timeout: attemptTimeout}
}

// HeliusTransfer is one normalized row from getTransfersByAddress. Amount is
// raw integer units, so no floating-point conversion is involved.
type HeliusTransfer struct {
	Signature           string `json:"signature"`
	BlockTime           int64  `json:"blockTime"`
	Type                string `json:"type"`
	FromUserAccount     string `json:"fromUserAccount"`
	ToUserAccount       string `json:"toUserAccount"`
	Mint                string `json:"mint"`
	Amount              string `json:"amount"`
	Decimals            int    `json:"decimals"`
	ConfirmationStatus  string `json:"confirmationStatus"`
	TransactionIndex    int    `json:"transactionIdx"`
	InstructionIndex    int    `json:"instructionIdx"`
	InnerInstructionIdx *int   `json:"innerInstructionIdx"`
}

func decodeHeliusTransfers(data []byte) ([]HeliusTransfer, bool, error) {
	fields, err := decodeExactJSONObject(data, "jsonrpc", "id", "result", "error")
	if err != nil {
		return nil, false, err
	}
	var version, id string
	if err := json.Unmarshal(fields["jsonrpc"], &version); err != nil {
		return nil, false, err
	}
	if err := json.Unmarshal(fields["id"], &id); err != nil {
		return nil, false, err
	}
	resultRaw, hasResult := fields["result"]
	errorRaw, hasError := fields["error"]
	if version != "2.0" || id != "kt-wallet" || hasResult == hasError {
		return nil, false, fmt.Errorf("invalid Helius JSON-RPC response envelope")
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
			return nil, false, fmt.Errorf("invalid Helius JSON-RPC error object")
		}
		return nil, true, nil
	}

	resultFields, err := decodeExactJSONObject(resultRaw, "data", "paginationToken")
	if err != nil {
		return nil, false, err
	}
	if paginationRaw, ok := resultFields["paginationToken"]; ok {
		var paginationToken string
		if err := json.Unmarshal(paginationRaw, &paginationToken); err != nil ||
			paginationToken == "" || len(paginationToken) > 512 {
			return nil, false, fmt.Errorf("invalid Helius pagination token")
		}
	}
	dataRaw, ok := resultFields["data"]
	if !ok {
		return nil, false, fmt.Errorf("Helius result has no data")
	}
	var entries []json.RawMessage
	if err := json.Unmarshal(dataRaw, &entries); err != nil || entries == nil {
		return nil, false, fmt.Errorf("Helius result data is not an array")
	}
	transfers := make([]HeliusTransfer, 0, len(entries))
	for _, entry := range entries {
		transfer, err := decodeHeliusTransfer(entry)
		if err != nil {
			return nil, false, err
		}
		transfers = append(transfers, transfer)
	}
	return transfers, false, nil
}

func decodeHeliusTransfer(raw json.RawMessage) (HeliusTransfer, error) {
	fields, err := decodeExactJSONObject(
		raw,
		"signature",
		"slot",
		"blockTime",
		"type",
		"fromUserAccount",
		"toUserAccount",
		"fromTokenAccount",
		"toTokenAccount",
		"mint",
		"amount",
		"decimals",
		"uiAmount",
		"feeAmount",
		"feeUiAmount",
		"confirmationStatus",
		"transactionIdx",
		"instructionIdx",
		"innerInstructionIdx",
	)
	if err != nil {
		return HeliusTransfer{}, err
	}
	for _, required := range []string{
		"signature",
		"slot",
		"blockTime",
		"type",
		"fromUserAccount",
		"toUserAccount",
		"mint",
		"amount",
		"decimals",
		"uiAmount",
		"confirmationStatus",
		"transactionIdx",
		"instructionIdx",
		"innerInstructionIdx",
	} {
		if _, ok := fields[required]; !ok {
			return HeliusTransfer{}, fmt.Errorf("incomplete Helius transfer row")
		}
	}
	type transferWire struct {
		Signature           *string `json:"signature"`
		Slot                *uint64 `json:"slot"`
		BlockTime           *int64  `json:"blockTime"`
		Type                *string `json:"type"`
		FromUserAccount     *string `json:"fromUserAccount"`
		ToUserAccount       *string `json:"toUserAccount"`
		FromTokenAccount    *string `json:"fromTokenAccount"`
		ToTokenAccount      *string `json:"toTokenAccount"`
		Mint                *string `json:"mint"`
		Amount              *string `json:"amount"`
		Decimals            *int    `json:"decimals"`
		UIAmount            *string `json:"uiAmount"`
		FeeAmount           *string `json:"feeAmount"`
		FeeUIAmount         *string `json:"feeUiAmount"`
		ConfirmationStatus  *string `json:"confirmationStatus"`
		TransactionIndex    *int    `json:"transactionIdx"`
		InstructionIndex    *int    `json:"instructionIdx"`
		InnerInstructionIdx *int    `json:"innerInstructionIdx"`
	}
	var wire transferWire
	if err := json.Unmarshal(raw, &wire); err != nil ||
		wire.Signature == nil || wire.Slot == nil || wire.BlockTime == nil || wire.Type == nil ||
		(wire.FromUserAccount == nil && wire.ToUserAccount == nil) || wire.Mint == nil ||
		wire.Amount == nil || wire.Decimals == nil || wire.UIAmount == nil ||
		wire.ConfirmationStatus == nil ||
		wire.TransactionIndex == nil || wire.InstructionIndex == nil {
		return HeliusTransfer{}, fmt.Errorf("incomplete Helius transfer row")
	}
	if bytes.Equal(bytes.TrimSpace(fields["innerInstructionIdx"]), []byte("null")) {
		wire.InnerInstructionIdx = nil
	} else if wire.InnerInstructionIdx == nil {
		return HeliusTransfer{}, fmt.Errorf("invalid Helius inner instruction index")
	}
	if *wire.Signature == "" || *wire.Mint == "" || !validUnsignedProviderInteger(*wire.Amount) ||
		!validProviderDecimal(*wire.UIAmount) || *wire.Decimals < 0 || *wire.Decimals > 36 ||
		*wire.BlockTime < 0 ||
		*wire.TransactionIndex < 0 || *wire.InstructionIndex < 0 ||
		(wire.InnerInstructionIdx != nil && *wire.InnerInstructionIdx < 0) {
		return HeliusTransfer{}, fmt.Errorf("invalid Helius transfer value")
	}
	switch *wire.Type {
	case "transfer", "mint", "burn", "wrap", "unwrap", "changeOwner", "withdrawWithheldFee":
	default:
		return HeliusTransfer{}, fmt.Errorf("invalid Helius transfer type")
	}
	if (wire.FromUserAccount != nil && *wire.FromUserAccount == "") ||
		(wire.ToUserAccount != nil && *wire.ToUserAccount == "") {
		return HeliusTransfer{}, fmt.Errorf("invalid Helius owner account")
	}
	for key, value := range map[string]*string{
		"fromTokenAccount": wire.FromTokenAccount,
		"toTokenAccount":   wire.ToTokenAccount,
	} {
		if _, present := fields[key]; present && (value == nil || *value == "") {
			return HeliusTransfer{}, fmt.Errorf("invalid Helius token account")
		}
	}
	_, hasFeeAmount := fields["feeAmount"]
	_, hasFeeUIAmount := fields["feeUiAmount"]
	if hasFeeAmount != hasFeeUIAmount ||
		(hasFeeAmount && (wire.FeeAmount == nil || wire.FeeUIAmount == nil ||
			!validUnsignedProviderInteger(*wire.FeeAmount) ||
			!validProviderDecimal(*wire.FeeUIAmount))) {
		return HeliusTransfer{}, fmt.Errorf("invalid Helius transfer fee")
	}
	fromUserAccount, toUserAccount := "", ""
	if wire.FromUserAccount != nil {
		fromUserAccount = *wire.FromUserAccount
	}
	if wire.ToUserAccount != nil {
		toUserAccount = *wire.ToUserAccount
	}
	return HeliusTransfer{
		Signature:           *wire.Signature,
		BlockTime:           *wire.BlockTime,
		Type:                *wire.Type,
		FromUserAccount:     fromUserAccount,
		ToUserAccount:       toUserAccount,
		Mint:                *wire.Mint,
		Amount:              *wire.Amount,
		Decimals:            *wire.Decimals,
		ConfirmationStatus:  *wire.ConfirmationStatus,
		TransactionIndex:    *wire.TransactionIndex,
		InstructionIndex:    *wire.InstructionIndex,
		InnerInstructionIdx: wire.InnerInstructionIdx,
	}, nil
}

func validUnsignedProviderInteger(value string) bool {
	if len(value) == 0 || len(value) > 128 {
		return false
	}
	for _, digit := range value {
		if digit < '0' || digit > '9' {
			return false
		}
	}
	return true
}

// Transfers fetches normalized transfer rows for a wallet owner address using
// Helius' current getTransfersByAddress RPC.
func (h *Helius) Transfers(ctx context.Context, address string, limit int) ([]HeliusTransfer, error) {
	q := url.Values{}
	q.Set("api-key", h.key)
	u := h.base + "?" + q.Encode()
	body, err := json.Marshal(map[string]any{
		"jsonrpc": "2.0",
		"id":      "kt-wallet",
		"method":  "getTransfersByAddress",
		"params": []any{
			address,
			map[string]any{
				"limit":      limit,
				"sortOrder":  "desc",
				"commitment": "finalized",
				"solMode":    "merged",
			},
		},
	})
	if err != nil {
		return nil, &Unavailable{Upstream: "helius", Message: "could not encode upstream request"}
	}

	actx, cancel := context.WithTimeout(ctx, h.timeout)
	defer cancel()
	req, err := http.NewRequestWithContext(actx, http.MethodPost, u, strings.NewReader(string(body)))
	if err != nil {
		return nil, safeRequestCreationFailure("helius")
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := h.client.Do(req)
	if err != nil {
		return nil, safeRequestFailure("helius", actx, err)
	}
	defer resp.Body.Close()
	data, err := readBoundedResponse(resp.Body, 8<<20)
	if err != nil {
		return nil, safeResponseReadFailure("helius")
	}
	if resp.StatusCode != http.StatusOK {
		return nil, &Unavailable{Upstream: "helius", Message: fmt.Sprintf("Helius returned HTTP %d", resp.StatusCode)}
	}
	transfers, rejected, err := decodeHeliusTransfers(data)
	if err != nil {
		return nil, &Unavailable{Upstream: "helius", Message: "malformed Helius response"}
	}
	if rejected {
		return nil, &Unavailable{Upstream: "helius", Message: "history provider rejected request"}
	}
	return transfers, nil
}
