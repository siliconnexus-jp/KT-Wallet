package upstream

import (
	"context"
	"net/http"
	"net/http/httptest"
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
