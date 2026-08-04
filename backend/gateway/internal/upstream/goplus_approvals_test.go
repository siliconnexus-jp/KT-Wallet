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
			"chain_id":"56",
            "token_name":"Tether\n\u202eUSD","token_symbol":"USDT","decimals":18,
			"balance":"12.5","is_open_source":1,"malicious_address":0,"malicious_behavior":[],
            "approved_list":[{
              "approved_contract":"0x10ed43c718714eb63d5aa57b78b54704e256024e",
              "approved_amount":"Unlimited","approved_time":1737626832,
			  "initial_approval_time":1737626800,
			  "initial_approval_hash":"0x5cc9b7fb572b65b932b56167079883fd0e1ba349750c68c9fa260a09cc4e1dbb",
              "hash":"0x5cc9b7fb572b65b932b56167079883fd0e1ba349750c68c9fa260a09cc4e1dbb",
              "address_info":{"contract_name":"PancakeRouter","tag":"Pancakeswap",
				"creator_address":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
				"is_contract":1,"doubt_list":0,"malicious_behavior":[],
				"deployed_time":1600000000,"trust_list":1,"is_open_source":1}
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
		  "chain_id":"1","token_name":"Risk","token_symbol":"RISK","decimals":18,"balance":"0",
		  "is_open_source":1,
          "malicious_address":"1","malicious_behavior":["gas_abuse"],
          "approved_list":[{"approved_contract":"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
			"approved_amount":"1.25E+9","approved_time":1,
			"initial_approval_time":1,"initial_approval_hash":"","hash":"",
            "address_info":{"contract_name":null,"tag":null,"doubt_list":"1",
			  "creator_address":null,"is_contract":0,"malicious_behavior":["phishing"],
			  "deployed_time":null,"trust_list":"0","is_open_source":0}}]}]}`)
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

func validApprovalTokenJSON(chainID string) string {
	return validApprovalTokenWithRowsJSON(chainID, "")
}

func validApprovalTokenWithRowsJSON(chainID, rows string) string {
	return `{"token_address":"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",` +
		`"chain_id":"` + chainID + `","token_name":"Token","token_symbol":"TOK",` +
		`"decimals":18,"balance":"1","is_open_source":1,` +
		`"malicious_address":0,"malicious_behavior":[],"approved_list":[` + rows + `]}`
}

func validApprovalRowJSON() string {
	return `{"approved_contract":"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",` +
		`"approved_amount":"1","approved_time":1,"initial_approval_time":1,` +
		`"initial_approval_hash":"","hash":"","address_info":` + validApprovalAddressInfoJSON() + `}`
}

func validApprovalAddressInfoJSON() string {
	return `{"contract_name":"Router","tag":"App",` +
		`"creator_address":"0xcccccccccccccccccccccccccccccccccccccccc",` +
		`"is_contract":1,"doubt_list":0,"malicious_behavior":[],` +
		`"deployed_time":1,"trust_list":1,"is_open_source":1}`
}

func TestGoPlusApprovalsRejectsAmbiguousNestedEvidenceAndDuplicateRows(t *testing.T) {
	row := validApprovalRowJSON()
	tests := map[string]string{
		"unknown approval member": strings.Replace(
			row,
			`"address_info":`,
			`"extra":1,"address_info":`,
			1,
		),
		"unknown address-info member": strings.Replace(
			row,
			`"contract_name":`,
			`"extra":1,"contract_name":`,
			1,
		),
		"invalid spender risk flag": strings.Replace(
			row,
			`"doubt_list":0`,
			`"doubt_list":"yes"`,
			1,
		),
		"future evidence time": strings.Replace(
			row,
			`"approved_time":1`,
			`"approved_time":4102444800`,
			1,
		),
		"missing initial evidence": strings.Replace(
			row,
			`"initial_approval_time":1,"initial_approval_hash":"",`,
			``,
			1,
		),
		"duplicate token spender": row + `,` + row,
	}
	for name, rows := range tests {
		t.Run(name, func(t *testing.T) {
			body := `{"code":1,"message":"ok","result":[` +
				validApprovalTokenWithRowsJSON("1", rows) + `]}`
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				_, _ = w.Write([]byte(body))
			}))
			defer server.Close()
			if _, err := NewGoPlusApprovals(server.URL, "", server.Client(), time.Second).
				TokenApprovals(context.Background(), "1", testApprovalOwner); err == nil {
				t.Fatal("ambiguous nested approval evidence must fail closed")
			}
		})
	}
}

func TestGoPlusApprovalsRejectsDuplicateTokenIdentity(t *testing.T) {
	first := validApprovalTokenWithRowsJSON("1", validApprovalRowJSON())
	second := validApprovalTokenWithRowsJSON(
		"1",
		strings.Replace(
			validApprovalRowJSON(),
			"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
			"0xdddddddddddddddddddddddddddddddddddddddd",
			1,
		),
	)
	body := `{"code":1,"message":"ok","result":[` + first + `,` + second + `]}`
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(body))
	}))
	defer server.Close()
	if _, err := NewGoPlusApprovals(server.URL, "", server.Client(), time.Second).
		TokenApprovals(context.Background(), "1", testApprovalOwner); err == nil {
		t.Fatal("duplicate token identity with conflicting rows must fail closed")
	}
}

func TestGoPlusLiveApprovalContract(t *testing.T) {
	if os.Getenv("KT_LIVE_GOPLUS") != "1" {
		t.Skip("set KT_LIVE_GOPLUS=1 for the read-only public zero-address approval smoke test")
	}
	_, err := NewGoPlusApprovals(
		"https://api.gopluslabs.io/api/v2/token_approval_security",
		"",
		http.DefaultClient,
		15*time.Second,
	).TokenApprovals(
		context.Background(),
		"1",
		"0x0000000000000000000000000000000000000000",
	)
	if err != nil {
		t.Fatalf("live GoPlus approval response rejected: %v", err)
	}
}

func TestGoPlusApprovalsRejectsAmbiguousUnboundOrMalformedRiskData(t *testing.T) {
	valid := validApprovalTokenJSON("1")
	tests := map[string]string{
		"unknown envelope member": `{"code":1,"message":"ok","result":[` + valid + `],"extra":1}`,
		"duplicate envelope code": `{"code":2,"code":1,"message":"ok","result":[` + valid + `]}`,
		"wrong response chain":    `{"code":1,"message":"ok","result":[` + validApprovalTokenJSON("56") + `]}`,
		"unknown token member": `{"code":1,"message":"ok","result":[` +
			strings.Replace(valid, `"approved_list":[]`, `"extra":1,"approved_list":[]`, 1) + `]}`,
		"invalid token risk flag": `{"code":1,"message":"ok","result":[` +
			strings.Replace(valid, `"malicious_address":0`, `"malicious_address":"yes"`, 1) + `]}`,
		"duplicate token risk flag": `{"code":1,"message":"ok","result":[` +
			strings.Replace(valid, `"malicious_address":0`, `"malicious_address":1,"malicious_address":0`, 1) + `]}`,
	}
	for name, body := range tests {
		t.Run(name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				_, _ = w.Write([]byte(body))
			}))
			defer server.Close()
			if _, err := NewGoPlusApprovals(server.URL, "", server.Client(), time.Second).
				TokenApprovals(context.Background(), "1", testApprovalOwner); err == nil {
				t.Fatal("ambiguous, request-unbound or malformed approval response must fail closed")
			}
		})
	}
}
