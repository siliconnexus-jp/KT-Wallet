package upstream

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
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

func TestGoPlusMissingRecordIsUnknownAndBase58IdentityIsCaseSensitive(t *testing.T) {
	const tronContract = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = fmt.Fprintf(w, `{"code":1,"result":{"%s":{"is_honeypot":"1"}}}`, strings.ToLower(tronContract))
	}))
	defer server.Close()

	got, err := NewGoPlus(server.URL, "", server.Client(), time.Second).
		TokenRisk(context.Background(), "tron", tronContract)
	if err != nil {
		t.Fatal(err)
	}
	if got.Found || got.Unsafe {
		t.Fatalf("case-changed Base58 identity must not match: %#v", got)
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
