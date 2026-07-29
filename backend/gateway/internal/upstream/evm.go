package upstream

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"math/big"
	"net/http"
	"strings"
	"time"

	"ktwallet/gateway/internal/clock"
)

// balanceOfSelector is the 4-byte selector of ERC-20 balanceOf(address).
const balanceOfSelector = "0x70a08231"

// EVM is a JSON-RPC client for an EVM chain, backed by a failover Pool.
type EVM struct {
	pool *Pool
}

// NewEVM builds an EVM client named after its network ("eth-mainnet",
// "polygon-amoy", ...).
func NewEVM(name string, urls []string, clk clock.Clock, client *http.Client, attemptTimeout time.Duration) *EVM {
	return &EVM{pool: NewPool(name, urls, clk, client, attemptTimeout)}
}

// NewEVMRoundRobin balances calls across the leading primaryCount endpoints,
// then uses any remaining endpoints as ordered fallbacks.
func NewEVMRoundRobin(
	name string,
	urls []string,
	primaryCount int,
	clk clock.Clock,
	client *http.Client,
	attemptTimeout time.Duration,
) *EVM {
	return &EVM{
		pool: NewPoolRoundRobinPrefix(
			name,
			urls,
			primaryCount,
			clk,
			client,
			attemptTimeout,
		),
	}
}

func (e *EVM) call(ctx context.Context, method string, params ...any) (json.RawMessage, error) {
	return e.pool.Call(ctx, method, params)
}

func (e *EVM) quantity(ctx context.Context, method string, params ...any) (*big.Int, error) {
	raw, err := e.call(ctx, method, params...)
	if err != nil {
		return nil, err
	}
	return parseQuantity(raw)
}

// GetBalance returns the native balance in wei.
func (e *EVM) GetBalance(ctx context.Context, address string) (*big.Int, error) {
	return e.quantity(ctx, "eth_getBalance", address, "latest")
}

// TokenBalance calls balanceOf(holder) on an ERC-20 contract.
func (e *EVM) TokenBalance(ctx context.Context, contract, holder string) (*big.Int, error) {
	data := balanceOfSelector + strings.Repeat("0", 24) + strings.ToLower(strings.TrimPrefix(holder, "0x"))
	return e.quantity(ctx, "eth_call", map[string]string{"to": contract, "data": data}, "latest")
}

// TransactionCount returns the pending nonce for address.
func (e *EVM) TransactionCount(ctx context.Context, address string) (*big.Int, error) {
	return e.quantity(ctx, "eth_getTransactionCount", address, "pending")
}

// TransactionStatus reads the node's transaction receipt directly. This is
// intentionally independent of explorer/indexer history: an explorer may lag
// behind the chain even after the recipient balance has changed.
//
// The returned status is one of "confirmed", "failed", "pending", "unknown".
func (e *EVM) TransactionStatus(ctx context.Context, hash string) (string, error) {
	raw, err := e.call(ctx, "eth_getTransactionReceipt", hash)
	if err != nil {
		return "", err
	}
	if !bytes.Equal(bytes.TrimSpace(raw), []byte("null")) {
		var receipt struct {
			Status string `json:"status"`
		}
		if err := json.Unmarshal(raw, &receipt); err != nil {
			return "", &Unavailable{Upstream: e.pool.name, Message: "malformed transaction receipt"}
		}
		switch strings.ToLower(receipt.Status) {
		case "0x1":
			return "confirmed", nil
		case "0x0":
			return "failed", nil
		default:
			return "", &Unavailable{Upstream: e.pool.name, Message: "transaction receipt has no valid status"}
		}
	}

	// A known transaction without a receipt is still in the mempool. If the
	// current node does not know it, keep the state "unknown" rather than
	// falsely marking it dropped: another RPC may have accepted it.
	raw, err = e.call(ctx, "eth_getTransactionByHash", hash)
	if err != nil {
		return "", err
	}
	if bytes.Equal(bytes.TrimSpace(raw), []byte("null")) {
		return "unknown", nil
	}
	return "pending", nil
}

// GasPrice returns eth_gasPrice in wei.
func (e *EVM) GasPrice(ctx context.Context) (*big.Int, error) {
	return e.quantity(ctx, "eth_gasPrice")
}

// FeeHistoryResult is the subset of eth_feeHistory the gateway consumes.
type FeeHistoryResult struct {
	BaseFeePerGas []*big.Int
	Reward        [][]*big.Int
}

// FeeHistory fetches fee history for blockCount blocks at the given reward
// percentiles.
func (e *EVM) FeeHistory(ctx context.Context, blockCount int, percentiles []float64) (*FeeHistoryResult, error) {
	raw, err := e.call(ctx, "eth_feeHistory", fmt.Sprintf("0x%x", blockCount), "latest", percentiles)
	if err != nil {
		return nil, err
	}
	var out struct {
		BaseFeePerGas []string   `json:"baseFeePerGas"`
		Reward        [][]string `json:"reward"`
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return nil, &Unavailable{Upstream: e.pool.name, Message: "malformed eth_feeHistory result"}
	}
	res := &FeeHistoryResult{}
	for _, h := range out.BaseFeePerGas {
		v, err := hexToBig(h)
		if err != nil {
			return nil, &Unavailable{Upstream: e.pool.name, Message: "malformed baseFeePerGas: " + h}
		}
		res.BaseFeePerGas = append(res.BaseFeePerGas, v)
	}
	for _, row := range out.Reward {
		var vals []*big.Int
		for _, h := range row {
			v, err := hexToBig(h)
			if err != nil {
				return nil, &Unavailable{Upstream: e.pool.name, Message: "malformed reward: " + h}
			}
			vals = append(vals, v)
		}
		res.Reward = append(res.Reward, vals)
	}
	return res, nil
}

// SendRawTransaction broadcasts a signed raw transaction (0x-hex) and returns
// the transaction hash.
func (e *EVM) SendRawTransaction(ctx context.Context, payload string) (string, error) {
	raw, err := e.call(ctx, "eth_sendRawTransaction", payload)
	if err != nil {
		return "", err
	}
	var hash string
	if err := json.Unmarshal(raw, &hash); err != nil {
		return "", &Unavailable{Upstream: e.pool.name, Message: "malformed eth_sendRawTransaction result"}
	}
	return hash, nil
}

func parseQuantity(raw json.RawMessage) (*big.Int, error) {
	var s string
	if err := json.Unmarshal(raw, &s); err != nil {
		return nil, &Unavailable{Upstream: "evm", Message: "expected hex quantity, got: " + truncateForError(raw)}
	}
	return hexToBig(s)
}

func hexToBig(s string) (*big.Int, error) {
	t := strings.TrimPrefix(strings.TrimPrefix(s, "0x"), "0X")
	if t == "" {
		return big.NewInt(0), nil // "0x" — empty eth_call return counts as zero
	}
	v, ok := new(big.Int).SetString(t, 16)
	if !ok {
		return nil, &Unavailable{Upstream: "evm", Message: "invalid hex quantity: " + s}
	}
	return v, nil
}

func truncateForError(raw []byte) string {
	const max = 64
	if len(raw) > max {
		return string(raw[:max]) + "…"
	}
	return string(raw)
}
