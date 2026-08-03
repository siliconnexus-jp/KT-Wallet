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

const testApprovalOwner = "0x85f6be9460291e86e0fb49b07d0a83cc5f7206cd"

func TestGoPlusApprovalsRequiresExplicitPublicOwnerRequestAndSanitizesRows(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/56" {
			t.Fatalf("path = %q", r.URL.Path)
		}
		if got := r.URL.Query().Get("addresses"); got != testApprovalOwner {
			t.Fatalf("addresses = %q", got)
		}
		if len(r.URL.Query()) != 1 {
			t.Fatalf("unexpected query fields: %v", r.URL.Query())
		}
		if got := r.Header.Get("Authorization"); got != "Bearer approval-token" {
			t.Fatalf("authorization = %q", got)
		}
		_, _ = fmt.Fprint(w, `{
          "code":1,"message":"ok","result":[{
            "token_address":"0x55d398326f99059ff775485246999027b3197955",
            "token_name":"Tether\n\u202eUSD","token_symbol":"USDT","decimals":18,
            "balance":"12.5","malicious_address":0,"malicious_behavior":[],
            "approved_list":[{
              "approved_contract":"0x10ed43c718714eb63d5aa57b78b54704e256024e",
              "approved_amount":"Unlimited","approved_time":1737626832,
              "hash":"0x5cc9b7fb572b65b932b56167079883fd0e1ba349750c68c9fa260a09cc4e1dbb",
              "address_info":{"contract_name":"PancakeRouter","tag":"Pancakeswap",
                "doubt_list":0,"trust_list":1,"malicious_behavior":[]}
            }]
          }]}`)
	}))
	defer server.Close()

	rows, err := NewGoPlusApprovals(server.URL, "approval-token", server.Client(), time.Second).
		TokenApprovals(context.Background(), "56", testApprovalOwner)
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 1 {
		t.Fatalf("rows = %#v", rows)
	}
	row := rows[0]
	if row.TokenName != "TetherUSD" || row.TokenSymbol != "USDT" || row.Decimals != 18 {
		t.Fatalf("token metadata = %#v", row)
	}
	if !row.Unlimited || row.Amount != "Unlimited" || row.TokenRisky || row.SpenderRisky {
		t.Fatalf("approval flags = %#v", row)
	}
	if !row.SpenderTrusted || row.SpenderName != "PancakeRouter" || row.SpenderTag != "Pancakeswap" {
		t.Fatalf("spender metadata = %#v", row)
	}
}

func TestGoPlusApprovalsSurfacesTokenAndSpenderRiskWithoutCallingZeroSafe(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = fmt.Fprint(w, `{"code":1,"result":[{
          "token_address":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "token_name":"Risk","token_symbol":"RISK","decimals":"18","balance":"0",
          "malicious_address":"1","malicious_behavior":["gas_abuse"],
          "approved_list":[{"approved_contract":"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            "approved_amount":"1.25E+9","approved_time":"1","hash":"",
            "address_info":{"contract_name":null,"tag":null,"doubt_list":"1",
              "trust_list":"0","malicious_behavior":["phishing"]}}]}]}`)
	}))
	defer server.Close()

	rows, err := NewGoPlusApprovals(server.URL, "", server.Client(), time.Second).
		TokenApprovals(context.Background(), "1", testApprovalOwner)
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 1 || !rows[0].TokenRisky || !rows[0].SpenderRisky || rows[0].Unlimited {
		t.Fatalf("rows = %#v", rows)
	}
}

func TestGoPlusApprovalsEmptyIsValidOnlyForCompleteResponse(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = fmt.Fprint(w, `{"code":1,"message":"ok","result":[]}`)
	}))
	defer server.Close()
	rows, err := NewGoPlusApprovals(server.URL, "", server.Client(), time.Second).
		TokenApprovals(context.Background(), "1", testApprovalOwner)
	if err != nil || len(rows) != 0 {
		t.Fatalf("rows=%#v err=%v", rows, err)
	}
}

func TestGoPlusApprovalsFailsClosedOnPartialMalformedAndOversizedData(t *testing.T) {
	tests := map[string]string{
		"partial":      `{"code":2,"result":[]}`,
		"not-list":     `{"code":1,"result":{}}`,
		"bad-owner":    `{"code":1,"result":[{"token_address":"bad","decimals":18,"balance":"0","approved_list":[]}]}`,
		"bad-decimals": `{"code":1,"result":[{"token_address":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","token_name":"A","token_symbol":"A","decimals":37,"balance":"0","approved_list":[]}]}`,
		"bad-row":      `{"code":1,"result":[{"token_address":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","token_name":"A","token_symbol":"A","decimals":18,"balance":"0","approved_list":[{"approved_contract":"bad","approved_amount":"1","approved_time":1,"hash":""}]}]}`,
		"oversized":    strings.Repeat("x", maxGoPlusResponseBytes+1),
	}
	for name, body := range tests {
		t.Run(name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				_, _ = w.Write([]byte(body))
			}))
			defer server.Close()
			rows, err := NewGoPlusApprovals(server.URL, "", server.Client(), time.Second).
				TokenApprovals(context.Background(), "1", testApprovalOwner)
			if err == nil || rows != nil {
				t.Fatalf("rows=%#v err=%v", rows, err)
			}
		})
	}
}

func TestGoPlusApprovalsRejectsInvalidOwnerBeforeNetwork(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		t.Fatal("invalid owner must not reach provider")
	}))
	defer server.Close()
	_, err := NewGoPlusApprovals(server.URL, "", server.Client(), time.Second).
		TokenApprovals(context.Background(), "1", "0x1234")
	if err == nil {
		t.Fatal("expected invalid owner error")
	}
}

func TestGoPlusApprovalsDoesNotFollowRedirectOrForwardCredentials(t *testing.T) {
	hits := 0
	destination := httptest.NewServer(http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) {
		hits++
		if r.Header.Get("Authorization") != "" {
			t.Fatal("redirect destination received authorization")
		}
	}))
	defer destination.Close()
	source := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Location", destination.URL)
		w.WriteHeader(http.StatusFound)
	}))
	defer source.Close()
	_, err := NewGoPlusApprovals(source.URL, "secret", source.Client(), time.Second).
		TokenApprovals(context.Background(), "1", testApprovalOwner)
	if err == nil || hits != 0 {
		t.Fatalf("err=%v destination hits=%d", err, hits)
	}
}
