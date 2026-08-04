package upstream

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"
)

const solanaUSDCMint = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"

func completeSolanaRiskRecord(authority string) string {
	return `{"trusted_token":1,"creators":[],` +
		`"metadata_mutable":{"status":"1","metadata_upgrade_authority":[{"address":"` + authority + `","malicious_address":0}]},` +
		`"mintable":{"status":"1","authority":[{"address":"` + authority + `","malicious_address":0}]},` +
		`"freezable":{"status":"1","authority":[{"address":"` + authority + `","malicious_address":0}]},` +
		`"closable":{"status":"0","authority":[]},` +
		`"transfer_fee_upgradable":{"status":"0","authority":[]},` +
		`"default_account_state_upgradable":{"status":"0","authority":[]},` +
		`"balance_mutable_authority":{"status":"0","authority":[]},` +
		`"transfer_hook":[],` +
		`"transfer_hook_upgradable":{"status":"0","authority":[]}}`
}

func TestGoPlusSolanaUsesOnlyPublicMintAndDoesNotMisclassifyCapabilities(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v1/solana/token_security" ||
			r.URL.Query().Get("contract_addresses") != solanaUSDCMint {
			t.Fatalf("unexpected provider request: %s", r.URL.String())
		}
		if got := r.Header.Get("Authorization"); got != "Bearer test-token" {
			t.Fatalf("authorization = %q", got)
		}
		_, _ = w.Write([]byte(`{"code":1,"result":{"` + solanaUSDCMint + `":` +
			completeSolanaRiskRecord(solanaUSDCMint) + `}}`))
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
	base := completeSolanaRiskRecord(solanaUSDCMint)
	for name, record := range map[string]string{
		"creators": strings.Replace(
			base,
			`"creators":[]`,
			`"creators":[{"address":"`+solanaUSDCMint+`","malicious_address":1}]`,
			1,
		),
		"transfer-hook": strings.Replace(
			base,
			`"transfer_hook":[]`,
			`"transfer_hook":[{"address":"`+solanaUSDCMint+`","malicious_address":"1"}]`,
			1,
		),
		"upgradable-hook": strings.Replace(
			base,
			`"transfer_hook_upgradable":{"status":"0","authority":[]}`,
			`"transfer_hook_upgradable":{"status":"1","authority":[{"address":"`+solanaUSDCMint+`","malicious_address":1}]}`,
			1,
		),
	} {
		t.Run(name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				_, _ = w.Write([]byte(`{"code":1,"result":{"` + solanaUSDCMint + `":` + record + `}}`))
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
		"bad-flag": `{"code":1,"result":{"` + solanaUSDCMint + `":` + strings.Replace(
			completeSolanaRiskRecord(solanaUSDCMint),
			`"malicious_address":0`,
			`"malicious_address":"yes"`,
			1,
		) + `}}`,
	} {
		t.Run(name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				_, _ = w.Write([]byte(body))
			}))
			defer server.Close()
			_, err := NewGoPlusSolana(server.URL, "", server.Client(), time.Second).
				TokenRisk(context.Background(), solanaUSDCMint)
			if name == "wrong-case-key" {
				if err == nil {
					t.Fatal("case-changed result identity must fail closed")
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

func TestGoPlusSolanaRejectsAmbiguousOrRequestUnboundResponses(t *testing.T) {
	tests := map[string]string{
		"unknown envelope member": `{"code":1,"message":"OK","result":{"` + solanaUSDCMint +
			`":{"creators":[]}},"extra":true}`,
		"duplicate envelope code": `{"code":2,"code":1,"message":"OK","result":{"` +
			solanaUSDCMint + `":{"creators":[]}}}`,
		"unexpected result identity": `{"code":1,"message":"OK","result":{"` +
			solanaUSDCMint + `":{"creators":[]},"11111111111111111111111111111111":{"creators":[]}}}`,
		"duplicate result identity": `{"code":1,"message":"OK","result":{"` +
			solanaUSDCMint + `":{"creators":[]},"` + solanaUSDCMint + `":{"creators":[]}}}`,
		"duplicate nested threat flag": `{"code":1,"message":"OK","result":{"` +
			solanaUSDCMint + `":{"creators":[{"address":"` + solanaUSDCMint +
			`","malicious_address":1,"malicious_address":0}]}}}`,
	}
	for name, body := range tests {
		t.Run(name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				_, _ = w.Write([]byte(body))
			}))
			defer server.Close()
			if _, err := NewGoPlusSolana(server.URL, "", server.Client(), time.Second).
				TokenRisk(context.Background(), solanaUSDCMint); err == nil {
				t.Fatal("ambiguous or request-unbound response must fail closed")
			}
		})
	}
}

func TestGoPlusSolanaDetectsDocumentedCreatorsField(t *testing.T) {
	record := strings.Replace(
		completeSolanaRiskRecord(solanaUSDCMint),
		`"creators":[]`,
		`"creators":[{"address":"`+solanaUSDCMint+`","malicious_address":1}]`,
		1,
	)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"code":1,"message":"OK","result":{"` + solanaUSDCMint +
			`":` + record + `}}`))
	}))
	defer server.Close()

	got, err := NewGoPlusSolana(server.URL, "", server.Client(), time.Second).
		TokenRisk(context.Background(), solanaUSDCMint)
	if err != nil {
		t.Fatal(err)
	}
	if !got.Found || !got.Unsafe || got.Category != "malicious" {
		t.Fatalf("documented creators threat = %#v", got)
	}
}

func TestGoPlusSolanaIncompleteSafeRecordFailsClosed(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"code":1,"message":"OK","result":{"` + solanaUSDCMint +
			`":{"creators":[]}}}`))
	}))
	defer server.Close()
	if _, err := NewGoPlusSolana(server.URL, "", server.Client(), time.Second).
		TokenRisk(context.Background(), solanaUSDCMint); err == nil {
		t.Fatal("partial non-malicious Solana risk record must not establish safety")
	}
}

func TestGoPlusSolanaRejectsInvalidMintBeforeNetwork(t *testing.T) {
	var calls int
	server := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		calls++
	}))
	defer server.Close()
	if _, err := NewGoPlusSolana(server.URL, "", server.Client(), time.Second).
		TokenRisk(context.Background(), "not-a-mint"); err == nil {
		t.Fatal("invalid mint must fail before network")
	}
	if calls != 0 {
		t.Fatalf("invalid mint reached provider %d times", calls)
	}
}

func TestGoPlusLiveSupportedSolanaTokenRisk(t *testing.T) {
	if os.Getenv("KT_LIVE_GOPLUS") != "1" {
		t.Skip("set KT_LIVE_GOPLUS=1 for the read-only GoPlus Solana catalog smoke test")
	}
	client := NewGoPlusSolana(
		"https://api.gopluslabs.io/api/v1/solana/token_security",
		"",
		http.DefaultClient,
		15*time.Second,
	)
	for _, mint := range []string{
		solanaUSDCMint,
		"Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB",
		"JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN",
		"DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263",
		"2b1kV6DkPAnxd5ixfnxCpjxmKwqjjaYmCZfHsFu24GXo",
	} {
		got, err := client.TokenRisk(context.Background(), mint)
		if err != nil {
			t.Fatalf("live GoPlus Solana response for %s rejected: %v", mint, err)
		}
		if !got.Found {
			t.Fatalf("live GoPlus Solana response for %s has no reviewed record", mint)
		}
	}
}
