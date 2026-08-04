package upstream

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"time"
	"unicode"
)

var tronTransactionIDPattern = regexp.MustCompile(`^[0-9a-fA-F]{64}$`)
var tronHexAddressPattern = regexp.MustCompile(`^41[0-9a-fA-F]{40}$`)
var tronUnsignedDecimalPattern = regexp.MustCompile(`^(0|[1-9][0-9]*)$`)

const (
	tronBase58Alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
	maxTronAccountRows = 1
	maxTronTRC20Rows   = 5000
)

var (
	maxTronNativeBalance = new(big.Int).SetUint64(^uint64(0) >> 1)
	maxTronTokenBalance  = new(big.Int).Sub(new(big.Int).Lsh(big.NewInt(1), 256), big.NewInt(1))
)

var tronReceiptResults = map[string]struct{}{
	"SUCCESS": {}, "REVERT": {},
	"BAD_JUMP_DESTINATION": {}, "OUT_OF_MEMORY": {},
	"PRECOMPILED_CONTRACT": {}, "STACK_TOO_SMALL": {},
	"STACK_TOO_LARGE": {}, "ILLEGAL_OPERATION": {},
	"STACK_OVERFLOW": {}, "OUT_OF_ENERGY": {}, "OUT_OF_TIME": {},
	"JVM_STACK_OVER_FLOW": {}, "TRANSFER_FAILED": {},
	"INVALID_CODE": {},
}

// Tron is a TronGrid REST client.
type Tron struct {
	base    string
	client  *http.Client
	timeout time.Duration
}

// NewTron builds a Tron client for the given TronGrid base URL.
func NewTron(base string, client *http.Client, attemptTimeout time.Duration) *Tron {
	if client == nil {
		client = http.DefaultClient
	}
	if attemptTimeout <= 0 {
		attemptTimeout = 10 * time.Second
	}
	return &Tron{base: strings.TrimRight(base, "/"), client: client, timeout: attemptTimeout}
}

func (t *Tron) unavailable(msg string) *Unavailable {
	return &Unavailable{Upstream: hostOf(t.base), Message: msg}
}

func (t *Tron) do(ctx context.Context, method, path string, body []byte, out any) error {
	data, err := t.fetch(ctx, method, path, body)
	if err != nil {
		return err
	}
	if err := json.Unmarshal(data, out); err != nil {
		return t.unavailable("malformed TronGrid response")
	}
	return nil
}

func (t *Tron) fetch(ctx context.Context, method, path string, body []byte) ([]byte, error) {
	actx, cancel := context.WithTimeout(ctx, t.timeout)
	defer cancel()
	var rd io.Reader
	if body != nil {
		rd = bytes.NewReader(body)
	}
	req, err := http.NewRequestWithContext(actx, method, t.base+path, rd)
	if err != nil {
		return nil, safeRequestCreationFailure(hostOf(t.base))
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := t.client.Do(req)
	if err != nil {
		return nil, safeRequestFailure(hostOf(t.base), actx, err)
	}
	defer resp.Body.Close()
	data, err := readBoundedResponse(resp.Body, 8<<20)
	if err != nil {
		return nil, safeResponseReadFailure(hostOf(t.base))
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, t.unavailable(fmt.Sprintf("TronGrid returned HTTP %d", resp.StatusCode))
	}
	return data, nil
}

// Account is the balance-relevant slice of GET /v1/accounts/{addr}.
type Account struct {
	Balance *big.Int          // native TRX in sun; zero when the account is unknown
	TRC20   map[string]string // contract address (base58, as returned) -> raw amount
}

// GetAccount fetches native and TRC-20 balances for addr.
func (t *Tron) GetAccount(ctx context.Context, addr string) (*Account, error) {
	data, err := t.fetch(ctx, http.MethodGet, "/v1/accounts/"+url.PathEscape(addr), nil)
	if err != nil {
		return nil, err
	}
	acct, err := decodeTronAccount(data, addr)
	if err != nil {
		return nil, t.unavailable("malformed or unbound TronGrid account response")
	}
	return acct, nil
}

// decodeTronAccount treats an account balance as financial data rather than a
// best-effort display hint. TronGrid's account object is intentionally
// extensible, but the envelope and every field consumed by KT Wallet are
// unambiguous, type checked and bound to the requested address. In particular,
// an invalid balance must never silently become zero.
func decodeTronAccount(data []byte, requestedAddress string) (*Account, error) {
	requestedHex, ok := tronBase58AddressHex(requestedAddress)
	if !ok {
		return nil, errors.New("invalid requested TRON address")
	}
	envelope, err := decodeExactJSONObject(data, "data", "success", "meta")
	if err != nil {
		return nil, err
	}
	dataRaw, hasData := envelope["data"]
	successRaw, hasSuccess := envelope["success"]
	if !hasData || !hasSuccess || !bytes.Equal(bytes.TrimSpace(successRaw), []byte("true")) {
		return nil, errors.New("incomplete TronGrid account envelope")
	}
	rows, err := decodeRawJSONArray(dataRaw, maxTronAccountRows)
	if err != nil {
		return nil, err
	}
	acct := &Account{Balance: big.NewInt(0), TRC20: map[string]string{}}
	if len(rows) == 0 {
		return acct, nil // never-activated account: all balances zero
	}
	fields, err := decodeUniqueJSONObject(rows[0])
	if err != nil {
		return nil, err
	}
	for key := range fields {
		for _, consumed := range []string{"address", "balance", "trc20"} {
			if strings.EqualFold(key, consumed) && key != consumed {
				return nil, fmt.Errorf("ambiguous TronGrid account member %q", key)
			}
		}
	}
	addressRaw, exists := fields["address"]
	if !exists {
		return nil, errors.New("missing TronGrid account identity")
	}
	var returnedHex string
	if err := json.Unmarshal(addressRaw, &returnedHex); err != nil ||
		!tronHexAddressPattern.MatchString(returnedHex) ||
		!strings.EqualFold(returnedHex, requestedHex) {
		return nil, errors.New("TronGrid account identity mismatch")
	}
	if balanceRaw, exists := fields["balance"]; exists {
		balance, err := parseTronUnsignedInteger(balanceRaw, maxTronNativeBalance, false)
		if err != nil {
			return nil, err
		}
		acct.Balance = balance
	}
	if trc20Raw, exists := fields["trc20"]; exists {
		tokens, err := decodeRawJSONArray(trc20Raw, maxTronTRC20Rows)
		if err != nil {
			return nil, err
		}
		seen := make(map[string]struct{}, len(tokens))
		for _, tokenRaw := range tokens {
			token, err := decodeUniqueJSONObject(tokenRaw)
			if err != nil || len(token) != 1 {
				return nil, errors.New("invalid TronGrid TRC-20 balance row")
			}
			for contract, amountRaw := range token {
				contractHex, valid := tronBase58AddressHex(contract)
				if !valid {
					return nil, errors.New("invalid TronGrid TRC-20 identity")
				}
				if _, duplicate := seen[contractHex]; duplicate {
					return nil, errors.New("duplicate TronGrid TRC-20 identity")
				}
				seen[contractHex] = struct{}{}
				amount, err := parseTronUnsignedInteger(amountRaw, maxTronTokenBalance, true)
				if err != nil {
					return nil, err
				}
				acct.TRC20[contract] = amount.String()
			}
		}
	}
	return acct, nil
}

func parseTronUnsignedInteger(raw []byte, maximum *big.Int, quoted bool) (*big.Int, error) {
	value := strings.TrimSpace(string(raw))
	if quoted {
		var decoded string
		if err := json.Unmarshal(raw, &decoded); err != nil {
			return nil, errors.New("invalid TronGrid decimal integer")
		}
		value = decoded
	}
	if !tronUnsignedDecimalPattern.MatchString(value) {
		return nil, errors.New("invalid TronGrid decimal integer")
	}
	parsed, ok := new(big.Int).SetString(value, 10)
	if !ok || parsed.Cmp(maximum) > 0 {
		return nil, errors.New("out-of-range TronGrid decimal integer")
	}
	return parsed, nil
}

// tronBase58AddressHex verifies TRON's Base58Check checksum and returns the
// canonical 21-byte 41-prefixed payload as lowercase hex.
func tronBase58AddressHex(address string) (string, bool) {
	if len(address) != 34 || !strings.HasPrefix(address, "T") {
		return "", false
	}
	n := new(big.Int)
	base := big.NewInt(58)
	for i := 0; i < len(address); i++ {
		index := strings.IndexByte(tronBase58Alphabet, address[i])
		if index < 0 {
			return "", false
		}
		n.Mul(n, base)
		n.Add(n, big.NewInt(int64(index)))
	}
	decoded := n.Bytes()
	leadingZeroes := 0
	for leadingZeroes < len(address) && address[leadingZeroes] == '1' {
		leadingZeroes++
	}
	if leadingZeroes > 0 {
		decoded = append(make([]byte, leadingZeroes), decoded...)
	}
	if len(decoded) != 25 || decoded[0] != 0x41 {
		return "", false
	}
	first := sha256.Sum256(decoded[:21])
	second := sha256.Sum256(first[:])
	if !bytes.Equal(decoded[21:], second[:4]) {
		return "", false
	}
	return hex.EncodeToString(decoded[:21]), true
}

// GenesisBlockID returns block zero's canonical id for network binding.
func (t *Tron) GenesisBlockID(ctx context.Context) (string, error) {
	body, err := json.Marshal(map[string]int{"num": 0})
	if err != nil {
		return "", err
	}
	var out struct {
		BlockID     string `json:"blockID"`
		BlockHeader struct {
			RawData struct {
				Number int64 `json:"number"`
			} `json:"raw_data"`
		} `json:"block_header"`
	}
	if err := t.do(ctx, http.MethodPost, "/wallet/getblockbynum", body, &out); err != nil {
		return "", err
	}
	decoded, decodeErr := hex.DecodeString(out.BlockID)
	if decodeErr != nil || len(decoded) != 32 || out.BlockHeader.RawData.Number != 0 {
		return "", t.unavailable("malformed genesis block")
	}
	return strings.ToLower(out.BlockID), nil
}

// TransactionStatus queries the full-node receipt directly. TronGrid returns
// an empty object while a tx is unknown/pending, and a receipt once included.
// The returned status is one of "confirmed", "failed", "pending", "unknown".
func (t *Tron) TransactionStatus(ctx context.Context, txID string) (string, error) {
	body, err := json.Marshal(map[string]string{"value": txID})
	if err != nil {
		return "", err
	}
	var out struct {
		ID          string `json:"id"`
		BlockNumber *int64 `json:"blockNumber"`
		Receipt     struct {
			Result string `json:"result"`
		} `json:"receipt"`
		Result string `json:"result"`
	}
	if err := t.do(ctx, http.MethodPost, "/wallet/gettransactioninfobyid", body, &out); err != nil {
		return "", err
	}
	if out.ID == "" && out.BlockNumber == nil && out.Receipt.Result == "" && out.Result == "" {
		return "unknown", nil
	}
	if !tronTransactionIDPattern.MatchString(txID) ||
		!tronTransactionIDPattern.MatchString(out.ID) ||
		!strings.EqualFold(out.ID, txID) ||
		out.BlockNumber == nil || *out.BlockNumber < 0 {
		return "", t.unavailable("malformed transaction receipt")
	}
	result := strings.ToUpper(out.Receipt.Result)
	if result == "" && out.Result != "" {
		if !strings.EqualFold(out.Result, "FAILED") {
			return "", t.unavailable("unknown transaction result")
		}
		result = "FAILED"
	}
	if result == "" {
		result, err = t.transactionContractResult(ctx, txID, body)
		if err != nil {
			return "", err
		}
	}
	if result == "FAILED" {
		return "failed", nil
	}
	if _, known := tronReceiptResults[result]; !known {
		return "", t.unavailable("unknown transaction receipt result")
	}
	switch result {
	case "SUCCESS":
		return "confirmed", nil
	default:
		return "failed", nil
	}
}

func (t *Tron) transactionContractResult(ctx context.Context, txID string, body []byte) (string, error) {
	var out struct {
		TxID string `json:"txID"`
		Ret  []struct {
			ContractRet string `json:"contractRet"`
		} `json:"ret"`
	}
	if err := t.do(ctx, http.MethodPost, "/wallet/gettransactionbyid", body, &out); err != nil {
		return "", err
	}
	if !tronTransactionIDPattern.MatchString(out.TxID) ||
		!strings.EqualFold(out.TxID, txID) || len(out.Ret) == 0 {
		return "", t.unavailable("malformed transaction result")
	}
	result := "SUCCESS"
	for _, row := range out.Ret {
		normalized := strings.ToUpper(row.ContractRet)
		if _, known := tronReceiptResults[normalized]; !known {
			return "", t.unavailable("unknown transaction contract result")
		}
		if normalized != "SUCCESS" {
			result = normalized
		}
	}
	return result, nil
}

// TRC20Transfer is one row of GET /v1/accounts/{addr}/transactions/trc20.
type TRC20Transfer struct {
	TransactionID  string
	From, To       string // base58
	Value          string
	BlockTimestamp int64
	Symbol         string
	Decimals       int
	Contract       string
}

// TRC20Transfers lists confirmed TRC-20 transfers touching addr, newest first.
func (t *Tron) TRC20Transfers(ctx context.Context, addr string, limit int) ([]TRC20Transfer, error) {
	path := fmt.Sprintf(
		"/v1/accounts/%s/transactions/trc20?limit=%d&only_confirmed=true&order_by=block_timestamp,desc",
		url.PathEscape(addr), limit,
	)
	data, err := t.fetch(ctx, http.MethodGet, path, nil)
	if err != nil {
		return nil, err
	}
	transfers, err := decodeTronTRC20History(data)
	if err != nil {
		return nil, t.unavailable("malformed TronGrid TRC-20 history response")
	}
	return transfers, nil
}

// NativeTransfer is a TransferContract extracted from
// GET /v1/accounts/{addr}/transactions. Non-transfer contract types are
// skipped by the caller-facing API.
type NativeTransfer struct {
	TxID           string
	Owner, To      string // hex (41-prefixed)
	Amount         string
	TokenID        string // non-empty for TransferAssetContract (TRC-10)
	ContractIndex  int    // index in raw_data.contract; part of event identity
	BlockTimestamp int64
	Status         ExecutionStatus
}

// NativeTransactions lists protocol-level value transfers for addr:
// TransferContract (TRX) and TransferAssetContract (TRC-10).
func (t *Tron) NativeTransactions(ctx context.Context, addr string, limit int) ([]NativeTransfer, error) {
	path := fmt.Sprintf(
		"/v1/accounts/%s/transactions?limit=%d&only_confirmed=true&order_by=block_timestamp,desc",
		url.PathEscape(addr),
		limit,
	)
	data, err := t.fetch(ctx, http.MethodGet, path, nil)
	if err != nil {
		return nil, err
	}
	transfers, err := decodeTronNativeHistory(data)
	if err != nil {
		return nil, t.unavailable("malformed TronGrid native history response")
	}
	return transfers, nil
}

// InternalTransfer is a TRX/TRC-10 value movement created while a smart
// contract executes. TronGrid normalizes the parent transaction id and the
// internal trace id separately.
type InternalTransfer struct {
	TxID, InternalTxID string
	From, To           string // hex (41-prefixed)
	Amount             string
	TokenID            string // empty means TRX
	AssetIndex         int    // stable identity when one trace moves two assets
	BlockTimestamp     int64
	Status             ExecutionStatus
}

// InternalTransactions lists contract-created value movements touching addr.
func (t *Tron) InternalTransactions(ctx context.Context, addr string, limit int) ([]InternalTransfer, error) {
	path := fmt.Sprintf(
		"/v1/accounts/%s/internal-transactions?limit=%d&only_confirmed=true&order_by=block_timestamp,desc",
		url.PathEscape(addr),
		limit,
	)
	data, err := t.fetch(ctx, http.MethodGet, path, nil)
	if err != nil {
		return nil, err
	}
	transfers, err := decodeTronInternalHistory(data)
	if err != nil {
		return nil, t.unavailable("malformed TronGrid internal history response")
	}
	return transfers, nil
}

// Broadcast POSTs a signed transaction and returns the txid. The endpoint
// follows from the payload shape, matching the mobile client:
//
//   - {"transaction": "<hex>"} — the full signed Transaction protobuf the
//     wallet-core signers emit, which only /wallet/broadcasthex accepts. Only
//     that one key is forwarded; TronGrid rejects unknown fields.
//   - anything else — a complete TronGrid transaction JSON, forwarded verbatim
//     to /wallet/broadcasttransaction. That endpoint dereferences `raw_data`
//     unconditionally and answers a bare NullPointerException without it.
//
// A node-side rejection comes back as *NodeError carrying the node's
// (hex-decoded when possible) message.
func (t *Tron) Broadcast(ctx context.Context, payload []byte) (string, error) {
	path := "/wallet/broadcasttransaction"
	var shape struct {
		Transaction string `json:"transaction"`
	}
	if err := json.Unmarshal(payload, &shape); err == nil && shape.Transaction != "" {
		path = "/wallet/broadcasthex"
		body, err := json.Marshal(map[string]string{"transaction": shape.Transaction})
		if err != nil {
			return "", err
		}
		payload = body
	}

	var out struct {
		Result  bool   `json:"result"`
		TxID    string `json:"txid"`
		Code    string `json:"code"`
		Message string `json:"message"`
		// Node-level failures (an unparsable body, most often) arrive as a
		// top-level `Error` with no `code`/`message` at all; without this the
		// reason was reported as an empty string.
		Error string `json:"Error"`
	}
	if err := t.do(ctx, http.MethodPost, path, payload, &out); err != nil {
		return "", err
	}
	if !out.Result {
		msg := decodeTronMessage(out.Message)
		if msg == "" {
			msg = out.Error
		}
		if msg == "" {
			msg = out.Code
		}
		if msg == "" {
			msg = "broadcast rejected"
		}
		if out.Code != "" && msg != out.Code {
			msg = out.Code + ": " + msg
		}
		return "", &NodeError{Code: -1, Message: msg}
	}
	return out.TxID, nil
}

// decodeTronMessage turns TronGrid's hex-encoded error message into readable
// text; anything undecodable is returned as-is.
func decodeTronMessage(msg string) string {
	if msg == "" {
		return ""
	}
	if b, err := hex.DecodeString(msg); err == nil {
		printable := true
		for _, r := range string(b) {
			if r == unicode.ReplacementChar || (!unicode.IsPrint(r) && !unicode.IsSpace(r)) {
				printable = false
				break
			}
		}
		if printable {
			return string(b)
		}
	}
	return msg
}
