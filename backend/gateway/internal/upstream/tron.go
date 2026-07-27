package upstream

import (
	"bytes"
	"context"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"net/url"
	"strings"
	"time"
	"unicode"
)

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
	actx, cancel := context.WithTimeout(ctx, t.timeout)
	defer cancel()
	var rd io.Reader
	if body != nil {
		rd = bytes.NewReader(body)
	}
	req, err := http.NewRequestWithContext(actx, method, t.base+path, rd)
	if err != nil {
		return t.unavailable(err.Error())
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := t.client.Do(req)
	if err != nil {
		return t.unavailable(err.Error())
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	if err != nil {
		return t.unavailable(err.Error())
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return t.unavailable(fmt.Sprintf("TronGrid returned HTTP %d", resp.StatusCode))
	}
	if err := json.Unmarshal(data, out); err != nil {
		return t.unavailable("malformed TronGrid response")
	}
	return nil
}

// Account is the balance-relevant slice of GET /v1/accounts/{addr}.
type Account struct {
	Balance *big.Int          // native TRX in sun; zero when the account is unknown
	TRC20   map[string]string // contract address (base58, as returned) -> raw amount
}

// GetAccount fetches native and TRC-20 balances for addr.
func (t *Tron) GetAccount(ctx context.Context, addr string) (*Account, error) {
	var out struct {
		Data []struct {
			Balance json.Number         `json:"balance"`
			TRC20   []map[string]string `json:"trc20"`
		} `json:"data"`
	}
	if err := t.do(ctx, http.MethodGet, "/v1/accounts/"+url.PathEscape(addr), nil, &out); err != nil {
		return nil, err
	}
	acct := &Account{Balance: big.NewInt(0), TRC20: map[string]string{}}
	if len(out.Data) == 0 {
		return acct, nil // never-activated account: all balances zero
	}
	d := out.Data[0]
	if d.Balance != "" {
		if v, ok := new(big.Int).SetString(d.Balance.String(), 10); ok {
			acct.Balance = v
		}
	}
	for _, m := range d.TRC20 {
		for contract, amount := range m {
			acct.TRC20[contract] = amount
		}
	}
	return acct, nil
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
	var out struct {
		Data []struct {
			TransactionID  string `json:"transaction_id"`
			From           string `json:"from"`
			To             string `json:"to"`
			Value          string `json:"value"`
			BlockTimestamp int64  `json:"block_timestamp"`
			TokenInfo      *struct {
				Symbol   string `json:"symbol"`
				Decimals int    `json:"decimals"`
				Address  string `json:"address"`
			} `json:"token_info"`
		} `json:"data"`
	}
	path := fmt.Sprintf("/v1/accounts/%s/transactions/trc20?limit=%d&only_confirmed=true", url.PathEscape(addr), limit)
	if err := t.do(ctx, http.MethodGet, path, nil, &out); err != nil {
		return nil, err
	}
	transfers := make([]TRC20Transfer, 0, len(out.Data))
	for _, d := range out.Data {
		tr := TRC20Transfer{
			TransactionID:  d.TransactionID,
			From:           d.From,
			To:             d.To,
			Value:          d.Value,
			BlockTimestamp: d.BlockTimestamp,
		}
		if d.TokenInfo != nil {
			tr.Symbol = d.TokenInfo.Symbol
			tr.Decimals = d.TokenInfo.Decimals
			tr.Contract = d.TokenInfo.Address
		}
		transfers = append(transfers, tr)
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
	BlockTimestamp int64
	Success        bool
}

// NativeTransactions lists native transactions for addr, keeping only
// TransferContract entries.
func (t *Tron) NativeTransactions(ctx context.Context, addr string, limit int) ([]NativeTransfer, error) {
	var out struct {
		Data []struct {
			TxID           string `json:"txID"`
			BlockTimestamp int64  `json:"block_timestamp"`
			Ret            []struct {
				ContractRet string `json:"contractRet"`
			} `json:"ret"`
			RawData struct {
				Contract []struct {
					Type      string `json:"type"`
					Parameter struct {
						Value struct {
							Amount       json.Number `json:"amount"`
							OwnerAddress string      `json:"owner_address"`
							ToAddress    string      `json:"to_address"`
						} `json:"value"`
					} `json:"parameter"`
				} `json:"contract"`
			} `json:"raw_data"`
		} `json:"data"`
	}
	path := fmt.Sprintf("/v1/accounts/%s/transactions?limit=%d", url.PathEscape(addr), limit)
	if err := t.do(ctx, http.MethodGet, path, nil, &out); err != nil {
		return nil, err
	}
	var transfers []NativeTransfer
	for _, d := range out.Data {
		if len(d.RawData.Contract) == 0 || d.RawData.Contract[0].Type != "TransferContract" {
			continue
		}
		v := d.RawData.Contract[0].Parameter.Value
		success := true
		if len(d.Ret) > 0 && d.Ret[0].ContractRet != "" && d.Ret[0].ContractRet != "SUCCESS" {
			success = false
		}
		transfers = append(transfers, NativeTransfer{
			TxID:           d.TxID,
			Owner:          v.OwnerAddress,
			To:             v.ToAddress,
			Amount:         v.Amount.String(),
			BlockTimestamp: d.BlockTimestamp,
			Success:        success,
		})
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
