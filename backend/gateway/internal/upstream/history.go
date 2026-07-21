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

// TxList fetches the newest `limit` normal transactions for address on the
// given chain id.
func (e *Etherscan) TxList(ctx context.Context, chainID int, address string, limit int) ([]EtherscanTx, error) {
	q := url.Values{}
	q.Set("chainid", fmt.Sprintf("%d", chainID))
	q.Set("module", "account")
	q.Set("action", "txlist")
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
		return nil, &Unavailable{Upstream: "etherscan", Message: err.Error()}
	}
	resp, err := e.client.Do(req)
	if err != nil {
		return nil, &Unavailable{Upstream: "etherscan", Message: err.Error()}
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	if err != nil {
		return nil, &Unavailable{Upstream: "etherscan", Message: err.Error()}
	}
	if resp.StatusCode != http.StatusOK {
		return nil, &Unavailable{Upstream: "etherscan", Message: fmt.Sprintf("Etherscan returned HTTP %d", resp.StatusCode)}
	}
	var out struct {
		Status  string          `json:"status"`
		Message string          `json:"message"`
		Result  json.RawMessage `json:"result"`
	}
	if err := json.Unmarshal(data, &out); err != nil {
		return nil, &Unavailable{Upstream: "etherscan", Message: "malformed Etherscan response"}
	}
	var txs []EtherscanTx
	if err := json.Unmarshal(out.Result, &txs); err != nil {
		// status "0" + non-array result carries an error string
		// ("Max rate limit reached", "Invalid API Key", ...). "No transactions
		// found" still returns an empty array, which parses above.
		var msg string
		_ = json.Unmarshal(out.Result, &msg)
		if msg == "" {
			msg = out.Message
		}
		return nil, &Unavailable{Upstream: "etherscan", Message: msg}
	}
	return txs, nil
}

// Helius is a client for the Helius parsed-transaction-history API, used for
// Solana history when HELIUS_API_KEY is configured.
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

// HeliusNativeTransfer is one native SOL movement inside a parsed transaction.
type HeliusNativeTransfer struct {
	FromUserAccount string      `json:"fromUserAccount"`
	ToUserAccount   string      `json:"toUserAccount"`
	Amount          json.Number `json:"amount"`
}

// HeliusTx is the subset of a Helius parsed transaction the gateway needs.
type HeliusTx struct {
	Signature        string                 `json:"signature"`
	Timestamp        int64                  `json:"timestamp"`
	TransactionError any                    `json:"transactionError"`
	NativeTransfers  []HeliusNativeTransfer `json:"nativeTransfers"`
}

// Transactions fetches the newest parsed transactions for address.
func (h *Helius) Transactions(ctx context.Context, address string, limit int) ([]HeliusTx, error) {
	q := url.Values{}
	q.Set("api-key", h.key)
	q.Set("limit", fmt.Sprintf("%d", limit))
	u := fmt.Sprintf("%s/v0/addresses/%s/transactions?%s", h.base, url.PathEscape(address), q.Encode())

	actx, cancel := context.WithTimeout(ctx, h.timeout)
	defer cancel()
	req, err := http.NewRequestWithContext(actx, http.MethodGet, u, nil)
	if err != nil {
		return nil, &Unavailable{Upstream: "helius", Message: err.Error()}
	}
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
	var txs []HeliusTx
	if err := json.Unmarshal(data, &txs); err != nil {
		return nil, &Unavailable{Upstream: "helius", Message: "malformed Helius response"}
	}
	return txs, nil
}
