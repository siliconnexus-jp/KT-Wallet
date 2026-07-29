package upstream

import (
	"context"
	"encoding/json"
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
