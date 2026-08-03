package upstream

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func TestEtherscanNullResultIsUnavailableNotEmptyHistory(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"status":"0","message":"chain not supported","result":null}`))
	}))
	defer server.Close()

	client := NewEtherscan(server.URL, "", server.Client(), time.Second)
	txs, err := client.TxList(context.Background(), 56, "0x1111111111111111111111111111111111111111", 20)
	if err == nil {
		t.Fatalf("null result must fail closed, got empty success: %#v", txs)
	}
}

func TestHeliusResponseRejectsAmbiguousProviderJSON(t *testing.T) {
	t.Parallel()

	const row = `{"signature":"sig","slot":123,"blockTime":1700000200,"type":"transfer",` +
		`"fromUserAccount":"from","toUserAccount":"to",` +
		`"mint":"So11111111111111111111111111111111111111111",` +
		`"amount":"42","decimals":9,"uiAmount":"0.000000042","confirmationStatus":"finalized",` +
		`"transactionIdx":1,"instructionIdx":2,"innerInstructionIdx":null}`
	validResult := fmt.Sprintf(`{"data":[%s]}`, row)
	rowUnknown := strings.Replace(row, `"instructionIdx":2`, `"instructionIdx":2,"unexpected":true`, 1)
	rowAmountAlias := strings.Replace(row, `"amount":"42"`, `"Amount":"42"`, 1)
	rowDuplicateAmount := strings.Replace(row, `"amount":"42"`, `"amount":"1","amount":"42"`, 1)

	tests := []struct {
		name    string
		payload string
	}{
		{"wrong response id", fmt.Sprintf(`{"jsonrpc":"2.0","id":"other","result":%s}`, validResult)},
		{"missing response id", fmt.Sprintf(`{"jsonrpc":"2.0","result":%s}`, validResult)},
		{"wrong version", fmt.Sprintf(`{"jsonrpc":"1.0","id":"kt-wallet","result":%s}`, validResult)},
		{"unknown envelope member", fmt.Sprintf(`{"jsonrpc":"2.0","id":"kt-wallet","result":%s,"unexpected":true}`, validResult)},
		{"result case alias", fmt.Sprintf(`{"jsonrpc":"2.0","id":"kt-wallet","Result":%s}`, validResult)},
		{"result case collision", fmt.Sprintf(`{"jsonrpc":"2.0","id":"kt-wallet","result":{"data":[]},"Result":%s}`, validResult)},
		{"duplicate response id ending expected", fmt.Sprintf(`{"jsonrpc":"2.0","id":"other","id":"kt-wallet","result":%s}`, validResult)},
		{"duplicate result ending valid", fmt.Sprintf(`{"jsonrpc":"2.0","id":"kt-wallet","result":{"data":[]},"result":%s}`, validResult)},
		{"unknown result member", fmt.Sprintf(`{"jsonrpc":"2.0","id":"kt-wallet","result":{"data":[%s],"unexpected":true}}`, row)},
		{"data case alias", fmt.Sprintf(`{"jsonrpc":"2.0","id":"kt-wallet","result":{"Data":[%s]}}`, row)},
		{"duplicate data ending valid", fmt.Sprintf(`{"jsonrpc":"2.0","id":"kt-wallet","result":{"data":[],"data":[%s]}}`, row)},
		{"unknown transfer member", fmt.Sprintf(`{"jsonrpc":"2.0","id":"kt-wallet","result":{"data":[%s]}}`, rowUnknown)},
		{"transfer field alias", fmt.Sprintf(`{"jsonrpc":"2.0","id":"kt-wallet","result":{"data":[%s]}}`, rowAmountAlias)},
		{"duplicate transfer amount", fmt.Sprintf(`{"jsonrpc":"2.0","id":"kt-wallet","result":{"data":[%s]}}`, rowDuplicateAmount)},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				_, _ = w.Write([]byte(tc.payload))
			}))
			defer server.Close()

			transfers, err := NewHelius(server.URL, "key", server.Client(), time.Second).
				Transfers(context.Background(), "wallet", 20)
			if err == nil {
				t.Fatalf("ambiguous Helius response must fail closed, got %#v", transfers)
			}
		})
	}
}

func TestHeliusResponseRejectsInvalidOfficialTransferValues(t *testing.T) {
	t.Parallel()

	const row = `{"signature":"sig","slot":123,"blockTime":1700000200,"type":"transfer",` +
		`"fromUserAccount":"from","toUserAccount":"to",` +
		`"mint":"So11111111111111111111111111111111111111111",` +
		`"amount":"42","decimals":9,"uiAmount":"0.000000042","confirmationStatus":"finalized",` +
		`"transactionIdx":1,"instructionIdx":2,"innerInstructionIdx":null}`
	tests := []struct {
		name string
		row  string
	}{
		{"missing slot", strings.Replace(row, `"slot":123,`, "", 1)},
		{"missing UI amount", strings.Replace(row, `"uiAmount":"0.000000042",`, "", 1)},
		{"missing inner instruction index", strings.Replace(row, `,"innerInstructionIdx":null`, "", 1)},
		{"negative raw amount", strings.Replace(row, `"amount":"42"`, `"amount":"-42"`, 1)},
		{"fractional raw amount", strings.Replace(row, `"amount":"42"`, `"amount":"4.2"`, 1)},
		{"invalid UI amount", strings.Replace(row, `"uiAmount":"0.000000042"`, `"uiAmount":"NaN"`, 1)},
		{"unknown transfer type", strings.Replace(row, `"type":"transfer"`, `"type":"airdrop"`, 1)},
		{"both owners null", strings.Replace(row, `"fromUserAccount":"from","toUserAccount":"to"`, `"fromUserAccount":null,"toUserAccount":null`, 1)},
		{"null optional token account", strings.Replace(row, `"mint":`, `"fromTokenAccount":null,"mint":`, 1)},
		{"partial token fee", strings.Replace(row, `"confirmationStatus":`, `"feeAmount":"1","confirmationStatus":`, 1)},
		{"null pagination token", row},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			result := fmt.Sprintf(`{"data":[%s]}`, tc.row)
			if tc.name == "null pagination token" {
				result = fmt.Sprintf(`{"data":[%s],"paginationToken":null}`, tc.row)
			}
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				_, _ = fmt.Fprintf(w, `{"jsonrpc":"2.0","id":"kt-wallet","result":%s}`, result)
			}))
			defer server.Close()

			transfers, err := NewHelius(server.URL, "key", server.Client(), time.Second).
				Transfers(context.Background(), "wallet", 20)
			if err == nil {
				t.Fatalf("invalid Helius value must fail closed, got %#v", transfers)
			}
		})
	}
}

func TestHeliusResponseAllowsStandardErrorDataAndEmptyHistory(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name      string
		payload   string
		wantError bool
	}{
		{
			name:      "standard error data",
			payload:   `{"jsonrpc":"2.0","id":"kt-wallet","error":{"code":-32000,"message":"limited","data":{"retryAfter":1}}}`,
			wantError: true,
		},
		{
			name:    "empty transfer array",
			payload: `{"jsonrpc":"2.0","id":"kt-wallet","result":{"data":[]}}`,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				_, _ = w.Write([]byte(tc.payload))
			}))
			defer server.Close()

			transfers, err := NewHelius(server.URL, "key", server.Client(), time.Second).
				Transfers(context.Background(), "wallet", 20)
			if tc.wantError {
				var unavailable *Unavailable
				if !errors.As(err, &unavailable) || unavailable.Message != "history provider rejected request" {
					t.Fatalf("standard error object was not preserved: %v", err)
				}
				return
			}
			if err != nil || transfers == nil || len(transfers) != 0 {
				t.Fatalf("empty history must remain a valid non-nil result: transfers=%#v err=%v", transfers, err)
			}
		})
	}
}

func TestHeliusResponseAllowsCurrentOfficialTransferFields(t *testing.T) {
	t.Parallel()

	payload := `{"jsonrpc":"2.0","id":"kt-wallet","result":{"data":[` +
		`{"signature":"fee-transfer","slot":409259683,"blockTime":1774635210,"type":"transfer",` +
		`"fromUserAccount":"from","toUserAccount":"to","fromTokenAccount":"from-token",` +
		`"toTokenAccount":"to-token","mint":"mint","amount":"48650000","decimals":5,` +
		`"uiAmount":"486.5","feeAmount":"13450000","feeUiAmount":"134.5",` +
		`"confirmationStatus":"finalized","transactionIdx":1315,"instructionIdx":4,"innerInstructionIdx":0},` +
		`{"signature":"mint-transfer","slot":409259684,"blockTime":1774635211,"type":"mint",` +
		`"fromUserAccount":null,"toUserAccount":"wallet",` +
		`"toTokenAccount":"to-token","mint":"mint","amount":"1","decimals":0,"uiAmount":"1",` +
		`"confirmationStatus":"finalized","transactionIdx":1316,"instructionIdx":1,"innerInstructionIdx":null}` +
		`],"paginationToken":"409259684:1316:1:0:mint"}}`
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(payload))
	}))
	defer server.Close()

	transfers, err := NewHelius(server.URL, "key", server.Client(), time.Second).
		Transfers(context.Background(), "wallet", 20)
	if err != nil || len(transfers) != 2 {
		t.Fatalf("current official response shape must remain compatible: transfers=%#v err=%v", transfers, err)
	}
	if transfers[0].Amount != "48650000" || transfers[0].InnerInstructionIdx == nil ||
		transfers[1].FromUserAccount != "" || transfers[1].ToUserAccount != "wallet" {
		t.Fatalf("official transfer semantics were not preserved: %#v", transfers)
	}
}

func TestAlchemyTransfersQueriesBothDirectionsAndUsesRawValues(t *testing.T) {
	var (
		mu         sync.Mutex
		directions = map[string]bool{}
	)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		var request struct {
			Method string           `json:"method"`
			Params []map[string]any `json:"params"`
		}
		if err := json.Unmarshal(body, &request); err != nil {
			t.Fatal(err)
		}
		if request.Method != "alchemy_getAssetTransfers" || len(request.Params) != 1 {
			t.Fatalf("unexpected request: %s", body)
		}
		direction := ""
		for _, key := range []string{"fromAddress", "toAddress"} {
			if request.Params[0][key] != nil {
				direction = key
			}
		}
		mu.Lock()
		directions[direction] = true
		mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		if direction == "toAddress" {
			_, _ = w.Write([]byte(`{"jsonrpc":"2.0","id":1,"result":{"transfers":[{
				"uniqueId":"0xtoken:log:2","hash":"0xtoken",
				"from":"0x2222222222222222222222222222222222222222",
				"to":"0x1111111111111111111111111111111111111111",
				"asset":"USDC","category":"erc20",
				"rawContract":{"value":"0x2625a0","address":"0x3333333333333333333333333333333333333333","decimal":"0x6"},
				"metadata":{"blockTimestamp":"2026-07-29T01:02:03.456Z"}
			}]}}`))
			return
		}
		_, _ = w.Write([]byte(`{"jsonrpc":"2.0","id":1,"result":{"transfers":[{
			"uniqueId":"0xnative:external","hash":"0xnative",
			"from":"0x1111111111111111111111111111111111111111",
			"to":"0x2222222222222222222222222222222222222222",
			"asset":"BNB","category":"external",
			"rawContract":{"value":"0x4d2","address":null,"decimal":"0x12"},
			"metadata":{"blockTimestamp":"2026-07-29T01:01:00Z"}
		}]}}`))
	}))
	defer server.Close()

	client := NewAlchemy([]string{server.URL}, server.Client(), time.Second)
	transfers, err := client.Transfers(
		context.Background(),
		"0x1111111111111111111111111111111111111111",
		20,
	)
	if err != nil {
		t.Fatal(err)
	}
	if len(transfers) != 2 {
		t.Fatalf("transfers = %#v", transfers)
	}
	mu.Lock()
	defer mu.Unlock()
	if !directions["fromAddress"] || !directions["toAddress"] || directions[""] {
		t.Fatalf("directions = %#v", directions)
	}
	for _, transfer := range transfers {
		if strings.HasPrefix(transfer.Hash, "0xtoken") &&
			(transfer.Raw.Value != "0x2625a0" || transfer.BlockTime == "") {
			t.Fatalf("raw token transfer was not preserved: %#v", transfer)
		}
	}
}

func TestAlchemyRetriesWithoutInternalCategory(t *testing.T) {
	var calls atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		body, _ := io.ReadAll(r.Body)
		if strings.Contains(string(body), `"internal"`) {
			_, _ = w.Write([]byte(`{"jsonrpc":"2.0","id":1,"error":{"code":-32602,"message":"internal category unsupported"}}`))
			return
		}
		_, _ = w.Write([]byte(`{"jsonrpc":"2.0","id":1,"result":{"transfers":[]}}`))
	}))
	defer server.Close()

	client := NewAlchemy([]string{server.URL}, server.Client(), time.Second)
	if _, err := client.Transfers(
		context.Background(),
		"0x1111111111111111111111111111111111111111",
		20,
	); err != nil {
		t.Fatal(err)
	}
	if calls.Load() != 4 {
		t.Fatalf("calls = %d, want two directions plus two category fallbacks", calls.Load())
	}
}

func TestAlchemyBackfillsMissingMetadataFromBlockBatch(t *testing.T) {
	var batchCalls atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		w.Header().Set("Content-Type", "application/json")
		if strings.HasPrefix(strings.TrimSpace(string(body)), "[") {
			batchCalls.Add(1)
			_, _ = w.Write([]byte(`[{
				"jsonrpc":"2.0","id":1,
				"result":{"timestamp":"0x6889777b"}
			}]`))
			return
		}
		if strings.Contains(string(body), `"toAddress"`) {
			_, _ = w.Write([]byte(`{"jsonrpc":"2.0","id":1,"result":{"transfers":[{
				"uniqueId":"0xmissing:external","blockNum":"0xabc","hash":"0xmissing",
				"from":"0x2222222222222222222222222222222222222222",
				"to":"0x1111111111111111111111111111111111111111",
				"asset":"BNB","category":"external",
				"rawContract":{"value":"0x1","address":null,"decimal":"0x12"},
				"metadata":null
			}]}}`))
			return
		}
		_, _ = w.Write([]byte(`{"jsonrpc":"2.0","id":1,"result":{"transfers":[]}}`))
	}))
	defer server.Close()

	client := NewAlchemy([]string{server.URL}, server.Client(), time.Second)
	transfers, err := client.Transfers(
		context.Background(),
		"0x1111111111111111111111111111111111111111",
		20,
	)
	if err != nil {
		t.Fatal(err)
	}
	if len(transfers) != 1 || transfers[0].BlockTime != "2025-07-30T01:38:03Z" {
		t.Fatalf("block time was not backfilled: %#v", transfers)
	}
	if batchCalls.Load() != 1 {
		t.Fatalf("block timestamps should use one batch request, calls = %d", batchCalls.Load())
	}
}
