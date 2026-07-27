// Package rpc implements the gateway's JSON-RPC 2.0 HTTP endpoint.
//
// Protocol notes (fixed contract):
//   - Single requests only; batch requests are rejected with -32600.
//   - A request without an id, or with an explicit null id, is treated as a
//     notification: the method still runs but no response body is returned
//     (HTTP 204).
//   - Error codes: -32700 parse, -32600 invalid request/batch, -32601 unknown
//     method, -32602 invalid params, -32000 upstream_error,
//     -32001 rate_limited, -32002 unsupported.
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
	"time"

	"ktwallet/gateway/internal/ratelimit"
)

// JSON-RPC error codes used by the gateway.
const (
	CodeParse          = -32700
	CodeInvalidRequest = -32600
	CodeMethodNotFound = -32601
	CodeInvalidParams  = -32602
	CodeUpstream       = -32000
	CodeRateLimited    = -32001
	CodeUnsupported    = -32002
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
	body, err := io.ReadAll(io.LimitReader(r.Body, s.maxBody))
	if err != nil {
		s.writeError(w, nil, Errorf(CodeParse, "parse error: unable to read request body"))
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

	if s.limiter != nil && !s.limiter.Allow(clientIP(r)) {
		rpcErr = Errorf(CodeRateLimited, "rate_limited")
	} else if h, ok := s.methods[req.Method]; !ok {
		rpcErr = Errorf(CodeMethodNotFound, "method not found: %s", req.Method)
	} else {
		ctx, cancel := context.WithTimeout(r.Context(), s.budget)
		result, rpcErr = h(ctx, req.Params)
		cancel()
	}
	if rpcErr != nil {
		outcome = fmt.Sprintf("error:%d", rpcErr.Code)
	}

	// One structured line per request. Addresses are always truncated and
	// payloads are never logged.
	var meta struct {
		Chain   string `json:"chain"`
		Network string `json:"network"`
		Address string `json:"address"`
	}
	_ = json.Unmarshal(req.Params, &meta)
	s.log.Info("rpc",
		"method", req.Method,
		"chain", meta.Chain,
		// Empty means the client sent no network (the chain's mainnet is used);
		// operators can use this to spot clients that predate the param.
		"network", meta.Network,
		"address", TruncateAddress(meta.Address),
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

func clientIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// TruncateAddress reduces an address to its first 6 and last 4 characters for
// logging. Short values are returned unchanged.
func TruncateAddress(a string) string {
	if len(a) <= 12 {
		return a
	}
	return a[:6] + "…" + a[len(a)-4:]
}
