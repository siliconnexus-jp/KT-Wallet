package handlers_test

import (
	"fmt"
	"strings"
	"testing"

	"ktwallet/gateway/internal/handlers"
	"ktwallet/gateway/internal/rpc"
)

const (
	evmHash      = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	evmOtherHash = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
	evmBlockHash = "0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
	tronHash     = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
	solHash      = "5KtPn3E1Z9ezPTVYPQ7V2FZx5zRW2aYw5gCz6tNQ8crShXKQ3Fd6ztqQmDN7Hjz3EN3YHhuYxqUjQK4rDgVjSxqR"
)

func TestEVMTransactionStatusUsesReceiptNotHistoryIndexer(t *testing.T) {
	node := newRPCFake(t)
	node.result("eth_getTransactionReceipt", map[string]any{
		"transactionHash":  evmHash,
		"blockHash":        evmBlockHash,
		"blockNumber":      "0x64",
		"transactionIndex": "0x0",
		"status":           "0x1",
	})
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EthURLs = []string{node.srv.URL}
	})

	res := result(t, e.rpc(
		"kt_getTransactionStatus",
		fmt.Sprintf(`{"chain":"eth","network":"eth-mainnet","hash":%q}`, evmHash),
	))
	if res["status"] != "confirmed" {
		t.Fatalf("expected confirmed, got %v", res)
	}
	if node.count("eth_getTransactionReceipt") != 1 {
		t.Fatal("status must query the chain receipt exactly once")
	}
}

func TestEVMTransactionStatusRejectsReceiptForAnotherHash(t *testing.T) {
	node := newRPCFake(t)
	node.result("eth_getTransactionReceipt", map[string]any{
		"transactionHash":  evmOtherHash,
		"blockHash":        evmBlockHash,
		"blockNumber":      "0x64",
		"transactionIndex": "0x0",
		"status":           "0x1",
	})
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EthURLs = []string{node.srv.URL}
	})

	assertErrCode(t, e.rpc(
		"kt_getTransactionStatus",
		fmt.Sprintf(`{"chain":"eth","hash":%q}`, evmHash),
	), rpc.CodeUpstream)
}

func TestEVMTransactionStatusRejectsIncompleteReceiptEvidence(t *testing.T) {
	node := newRPCFake(t)
	node.result("eth_getTransactionReceipt", map[string]any{
		"transactionHash": evmHash,
		"blockNumber":     "0x64",
		"status":          "0x1",
	})
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EthURLs = []string{node.srv.URL}
	})

	assertErrCode(t, e.rpc(
		"kt_getTransactionStatus",
		fmt.Sprintf(`{"chain":"eth","hash":%q}`, evmHash),
	), rpc.CodeUpstream)
}

func TestEVMTransactionStatusRejectsNonCanonicalReceiptEvidence(t *testing.T) {
	tests := []struct {
		name        string
		blockNumber string
		status      string
	}{
		{name: "oversized block number", blockNumber: "0x" + strings.Repeat("1", 65), status: "0x1"},
		{name: "non-canonical status", blockNumber: "0x64", status: "0x01"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			node := newRPCFake(t)
			node.result("eth_getTransactionReceipt", map[string]any{
				"transactionHash":  evmHash,
				"blockHash":        evmBlockHash,
				"blockNumber":      tc.blockNumber,
				"transactionIndex": "0x0",
				"status":           tc.status,
			})
			e := newEnv(t, func(cfg *handlers.Config) {
				cfg.EthURLs = []string{node.srv.URL}
			})

			assertErrCode(t, e.rpc(
				"kt_getTransactionStatus",
				fmt.Sprintf(`{"chain":"eth","hash":%q}`, evmHash),
			), rpc.CodeUpstream)
		})
	}
}

func TestEVMTransactionStatusKnownWithoutReceiptIsPending(t *testing.T) {
	node := newRPCFake(t)
	node.result("eth_getTransactionReceipt", nil)
	node.result("eth_getTransactionByHash", map[string]any{"hash": evmHash})
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EthURLs = []string{node.srv.URL}
	})

	res := result(t, e.rpc(
		"kt_getTransactionStatus",
		fmt.Sprintf(`{"chain":"eth","hash":%q}`, evmHash),
	))
	if res["status"] != "pending" {
		t.Fatalf("expected pending, got %v", res)
	}
}

func TestEVMTransactionStatusRejectsAnotherKnownTransaction(t *testing.T) {
	node := newRPCFake(t)
	node.result("eth_getTransactionReceipt", nil)
	node.result("eth_getTransactionByHash", map[string]any{"hash": evmOtherHash})
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.EthURLs = []string{node.srv.URL}
	})

	assertErrCode(t, e.rpc(
		"kt_getTransactionStatus",
		fmt.Sprintf(`{"chain":"eth","hash":%q}`, evmHash),
	), rpc.CodeUpstream)
}

func TestSolanaTransactionStatusReportsExecutionFailure(t *testing.T) {
	node := newRPCFake(t)
	node.result("getSignatureStatuses", map[string]any{
		"value": []any{map[string]any{
			"confirmationStatus": "finalized",
			"err":                map[string]any{"InstructionError": []any{0, "Custom"}},
		}},
	})
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.SolanaURLs = []string{node.srv.URL}
	})

	res := result(t, e.rpc(
		"kt_getTransactionStatus",
		fmt.Sprintf(`{"chain":"solana","hash":%q}`, solHash),
	))
	if res["status"] != "failed" {
		t.Fatalf("expected failed, got %v", res)
	}
}

func TestSolanaTransactionStatusMissingErrIsUnknown(t *testing.T) {
	node := newRPCFake(t)
	node.result("getSignatureStatuses", map[string]any{
		"value": []any{map[string]any{
			"confirmationStatus": "finalized",
		}},
	})
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.SolanaURLs = []string{node.srv.URL}
	})

	res := result(t, e.rpc(
		"kt_getTransactionStatus",
		fmt.Sprintf(`{"chain":"solana","hash":%q}`, solHash),
	))
	if res["status"] != "unknown" {
		t.Fatalf("missing err evidence must stay unknown, got %v", res)
	}
}

func TestTronTransactionStatusUsesFullNodeReceipt(t *testing.T) {
	grid := newRESTFake(t)
	grid.routeJSON(
		"/wallet/gettransactioninfobyid",
		fmt.Sprintf(`{"id":%q,"receipt":{"result":"SUCCESS"}}`, tronHash),
	)
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.TronURL = grid.srv.URL
	})

	res := result(t, e.rpc(
		"kt_getTransactionStatus",
		fmt.Sprintf(`{"chain":"tron","hash":%q}`, tronHash),
	))
	if res["status"] != "confirmed" {
		t.Fatalf("expected confirmed, got %v", res)
	}
}

func TestTronTransactionStatusMissingReceiptResultIsUnknown(t *testing.T) {
	grid := newRESTFake(t)
	grid.routeJSON(
		"/wallet/gettransactioninfobyid",
		fmt.Sprintf(`{"id":%q,"receipt":{}}`, tronHash),
	)
	e := newEnv(t, func(cfg *handlers.Config) {
		cfg.TronURL = grid.srv.URL
	})

	res := result(t, e.rpc(
		"kt_getTransactionStatus",
		fmt.Sprintf(`{"chain":"tron","hash":%q}`, tronHash),
	))
	if res["status"] != "unknown" {
		t.Fatalf("missing receipt result must stay unknown, got %v", res)
	}
}
