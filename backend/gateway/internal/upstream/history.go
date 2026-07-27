package upstream

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

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
	Hash      string `json:"hash"`
	From      string `json:"from"`
	To        string `json:"to"`
	Value     string `json:"value"`
	TimeStamp string `json:"timeStamp"`
	IsError   string `json:"isError"`
}

// EtherscanTokenTx is one ERC-20 transfer row from
// module=account&action=tokentx.
type EtherscanTokenTx struct {
	Hash            string `json:"hash"`
	LogIndex        string `json:"logIndex"`
	From            string `json:"from"`
	To              string `json:"to"`
	Value           string `json:"value"`
	TimeStamp       string `json:"timeStamp"`
	TokenDecimal    string `json:"tokenDecimal"`
	TokenSymbol     string `json:"tokenSymbol"`
	ContractAddress string `json:"contractAddress"`
	IsError         string `json:"isError"`
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
		return &Unavailable{Upstream: "etherscan", Message: err.Error()}
	}
	resp, err := e.client.Do(req)
	if err != nil {
		return &Unavailable{Upstream: "etherscan", Message: err.Error()}
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	if err != nil {
		return &Unavailable{Upstream: "etherscan", Message: err.Error()}
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
	if err := json.Unmarshal(out.Result, dest); err != nil {
		// status "0" + non-array result carries an error string
		// ("Max rate limit reached", "Invalid API Key", ...). "No transactions
		// found" still returns an empty array, which parses above.
		var msg string
		_ = json.Unmarshal(out.Result, &msg)
		if msg == "" {
			msg = out.Message
		}
		return &Unavailable{Upstream: "etherscan", Message: msg}
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
		return nil, &Unavailable{Upstream: "helius", Message: err.Error()}
	}

	actx, cancel := context.WithTimeout(ctx, h.timeout)
	defer cancel()
	req, err := http.NewRequestWithContext(actx, http.MethodPost, u, strings.NewReader(string(body)))
	if err != nil {
		return nil, &Unavailable{Upstream: "helius", Message: err.Error()}
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := h.client.Do(req)
	if err != nil {
		return nil, &Unavailable{Upstream: "helius", Message: err.Error()}
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	if err != nil {
		return nil, &Unavailable{Upstream: "helius", Message: err.Error()}
	}
	if resp.StatusCode != http.StatusOK {
		return nil, &Unavailable{Upstream: "helius", Message: fmt.Sprintf("Helius returned HTTP %d", resp.StatusCode)}
	}
	var out struct {
		Result struct {
			Data []HeliusTransfer `json:"data"`
		} `json:"result"`
		Error *struct {
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.Unmarshal(data, &out); err != nil {
		return nil, &Unavailable{Upstream: "helius", Message: "malformed Helius response"}
	}
	if out.Error != nil {
		return nil, &Unavailable{Upstream: "helius", Message: out.Error.Message}
	}
	return out.Result.Data, nil
}
