// Package upstream contains the chain/API clients the gateway proxies to:
// EVM JSON-RPC (with URL failover + circuit breaking), TronGrid REST, Solana
// JSON-RPC, CoinGecko prices, and the Etherscan/Helius history APIs.
package upstream

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"sync"
	"time"

	"ktwallet/gateway/internal/clock"
)

// FailThreshold is the number of consecutive failures after which an endpoint
// circuit opens; OpenDuration is how long it then stays skipped.
const (
	FailThreshold = 3
	OpenDuration  = 30 * time.Second
)

// NodeError is a valid JSON-RPC error returned by an upstream node. It does
// NOT trigger failover — the node answered, it just said no.
type NodeError struct {
	Code    int
	Message string
}

func (e *NodeError) Error() string { return fmt.Sprintf("node error %d: %s", e.Code, e.Message) }

// Unavailable means the upstream(s) could not produce an answer: transport
// error, 5xx/429, garbage response, or every circuit open.
type Unavailable struct {
	Upstream string
	Message  string
}

func (e *Unavailable) Error() string { return e.Upstream + ": " + e.Message }

type endpoint struct {
	url       string
	fails     int
	openUntil time.Time
}

// Pool is an ordered list of JSON-RPC endpoints with failover and a
// per-endpoint circuit breaker. Failover triggers on transport errors,
// HTTP 5xx and HTTP 429 — never on a well-formed JSON-RPC error result.
type Pool struct {
	name    string
	clk     clock.Clock
	client  *http.Client
	timeout time.Duration // per-attempt budget

	mu  sync.Mutex
	eps []*endpoint
}

// NewPool builds a Pool over urls, tried in order.
func NewPool(name string, urls []string, clk clock.Clock, client *http.Client, attemptTimeout time.Duration) *Pool {
	eps := make([]*endpoint, 0, len(urls))
	for _, u := range urls {
		if u != "" {
			eps = append(eps, &endpoint{url: u})
		}
	}
	if client == nil {
		client = http.DefaultClient
	}
	if attemptTimeout <= 0 {
		attemptTimeout = 10 * time.Second
	}
	return &Pool{name: name, clk: clk, client: client, timeout: attemptTimeout, eps: eps}
}

// Call performs one JSON-RPC call, failing over between endpoints. The
// returned error is either *NodeError or *Unavailable.
func (p *Pool) Call(ctx context.Context, method string, params any) (json.RawMessage, error) {
	if params == nil {
		params = []any{}
	}
	body, err := json.Marshal(map[string]any{
		"jsonrpc": "2.0",
		"id":      1,
		"method":  method,
		"params":  params,
	})
	if err != nil {
		return nil, &Unavailable{Upstream: p.name, Message: "marshal request: " + err.Error()}
	}

	var lastErr *Unavailable
	attempted := false
	for _, ep := range p.eps {
		if p.circuitOpen(ep) {
			continue
		}
		attempted = true
		result, nodeErr, failure := p.attempt(ctx, ep.url, body)
		if failure != nil {
			p.recordFailure(ep)
			lastErr = &Unavailable{Upstream: hostOf(ep.url), Message: failure.Error()}
			// If the overall context is done there is no point trying more URLs.
			if ctx.Err() != nil {
				return nil, lastErr
			}
			continue
		}
		p.recordSuccess(ep)
		if nodeErr != nil {
			return nil, nodeErr
		}
		return result, nil
	}
	if !attempted {
		return nil, &Unavailable{Upstream: p.name, Message: "all upstreams temporarily unavailable (circuit open)"}
	}
	return nil, lastErr
}

// attempt runs a single HTTP exchange. failure != nil marks a failover-worthy
// problem; nodeErr is a valid JSON-RPC error answer.
func (p *Pool) attempt(ctx context.Context, u string, body []byte) (result json.RawMessage, nodeErr *NodeError, failure error) {
	actx, cancel := context.WithTimeout(ctx, p.timeout)
	defer cancel()
	req, err := http.NewRequestWithContext(actx, http.MethodPost, u, bytes.NewReader(body))
	if err != nil {
		return nil, nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := p.client.Do(req)
	if err != nil {
		return nil, nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusTooManyRequests || resp.StatusCode >= 500 {
		_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 4096))
		return nil, nil, fmt.Errorf("upstream returned HTTP %d", resp.StatusCode)
	}
	data, err := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	if err != nil {
		return nil, nil, err
	}
	var out struct {
		Result json.RawMessage `json:"result"`
		Error  *struct {
			Code    int    `json:"code"`
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.Unmarshal(data, &out); err != nil {
		return nil, nil, fmt.Errorf("invalid JSON-RPC response (HTTP %d)", resp.StatusCode)
	}
	if out.Error != nil {
		return nil, &NodeError{Code: out.Error.Code, Message: out.Error.Message}, nil
	}
	return out.Result, nil, nil
}

func (p *Pool) circuitOpen(ep *endpoint) bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return ep.openUntil.After(p.clk.Now())
}

func (p *Pool) recordFailure(ep *endpoint) {
	p.mu.Lock()
	defer p.mu.Unlock()
	ep.fails++
	if ep.fails >= FailThreshold {
		ep.openUntil = p.clk.Now().Add(OpenDuration)
	}
}

func (p *Pool) recordSuccess(ep *endpoint) {
	p.mu.Lock()
	defer p.mu.Unlock()
	ep.fails = 0
	ep.openUntil = time.Time{}
}

func hostOf(raw string) string {
	if u, err := url.Parse(raw); err == nil && u.Host != "" {
		return u.Host
	}
	return raw
}
