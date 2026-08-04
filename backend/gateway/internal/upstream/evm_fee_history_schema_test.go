package upstream

import (
	"context"
	"net/http"
	"os"
	"testing"
	"time"

	"ktwallet/gateway/internal/clock"
)

const exactFeeHistoryResult = `{
  "oldestBlock":"0x64",
  "baseFeePerGas":["0x10","0x11","0x12"],
  "baseFeePerBlobGas":["0x1","0x2","0x3"],
  "gasUsedRatio":[0.25,1],
  "blobGasUsedRatio":[0,0.5],
  "reward":[["0x1","0x2","0x3"],["0x2","0x3","0x4"]]
}`

func feeHistoryResultClient(t *testing.T, result string) (*EVM, *fakeNode) {
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

func TestEVMFeeHistoryAcceptsExactOfficialShape(t *testing.T) {
	t.Parallel()
	client, _ := feeHistoryResultClient(t, exactFeeHistoryResult)
	got, err := client.FeeHistory(context.Background(), 5, []float64{10, 50, 90})
	if err != nil {
		t.Fatalf("exact fee history rejected: %v", err)
	}
	if len(got.BaseFeePerGas) != 3 || len(got.Reward) != 2 {
		t.Fatalf("unexpected exact fee history shape: %+v", got)
	}
}

func TestEVMFeeHistoryLiveExecutionNodeShape(t *testing.T) {
	if os.Getenv("KT_LIVE_EVM_FEE_HISTORY") != "1" {
		t.Skip("set KT_LIVE_EVM_FEE_HISTORY=1 for the read-only Ethereum fee history smoke test")
	}
	client := NewEVM(
		"eth-mainnet",
		[]string{"https://ethereum-rpc.publicnode.com"},
		clock.Real{},
		http.DefaultClient,
		15*time.Second,
	)
	result, err := client.FeeHistory(context.Background(), 5, []float64{10, 50, 90})
	if err != nil || len(result.BaseFeePerGas) < 2 || len(result.Reward) == 0 {
		t.Fatalf("live Ethereum fee history rejected: result=%+v err=%v", result, err)
	}
}

func TestEVMFeeHistoryRejectsAmbiguousOrInconsistentResults(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name   string
		result string
	}{
		{"missing oldest block", `{"baseFeePerGas":["0x10","0x11","0x12"],"gasUsedRatio":[0.25,1],"reward":[["0x1","0x2","0x3"],["0x2","0x3","0x4"]]}`},
		{"missing gas used ratio", `{"oldestBlock":"0x64","baseFeePerGas":["0x10","0x11","0x12"],"reward":[["0x1","0x2","0x3"],["0x2","0x3","0x4"]]}`},
		{"unknown result member", `{"oldestBlock":"0x64","baseFeePerGas":["0x10","0x11","0x12"],"gasUsedRatio":[0.25,1],"reward":[["0x1","0x2","0x3"],["0x2","0x3","0x4"]],"nextBaseFeePerGas":"0x12"}`},
		{"duplicate oldest block", `{"oldestBlock":"0x63","oldestBlock":"0x64","baseFeePerGas":["0x10","0x11","0x12"],"gasUsedRatio":[0.25,1],"reward":[["0x1","0x2","0x3"],["0x2","0x3","0x4"]]}`},
		{"noncanonical oldest block", `{"oldestBlock":"0x064","baseFeePerGas":["0x10","0x11","0x12"],"gasUsedRatio":[0.25,1],"reward":[["0x1","0x2","0x3"],["0x2","0x3","0x4"]]}`},
		{"base fee count mismatch", `{"oldestBlock":"0x64","baseFeePerGas":["0x10","0x11"],"gasUsedRatio":[0.25,1],"reward":[["0x1","0x2","0x3"],["0x2","0x3","0x4"]]}`},
		{"gas ratio count mismatch", `{"oldestBlock":"0x64","baseFeePerGas":["0x10","0x11","0x12"],"gasUsedRatio":[0.25],"reward":[["0x1","0x2","0x3"],["0x2","0x3","0x4"]]}`},
		{"negative gas ratio", `{"oldestBlock":"0x64","baseFeePerGas":["0x10","0x11","0x12"],"gasUsedRatio":[-0.01,1],"reward":[["0x1","0x2","0x3"],["0x2","0x3","0x4"]]}`},
		{"gas ratio above one", `{"oldestBlock":"0x64","baseFeePerGas":["0x10","0x11","0x12"],"gasUsedRatio":[0.25,1.01],"reward":[["0x1","0x2","0x3"],["0x2","0x3","0x4"]]}`},
		{"string gas ratio", `{"oldestBlock":"0x64","baseFeePerGas":["0x10","0x11","0x12"],"gasUsedRatio":["0.25",1],"reward":[["0x1","0x2","0x3"],["0x2","0x3","0x4"]]}`},
		{"reward row count mismatch", `{"oldestBlock":"0x64","baseFeePerGas":["0x10","0x11","0x12"],"gasUsedRatio":[0.25,1],"reward":[["0x1","0x2","0x3"]]}`},
		{"reward percentile count mismatch", `{"oldestBlock":"0x64","baseFeePerGas":["0x10","0x11","0x12"],"gasUsedRatio":[0.25,1],"reward":[["0x1","0x2","0x3","0x4"],["0x2","0x3","0x4","0x5"]]}`},
		{"nonmonotonic reward row", `{"oldestBlock":"0x64","baseFeePerGas":["0x10","0x11","0x12"],"gasUsedRatio":[0.25,1],"reward":[["0x3","0x2","0x1"],["0x2","0x3","0x4"]]}`},
		{"more blocks than requested", `{"oldestBlock":"0x64","baseFeePerGas":["0x1","0x2","0x3","0x4","0x5","0x6","0x7"],"gasUsedRatio":[0,0,0,0,0,0],"reward":[["0x1","0x2","0x3"],["0x1","0x2","0x3"],["0x1","0x2","0x3"],["0x1","0x2","0x3"],["0x1","0x2","0x3"],["0x1","0x2","0x3"]]}`},
		{"blob base fee count mismatch", `{"oldestBlock":"0x64","baseFeePerGas":["0x10","0x11","0x12"],"baseFeePerBlobGas":["0x1"],"gasUsedRatio":[0.25,1],"reward":[["0x1","0x2","0x3"],["0x2","0x3","0x4"]]}`},
		{"blob gas ratio count mismatch", `{"oldestBlock":"0x64","baseFeePerGas":["0x10","0x11","0x12"],"gasUsedRatio":[0.25,1],"blobGasUsedRatio":[0],"reward":[["0x1","0x2","0x3"],["0x2","0x3","0x4"]]}`},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			client, _ := feeHistoryResultClient(t, tc.result)
			if got, err := client.FeeHistory(context.Background(), 5, []float64{10, 50, 90}); err == nil {
				t.Fatalf("ambiguous fee history must fail closed, got %+v", got)
			}
		})
	}
}

func TestEVMFeeHistoryRejectsInvalidRequestBeforeNetwork(t *testing.T) {
	t.Parallel()
	client, node := feeHistoryResultClient(t, exactFeeHistoryResult)
	tests := []struct {
		blockCount  int
		percentiles []float64
	}{
		{0, []float64{10, 50, 90}},
		{5, []float64{-1, 50, 90}},
		{5, []float64{10, 101}},
		{5, []float64{50, 10}},
		{5, []float64{10, 10}},
	}
	for _, tc := range tests {
		if _, err := client.FeeHistory(context.Background(), tc.blockCount, tc.percentiles); err == nil {
			t.Fatalf("invalid fee history request accepted: count=%d percentiles=%v", tc.blockCount, tc.percentiles)
		}
	}
	if got := node.hits.Load(); got != 0 {
		t.Fatalf("invalid fee history requests reached upstream %d times", got)
	}
}
