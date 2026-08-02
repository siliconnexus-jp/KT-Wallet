package upstream

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

const solanaUSDCMint = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"

func TestGoPlusSolanaUsesOnlyPublicMintAndDoesNotMisclassifyCapabilities(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v1/solana/token_security" ||
			r.URL.Query().Get("contract_addresses") != solanaUSDCMint {
			t.Fatalf("unexpected provider request: %s", r.URL.String())
		}
		if got := r.Header.Get("Authorization"); got != "Bearer test-token" {
			t.Fatalf("authorization = %q", got)
		}
		_, _ = w.Write([]byte(`{"code":1,"result":{"` + solanaUSDCMint + `":{
          "trusted_token":1,
          "metadata_mutable":{"status":"1","metadata_upgrade_authority":[{"malicious_address":0}]},
          "mintable":{"status":"1","authority":[{"malicious_address":"0"}]},
          "freezable":{"status":"1","authority":[{"malicious_address":false}]},
          "balance_mutable_authority":{"status":"0","authority":[]}
        }}}`))
	}))
	defer server.Close()

	got, err := NewGoPlusSolana(
		server.URL+"/api/v1/solana/token_security",
		"test-token",
		server.Client(),
		time.Second,
	).TokenRisk(context.Background(), solanaUSDCMint)
	if err != nil {
		t.Fatal(err)
	}
	if !got.Found || got.Unsafe || got.Category != "" {
		t.Fatalf("legitimate capabilities must stay non-malicious: %#v", got)
	}
}

func TestGoPlusSolanaBlocksOnlyExplicitMaliciousPrivilegedAuthority(t *testing.T) {
	for name, record := range map[string]string{
		"creator":         `"creator":[{"address":"creator","malicious_address":1}]`,
		"transfer-hook":   `"transfer_hook":[{"address":"hook","malicious_address":"1"}]`,
		"upgradable-hook": `"transfer_hook_upgradable":{"status":"1","authority":[{"malicious_address":true}]}`,
	} {
		t.Run(name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				_, _ = w.Write([]byte(`{"code":1,"result":{"` + solanaUSDCMint + `":{` + record + `}}}`))
			}))
			defer server.Close()

			got, err := NewGoPlusSolana(server.URL, "", server.Client(), time.Second).
				TokenRisk(context.Background(), solanaUSDCMint)
			if err != nil {
				t.Fatal(err)
			}
			if !got.Found || !got.Unsafe || got.Category != "malicious" {
				t.Fatalf("explicit malicious authority = %#v", got)
			}
		})
	}
}

func TestGoPlusSolanaNoDataCodesStayUnknown(t *testing.T) {
	for _, code := range []string{"2020", "2021"} {
		t.Run(code, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				_, _ = w.Write([]byte(`{"code":` + code + `,"result":null}`))
			}))
			defer server.Close()

			got, err := NewGoPlusSolana(server.URL, "", server.Client(), time.Second).
				TokenRisk(context.Background(), solanaUSDCMint)
			if err != nil || got.Found || got.Unsafe {
				t.Fatalf("no-data response = %#v, %v", got, err)
			}
		})
	}
}

func TestGoPlusSolanaMintLookupIsCaseSensitiveAndMalformedFlagsFailClosed(t *testing.T) {
	for name, body := range map[string]string{
		"wrong-case-key": `{"code":1,"result":{"epjfwdd5aufqssqem2qn1xzybapc8g4weggkzwytdt1v":{}}}`,
		"bad-flag":       `{"code":1,"result":{"` + solanaUSDCMint + `":{"mintable":{"authority":[{"malicious_address":"yes"}]}}}}`,
	} {
		t.Run(name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				_, _ = w.Write([]byte(body))
			}))
			defer server.Close()
			got, err := NewGoPlusSolana(server.URL, "", server.Client(), time.Second).
				TokenRisk(context.Background(), solanaUSDCMint)
			if name == "wrong-case-key" {
				if err != nil || got.Found {
					t.Fatalf("case-sensitive missing record = %#v, %v", got, err)
				}
				return
			}
			var unavailable *Unavailable
			if err == nil || !errors.As(err, &unavailable) ||
				unavailable.Message != "malformed token risk record" {
				t.Fatalf("malformed authority flag must fail closed: %v", err)
			}
		})
	}
}

func TestGoPlusSolanaRejectsOversizedResponsesAndRedirects(t *testing.T) {
	for name, handler := range map[string]http.HandlerFunc{
		"oversized": func(w http.ResponseWriter, _ *http.Request) {
			_, _ = w.Write([]byte(strings.Repeat("x", maxGoPlusResponseBytes+1)))
		},
		"redirect": func(w http.ResponseWriter, _ *http.Request) {
			w.Header().Set("Location", "https://example.com/collect")
			w.WriteHeader(http.StatusFound)
		},
	} {
		t.Run(name, func(t *testing.T) {
			server := httptest.NewServer(handler)
			defer server.Close()
			_, err := NewGoPlusSolana(server.URL, "secret", server.Client(), time.Second).
				TokenRisk(context.Background(), solanaUSDCMint)
			if err == nil {
				t.Fatal("provider failure must remain unavailable")
			}
		})
	}
}
