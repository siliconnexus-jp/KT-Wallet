package upstream

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"
)

const (
	tronAccountAddress = "TJmmqjb1DK9TTZbQXzRQ2AuA94z4gKAPFh"
	tronAccountHex     = "41608f8da72479edc7dd921e4c30bb7e7cddbe722e"
	tronUSDTAddress    = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"
)

func tronAccountClient(t *testing.T, payload string) *Tron {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet || r.URL.Path != "/v1/accounts/"+tronAccountAddress {
			t.Errorf("unexpected account request: %s %s", r.Method, r.URL.RequestURI())
			http.Error(w, "unexpected request", http.StatusBadRequest)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(payload))
	}))
	t.Cleanup(server.Close)
	return NewTron(server.URL, server.Client(), time.Second)
}

func TestTronAccountBindsIdentityAndRejectsAmbiguousFinancialData(t *testing.T) {
	t.Parallel()
	validRow := `{"address":"` + tronAccountHex + `","balance":3577033,"trc20":[{"` +
		tronUSDTAddress + `":"1000000"}]}`
	tests := []struct {
		name    string
		payload string
	}{
		{"unknown envelope member", `{"data":[` + validRow + `],"success":true,"unexpected":1}`},
		{"false success", `{"data":[` + validRow + `],"success":false}`},
		{"missing data", `{"success":true}`},
		{"duplicate data ending valid", `{"data":[],"data":[` + validRow + `],"success":true}`},
		{"data alias collision", `{"Data":[],"data":[` + validRow + `],"success":true}`},
		{"multiple account rows", `{"data":[` + validRow + `,` + validRow + `],"success":true}`},
		{"wrong account identity", `{"data":[` +
			`{"address":"410000000000000000000000000000000000000000","balance":3577033}],"success":true}`},
		{"missing account identity", `{"data":[{"balance":3577033}],"success":true}`},
		{"balance alias", `{"data":[{"address":"` + tronAccountHex + `","Balance":3577033}],"success":true}`},
		{"duplicate balance ending valid", `{"data":[{"address":"` + tronAccountHex +
			`","balance":1,"balance":3577033}],"success":true}`},
		{"string balance", `{"data":[{"address":"` + tronAccountHex + `","balance":"3577033"}],"success":true}`},
		{"negative balance", `{"data":[{"address":"` + tronAccountHex + `","balance":-1}],"success":true}`},
		{"fractional balance", `{"data":[{"address":"` + tronAccountHex + `","balance":1.5}],"success":true}`},
		{"trc20 alias", `{"data":[{"address":"` + tronAccountHex + `","trc20":[],"TRC20":[]}],"success":true}`},
		{"duplicate token identity", `{"data":[{"address":"` + tronAccountHex + `","trc20":[{"` +
			tronUSDTAddress + `":"1"},{"` + tronUSDTAddress + `":"2"}]}],"success":true}`},
		{"duplicate contract ending valid", `{"data":[{"address":"` + tronAccountHex + `","trc20":[{"` +
			tronUSDTAddress + `":"1","` + tronUSDTAddress + `":"1000000"}]}],"success":true}`},
		{"invalid token identity", `{"data":[{"address":"` + tronAccountHex + `","trc20":[{"not-a-contract":"1"}]}],"success":true}`},
		{"non decimal token amount", `{"data":[{"address":"` + tronAccountHex + `","trc20":[{"` +
			tronUSDTAddress + `":"not-a-number"}]}],"success":true}`},
		{"negative token amount", `{"data":[{"address":"` + tronAccountHex + `","trc20":[{"` +
			tronUSDTAddress + `":"-1"}]}],"success":true}`},
		{"uint256 overflow", `{"data":[{"address":"` + tronAccountHex + `","trc20":[{"` +
			tronUSDTAddress + `":"115792089237316195423570985008687907853269984665640564039457584007913129639936"}]}],"success":true}`},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			_, err := tronAccountClient(t, tc.payload).GetAccount(context.Background(), tronAccountAddress)
			if err == nil {
				t.Fatal("ambiguous, unbound or invalid TRON account data must fail closed")
			}
		})
	}
}

func TestTronAccountAcceptsBoundBalancesAndExplicitEmptyAccount(t *testing.T) {
	t.Parallel()
	payload := `{"data":[{"account_resource":{"energy_window_optimized":true},"address":"` +
		tronAccountHex + `","create_time":1535012682000,"balance":3577033,"trc20":[{"` +
		tronUSDTAddress + `":"1000000"}],"frozenV2":[{}, {"type":"ENERGY"}]}],` +
		`"success":true,"meta":{"at":1785814844638,"page_size":1}}`
	account, err := tronAccountClient(t, payload).GetAccount(context.Background(), tronAccountAddress)
	if err != nil {
		t.Fatalf("valid account rejected: %v", err)
	}
	if account.Balance.String() != "3577033" || account.TRC20[tronUSDTAddress] != "1000000" {
		t.Fatalf("unexpected account balances: %+v", account)
	}

	empty, err := tronAccountClient(t, `{"data":[],"success":true,"meta":{"page_size":0}}`).
		GetAccount(context.Background(), tronAccountAddress)
	if err != nil {
		t.Fatalf("explicit never-activated account rejected: %v", err)
	}
	if empty.Balance.Sign() != 0 || len(empty.TRC20) != 0 {
		t.Fatalf("unexpected empty account balances: %+v", empty)
	}

	activeZero, err := tronAccountClient(t, `{"data":[{"address":"`+tronAccountHex+
		`","trc20":[]}],"success":true}`).GetAccount(context.Background(), tronAccountAddress)
	if err != nil || activeZero.Balance.Sign() != 0 || len(activeZero.TRC20) != 0 {
		t.Fatalf("valid protobuf zero-value account rejected: account=%+v err=%v", activeZero, err)
	}
}

func TestTronLiveAccountSchema(t *testing.T) {
	if os.Getenv("KT_LIVE_TRON_ACCOUNT") != "1" {
		t.Skip("set KT_LIVE_TRON_ACCOUNT=1 for the read-only TronGrid account schema smoke test")
	}
	account, err := NewTron("https://api.trongrid.io", http.DefaultClient, 15*time.Second).
		GetAccount(context.Background(), tronAccountAddress)
	if err != nil {
		t.Fatalf("live TronGrid account response rejected by reviewed schema: %v", err)
	}
	if account.Balance.Sign() < 0 {
		t.Fatalf("live TronGrid returned a negative native balance: %s", account.Balance)
	}
}
