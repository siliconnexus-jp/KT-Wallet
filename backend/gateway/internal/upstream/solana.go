package upstream

import (
	"context"
	"encoding/json"
	"math/big"
	"net/http"
	"time"

	"ktwallet/gateway/internal/clock"
)

// Solana is a Solana JSON-RPC client backed by a failover Pool.
type Solana struct {
	pool *Pool
}

// NewSolana builds a Solana client over the given RPC URLs.
func NewSolana(urls []string, clk clock.Clock, client *http.Client, attemptTimeout time.Duration) *Solana {
	return &Solana{pool: NewPool("solana", urls, clk, client, attemptTimeout)}
}

// GetBalance returns the lamport balance of address.
func (s *Solana) GetBalance(ctx context.Context, address string) (*big.Int, error) {
	raw, err := s.pool.Call(ctx, "getBalance", []any{address})
	if err != nil {
		return nil, err
	}
	var out struct {
		Value json.Number `json:"value"`
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return nil, &Unavailable{Upstream: "solana", Message: "malformed getBalance result"}
	}
	v, ok := new(big.Int).SetString(out.Value.String(), 10)
	if !ok {
		return nil, &Unavailable{Upstream: "solana", Message: "malformed getBalance value: " + out.Value.String()}
	}
	return v, nil
}

// SendTransaction broadcasts a base64-encoded signed transaction and returns
// its signature.
func (s *Solana) SendTransaction(ctx context.Context, payloadBase64 string) (string, error) {
	raw, err := s.pool.Call(ctx, "sendTransaction", []any{payloadBase64, map[string]string{"encoding": "base64"}})
	if err != nil {
		return "", err
	}
	var sig string
	if err := json.Unmarshal(raw, &sig); err != nil {
		return "", &Unavailable{Upstream: "solana", Message: "malformed sendTransaction result"}
	}
	return sig, nil
}
