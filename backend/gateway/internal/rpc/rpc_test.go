package rpc

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"ktwallet/gateway/internal/clock"
	"ktwallet/gateway/internal/ratelimit"
)

func testServer(limiter *ratelimit.Limiter) *Server {
	s := NewServer(slog.New(slog.NewTextHandler(io.Discard, nil)), limiter, 25*time.Second)
	s.Register("echo", func(_ context.Context, params json.RawMessage) (any, *Error) {
		return map[string]string{"got": string(params)}, nil
	})
	s.Register("boom", func(_ context.Context, _ json.RawMessage) (any, *Error) {
		return nil, Errorf(CodeInvalidParams, "invalid params: nope")
	})
	return s
}

func post(t *testing.T, s *Server, body string, remoteAddr string) (int, map[string]any) {
	t.Helper()
	req := httptest.NewRequest("POST", "/rpc", strings.NewReader(body))
	if remoteAddr != "" {
		req.RemoteAddr = remoteAddr
	}
	rec := httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Body.Len() == 0 {
		return rec.Code, nil
	}
	var out map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatalf("response is not JSON: %v\n%s", err, rec.Body.String())
	}
	return rec.Code, out
}

func errCode(t *testing.T, resp map[string]any) float64 {
	t.Helper()
	e, ok := resp["error"].(map[string]any)
	if !ok {
		t.Fatalf("expected error in response, got %v", resp)
	}
	return e["code"].(float64)
}

func TestParseError(t *testing.T) {
	for _, body := range []string{"{", "", "not json at all", `{"jsonrpc":"2.0","method":`} {
		_, resp := post(t, testServer(nil), body, "")
		if c := errCode(t, resp); c != CodeParse {
			t.Fatalf("body %q: want -32700, got %v", body, c)
		}
		if resp["id"] != nil {
			t.Fatalf("parse error must carry null id, got %v", resp["id"])
		}
	}
}

func TestBatchRejected(t *testing.T) {
	for _, body := range []string{
		`[]`,
		`[{"jsonrpc":"2.0","id":1,"method":"echo"}]`,
		`  [{"jsonrpc":"2.0","id":1,"method":"echo"}]`, // leading whitespace
	} {
		_, resp := post(t, testServer(nil), body, "")
		if c := errCode(t, resp); c != CodeInvalidRequest {
			t.Fatalf("body %q: want -32600, got %v", body, c)
		}
	}
}

func TestInvalidRequest(t *testing.T) {
	cases := []string{
		`{"id":1,"method":"echo"}`,                 // missing jsonrpc
		`{"jsonrpc":"1.0","id":1,"method":"echo"}`, // wrong version
		`{"jsonrpc":"2.0","id":1}`,                 // missing method
		`{"jsonrpc":"2.0","id":1,"method":""}`,     // empty method
	}
	for _, body := range cases {
		_, resp := post(t, testServer(nil), body, "")
		if c := errCode(t, resp); c != CodeInvalidRequest {
			t.Fatalf("body %q: want -32600, got %v", body, c)
		}
	}
}

func TestUnknownMethod(t *testing.T) {
	_, resp := post(t, testServer(nil), `{"jsonrpc":"2.0","id":1,"method":"kt_nope"}`, "")
	if c := errCode(t, resp); c != CodeMethodNotFound {
		t.Fatalf("want -32601, got %v", c)
	}
	if msg := resp["error"].(map[string]any)["message"].(string); !strings.Contains(msg, "kt_nope") {
		t.Fatalf("error message should name the method, got %q", msg)
	}
}

func TestIDEchoStringAndNumber(t *testing.T) {
	cases := []struct {
		id   string
		want any
	}{
		{`"abc-123"`, "abc-123"},
		{`7`, float64(7)},
		{`0`, float64(0)},
	}
	for _, tc := range cases {
		_, resp := post(t, testServer(nil), `{"jsonrpc":"2.0","id":`+tc.id+`,"method":"echo","params":{}}`, "")
		if resp["id"] != tc.want {
			t.Fatalf("id %s: echoed %v (%T), want %v", tc.id, resp["id"], resp["id"], tc.want)
		}
		if resp["result"] == nil {
			t.Fatalf("id %s: expected a result", tc.id)
		}
	}
}

func TestIDEchoOnHandlerError(t *testing.T) {
	_, resp := post(t, testServer(nil), `{"jsonrpc":"2.0","id":"e1","method":"boom"}`, "")
	if resp["id"] != "e1" {
		t.Fatalf("error responses must echo the id, got %v", resp["id"])
	}
	if c := errCode(t, resp); c != CodeInvalidParams {
		t.Fatalf("want -32602, got %v", c)
	}
}

func TestNotificationNoBody(t *testing.T) {
	for _, body := range []string{
		`{"jsonrpc":"2.0","method":"echo","params":{}}`,           // no id
		`{"jsonrpc":"2.0","id":null,"method":"echo","params":{}}`, // explicit null id
	} {
		code, resp := post(t, testServer(nil), body, "")
		if code != 204 || resp != nil {
			t.Fatalf("notification %q: want 204 with empty body, got %d %v", body, code, resp)
		}
	}
}

func TestNotificationStillExecutes(t *testing.T) {
	s := testServer(nil)
	ran := false
	s.Register("side", func(_ context.Context, _ json.RawMessage) (any, *Error) {
		ran = true
		return "x", nil
	})
	post(t, s, `{"jsonrpc":"2.0","method":"side"}`, "")
	if !ran {
		t.Fatal("notification should still execute the handler")
	}
}

func TestRateLimitExhaustion(t *testing.T) {
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	s := testServer(ratelimit.New(clk, 1, 2))
	for i := 0; i < 2; i++ {
		_, resp := post(t, s, `{"jsonrpc":"2.0","id":1,"method":"echo","params":{}}`, "10.0.0.1:1234")
		if resp["error"] != nil {
			t.Fatalf("request %d within burst should pass: %v", i+1, resp)
		}
	}
	_, resp := post(t, s, `{"jsonrpc":"2.0","id":1,"method":"echo","params":{}}`, "10.0.0.1:1234")
	if c := errCode(t, resp); c != CodeRateLimited {
		t.Fatalf("want -32001 after burst exhaustion, got %v", c)
	}
}

func TestRateLimitIPIsolation(t *testing.T) {
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	s := testServer(ratelimit.New(clk, 1, 1))
	if _, resp := post(t, s, `{"jsonrpc":"2.0","id":1,"method":"echo","params":{}}`, "10.0.0.1:1"); resp["error"] != nil {
		t.Fatalf("first IP first call should pass: %v", resp)
	}
	if _, resp := post(t, s, `{"jsonrpc":"2.0","id":1,"method":"echo","params":{}}`, "10.0.0.1:2"); errCode(t, resp) != CodeRateLimited {
		t.Fatal("same IP different port should share a bucket and be limited")
	}
	if _, resp := post(t, s, `{"jsonrpc":"2.0","id":1,"method":"echo","params":{}}`, "10.0.0.2:1"); resp["error"] != nil {
		t.Fatalf("a different IP must not be affected: %v", resp)
	}
}

func TestTruncateAddress(t *testing.T) {
	cases := []struct{ in, want string }{
		{"0x52908400098527886E0F7030069857D2E4169EE7", "0x5290…9EE7"},
		{"TS6pWDWcKRYfZFzDMgUp7vzjVhyHfq4c4C", "TS6pWD…4c4C"},
		{"short", "short"},
		{"", ""},
	}
	for _, tc := range cases {
		if got := TruncateAddress(tc.in); got != tc.want {
			t.Fatalf("TruncateAddress(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}
