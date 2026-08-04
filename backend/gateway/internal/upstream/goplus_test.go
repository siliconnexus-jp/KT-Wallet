package upstream

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"
)

const testTokenContract = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

func TestGoPlusTokenRiskUsesOnlyPublicIdentityAndClassifiesExplicitThreats(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/1" {
			t.Fatalf("path = %q", r.URL.Path)
		}
		if got := r.URL.Query().Get("contract_addresses"); got != testTokenContract {
			t.Fatalf("contract = %q", got)
		}
		if got := r.Header.Get("Authorization"); got != "Bearer test-access-token" {
			t.Fatalf("authorization header = %q", got)
		}
		if len(r.URL.Query()) != 1 {
			t.Fatalf("unexpected query fields: %v", r.URL.Query())
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = fmt.Fprintf(w, `{"code":1,"result":{%q:{"is_honeypot":"1","is_mintable":"1"}}}`, testTokenContract)
	}))
	defer server.Close()

	client := NewGoPlus(server.URL, "test-access-token", server.Client(), time.Second)
	got, err := client.TokenRisk(context.Background(), "1", testTokenContract)
	if err != nil {
		t.Fatal(err)
	}
	if !got.Found || !got.Unsafe || got.Category != "honeypot" {
		t.Fatalf("threat = %#v", got)
	}
}

func TestGoPlusDoesNotTreatLegitimateAdminCapabilitiesAsMalicious(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = fmt.Fprintf(w, `{"code":1,"result":{%q:{"is_honeypot":"0","is_mintable":"1","is_blacklisted":"1","is_proxy":"1","transfer_pausable":"1"}}}`, testTokenContract)
	}))
	defer server.Close()

	got, err := NewGoPlus(server.URL, "", server.Client(), time.Second).
		TokenRisk(context.Background(), "1", testTokenContract)
	if err != nil {
		t.Fatal(err)
	}
	if !got.Found || got.Unsafe || got.Category != "" {
		t.Fatalf("threat = %#v", got)
	}
}

func TestGoPlusRejectsCaseChangedBase58ResultIdentity(t *testing.T) {
	const tronContract = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = fmt.Fprintf(w, `{"code":1,"result":{"%s":{"is_honeypot":"1"}}}`, strings.ToLower(tronContract))
	}))
	defer server.Close()

	_, err := NewGoPlus(server.URL, "", server.Client(), time.Second).
		TokenRisk(context.Background(), "tron", tronContract)
	if err == nil {
		t.Fatal("case-changed Base58 result identity must fail closed")
	}
}

func TestGoPlusDocumentedNoDataCodesStayUnknown(t *testing.T) {
	for _, code := range []int{2020, 2021} {
		t.Run(fmt.Sprintf("code-%d", code), func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				_, _ = fmt.Fprintf(w, `{"code":%d,"result":null}`, code)
			}))
			defer server.Close()
			got, err := NewGoPlus(server.URL, "", server.Client(), time.Second).
				TokenRisk(context.Background(), "1", testTokenContract)
			if err != nil {
				t.Fatal(err)
			}
			if got.Found || got.Unsafe {
				t.Fatalf("no-data result = %#v", got)
			}
		})
	}
}

func TestGoPlusFailsClosedOnPartialRateLimitedMalformedAndOversizedResponses(t *testing.T) {
	tests := map[string]http.HandlerFunc{
		"partial": func(w http.ResponseWriter, _ *http.Request) {
			_, _ = w.Write([]byte(`{"code":2,"result":{}}`))
		},
		"rate-limited": func(w http.ResponseWriter, _ *http.Request) {
			w.WriteHeader(http.StatusTooManyRequests)
			_, _ = w.Write([]byte("provider-secret-body"))
		},
		"malformed": func(w http.ResponseWriter, _ *http.Request) {
			_, _ = w.Write([]byte(`{"code":1,"result":[]}`))
		},
		"oversized": func(w http.ResponseWriter, _ *http.Request) {
			_, _ = w.Write([]byte(strings.Repeat("x", maxGoPlusResponseBytes+1)))
		},
	}
	for name, handler := range tests {
		t.Run(name, func(t *testing.T) {
			server := httptest.NewServer(handler)
			defer server.Close()
			_, err := NewGoPlus(server.URL, "", server.Client(), time.Second).
				TokenRisk(context.Background(), "1", testTokenContract)
			if err == nil {
				t.Fatal("expected fail-closed provider error")
			}
			if strings.Contains(err.Error(), "provider-secret-body") {
				t.Fatalf("provider body leaked in error: %v", err)
			}
		})
	}
}

func TestValidateGoPlusURLRequiresSecureCredentialSafeEndpoint(t *testing.T) {
	for _, valid := range []string{
		"https://api.gopluslabs.io/api/v1/token_security",
		"http://127.0.0.1:8080/risk",
		"http://[::1]:8080/risk",
		"http://localhost:8080/risk",
	} {
		if err := ValidateGoPlusURL(valid); err != nil {
			t.Errorf("valid endpoint %q rejected: %v", valid, err)
		}
	}
	for _, invalid := range []string{
		"http://api.gopluslabs.io/api/v1/token_security",
		"https://user:secret@api.gopluslabs.io/risk",
		"https://api.gopluslabs.io/risk?target=elsewhere",
		"https://api.gopluslabs.io/risk#fragment",
		"file:///tmp/risk",
		"not a url",
	} {
		if err := ValidateGoPlusURL(invalid); err == nil {
			t.Errorf("unsafe endpoint %q accepted", invalid)
		} else if strings.Contains(err.Error(), "secret") || strings.Contains(err.Error(), invalid) {
			t.Errorf("validation error leaked endpoint material: %v", err)
		}
	}
}

func TestGoPlusDoesNotForwardCredentialsThroughRedirects(t *testing.T) {
	redirectHits := 0
	destination := httptest.NewServer(http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) {
		redirectHits++
		if auth := r.Header.Get("Authorization"); auth != "" {
			t.Fatalf("redirect destination received credentials: %q", auth)
		}
	}))
	defer destination.Close()
	source := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Location", destination.URL)
		w.WriteHeader(http.StatusFound)
	}))
	defer source.Close()

	_, err := NewGoPlus(source.URL, "redirect-secret", source.Client(), time.Second).
		TokenRisk(context.Background(), "1", testTokenContract)
	if err == nil {
		t.Fatal("redirect must fail closed")
	}
	if redirectHits != 0 {
		t.Fatalf("redirect destination hits = %d", redirectHits)
	}
}

func TestGoPlusRejectsAmbiguousOrRequestUnboundResponses(t *testing.T) {
	tests := map[string]string{
		"unknown envelope member": `{"code":1,"message":"OK","result":{` +
			`"` + testTokenContract + `":{"is_honeypot":"0"}},"extra":true}`,
		"duplicate envelope code": `{"code":2,"code":1,"message":"OK","result":{` +
			`"` + testTokenContract + `":{"is_honeypot":"0"}}}`,
		"envelope member alias": `{"Code":2,"code":1,"message":"OK","result":{` +
			`"` + testTokenContract + `":{"is_honeypot":"0"}}}`,
		"unexpected result identity": `{"code":1,"message":"OK","result":{` +
			`"` + testTokenContract + `":{"is_honeypot":"0"},` +
			`"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb":{"is_honeypot":"1"}}}`,
		"duplicate result identity": `{"code":1,"message":"OK","result":{` +
			`"` + testTokenContract + `":{"is_honeypot":"1"},` +
			`"` + testTokenContract + `":{"is_honeypot":"0"}}}`,
		"invalid threat flag": `{"code":1,"message":"OK","result":{` +
			`"` + testTokenContract + `":{"is_honeypot":"yes"}}}`,
		"duplicate threat flag": `{"code":1,"message":"OK","result":{` +
			`"` + testTokenContract + `":{"is_honeypot":"1","is_honeypot":"0"}}}`,
	}
	for name, body := range tests {
		t.Run(name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				_, _ = w.Write([]byte(body))
			}))
			defer server.Close()
			if _, err := NewGoPlus(server.URL, "", server.Client(), time.Second).
				TokenRisk(context.Background(), "1", testTokenContract); err == nil {
				t.Fatal("ambiguous or request-unbound response must fail closed")
			}
		})
	}
}

func TestGoPlusParsesDocumentedFakeTokenObject(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = fmt.Fprintf(w, `{"code":1,"message":"OK","result":{%q:{`+
			`"is_honeypot":"0","fake_token":{`+
			`"true_token_address":"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","value":1}}}}`,
			testTokenContract)
	}))
	defer server.Close()

	got, err := NewGoPlus(server.URL, "", server.Client(), time.Second).
		TokenRisk(context.Background(), "1", testTokenContract)
	if err != nil {
		t.Fatal(err)
	}
	if !got.Found || !got.Unsafe || got.Category != "impersonation" {
		t.Fatalf("documented fake_token object = %#v", got)
	}
}

func TestGoPlusIncompleteNonMaliciousRecordStaysUnknown(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = fmt.Fprintf(w, `{"code":1,"message":"OK","result":{%q:{"is_mintable":"1"}}}`,
			testTokenContract)
	}))
	defer server.Close()

	got, err := NewGoPlus(server.URL, "", server.Client(), time.Second).
		TokenRisk(context.Background(), "1", testTokenContract)
	if err != nil {
		t.Fatal(err)
	}
	if got.Found || got.Unsafe {
		t.Fatalf("record without a reviewed decisive signal must stay unknown: %#v", got)
	}
}

func TestGoPlusRejectsInvalidIdentityBeforeNetwork(t *testing.T) {
	var calls int
	server := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		calls++
	}))
	defer server.Close()
	client := NewGoPlus(server.URL, "", server.Client(), time.Second)
	for _, tc := range []struct {
		chainID  string
		contract string
	}{
		{"../1", testTokenContract},
		{"1", "0x1234"},
		{"tron", strings.ToLower("TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t")},
	} {
		if _, err := client.TokenRisk(context.Background(), tc.chainID, tc.contract); err == nil {
			t.Fatalf("invalid identity %#v must fail before network", tc)
		}
	}
	if calls != 0 {
		t.Fatalf("invalid identities reached provider %d times", calls)
	}
}

func TestGoPlusLiveSupportedTokenRiskCatalog(t *testing.T) {
	if os.Getenv("KT_LIVE_GOPLUS") != "1" {
		t.Skip("set KT_LIVE_GOPLUS=1 for the read-only GoPlus token catalog smoke test")
	}
	client := NewGoPlus(
		"https://api.gopluslabs.io/api/v1/token_security",
		"",
		http.DefaultClient,
		15*time.Second,
	)
	for _, tc := range []struct {
		chainID string
		token   string
	}{
		{"1", "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"},
		{"137", "0x3c499c542cef5e3811e1192ce70d8cc03d5c3359"},
		{"8453", "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"},
		{"42161", "0xaf88d065e77c8cc2239327c5edb3a432268e5831"},
		{"43114", "0xb97ef9ef8734c71904d8002f8b6bc66dd9c48a6e"},
		{"56", "0xe9e7cea3dedca5984780bafc599bd69add087d56"},
		{"tron", "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"},
	} {
		got, err := client.TokenRisk(context.Background(), tc.chainID, tc.token)
		if err != nil {
			t.Fatalf("live GoPlus response for %s/%s rejected: %v", tc.chainID, tc.token, err)
		}
		if !got.Found || got.Unsafe {
			t.Fatalf("reviewed official token lacks a clean evaluated record: %s/%s %#v", tc.chainID, tc.token, got)
		}
	}
}
