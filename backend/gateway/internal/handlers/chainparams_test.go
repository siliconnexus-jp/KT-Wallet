package handlers_test

import (
	"fmt"
	"math/big"
	"testing"

	"ktwallet/gateway/internal/handlers"
	"ktwallet/gateway/internal/rpc"
)

func feeTiers(t *testing.T, res map[string]any) (slow, standard, fast map[string]any) {
	t.Helper()
	fees, ok := res["fees"].(map[string]any)
	if !ok {
		t.Fatalf("missing fees: %v", res)
	}
	return fees["slow"].(map[string]any), fees["standard"].(map[string]any), fees["fast"].(map[string]any)
}

func mustBig(t *testing.T, v any) *big.Int {
	t.Helper()
	s, ok := v.(string)
	if !ok {
		t.Fatalf("fee field is not a decimal string: %v (%T)", v, v)
	}
	n, ok := new(big.Int).SetString(s, 10)
	if !ok {
		t.Fatalf("fee field is not decimal: %q", s)
	}
	return n
}

func assertMonotonicTiers(t *testing.T, slow, standard, fast map[string]any) {
	t.Helper()
	for _, field := range []string{"maxPriorityFeePerGas", "maxFeePerGas"} {
		s, m, f := mustBig(t, slow[field]), mustBig(t, standard[field]), mustBig(t, fast[field])
		if s.Cmp(m) > 0 || m.Cmp(f) > 0 {
			t.Fatalf("%s tiers not monotonic: slow=%v standard=%v fast=%v", field, s, m, f)
		}
	}
}

func TestChainParamsFromFeeHistory(t *testing.T) {
	node := newRPCFake(t)
	node.result("eth_getTransactionCount", "0x2a") // 42
	// Two blocks, base fee 1 gwei, rewards 1/2/3 gwei at p10/p50/p90.
	node.result("eth_feeHistory", map[string]any{
		"baseFeePerGas": []string{"0x3b9aca00", "0x3b9aca00"},
		"reward": [][]string{
			{"0x3b9aca00", "0x77359400", "0xb2d05e00"},
			{"0x3b9aca00", "0x77359400", "0xb2d05e00"},
		},
	})
	e := newEnv(t, func(cfg *handlers.Config) { cfg.EthURLs = []string{node.srv.URL} })

	res := result(t, e.rpc("kt_getChainParams", fmt.Sprintf(`{"chain":"eth","address":%q}`, evmSelf)))
	if res["nonce"] != "42" {
		t.Fatalf("nonce = %v, want \"42\" (decimal string)", res["nonce"])
	}
	slow, standard, fast := feeTiers(t, res)
	assertMonotonicTiers(t, slow, standard, fast)

	// maxFee = 2*nextBaseFee + priority.
	assertJSONEq(t, `{"maxPriorityFeePerGas":"1000000000","maxFeePerGas":"3000000000"}`, slow)
	assertJSONEq(t, `{"maxPriorityFeePerGas":"2000000000","maxFeePerGas":"4000000000"}`, standard)
	assertJSONEq(t, `{"maxPriorityFeePerGas":"3000000000","maxFeePerGas":"5000000000"}`, fast)

	// eth_feeHistory succeeded, so eth_gasPrice must not have been consulted.
	if node.count("eth_gasPrice") != 0 {
		t.Fatal("gasPrice fallback must not fire when feeHistory works")
	}
}

func TestChainParamsGasPriceFallback(t *testing.T) {
	node := newRPCFake(t)
	node.result("eth_getTransactionCount", "0x0")
	node.nodeError("eth_feeHistory", -32601, "the method eth_feeHistory does not exist")
	node.result("eth_gasPrice", "0x77359400") // 2 gwei
	e := newEnv(t, func(cfg *handlers.Config) { cfg.PolygonURLs = []string{node.srv.URL} })

	res := result(t, e.rpc("kt_getChainParams", fmt.Sprintf(`{"chain":"polygon","address":%q}`, evmSelf)))
	if res["nonce"] != "0" {
		t.Fatalf("nonce = %v, want \"0\"", res["nonce"])
	}
	slow, standard, fast := feeTiers(t, res)
	assertMonotonicTiers(t, slow, standard, fast)
	assertJSONEq(t, `{"maxPriorityFeePerGas":"200000000","maxFeePerGas":"2000000000"}`, slow)
	assertJSONEq(t, `{"maxPriorityFeePerGas":"300000000","maxFeePerGas":"2500000000"}`, standard)
	assertJSONEq(t, `{"maxPriorityFeePerGas":"400000000","maxFeePerGas":"3000000000"}`, fast)

	if node.count("eth_gasPrice") != 1 {
		t.Fatalf("expected exactly one eth_gasPrice call, got %d", node.count("eth_gasPrice"))
	}
}

func TestChainParamsEmptyFeeHistoryFallsBack(t *testing.T) {
	node := newRPCFake(t)
	node.result("eth_getTransactionCount", "0x1")
	node.result("eth_feeHistory", map[string]any{"baseFeePerGas": []string{}, "reward": [][]string{}})
	node.result("eth_gasPrice", "0x3b9aca00")
	e := newEnv(t, func(cfg *handlers.Config) { cfg.EthURLs = []string{node.srv.URL} })

	res := result(t, e.rpc("kt_getChainParams", fmt.Sprintf(`{"chain":"eth","address":%q}`, evmSelf)))
	slow, standard, fast := feeTiers(t, res)
	assertMonotonicTiers(t, slow, standard, fast)
	if node.count("eth_gasPrice") != 1 {
		t.Fatal("empty feeHistory must fall back to gasPrice")
	}
}

func TestChainParamsNonEVMRejected(t *testing.T) {
	e := newEnv(t, nil)
	for _, chain := range []string{"tron", "solana"} {
		resp := e.rpc("kt_getChainParams", fmt.Sprintf(`{"chain":%q,"address":%q}`, chain, tronSelfB58))
		assertErrCode(t, resp, rpc.CodeInvalidParams)
	}
}

func TestChainParamsInvalidParams(t *testing.T) {
	e := newEnv(t, nil)
	for _, params := range []string{
		`{"chain":"eth"}`,
		`{"chain":"eth","address":""}`,
		`{"chain":"nope","address":"0x1111111111111111111111111111111111111111"}`,
	} {
		assertErrCode(t, e.rpc("kt_getChainParams", params), rpc.CodeInvalidParams)
	}
}

func TestChainParamsAlwaysRefreshesPendingNonce(t *testing.T) {
	node := newRPCFake(t)
	node.result("eth_getTransactionCount", "0x5")
	node.result("eth_gasPrice", "0x3b9aca00")
	node.nodeError("eth_feeHistory", -32601, "no")
	e := newEnv(t, func(cfg *handlers.Config) { cfg.EthURLs = []string{node.srv.URL} })

	p := fmt.Sprintf(`{"chain":"eth","address":%q}`, evmSelf)
	result(t, e.rpc("kt_getChainParams", p))
	result(t, e.rpc("kt_getChainParams", p))
	result(t, e.rpc("kt_getChainParams", p))
	if node.count("eth_getTransactionCount") != 3 {
		t.Fatalf("pending nonce must be fetched for every quote, calls = %d", node.count("eth_getTransactionCount"))
	}
}
