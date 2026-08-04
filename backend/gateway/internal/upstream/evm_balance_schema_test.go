package upstream

import (
	"context"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"

	"ktwallet/gateway/internal/clock"
)

const (
	evmBalanceHolder   = "0x1234567890abcdef1234567890abcdef12345678"
	evmBalanceContract = "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd"
)

func evmBalanceResultClient(t *testing.T, result string) (*EVM, *fakeNode) {
	t.Helper()
	node := newFakeNode(t, func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"jsonrpc":"2.0","id":1,"result":` + result + `}`))
	})
	return NewEVM(
		"eth-mainnet",
		[]string{node.srv.URL},
		clock.NewFake(time.Unix(1_700_000_000, 0)),
		node.srv.Client(),
		time.Second,
	), node
}

func TestEVMNativeBalanceRejectsNonCanonicalOrOutOfRangeQuantities(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name   string
		result string
	}{
		{"empty quantity", `"0x"`},
		{"missing prefix", `"1"`},
		{"uppercase prefix", `"0X1"`},
		{"leading zero", `"0x01"`},
		{"negative", `"-1"`},
		{"non hex", `"0xgg"`},
		{"not a string", `1`},
		{"uint256 overflow", `"0x1` + strings.Repeat("0", 64) + `"`},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			client, _ := evmBalanceResultClient(t, tc.result)
			if _, err := client.GetBalance(context.Background(), evmBalanceHolder); err == nil {
				t.Fatal("non-canonical EVM balance quantity must fail closed")
			}
		})
	}
}

func TestEVMLiveBalanceShapes(t *testing.T) {
	if os.Getenv("KT_LIVE_EVM_BALANCE") != "1" {
		t.Skip("set KT_LIVE_EVM_BALANCE=1 for the read-only EVM balance schema smoke test")
	}
	client := NewEVM(
		"eth-mainnet",
		[]string{"https://ethereum-rpc.publicnode.com"},
		clock.Real{},
		http.DefaultClient,
		15*time.Second,
	)
	native, err := client.GetBalance(context.Background(), "0x0000000000000000000000000000000000000000")
	if err != nil || native.Sign() < 0 {
		t.Fatalf("live native balance rejected by reviewed quantity schema: value=%v err=%v", native, err)
	}
	token, err := client.TokenBalance(
		context.Background(),
		"0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
		"0x0000000000000000000000000000000000000000",
	)
	if err != nil || token.Sign() < 0 {
		t.Fatalf("live USDC balanceOf rejected by reviewed ABI schema: value=%v err=%v", token, err)
	}
}

func TestEVMTokenBalanceRequiresOneCanonicalABIUint256Word(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name   string
		result string
	}{
		{"empty return", `"0x"`},
		{"quantity instead of data", `"0x0"`},
		{"short byte", `"0x01"`},
		{"31 bytes", `"0x` + strings.Repeat("00", 31) + `"`},
		{"33 bytes", `"0x` + strings.Repeat("00", 33) + `"`},
		{"missing prefix", `"` + strings.Repeat("00", 32) + `"`},
		{"non hex", `"0x` + strings.Repeat("00", 31) + `gg"`},
		{"not a string", `0`},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			client, _ := evmBalanceResultClient(t, tc.result)
			if _, err := client.TokenBalance(
				context.Background(),
				evmBalanceContract,
				evmBalanceHolder,
			); err == nil {
				t.Fatal("non-canonical ERC-20 balanceOf return must fail closed")
			}
		})
	}
}

func TestEVMBalancesAcceptCanonicalValuesAndRejectInvalidRequestsPreNetwork(t *testing.T) {
	t.Parallel()
	native, _ := evmBalanceResultClient(t, `"0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"`)
	got, err := native.GetBalance(context.Background(), evmBalanceHolder)
	if err != nil || got.BitLen() != 256 {
		t.Fatalf("canonical uint256 quantity rejected: value=%v err=%v", got, err)
	}

	token, _ := evmBalanceResultClient(t, `"0x`+strings.Repeat("00", 31)+`2a"`)
	got, err = token.TokenBalance(context.Background(), evmBalanceContract, evmBalanceHolder)
	if err != nil || got.String() != "42" {
		t.Fatalf("canonical ABI uint256 rejected: value=%v err=%v", got, err)
	}

	invalid, node := evmBalanceResultClient(t, `"0x0"`)
	if _, err := invalid.GetBalanceAt(context.Background(), "not-an-address", "latest"); err == nil {
		t.Fatal("invalid holder must fail before network access")
	}
	if _, err := invalid.GetBalanceAt(context.Background(), evmBalanceHolder, "safe"); err == nil {
		t.Fatal("unsupported balance block tag must fail before network access")
	}
	if _, err := invalid.TokenBalanceAt(context.Background(), "not-a-contract", evmBalanceHolder, "latest"); err == nil {
		t.Fatal("invalid token contract must fail before network access")
	}
	if _, err := invalid.TokenBalanceAt(context.Background(), evmBalanceContract, "not-a-holder", "pending"); err == nil {
		t.Fatal("invalid token holder must fail before network access")
	}
	if got := node.hits.Load(); got != 0 {
		t.Fatalf("invalid EVM balance request reached upstream %d times", got)
	}
}
