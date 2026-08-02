package rpc

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"ktwallet/gateway/internal/clock"
	"ktwallet/gateway/internal/ratelimit"
)

type trackingBody struct {
	reads int
}

func (b *trackingBody) Read(_ []byte) (int, error) {
	b.reads++
	return 0, io.EOF
}

func (*trackingBody) Close() error { return nil }

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
	return postWithHeaders(t, s, body, remoteAddr, nil)
}

func postWithHeaders(t *testing.T, s *Server, body string, remoteAddr string, headers map[string]string) (int, map[string]any) {
	t.Helper()
	req := httptest.NewRequest("POST", "/rpc", strings.NewReader(body))
	if remoteAddr != "" {
		req.RemoteAddr = remoteAddr
	}
	for name, value := range headers {
		req.Header.Set(name, value)
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

func TestOversizedRequestWithValidJSONPrefixNeverExecutes(t *testing.T) {
	s := testServer(nil)
	s.maxBody = 96
	ran := false
	s.Register("side", func(_ context.Context, _ json.RawMessage) (any, *Error) {
		ran = true
		return "x", nil
	})
	body := `{"jsonrpc":"2.0","id":1,"method":"side","params":{}}` +
		strings.Repeat(" ", int(s.maxBody))

	_, resp := post(t, s, body, "")
	if c := errCode(t, resp); c != CodeInvalidRequest {
		t.Fatalf("oversized request: want -32600, got %v", c)
	}
	if ran {
		t.Fatal("an oversized request must be rejected before handler execution")
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

func TestRateLimitedRequestDoesNotReadBody(t *testing.T) {
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	s := testServer(ratelimit.New(clk, 1, 1))
	if _, resp := post(t, s, `{"jsonrpc":"2.0","id":1,"method":"echo","params":{}}`, "10.0.0.1:1"); resp["error"] != nil {
		t.Fatalf("first request should consume the burst token: %v", resp)
	}

	body := &trackingBody{}
	req := httptest.NewRequest("POST", "/rpc", body)
	req.RemoteAddr = "10.0.0.1:2"
	rec := httptest.NewRecorder()
	s.ServeHTTP(rec, req)

	var resp map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("response is not JSON: %v\n%s", err, rec.Body.String())
	}
	if code := errCode(t, resp); code != CodeRateLimited {
		t.Fatalf("want -32001 before body processing, got %v", code)
	}
	if body.reads != 0 {
		t.Fatalf("rate-limited body was read %d time(s)", body.reads)
	}
}

func TestMalformedRequestConsumesInboundRateLimitToken(t *testing.T) {
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	s := testServer(ratelimit.New(clk, 1, 1))
	if _, resp := post(t, s, "not-json", "10.0.0.1:1"); errCode(t, resp) != CodeParse {
		t.Fatalf("first malformed request must still return a parse error: %v", resp)
	}
	_, resp := post(t, s, `{"jsonrpc":"2.0","id":1,"method":"echo","params":{}}`, "10.0.0.1:2")
	if code := errCode(t, resp); code != CodeRateLimited {
		t.Fatalf("malformed requests must consume inbound tokens; got %v", code)
	}
}

func TestDeclaredOversizedBodyIsRejectedWithoutRead(t *testing.T) {
	s := testServer(nil)
	body := &trackingBody{}
	req := httptest.NewRequest("POST", "/rpc", body)
	req.ContentLength = s.maxBody + 1
	rec := httptest.NewRecorder()
	s.ServeHTTP(rec, req)

	var resp map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("response is not JSON: %v\n%s", err, rec.Body.String())
	}
	if code := errCode(t, resp); code != CodeInvalidRequest {
		t.Fatalf("want -32600 for declared oversized body, got %v", code)
	}
	if body.reads != 0 {
		t.Fatalf("declared oversized body was read %d time(s)", body.reads)
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

func TestForwardedIPIgnoredFromUntrustedPeer(t *testing.T) {
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	s := testServer(ratelimit.New(clk, 1, 1))
	body := `{"jsonrpc":"2.0","id":1,"method":"echo","params":{}}`
	if _, resp := postWithHeaders(t, s, body, "192.0.2.10:1", map[string]string{"X-Forwarded-For": "198.51.100.1"}); resp["error"] != nil {
		t.Fatalf("first call should pass: %v", resp)
	}
	_, resp := postWithHeaders(t, s, body, "192.0.2.10:2", map[string]string{"X-Forwarded-For": "198.51.100.2"})
	if errCode(t, resp) != CodeRateLimited {
		t.Fatal("untrusted peers must not choose rate-limit buckets through headers")
	}
}

func TestTrustedProxyKeepsClientBucketsIndependent(t *testing.T) {
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	s := testServer(ratelimit.New(clk, 1, 1))
	if err := s.SetTrustedProxyCIDRs("127.0.0.1/32, ::1/128"); err != nil {
		t.Fatal(err)
	}
	body := `{"jsonrpc":"2.0","id":1,"method":"echo","params":{}}`
	for _, client := range []string{"198.51.100.1", "198.51.100.2"} {
		_, resp := postWithHeaders(t, s, body, "127.0.0.1:4000", map[string]string{"X-Forwarded-For": client})
		if resp["error"] != nil {
			t.Fatalf("client %s should have its own first token: %v", client, resp)
		}
	}
}

func TestTrustedProxyRejectsLeftmostSpoofing(t *testing.T) {
	clk := clock.NewFake(time.Unix(1_700_000_000, 0))
	s := testServer(ratelimit.New(clk, 1, 1))
	if err := s.SetTrustedProxyCIDRs("127.0.0.1/32,10.0.0.0/8"); err != nil {
		t.Fatal(err)
	}
	body := `{"jsonrpc":"2.0","id":1,"method":"echo","params":{}}`
	headers := map[string]string{"X-Forwarded-For": "192.0.2.1, 198.51.100.9, 10.2.3.4"}
	if _, resp := postWithHeaders(t, s, body, "127.0.0.1:4000", headers); resp["error"] != nil {
		t.Fatalf("first call should pass: %v", resp)
	}
	// Changing only the attacker-controlled leftmost value must not acquire a
	// new token; the first non-trusted hop from the right is the real client.
	headers["X-Forwarded-For"] = "192.0.2.99, 198.51.100.9, 10.2.3.4"
	_, resp := postWithHeaders(t, s, body, "127.0.0.1:4001", headers)
	if errCode(t, resp) != CodeRateLimited {
		t.Fatal("spoofed leftmost forwarding values must share the real client's bucket")
	}
}

func TestMalformedForwardedChainFallsBackToPeer(t *testing.T) {
	s := testServer(nil)
	if err := s.SetTrustedProxyCIDRs("127.0.0.1/32"); err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest("POST", "/rpc", nil)
	req.RemoteAddr = "127.0.0.1:4000"
	req.Header.Set("X-Forwarded-For", "198.51.100.1, not-an-ip")
	req.Header.Set("X-Real-IP", "203.0.113.7")
	if got := s.clientIP(req); got != "127.0.0.1" {
		t.Fatalf("malformed chain must ignore all forwarding headers, got %q", got)
	}
}

func TestMultipleForwardedFieldsFollowHAProxyAppendOrder(t *testing.T) {
	s := testServer(nil)
	if err := s.SetTrustedProxyCIDRs("127.0.0.1/32,10.0.0.0/8"); err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest("POST", "/rpc", nil)
	req.RemoteAddr = "127.0.0.1:4000"
	// FluxGate supplies the sanitized client chain and HAProxy's `option
	// forwardfor` appends its TCP peer as a final field line.
	req.Header.Add("X-Forwarded-For", "192.0.2.77, 198.51.100.9")
	req.Header.Add("X-Forwarded-For", "10.2.3.4")
	req.Header.Set("X-Real-IP", "203.0.113.7")
	if got := s.clientIP(req); got != "198.51.100.9" {
		t.Fatalf("multiple XFF fields must preserve append order, got %q", got)
	}
}

func TestMalformedMultipleForwardedFieldsFallBackToPeer(t *testing.T) {
	s := testServer(nil)
	if err := s.SetTrustedProxyCIDRs("127.0.0.1/32,10.0.0.0/8"); err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest("POST", "/rpc", nil)
	req.RemoteAddr = "127.0.0.1:4000"
	req.Header.Add("X-Forwarded-For", "198.51.100.9")
	req.Header.Add("X-Forwarded-For", "not-an-ip")
	req.Header.Set("X-Real-IP", "203.0.113.7")
	if got := s.clientIP(req); got != "127.0.0.1" {
		t.Fatalf("a malformed XFF field must ignore every identity header, got %q", got)
	}
}

func TestEmptyForwardedFieldDoesNotFallThroughToRealIP(t *testing.T) {
	s := testServer(nil)
	if err := s.SetTrustedProxyCIDRs("127.0.0.1/32"); err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest("POST", "/rpc", nil)
	req.RemoteAddr = "127.0.0.1:4000"
	req.Header.Set("X-Forwarded-For", "   ")
	req.Header.Set("X-Real-IP", "203.0.113.7")
	if got := s.clientIP(req); got != "127.0.0.1" {
		t.Fatalf("empty XFF must fail closed to the peer, got %q", got)
	}
}

func TestTrustedProxySupportsExplicitRealIP(t *testing.T) {
	s := testServer(nil)
	if err := s.SetTrustedProxyCIDRs("127.0.0.1/32"); err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest("POST", "/rpc", nil)
	req.RemoteAddr = "127.0.0.1:4000"
	req.Header.Set("X-Real-IP", "203.0.113.7")
	if got := s.clientIP(req); got != "203.0.113.7" {
		t.Fatalf("trusted proxy X-Real-IP not used, got %q", got)
	}
}

func TestDuplicateRealIPFieldsFallBackToPeer(t *testing.T) {
	s := testServer(nil)
	if err := s.SetTrustedProxyCIDRs("127.0.0.1/32"); err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest("POST", "/rpc", nil)
	req.RemoteAddr = "127.0.0.1:4000"
	req.Header.Add("X-Real-IP", "203.0.113.7")
	req.Header.Add("X-Real-IP", "203.0.113.8")
	if got := s.clientIP(req); got != "127.0.0.1" {
		t.Fatalf("duplicate X-Real-IP fields must fail closed to the peer, got %q", got)
	}
}

func TestTrustedProxyConfigurationFailsClosed(t *testing.T) {
	s := testServer(nil)
	if err := s.SetTrustedProxyCIDRs("127.0.0.1/32,not-a-cidr"); err == nil {
		t.Fatal("invalid proxy CIDR must be rejected")
	}
	if len(s.trusted) != 0 {
		t.Fatal("a partially valid list must not change the trust boundary")
	}
}

func TestStructuredRequestLogNeverContainsWalletAddress(t *testing.T) {
	var logs bytes.Buffer
	s := NewServer(slog.New(slog.NewJSONHandler(&logs, nil)), nil, 25*time.Second)
	s.Register("echo", func(_ context.Context, _ json.RawMessage) (any, *Error) {
		return "ok", nil
	})
	const address = "0x52908400098527886E0F7030069857D2E4169EE7"
	post(t, s, `{"jsonrpc":"2.0","id":1,"method":"echo","params":{"chain":"eth","network":"eth-mainnet","address":"`+address+`"}}`, "192.0.2.1:1")
	line := logs.String()
	for _, forbidden := range []string{address, "0x5290", "9EE7", `"address"`} {
		if strings.Contains(line, forbidden) {
			t.Fatalf("structured log leaked wallet-derived address data %q: %s", forbidden, line)
		}
	}
	for _, required := range []string{`"method":"echo"`, `"chain":"eth"`, `"network":"eth-mainnet"`, `"outcome":"ok"`} {
		if !strings.Contains(line, required) {
			t.Fatalf("structured log missing operational field %s: %s", required, line)
		}
	}
}

func TestStructuredRequestLogNormalizesAllClientControlledLabels(t *testing.T) {
	var logs bytes.Buffer
	s := NewServer(slog.New(slog.NewJSONHandler(&logs, nil)), nil, 25*time.Second)
	s.Register("echo", func(_ context.Context, _ json.RawMessage) (any, *Error) {
		return "ok", nil
	})
	const secret = "abandon-abandon-abandon-private-canary"
	body := `{"jsonrpc":"2.0","id":1,"method":"` + secret +
		`","params":{"chain":"` + secret + `","network":"` + secret + `"}}`
	post(t, s, body, "192.0.2.1:1")

	line := logs.String()
	if strings.Contains(line, secret) {
		t.Fatalf("structured log retained attacker-controlled routing data: %s", line)
	}
	for _, required := range []string{
		`"method":"unknown"`,
		`"chain":"invalid"`,
		`"network":"invalid"`,
		fmt.Sprintf(`"outcome":"error:%d"`, CodeMethodNotFound),
	} {
		if !strings.Contains(line, required) {
			t.Fatalf("structured log missing normalized field %s: %s", required, line)
		}
	}
}

func TestPrivacySafeRoutingLabelsOnlyAcceptCanonicalValues(t *testing.T) {
	tests := []struct {
		chain, network string
		wantChain      string
		wantNetwork    string
	}{
		{"eth", "eth-mainnet", "eth", "eth-mainnet"},
		{"solana", "sol-devnet", "solana", "sol-devnet"},
		{"", "", "", ""},
		{"ETH", "eth-mainnet ", "invalid", "invalid"},
		{"0x52908400098527886E0F7030069857D2E4169EE7", "secret", "invalid", "invalid"},
	}
	for _, test := range tests {
		gotChain, gotNetwork := privacySafeRoutingLabels(test.chain, test.network)
		if gotChain != test.wantChain || gotNetwork != test.wantNetwork {
			t.Fatalf(
				"privacySafeRoutingLabels(%q, %q) = (%q, %q), want (%q, %q)",
				test.chain, test.network, gotChain, gotNetwork,
				test.wantChain, test.wantNetwork,
			)
		}
	}
}
