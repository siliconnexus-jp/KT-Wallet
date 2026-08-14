package upstream

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func tronBalancePayload(holder, contract, word string) string {
	holderHex, _ := tronBase58AddressHex(holder)
	parameter := strings.Repeat("0", 24) + holderHex[2:]
	return `{"transaction":{"raw_data":{"contract":[{"parameter":{"value":{` +
		`"owner_address":"` + holder + `","contract_address":"` + contract + `",` +
		`"data":"70a08231` + parameter + `"},` +
		`"type_url":"type.googleapis.com/protocol.TriggerSmartContract"},` +
		`"type":"TriggerSmartContract"}]},"visible":true},` +
		`"constant_result":["` + word + `"],"result":{"result":true}}`
}

func TestTronTRC20BalanceUsesBoundConstantContractResult(t *testing.T) {
	t.Parallel()
	const word = "0000000000000000000000000000000000000000000000000000000000989680"
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || r.URL.Path != "/wallet/triggerconstantcontract" {
			t.Fatalf("unexpected request: %s %s", r.Method, r.URL.Path)
		}
		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Fatal(err)
		}
		wantParameter := strings.Repeat("0", 24) + tronAccountHex[2:]
		if body["owner_address"] != tronAccountAddress ||
			body["contract_address"] != tronUSDTAddress ||
			body["function_selector"] != "balanceOf(address)" ||
			body["parameter"] != wantParameter || body["visible"] != true {
			t.Fatalf("unexpected balanceOf request: %v", body)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(tronBalancePayload(tronAccountAddress, tronUSDTAddress, word)))
	}))
	t.Cleanup(server.Close)

	balance, err := NewTron(server.URL, server.Client(), time.Second).
		TRC20Balance(context.Background(), tronAccountAddress, tronUSDTAddress)
	if err != nil {
		t.Fatalf("valid balanceOf response rejected: %v", err)
	}
	if balance.String() != "10000000" {
		t.Fatalf("balance = %s, want 10000000", balance)
	}
}

func TestTronTRC20BalanceRejectsUnboundOrMalformedFinancialData(t *testing.T) {
	t.Parallel()
	const word = "0000000000000000000000000000000000000000000000000000000000989680"
	valid := tronBalancePayload(tronAccountAddress, tronUSDTAddress, word)
	tests := []struct {
		name    string
		payload string
	}{
		{"wrong holder", strings.Replace(valid, tronAccountAddress, tronUSDTAddress, 1)},
		{"owner alias", strings.Replace(valid, `"owner_address":`, `"Owner_address":"x","owner_address":`, 1)},
		{"duplicate result", strings.Replace(valid, `"constant_result":`, `"constant_result":[],"constant_result":`, 1)},
		{"short result", strings.Replace(valid, word, "01", 1)},
		{"failed call", strings.Replace(valid, `"result":true`, `"result":false`, 1)},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				_, _ = w.Write([]byte(tc.payload))
			}))
			defer server.Close()
			if balance, err := NewTron(server.URL, server.Client(), time.Second).
				TRC20Balance(context.Background(), tronAccountAddress, tronUSDTAddress); err == nil {
				t.Fatalf("invalid response returned balance %s", balance)
			}
		})
	}
}
