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

const solanaStatusSignature = "5KtPn3E1Z9ezPTVYPQ7V2FZx5zRW2aYw5gCz6tNQ8crShXKQ3Fd6ztqQmDN7Hjz3EN3YHhuYxqUjQK4rDgVjSxqR"

func solanaStatusResultClient(t *testing.T, result string) (*Solana, *fakeNode) {
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

func TestSolanaSignatureStatusRejectsAmbiguousOrIncompleteResults(t *testing.T) {
	t.Parallel()
	success := `{"slot":48,"confirmations":null,"err":null,"status":{"Ok":null},"confirmationStatus":"finalized"}`
	tests := []struct {
		name   string
		result string
	}{
		{"missing context", `{"value":[` + success + `]}`},
		{"unknown result member", `{"context":{"slot":82},"value":[` + success + `],"extra":true}`},
		{"missing context slot", `{"context":{},"value":[` + success + `]}`},
		{"negative context slot", `{"context":{"slot":-1},"value":[` + success + `]}`},
		{"overflow context slot", `{"context":{"slot":18446744073709551616},"value":[` + success + `]}`},
		{"malformed API version", `{"context":{"slot":82,"apiVersion":" bad "},"value":[` + success + `]}`},
		{"duplicate context slot", `{"context":{"slot":82,"slot":83},"value":[` + success + `]}`},
		{"two values for one signature", `{"context":{"slot":82},"value":[` + success + `,null]}`},
		{"unknown entry member", `{"context":{"slot":82},"value":[{"slot":48,"confirmations":null,"err":null,"status":{"Ok":null},"confirmationStatus":"finalized","extra":true}]}`},
		{"missing slot", `{"context":{"slot":82},"value":[{"confirmations":null,"err":null,"status":{"Ok":null},"confirmationStatus":"finalized"}]}`},
		{"missing confirmations", `{"context":{"slot":82},"value":[{"slot":48,"err":null,"status":{"Ok":null},"confirmationStatus":"finalized"}]}`},
		{"missing status", `{"context":{"slot":82},"value":[{"slot":48,"confirmations":null,"err":null,"confirmationStatus":"finalized"}]}`},
		{"negative transaction slot", `{"context":{"slot":82},"value":[{"slot":-1,"confirmations":null,"err":null,"status":{"Ok":null},"confirmationStatus":"finalized"}]}`},
		{"overflow transaction slot", `{"context":{"slot":82},"value":[{"slot":18446744073709551616,"confirmations":null,"err":null,"status":{"Ok":null},"confirmationStatus":"finalized"}]}`},
		{"future transaction slot", `{"context":{"slot":47},"value":[` + success + `]}`},
		{"negative confirmations", `{"context":{"slot":82},"value":[{"slot":48,"confirmations":-1,"err":null,"status":{"Ok":null},"confirmationStatus":"confirmed"}]}`},
		{"string confirmations", `{"context":{"slot":82},"value":[{"slot":48,"confirmations":"2","err":null,"status":{"Ok":null},"confirmationStatus":"confirmed"}]}`},
		{"finalized with confirmations", `{"context":{"slot":82},"value":[{"slot":48,"confirmations":3,"err":null,"status":{"Ok":null},"confirmationStatus":"finalized"}]}`},
		{"duplicate err", `{"context":{"slot":82},"value":[{"slot":48,"confirmations":null,"err":null,"err":"AccountInUse","status":{"Err":"AccountInUse"},"confirmationStatus":"finalized"}]}`},
		{"success err conflicts with status", `{"context":{"slot":82},"value":[{"slot":48,"confirmations":null,"err":null,"status":{"Err":"AccountInUse"},"confirmationStatus":"finalized"}]}`},
		{"failure err conflicts with status", `{"context":{"slot":82},"value":[{"slot":48,"confirmations":2,"err":"AccountInUse","status":{"Ok":null},"confirmationStatus":"confirmed"}]}`},
		{"different failure details", `{"context":{"slot":82},"value":[{"slot":48,"confirmations":2,"err":"AccountInUse","status":{"Err":"BlockhashNotFound"},"confirmationStatus":"confirmed"}]}`},
		{"numeric transaction error", `{"context":{"slot":82},"value":[{"slot":48,"confirmations":2,"err":7,"status":{"Err":7},"confirmationStatus":"confirmed"}]}`},
		{"empty transaction error", `{"context":{"slot":82},"value":[{"slot":48,"confirmations":2,"err":{},"status":{"Err":{}},"confirmationStatus":"confirmed"}]}`},
		{"multiple transaction errors", `{"context":{"slot":82},"value":[{"slot":48,"confirmations":2,"err":{"AccountInUse":null,"BlockhashNotFound":null},"status":{"Err":{"AccountInUse":null,"BlockhashNotFound":null}},"confirmationStatus":"confirmed"}]}`},
		{"both deprecated status variants", `{"context":{"slot":82},"value":[{"slot":48,"confirmations":2,"err":null,"status":{"Ok":null,"Err":"AccountInUse"},"confirmationStatus":"confirmed"}]}`},
		{"unknown confirmation status", `{"context":{"slot":82},"value":[{"slot":48,"confirmations":2,"err":null,"status":{"Ok":null},"confirmationStatus":"safe"}]}`},
		{"numeric confirmation status", `{"context":{"slot":82},"value":[{"slot":48,"confirmations":2,"err":null,"status":{"Ok":null},"confirmationStatus":1}]}`},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			client, _ := solanaStatusResultClient(t, tc.result)
			if status, err := client.SignatureStatus(context.Background(), solanaStatusSignature); err == nil {
				t.Fatalf("ambiguous Solana signature status must fail closed, got %q", status)
			}
		})
	}
}

func TestSolanaSignatureStatusLiveOfficialShape(t *testing.T) {
	if os.Getenv("KT_LIVE_SOLANA_STATUS") != "1" {
		t.Skip("set KT_LIVE_SOLANA_STATUS=1 for the read-only Solana status schema smoke test")
	}
	client := NewSolana(
		[]string{"https://api.devnet.solana.com"},
		clock.Real{},
		http.DefaultClient,
		15*time.Second,
	)
	status, err := client.SignatureStatus(
		context.Background(),
		"23J1Vn2WniBbsdmGYVgoViGhZmrgErjUKbaQ1eikWEhiW4KjTAVjNL6ZwmuYtWro8L1oXxyPBGAJwAUCEgXvzzbX",
	)
	if err != nil || status != "confirmed" {
		t.Fatalf("live finalized Solana transaction rejected by reviewed status schema: status=%q err=%v", status, err)
	}
}

func TestSolanaSignatureStatusAcceptsExactOfficialShapes(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name   string
		result string
		want   string
	}{
		{"not found", `{"context":{"slot":82},"value":[null]}`, "unknown"},
		{"processed", `{"context":{"slot":82},"value":[{"slot":81,"confirmations":0,"err":null,"status":{"Ok":null},"confirmationStatus":"processed"}]}`, "pending"},
		{"processed failure", `{"context":{"slot":82},"value":[{"slot":81,"confirmations":0,"err":"AccountInUse","status":{"Err":"AccountInUse"},"confirmationStatus":"processed"}]}`, "pending"},
		{"confirmed", `{"context":{"slot":82,"apiVersion":"2.3.0"},"value":[{"slot":80,"confirmations":2,"err":null,"status":{"Ok":null},"confirmationStatus":"confirmed"}]}`, "confirmed"},
		{"finalized", `{"context":{"slot":82},"value":[{"slot":48,"confirmations":null,"err":null,"status":{"Ok":null},"confirmationStatus":"finalized"}]}`, "confirmed"},
		{"legacy unknown confirmation", `{"context":{"slot":82},"value":[{"slot":48,"confirmations":null,"err":null,"status":{"Ok":null},"confirmationStatus":null}]}`, "unknown"},
		{"legacy unknown failed confirmation", `{"context":{"slot":82},"value":[{"slot":48,"confirmations":null,"err":"AccountInUse","status":{"Err":"AccountInUse"},"confirmationStatus":null}]}`, "unknown"},
		{"failed enum", `{"context":{"slot":82},"value":[{"slot":80,"confirmations":2,"err":"AccountInUse","status":{"Err":"AccountInUse"},"confirmationStatus":"confirmed"}]}`, "failed"},
		{"failed instruction", `{"context":{"slot":82},"value":[{"slot":80,"confirmations":2,"err":{"InstructionError":[0,"Custom"]},"status":{"Err":{"InstructionError":[0,"Custom"]}},"confirmationStatus":"confirmed"}]}`, "failed"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			client, _ := solanaStatusResultClient(t, tc.result)
			got, err := client.SignatureStatus(context.Background(), solanaStatusSignature)
			if err != nil || got != tc.want {
				t.Fatalf("exact Solana signature status rejected: got=%q want=%q err=%v", got, tc.want, err)
			}
		})
	}
}

func TestSolanaSignatureStatusRejectsInvalidSignatureBeforeNetwork(t *testing.T) {
	t.Parallel()
	client, node := solanaStatusResultClient(t, `{"context":{"slot":82},"value":[null]}`)
	for _, signature := range []string{
		"not-a-signature",
		strings.Repeat("1", 63),
		strings.Repeat("1", 65),
		strings.Repeat("z", 89),
	} {
		if _, err := client.SignatureStatus(context.Background(), signature); err == nil {
			t.Fatalf("invalid signature %q must fail before network access", signature)
		}
	}
	if got := node.hits.Load(); got != 0 {
		t.Fatalf("invalid Solana signatures reached upstream %d times", got)
	}
}
