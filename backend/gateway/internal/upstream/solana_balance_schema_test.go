package upstream

import (
	"context"
	"net/http"
	"strings"
	"testing"
	"time"

	"ktwallet/gateway/internal/clock"
)

const (
	solanaBalanceOwner        = "A1TMhSGzQxMr1TboBKtgixKz1sS6REASMxPo1qsyTSJd"
	solanaBalanceMint         = "2cHr7QS3xfuSV8wdxo3ztuF4xbiarF6Nrgx3qpx3HzXR"
	solanaBalanceTokenAccount = "BGocb4GEpbTFm8UFV2VsDSaBXHELPfAXrvd4vtt8QWrA"
)

func solanaResultClient(t *testing.T, result string) (*Solana, *fakeNode) {
	t.Helper()
	node := newFakeNode(t, func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"jsonrpc":"2.0","id":1,"result":` + result + `}`))
	})
	return NewSolana(
		[]string{node.srv.URL},
		clock.NewFake(time.Unix(1_700_000_000, 0)),
		node.srv.Client(),
		time.Second,
	), node
}

func TestSolanaNativeBalanceRejectsAmbiguousOrInvalidFinancialResults(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name   string
		result string
	}{
		{"unknown result member", `{"context":{"slot":1},"value":5,"unexpected":1}`},
		{"missing context", `{"value":5}`},
		{"context alias", `{"Context":{"slot":1},"value":5}`},
		{"missing slot", `{"context":{},"value":5}`},
		{"negative slot", `{"context":{"slot":-1},"value":5}`},
		{"value alias", `{"context":{"slot":1},"Value":5}`},
		{"duplicate value ending valid", `{"context":{"slot":1},"value":1,"value":5}`},
		{"string value", `{"context":{"slot":1},"value":"5"}`},
		{"negative value", `{"context":{"slot":1},"value":-1}`},
		{"u64 overflow", `{"context":{"slot":1},"value":18446744073709551616}`},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			client, _ := solanaResultClient(t, tc.result)
			if _, err := client.GetBalance(context.Background(), solanaBalanceOwner); err == nil {
				t.Fatal("ambiguous or invalid Solana native balance must fail closed")
			}
		})
	}
}

func solanaTokenAccountRow(overrides ...string) string {
	row := `{"pubkey":"` + solanaBalanceTokenAccount + `","account":{` +
		`"data":{"program":"spl-token","parsed":{"info":{` +
		`"isNative":false,"mint":"` + solanaBalanceMint + `","owner":"` + solanaBalanceOwner + `",` +
		`"state":"initialized","tokenAmount":{"amount":"420000000000000","decimals":6,` +
		`"uiAmount":420000000.0,"uiAmountString":"420000000"}},"type":"account"},"space":165},` +
		`"executable":false,"lamports":2039280,"owner":"` + splTokenProgram + `",` +
		`"rentEpoch":18446744073709551615,"space":165}}`
	for i := 0; i+1 < len(overrides); i += 2 {
		row = strings.Replace(row, overrides[i], overrides[i+1], 1)
	}
	return row
}

func solanaTokenAccountResult(overrides ...string) string {
	return `{"context":{"apiVersion":"2.0.15","slot":341197933},"value":[` +
		solanaTokenAccountRow(overrides...) + `]}`
}

func TestSolanaTokenBalanceBindsOwnerMintAndCanonicalAccountData(t *testing.T) {
	t.Parallel()
	wrongOwner := "9xQeWvG816bUx9EPjHmaT23yvVM2ZWbrrpZb9PusVFin"
	wrongMint := "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
	tests := []struct {
		name   string
		result string
	}{
		{"unknown result member", strings.Replace(solanaTokenAccountResult(), `,"value":`, `,"unexpected":1,"value":`, 1)},
		{"missing context", strings.Replace(solanaTokenAccountResult(), `"context":{"apiVersion":"2.0.15","slot":341197933},`, "", 1)},
		{"wrong mint", solanaTokenAccountResult(`"mint":"`+solanaBalanceMint+`"`, `"mint":"`+wrongMint+`"`)},
		{"wrong owner", solanaTokenAccountResult(`"owner":"`+solanaBalanceOwner+`"`, `"owner":"`+wrongOwner+`"`)},
		{"invalid token account pubkey", solanaTokenAccountResult(`"pubkey":"`+solanaBalanceTokenAccount+`"`, `"pubkey":"not-a-pubkey"`)},
		{"wrong account program", solanaTokenAccountResult(`"owner":"`+splTokenProgram+`"`, `"owner":"11111111111111111111111111111111"`)},
		{"wrong parsed type", solanaTokenAccountResult(`"type":"account"`, `"type":"mint"`)},
		{"negative amount", solanaTokenAccountResult(`"amount":"420000000000000"`, `"amount":"-1"`)},
		{"u64 amount overflow", solanaTokenAccountResult(`"amount":"420000000000000"`, `"amount":"18446744073709551616"`)},
		{"duplicate amount ending valid", solanaTokenAccountResult(`"amount":"420000000000000"`, `"amount":"1","amount":"420000000000000"`)},
		{"token amount alias", solanaTokenAccountResult(`"tokenAmount":`, `"TokenAmount":`)},
		{"executable token account", solanaTokenAccountResult(`"executable":false`, `"executable":true`)},
		{"duplicate account counts twice", `{"context":{"apiVersion":"2.0.15","slot":341197933},"value":[` +
			solanaTokenAccountRow() + `,` + solanaTokenAccountRow() + `]}`},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			client, _ := solanaResultClient(t, tc.result)
			if _, err := client.GetTokenBalance(
				context.Background(),
				solanaBalanceOwner,
				solanaBalanceMint,
			); err == nil {
				t.Fatal("unbound or malformed Solana token balance must fail closed")
			}
		})
	}
}

func TestSolanaBalancesAcceptCurrentOfficialShapesAndRejectInvalidRequestsPreNetwork(t *testing.T) {
	t.Parallel()
	native, _ := solanaResultClient(t, `{"context":{"apiVersion":"2.0.15","slot":341197933},"value":2039280}`)
	balance, err := native.GetBalance(context.Background(), solanaBalanceOwner)
	if err != nil || balance.String() != "2039280" {
		t.Fatalf("valid native balance rejected: balance=%v err=%v", balance, err)
	}

	token, _ := solanaResultClient(t, solanaTokenAccountResult())
	total, err := token.GetTokenBalance(context.Background(), solanaBalanceOwner, solanaBalanceMint)
	if err != nil || total.String() != "420000000000000" {
		t.Fatalf("valid token balance rejected: total=%v err=%v", total, err)
	}

	invalid, node := solanaResultClient(t, solanaTokenAccountResult())
	if _, err := invalid.GetTokenBalance(context.Background(), "not-an-owner", solanaBalanceMint); err == nil {
		t.Fatal("invalid owner must fail before network access")
	}
	if _, err := invalid.GetTokenBalance(context.Background(), solanaBalanceOwner, "not-a-mint"); err == nil {
		t.Fatal("invalid mint must fail before network access")
	}
	if got := node.hits.Load(); got != 0 {
		t.Fatalf("invalid Solana identities reached upstream %d times", got)
	}
}
