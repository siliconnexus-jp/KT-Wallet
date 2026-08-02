// Package rpc implements the gateway's JSON-RPC 2.0 HTTP endpoint.
//
// Protocol notes (fixed contract):
//   - Single requests only; batch requests are rejected with -32600.
//   - A request without an id, or with an explicit null id, is treated as a
//     notification: the method still runs but no response body is returned
//     (HTTP 204).
//   - Error codes: -32700 parse, -32600 invalid request/batch, -32601 unknown
//     method, -32602 invalid params, -32000 upstream_error,
//     -32001 rate_limited, -32002 unsupported, -32003 submission_unknown.
package rpc

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"strings"
	"time"

	"ktwallet/gateway/internal/ratelimit"
)

// JSON-RPC error codes used by the gateway.
const (
	CodeParse             = -32700
	CodeInvalidRequest    = -32600
	CodeMethodNotFound    = -32601
	CodeInvalidParams     = -32602
	CodeUpstream          = -32000
	CodeRateLimited       = -32001
	CodeUnsupported       = -32002
	CodeSubmissionUnknown = -32003
)

// Error is a JSON-RPC 2.0 error object.
type Error struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
	Data    any    `json:"data,omitempty"`
}

// Errorf builds an *Error with a formatted message and no data.
func Errorf(code int, format string, args ...any) *Error {
	return &Error{Code: code, Message: fmt.Sprintf(format, args...)}
}

// Handler executes one JSON-RPC method. It returns either a result or an
// *Error (never both).
type Handler func(ctx context.Context, params json.RawMessage) (any, *Error)

// Server routes JSON-RPC requests to registered handlers.
type Server struct {
	methods map[string]Handler
	limiter *ratelimit.Limiter // per-client-IP; nil disables inbound limiting
	log     *slog.Logger
	budget  time.Duration // request-level time budget
	maxBody int64
	trusted []*net.IPNet
}

// NewServer builds a Server. limiter may be nil to disable inbound rate
// limiting; budget is the whole-request deadline (25s per the contract).
func NewServer(log *slog.Logger, limiter *ratelimit.Limiter, budget time.Duration) *Server {
	if log == nil {
		log = slog.Default()
	}
	if budget <= 0 {
		budget = 25 * time.Second
	}
	return &Server{
		methods: make(map[string]Handler),
		limiter: limiter,
		log:     log,
		budget:  budget,
		maxBody: 4 << 20,
	}
}

// Register binds a method name to a handler.
func (s *Server) Register(method string, h Handler) { s.methods[method] = h }

// SetTrustedProxyCIDRs configures the only peers whose forwarding headers may
// influence per-client rate limiting. An empty string trusts no proxy. The
// caller should normally set loopback CIDRs when Nginx runs on the same host.
// Invalid input is rejected instead of silently widening the trust boundary.
func (s *Server) SetTrustedProxyCIDRs(raw string) error {
	var parsed []*net.IPNet
	for _, item := range strings.Split(raw, ",") {
		item = strings.TrimSpace(item)
		if item == "" {
			continue
		}
		_, network, err := net.ParseCIDR(item)
		if err != nil {
			return fmt.Errorf("invalid trusted proxy CIDR %q", item)
		}
		parsed = append(parsed, network)
	}
	s.trusted = parsed
	return nil
}

type request struct {
	JSONRPC string          `json:"jsonrpc"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params"`
	ID      json.RawMessage `json:"id"`
}

type response struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id"`
	Result  any             `json:"result,omitempty"`
	Error   *Error          `json:"error,omitempty"`
}

// ServeHTTP handles POST /rpc.
func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	start := time.Now()
	// Enforce the per-client budget before reading or decoding attacker-controlled
	// input. Otherwise an exhausted client can keep forcing 4 MiB reads and JSON
	// parsing, while malformed requests never consume a token at all. The request
	// ID is intentionally unknown at this boundary, so the fixed JSON-RPC error
	// uses id=null.
	if s.limiter != nil && !s.limiter.Allow(s.clientIP(r)) {
		s.log.Info("rpc",
			"method", "unknown",
			"chain", "",
			"network", "",
			"durationMs", time.Since(start).Milliseconds(),
			"outcome", fmt.Sprintf("error:%d", CodeRateLimited),
		)
		s.writeError(w, nil, Errorf(CodeRateLimited, "rate_limited"))
		return
	}
	if r.ContentLength > s.maxBody {
		s.writeError(w, nil, Errorf(CodeInvalidRequest, "invalid request: request body is too large"))
		return
	}
	body, err := io.ReadAll(io.LimitReader(r.Body, s.maxBody+1))
	if err != nil {
		s.writeError(w, nil, Errorf(CodeParse, "parse error: unable to read request body"))
		return
	}
	if int64(len(body)) > s.maxBody {
		s.writeError(w, nil, Errorf(CodeInvalidRequest, "invalid request: request body is too large"))
		return
	}

	trimmed := bytes.TrimLeft(body, " \t\r\n")
	if len(trimmed) > 0 && trimmed[0] == '[' {
		s.writeError(w, nil, Errorf(CodeInvalidRequest, "batch requests are not supported"))
		return
	}

	var req request
	if err := json.Unmarshal(body, &req); err != nil {
		s.writeError(w, nil, Errorf(CodeParse, "parse error: invalid JSON"))
		return
	}
	if req.JSONRPC != "2.0" || req.Method == "" {
		s.writeError(w, req.ID, Errorf(CodeInvalidRequest, `invalid request: "jsonrpc" must be "2.0" and "method" must be set`))
		return
	}

	// A missing id or an explicit null id marks a notification.
	notification := len(req.ID) == 0 || string(req.ID) == "null"

	outcome := "ok"
	var result any
	var rpcErr *Error

	if h, ok := s.methods[req.Method]; !ok {
		rpcErr = Errorf(CodeMethodNotFound, "method not found: %s", req.Method)
	} else {
		ctx, cancel := context.WithTimeout(r.Context(), s.budget)
		result, rpcErr = h(ctx, req.Params)
		cancel()
	}
	if rpcErr != nil {
		outcome = fmt.Sprintf("error:%d", rpcErr.Code)
	}

	// One privacy-safe structured line per request. Every string written below
	// comes from a server-owned fixed vocabulary. In particular, do not log the
	// raw method/chain/network strings: an unauthenticated caller could place an
	// address, recovery phrase or provider credential in any of those fields.
	var meta struct {
		Chain   string `json:"chain"`
		Network string `json:"network"`
	}
	_ = json.Unmarshal(req.Params, &meta)
	chainLabel, networkLabel := privacySafeRoutingLabels(meta.Chain, meta.Network)
	s.log.Info("rpc",
		"method", s.privacySafeMethodLabel(req.Method),
		"chain", chainLabel,
		// Empty means the client sent no network (the chain's mainnet is used);
		// operators can use this to spot clients that predate the param.
		"network", networkLabel,
		"durationMs", time.Since(start).Milliseconds(),
		"outcome", outcome,
	)

	if notification {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	if rpcErr != nil {
		s.writeError(w, req.ID, rpcErr)
		return
	}
	s.write(w, response{JSONRPC: "2.0", ID: req.ID, Result: result})
}

func (s *Server) privacySafeMethodLabel(method string) string {
	if _, ok := s.methods[method]; ok {
		// Registered method names are application-owned constants, never client
		// content. Unknown values deliberately collapse to one bounded label.
		return method
	}
	return "unknown"
}

func privacySafeRoutingLabels(chain, network string) (string, string) {
	safeChain := ""
	switch chain {
	case "eth", "polygon", "base", "arbitrum", "avalanche", "bnb", "tron", "solana":
		safeChain = chain
	case "":
	default:
		safeChain = "invalid"
	}

	safeNetwork := ""
	switch network {
	case "eth-mainnet", "eth-sepolia",
		"polygon-mainnet", "polygon-amoy",
		"base-mainnet", "base-sepolia",
		"arbitrum-mainnet", "arbitrum-sepolia",
		"avalanche-mainnet", "avalanche-fuji",
		"bnb-mainnet", "bnb-testnet",
		"tron-mainnet", "tron-nile",
		"sol-mainnet", "sol-devnet":
		safeNetwork = network
	case "":
	default:
		safeNetwork = "invalid"
	}
	return safeChain, safeNetwork
}

func (s *Server) writeError(w http.ResponseWriter, id json.RawMessage, e *Error) {
	s.write(w, response{JSONRPC: "2.0", ID: id, Error: e})
}

func (s *Server) write(w http.ResponseWriter, resp response) {
	if len(resp.ID) == 0 {
		resp.ID = json.RawMessage("null")
	}
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(resp); err != nil {
		s.log.Error("rpc write failed", "err", err)
	}
}

func (s *Server) clientIP(r *http.Request) string {
	peer := parseIP(r.RemoteAddr)
	if peer == nil {
		return r.RemoteAddr
	}
	if !containsIP(s.trusted, peer) {
		return peer.String()
	}

	// Reverse proxies may append either a comma-separated value or another XFF
	// field line. Preserve the wire order across every field, validate the whole
	// chain, then walk right-to-left and discard only configured proxy hops. This
	// is compatible with HAProxy's `option forwardfor` append behavior while a
	// client-supplied leftmost value still cannot select another limiter bucket.
	forwardedValues := r.Header.Values("X-Forwarded-For")
	if len(forwardedValues) > 0 {
		parts := make([]string, 0, len(forwardedValues))
		for _, raw := range forwardedValues {
			parts = append(parts, strings.Split(raw, ",")...)
			if len(parts) > 32 {
				return peer.String()
			}
		}
		chain := make([]net.IP, len(parts))
		for i, part := range parts {
			chain[i] = parseIP(strings.TrimSpace(part))
			if chain[i] == nil {
				return peer.String()
			}
		}
		for i := len(chain) - 1; i >= 0; i-- {
			if !containsIP(s.trusted, chain[i]) {
				return chain[i].String()
			}
		}
		if len(chain) > 0 {
			return chain[0].String()
		}
		// A malformed or unreasonably long chain is not partially trusted and
		// cannot fall through to a second, potentially client-supplied header.
		return peer.String()
	}
	realValues := r.Header.Values("X-Real-IP")
	if len(realValues) != 1 {
		return peer.String()
	}
	if real := parseIP(strings.TrimSpace(realValues[0])); real != nil {
		return real.String()
	}
	return peer.String()
}

func parseIP(value string) net.IP {
	if host, _, err := net.SplitHostPort(value); err == nil {
		value = host
	}
	value = strings.Trim(value, "[]")
	return net.ParseIP(value)
}

func containsIP(networks []*net.IPNet, ip net.IP) bool {
	for _, network := range networks {
		if network.Contains(ip) {
			return true
		}
	}
	return false
}
